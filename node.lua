gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

node.alias "*" -- catch all communication

util.noglobals()

local json = require "json"
local loader = require "loader"
local helper = require "helper"
local placement = require "placement"
local easing = require "easing"

local min, max, abs, floor = math.min, math.max, math.abs, math.floor

local font_regl = resource.load_font "default-font.ttf"
local font_bold = resource.load_font "default-font-bold.ttf"

local function log(system, format, ...)
    return print(string.format("[%s] " .. format, system, ...))
end

local function Music()
    local asset_name = nil
    local music = nil

    node.event("config_updated", function(config)
        log("music", "updating music config settings")
        if config.music.asset_id == "mute.mp4" then
            if music then
                music:dispose()
            end
            asset_name = nil
            music = nil
        elseif config.music.asset_name ~= asset_name then
            if music then
                music:dispose()
            end
            asset_name = config.music.asset_name
            music = resource.load_video{
                file = config.music.asset_name,
                looped = true,
                audio = true,
                raw = true,
            }
        end
    end)
end

local music = Music()

local function TCPClients()
    local clients = {}
    local handlers = {}

    node.event("connect", function(client, path)
        log("tcpclient", "new tcp client for %s", path)
        clients[client] = {
            path = path;
            send = function(...)
                node.client_write(client, ...)
            end
        }
    end)

    node.event("input", function(line, client)
        local cinfo = clients[client]
        if handlers[cinfo.path] then
            handlers[cinfo.path](line)
        end
    end)

    node.event("disconnect", function(client)
        clients[client] = nil
    end)

    local function send(path, ...)
        for client, cinfo in pairs(clients) do
            if cinfo.path == path then
                cinfo.send(...)
            end
        end
    end

    local function add_handler(path, handler)
        handlers[path] = handler
    end

    return {
        send = send;
        add_handler = add_handler;
    }
end

local tcp_clients = TCPClients()

local function Screen()
    local placer
    local rotation
    local frame_time = 1/60

    pcall(function()
        local fps, swap_interval = sys.get_ext("screen").get_display_info()
        frame_time = 1 / fps * swap_interval
        log("screen", "detected frame delay is %f", frame_time)
    end)

    node.event("config_updated", function(config)
        rotation = config.rotation
        local is_portrait = rotation == 90 or rotation == 270
        local width, height = config.resolution[1], config.resolution[2]
        log("screen", "configured content resolution is %dx%d", width, height)

        local surface = {
            width = width,
            height = height,
        }

        local target = {
            x = 0,
            y = 0,
            width = NATIVE_WIDTH,
            height = NATIVE_HEIGHT,
            rotation = rotation,
        }

        if is_portrait then
            surface.width, surface.height = surface.height, surface.width
        end

        placer = placement.Screen(target, surface)
    end)

    local function setup()
        return placer.setup()
    end

    local function place_video(...)
        return placer.place(...)
    end

    local function get_rotation()
        return rotation
    end

    return {
        setup = setup;
        place_video = place_video;
        frame_time = frame_time;
        get_rotation = get_rotation;
    }
end

local screen = Screen()

local error_img = resource.create_colored_texture(1,0,0,1)
local function ImageCache()
    local images = {}

    local function get(asset_name, keep) 
        if not images[asset_name] then
            register(asset_name, keep)
        end
        local image = images[asset_name]
        if not image then
            return error_img
        end
        if not image.obj then
            image.obj = resource.load_image(image.file)
        end
        image.lru = max(image.lru, sys.now() + keep)
        return image.obj
    end

    local function register(asset_name, keep)
        log("imagecache", "register %s %d", asset_name, keep)
        if not images[asset_name] then
            images[asset_name] = {
                file = resource.open_file(asset_name),
                lru = sys.now() + keep
            }
        end
        return function(keep)
            return get(asset_name, keep or 0)
        end
    end

    local function tick()
        for asset_name, image in pairs(images) do
            local max_age = 0.5
            if not image.obj then
                max_age = 10
            end
            if sys.now() - image.lru > max_age then
              log("imagecache", "purging image %s", asset_name)
              image.file:dispose()
              if image.obj then
                  image.obj:dispose()
              end
              images[asset_name] = nil
            end
        end
    end

    return {
        register = register;
        get = get;
        tick = tick;
    }
end

local ImageCache = ImageCache()

local function Clock()
    local has_time = false
    local time = {diff=0}

    util.data_mapper{
        ["clock"] = function(data)
            time = json.decode(data)
            has_time = true
        end;
    }

    return {
        human = function()
            local t = time.since_midnight % 86400
            return string.format("%02d:%02d", math.floor(t / 3600), math.floor(t % 3600 / 60))
        end;
        has_time = function()
            return has_time
        end;
        unix = function()
            return os.time() + time.diff
        end;
        week_hour = function()
            return time.week_hour
        end;
        day_of_week = function()
            return time.dow
        end;
        since_midnight = function()
            return time.since_midnight
        end,
        today = function()
            return {
                day = time.day;
                month = time.month;
                year = time.year;
            }
        end;
    }
end

local clock = Clock()

local SharedData = function()
    -- {
    --    scope: { key: data }
    -- }
    local data = {}

    -- {
    --    key: { scope: listener }
    -- }
    local listeners = {}

    local function call_listener(scope, listener, key, value)
        local ok, err = xpcall(listener, debug.traceback, scope, value)
        if not ok then
            log("shareddata", "while calling listener for key %s: %s", key, err)
        end
    end

    local function call_listeners(scope, key, value)
        local key_listeners = listeners[key]
        if not key_listeners then
            return
        end

        for _, listener in pairs(key_listeners) do
            call_listener(scope, listener, key, value)
        end
    end

    local function update(scope, key, value)
        if not data[scope] then
            data[scope] = {}
        end
        data[scope][key] = value
        if value == nil and not next(data[scope]) then
            data[scope] = nil
        end
        return call_listeners(scope, key, value)
    end

    local function delete(scope, key)
        return update(scope, key, nil)
    end

    local function add_listener(scope, key, listener)
        local key_listeners = listeners[key]
        if not key_listeners then
            listeners[key] = {}
            key_listeners = listeners[key]
        end
        if key_listeners[scope] then
            error "right now only a single listener is supported per scope"
        end
        key_listeners[scope] = listener
        for scope, scoped_data in pairs(data) do
            for key, value in pairs(scoped_data) do
                call_listener(scope, listener, key, value)
            end
        end
    end

    local function del_scope(scope)
        for key, key_listeners in pairs(listeners) do
            key_listeners[scope] = nil
            if not next(key_listeners) then
                listeners[key] = nil
            end
        end

        local scoped_data = data[scope]
        if scoped_data then
            for key, value in pairs(scoped_data) do
                delete(scope, key)
            end
        end
        data[scope] = nil
    end

    return {
        update = update;
        delete = delete;
        add_listener = add_listener;
        del_scope = del_scope;
    }
end

local data = SharedData()

local tile_loader = loader.setup "tile.lua"

tile_loader.before_load = function(tile, exports)
    exports.tcp_clients = tcp_clients
    exports.wait_frame = helper.wait_frame
    exports.wait_t = helper.wait_t
    exports.frame_between = helper.frame_between

    exports.screen = {
        place_video = screen.place_video;
        get_rotation = screen.get_rotation;
    }

    exports.clock = clock

    exports.update_data = function(key, value)
        data.delete(tile, key)
        data.update(tile, key, value)
    end
    exports.add_listener = function(key, listener)
        data.add_listener(tile, key, listener)
    end
end

tile_loader.unload = function(tile)
    data.del_scope(tile)
end

local function dispatch_to_all_tiles(event, ...)
    for module_name, module in pairs(tile_loader.modules) do
        local fn = module[event]
        if fn then
            local ok, err = xpcall(fn, debug.traceback, ...)
            if not ok then
                log(
                    "dispatch_to_all_tiles", 
                    "cannot dispatch '%s' into '%s': %s",
                    event, module_name, err
                )
            end
        end
    end
end

local kenburns_shader = resource.create_shader[[
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 Color;
    uniform float x, y, s;
    void main() {
        gl_FragColor = texture2D(Texture, TexCoord * vec2(s, s) + vec2(x, y)) * Color;
    }
]]

local gl_effects = {
    none = function(x1, y1, x2, y2)
        local w, h = x2-x1, y2-y1
        return function(draw, t)
            gl.pushMatrix()
                gl.translate(x1, y1)
                draw(t)
            gl.popMatrix()
        end, w, h
    end,
    rotation = function(x1, y1, x2, y2, config)
        local w, h = x2-x1, y2-y1
        return function(draw, t, starts, ends)
            local effect_easing = config.effect_easing or 'inQuad'
            local effect_rotation = config.effect_rotation or 'y-axis'
            local effect_pivot = config.effect_pivot or 'center'

            local pivot_x, pivot_y = unpack(({
                center = { .5, .5},
                top  =   { .5,  0},
                bottom = { .5,  1},
                left =   {  0, .5},
                right =  {  1, .5},
            })[effect_pivot])

            local enter_t = min(t-starts, 1)
            local exit_t = 1-max(0, 1-(ends-t))
            local effect_value = (
              -easing[effect_easing](1-enter_t, 0, 1, 1) 
              +easing[effect_easing](1-exit_t,  0, 1, 1) 
            )

            gl.pushMatrix()
                gl.translate(x1+w*pivot_x, y1+h*pivot_y)
                if effect_rotation == 'y-axis' then
                    gl.rotate(effect_value*90, 0, 1, 0)
                elseif effect_rotation == 'x-axis' then
                    gl.rotate(effect_value*90, 1, 0, 0)
                end
                gl.translate(-w*pivot_x, -h*pivot_y)
                draw(t)
            gl.popMatrix()
        end, w, h
    end,
    enter_exit_move = function(x1, y1, x2, y2, config)
        local w, h = x2-x1, y2-y1
        return function(draw, t, starts, ends)
            local effect_duration = config.effect_duration or 1
            local effect_easing = config.effect_easing or 'inQuad'
            local effect_direction = config.effect_direction or 'from_left'

            local progress = easing[effect_easing](
                1 - helper.ramp(starts, ends, t, effect_duration),
                0, 1, 1
            )
            local move_x, move_y = unpack(({
                from_left   = {-w,  0},
                from_right  = { w,  0},
                from_bottom = { 0,  h},
                from_top    = { 0, -h},
            })[effect_direction])
            gl.pushMatrix()
                gl.translate(x1+move_x*progress, y1+move_y*progress)
                draw(t)
            gl.popMatrix()
        end, w, h
    end,
}

local function ChildTile(asset, config, x1, y1, x2, y2)
    return function(starts, ends)
        local tile = tile_loader.modules[asset.asset_name]
        return tile.task(starts, ends, config, x1, y1, x2, y2)
    end
end

local function ImageTile(asset, config, x1, y1, x2, y2)
    -- config:
    --   kenburns: true/false
    --   fade_time: 0-1
    --   fit: true/false

    local img = ImageCache.register(asset.asset_name, 10)
    local fade_time = config.fade_time or 0

    return function(starts, ends)
        helper.wait_t(starts - 2)

        -- force loading and keep around for 3 seconds minimum
        img(3)

        local effect, width, height = gl_effects[
            config.effect or 'none'
        ](x1, y1, x2, y2, config)

        local function draw(now)
            if config.fit then
                util.draw_correct(img(), 0, 0, width, height, helper.ramp(
                    starts, ends, now, fade_time
                ))
            else
                img():draw(0, 0, width, height, helper.ramp(
                    starts, ends, now, fade_time
                ))
            end
        end

        if config.kenburns then
            local function lerp(s, e, t)
                return s + t * (e-s)
            end

            local paths = {
                {from = {x=0.0,  y=0.0,  s=1.0 }, to = {x=0.08, y=0.08, s=0.9 }},
                {from = {x=0.05, y=0.0,  s=0.93}, to = {x=0.03, y=0.03, s=0.97}},
                {from = {x=0.02, y=0.05, s=0.91}, to = {x=0.01, y=0.05, s=0.95}},
                {from = {x=0.07, y=0.05, s=0.91}, to = {x=0.04, y=0.03, s=0.95}},
            }

            local path = paths[math.random(1, #paths)]

            local to, from = path.to, path.from
            if math.random() >= 0.5 then
                to, from = from, to
            end

            local w, h = img():size()
            local duration = ends - starts

            local function lerp(s, e, t)
                return s + t * (e-s)
            end

            for now in helper.frame_between(starts, ends) do
                local t = (now - starts) / duration
                kenburns_shader:use{
                    x = lerp(from.x, to.x, t);
                    y = lerp(from.y, to.y, t);
                    s = lerp(from.s, to.s, t);
                }
                effect(draw, now, starts, ends)
                kenburns_shader:deactivate()
            end
        else
            for now in helper.frame_between(starts, ends) do
                effect(draw, now, starts, ends)
            end
        end
    end
end

local function VideoTile(asset, config, x1, y1, x2, y2)
    -- config:
    --   fade_time: 0-1
    --   looped

    local file = resource.open_file(asset.asset_name)
    local fade_time = config.fade_time or 0.5
    local looped = config.looped
    local audio = config.audio

    return function(starts, ends)
        helper.wait_t(starts - 2)

        local vid = resource.load_video{
            file = file,
            paused = true,
            looped = looped,
            audio = audio,
        }

        for now in helper.frame_between(starts, ends) do
            vid:draw(x1, y1, x2, y2, helper.ramp(
                starts, ends, now, fade_time
            )):start()
        end

        vid:dispose()
    end
end

local function RawVideoTile(asset, config, x1, y1, x2, y2)
    -- config:
    --   asset_name: 'foo.mp4'
    --   fit: aspect fit or scale?
    --   fade_time: 0-1
    --   looped
    --   layer: video layer for raw videos

    local file = resource.open_file(asset.asset_name)
    local fade_time = config.fade_time or 0.5
    local looped = config.looped
    local audio = config.audio
    local layer = config.layer or 5

    return function(starts, ends)
        helper.wait_t(starts - 2)

        local vid = resource.load_video{
            file = file,
            paused = true,
            looped = looped,
            audio = audio,
            raw = true,
        }
        vid:layer(-10)

        for now in helper.frame_between(starts, ends) do
            screen.place_video(vid, layer, helper.ramp(
                starts, ends, now, fade_time
            ), x1, y1, x2, y2):start()
        end

        vid:dispose()
    end
end

local function StreamTile(asset, config, x1, y1, x2, y2)
    local layer = config.layer or 5
    local url = config.url or ""
    local audio = config.audio

    return function(starts, ends)
        helper.wait_t(starts - 2)

        local vid
        local next_load = 0

        local function load_stream()
            if vid then
                vid:dispose()
                vid = nil
            end
            if sys.now() < next_load then
                return
            end
            vid = resource.load_video{
                file = url,
                raw = true,
                audio = audio,
            }
            vid:layer(-10):target(0, 0, 0, 0):alpha(0)
            next_load = sys.now() + 5
        end

        load_stream()

        for now in helper.frame_between(starts, ends) do
            local state = vid and vid:state()
            if state == "finished" or state == "error" then
                load_stream()
            end
            if vid then
                screen.place_video(vid, layer, 1, x1, y1, x2, y2)
            end
        end

        if vid then
            vid:dispose()
        end
    end
end

local function FlatTile(asset, config, x1, y1, x2, y2)
    -- config:
    --   color: "#rrggbb"
    --   fade_time: 0-1

    local r, g, b = helper.parse_rgb(config.color or "#ffffff")
    local a = (config.alpha or 255)/255

    local flat = resource.create_colored_texture(r, g, b, a)
    local fade_time = config.fade_time or 0.5

    return function(starts, ends)
        for now in helper.frame_between(starts, ends) do
            flat:draw(x1, y1, x2, y2, helper.ramp(
                starts, ends, now, fade_time
            ))
        end
        flat:dispose()
    end
end

local function FontCache()
    local fonts = {}

    local function get(filename)
        local font = fonts[filename]
        if not font then
            font = {
                obj = resource.load_font(filename),
            }
            fonts[filename] = font
        end
        font.lru = sys.now()
        return font.obj
    end

    local function tick()
        for filename, font in pairs(fonts) do
            if sys.now() - font.lru > 300 then
                log("fontcache", "purging font %s", filename)
                fonts[filename] = nil
            end
        end
    end

    return {
        get = get;
        tick = tick;
    }
end

local FontCache = FontCache()

local function MarkupTile(asset, config, x1, y1, x2, y2)
    local fade_time = config.fade_time or 0
    local text = config.text or ""
    local font_size = config.font_size or 35
    local align = config.align or "tl"
    local font = FontCache.get(asset.asset_name)

    local width = x2 - x1
    local height = y2 - y1
    local r, g, b = helper.parse_rgb(config.color or "#ffffff")

    local y = 0
    local max_x = 0
    local writes = {}

    local cell_padding = 40
    local paragraph_split = 40
    local line_height = 1.05

    local default_font_size = font_size
    local h1_font_size = default_font_size * 2
    local h2_font_size = floor(h1_font_size * 0.75)

    local function max_per_line(font, size, width)
        -- try to calculate the max characters/line
        -- number based on the average character width
        -- of the specified font.
        local test_width = font:width("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz", size)
        local avg_width = test_width / 52
        local chars_per_line = width / avg_width
        return floor(chars_per_line)
    end

    local rows = {}
    local function flush_table()
        local max_w = {}
        for ri = 1, #rows do
            local row = rows[ri]
            for ci = 1, #row do
                local col = row[ci]
                max_w[ci] = max(max_w[ci] or 0, col.width)
            end
        end

        local TABLE_SEPARATE = 40

        for ri = 1, #rows do
            local row = rows[ri]
            local x = 0
            for ci = 1, #row do
                local col = row[ci]
                if col.text ~= "" then
                    col.x = floor(x)
                    col.y = floor(y)
                    writes[#writes+1] = col
                end
                x = x + max_w[ci]+cell_padding
            end
            y = y + default_font_size * line_height
            max_x = max(max_x, x-cell_padding)
        end
        rows = {}
    end

    local function add_row()
        local cols = {}
        rows[#rows+1] = cols
        return cols
    end

    local function layout_paragraph(paragraph)
        for line in string.gmatch(paragraph, "[^\n]+") do
            local size = default_font_size -- font size for line
            local maxl = max_per_line(font, size, width)

            if line:find "|" then
                -- table row
                local cols = add_row()
                for field in line:gmatch("[^|]+") do
                    field = helper.trim(field)
                    local width = font:width(field, size)
                    cols[#cols+1] = {
                        font = font,
                        text = field,
                        size = size,
                        width = width,
                    }
                end
            else
                -- plain text, wrapped
                flush_table()

                -- markdown header # and ##
                if line:sub(1,2) == "##" then
                    line = line:sub(3)
                    font = font
                    size = h2_font_size
                    maxl = max_per_line(font, size, width)
                elseif line:sub(1,1) == "#" then
                    line = line:sub(2)
                    font = font
                    size = h1_font_size
                    maxl = max_per_line(font, size, width)
                end

                local chunks = helper.wrap(line, maxl)
                for idx = 1, #chunks do
                    local chunk = chunks[idx]
                    chunk = helper.trim(chunk)
                    writes[#writes+1] = {
                        font = font,
                        x = 0,
                        y = floor(y),
                        text = chunk,
                        size = size,
                    }
                    local width = font:width(chunk, size)
                    y = y + size * line_height
                    max_x = max(max_x, width)
                end
            end
        end

        flush_table()
    end

    local paragraphs = helper.split(text, "\n\n")
    for idx = 1, #paragraphs do
        local paragraph = paragraphs[idx]
        paragraph = paragraph:gsub("\t", " ")
        layout_paragraph(paragraph)
        y = y + paragraph_split
    end

    -- remove one split
    local max_y = y - paragraph_split
    local base_x, base_y

    if align == "tl" then
        base_x = 0
        base_y = 0
    elseif align == "center" then
        base_x = floor((width-max_x) / 2)
        base_y = floor((height-max_y) / 2)
    end

    return function(starts, ends)
        for now in helper.frame_between(starts, ends) do
            local x = x1 + base_x
            local y = y1 + base_y
            for idx = 1, #writes do
                local w = writes[idx]
                w.font:write(x+w.x, y+w.y, w.text, w.size, r,g,b,helper.ramp(
                    starts, ends, now, fade_time
                ))
            end
        end
    end
end

local function JobQueue()
    local jobs = {}

    local function add(fn, starts, ends)
        local co = coroutine.create(fn)
        local ok, again = coroutine.resume(co, starts, ends)
        if not ok then
            log(
                "jobqueue",
                "cannot create task:\n%s\n%s\ninside coroutine started by",
                again, debug.traceback(co)
            )
        elseif not again then
            return
        end

        local job = {
            starts = starts,
            ends = ends,
            co = co,
        }

        jobs[#jobs+1] = job
    end

    local function tick(now)
        for idx, job in ipairs(jobs) do
            local ok, again = coroutine.resume(job.co, now)
            if not ok then
                log(
                    "jobqueue",
                    "cannot run task:\n%s\n%s\ninside coroutine %s resumed by",
                    again, debug.traceback(job.co), job
                )
                job.done = true
            elseif not again then
                job.done = true
            end
        end

        -- iterate backwards so we can remove finished jobs
        for idx = #jobs,1,-1 do
            local job = jobs[idx]
            if job.done then
                table.remove(jobs, idx)
            end
        end
    end

    local function flush()
        jobs = {}
        node.gc()
    end

    return {
        tick = tick;
        add = add;
        flush = flush;
    }
end

local layouts = {}
local background = {r = 0, g = 0, b = 0, a = 0}
node.event("config_updated", function(config)
    layouts = config.layouts
    for _, layout in ipairs(layouts) do
        for _, tile in ipairs(layout.tiles) do
            local asset = tile.asset
            if asset.type == "image" or asset.type == "video" then
                log("config_updated", "fixing layout asset %s", asset.asset_name)
                asset.asset_name = resource.open_file(asset.asset_name)
            end
        end
    end
    background = config.background
end)

local function Page(page)
    local function get_duration(mode)
        local duration = page.duration
        if duration == 0 then
            duration = page.auto_duration
        end
        if mode == "interactive" and page.interaction.duration == "forever" then
            duration = 100000000
        end
        return duration
    end

    local function get_tiles()
        local tiles = {}

        local function append_page_tiles()
            for _, tile in ipairs(page.tiles) do
                tiles[#tiles+1] = tile
            end
        end

        if page.layout_id == -1 then
            append_page_tiles()
        else
            local layout = layouts[page.layout_id+1]
            for _, tile in ipairs(layout.tiles) do
                if tile.type == "page" then
                    append_page_tiles()
                else
                    tiles[#tiles+1] = tile
                end
            end
        end
        return tiles
    end

    return {
        get_duration = get_duration;
        get_tiles = get_tiles;
        is_fallback = page.is_fallback;
    }
end

local function Scheduler(page_source, job_queue)
    local SCHEDULE_LOOKAHEAD = 2

    local scheduled_until = sys.now()
    local next_schedule = 0
    local showing_fallback = false

    local function enqueue_page(page, duration)
        duration = duration or page.get_duration()
        local tiles = page.get_tiles()

        for _, tile in ipairs(tiles) do
            local handler = ({
                image = ImageTile,
                video = VideoTile,
                rawvideo = RawVideoTile,
                stream = StreamTile,
                child = ChildTile,
                flat = FlatTile,
                markup = MarkupTile,
            })[tile.type]

            -- print "adding tile"
            job_queue.add(
                handler(tile.asset, tile.config, tile.x1, tile.y1, tile.x2, tile.y2),
                scheduled_until,
                scheduled_until + duration
            )
        end

        scheduled_until = scheduled_until + duration
        next_schedule = scheduled_until - SCHEDULE_LOOKAHEAD
        showing_fallback = page.is_fallback

        tcp_clients.send(
            "root/__fallback__",
            page.is_fallback and "1" or "0"
        )
        -- print("FALLBACK?", showing_fallback)
    end

    local function tick(now)
        if now < next_schedule then
            return
        end

        enqueue_page(page_source.get_next())
    end

    local function reset_scheduler()
        job_queue.flush()
        scheduled_until = sys.now()
        next_schedule = sys.now()
    end

    local function handle_keyboard(event)
        -- if event.action ~= "down" and event.action ~= "hold" then
        if event.action ~= "down" then
            return
        end

        if event.key == "esc" then
            reset_scheduler()
            return
        end

        if event.key == "left" then
            reset_scheduler()
            enqueue_page(page_source.get_prev())
            return
        end

        if event.key == "right" then
            reset_scheduler()
            enqueue_page(page_source.get_next())
            return
        end

        local page = page_source.find_by_key(event.key)
        if not page then
            return
        end

        local duration = page.get_duration "interactive"

        reset_scheduler()
        enqueue_page(page, duration)
    end

    local function handle_gamepad(event)
        local page = page_source.find_by_key(event.key)
        if not page then
            return
        end

        local duration = page.get_duration "interactive"

        reset_scheduler()
        enqueue_page(page, duration)
    end

    local function handle_gpio(event)
        local page = page_source.find_by_gpio(event.pin)
        if not page then
            return
        end

        local duration = page.get_duration "interactive"

        reset_scheduler()
        enqueue_page(page, duration)
    end

    local function handle_remote_trigger(remote)
        print("remote trigger", remote)
        local page = page_source.find_by_remote(remote)
        if not page then
            return
        end

        local duration = page.get_duration "interactive"

        reset_scheduler()
        enqueue_page(page, duration)
    end

    local function handle_cec(cec_key)
        if cec_key == "left" then
            reset_scheduler()
            enqueue_page(page_source.get_prev())
            return
        end

        if cec_key == "right" then
            reset_scheduler()
            enqueue_page(page_source.get_next())
            return
        end
    end

    return {
        tick = tick;
        handle_keyboard = handle_keyboard;
        handle_gamepad = handle_gamepad;
        handle_gpio = handle_gpio;
        handle_remote_trigger = handle_remote_trigger;
        handle_cec = handle_cec;
    }
end

local function PageSource(clock)
    local schedules = {}

    local cycle_pages = {}
    local cycle_offset = 0

    local fallback
    local debug_schedule_id, debug_page_id

    node.event("config_updated", function(config)
        schedules = config.schedules

        for _, schedule in ipairs(schedules) do
            for page_id = #schedule.pages, 1, -1 do
                local page = schedule.pages[page_id]
                page.is_fallback = false
                if page.duration == -1 then
                    -- disabled page? then remove it
                    table.remove(schedule.pages, page_id)
                else
                    for _, tile in ipairs(page.tiles) do
                        local asset = tile.asset
                        if asset.type == "image" or asset.type == "video" then
                            log("config_updated", "fixing schedule asset %s", asset.asset_name)
                            asset.asset_name = resource.open_file(asset.asset_name)
                        end
                    end
                end
            end
        end

        debug_schedule_id = config.scratch.debug_schedule_id
        debug_page_id = config.scratch.debug_page_id
        fallback = config.fallback
    end)

    local function date_within(starts, ends, test)
        local function expand(date)
            return date.year * 600 + date.month * 40 + date.day
        end
        local t = expand(test)
        local s = 0
        if starts then
            s = expand(starts)
        end
        local e = 100000000
        if ends then
            e = expand(ends)
        end
        return t >= s and t <= e
    end

    local function parse_date(d)
        if not d then
            return nil
        end
        local year, month, day = d:match "(%d+)-(%d+)-(%d+)"
        if not year then
            return nil
        end
        return {year=tonumber(year), month=tonumber(month), day=tonumber(day)}
    end

    local function parse_hour(h)
        local hour, minute = h:match "(%d+):(%d+)"
        return {hour=tonumber(hour), minute=tonumber(minute)}
    end

    local function minutes_since_midnight(t)
        return t.hour * 60 + t.minute
    end

    local function is_scheduled(schedule)
        local scheduling = schedule.scheduling
        local mode = scheduling.mode or "span"
        local starts = parse_date(scheduling.starts)
        local ends = parse_date(scheduling.ends)

        if not clock.has_time() then
            if starts or ends then
                log("schedule", "no current time. can't schedule playlist with start/end date")
                return false
            end
            if mode == "hour" then
                local hours = scheduling.hours or {}
                for hour = 1, 24*7+1 do
                    -- see if all hours are unchecked. If any is checked,
                    -- we can't schedule as we need to know the current
                    -- hour.
                    if hours[hour+1] == false then
                        log("schedule", "no current time. can't schedule hour based playlist")
                        return false
                    end
                end
            elseif mode == "span" then
                local spans = scheduling.spans or {}
                -- If a timestamp is set, we can't schedule.
                if #spans > 0 then
                    log("schedule", "no current time. can't schedule span scheduled playlist")
                    return false
                end
            end
            log("schedule", "scheduling although we don't have a correct time as schedule is always active")
            return true
        end

        local today = clock.today()

        if not date_within(starts, ends, today) then
            log("schedule", "outside of scheduled dates. can't schedule")
            return false
        end

        if mode == "hour" then
            local current_hour = clock.week_hour()
            local hours = scheduling.hours or {}
            if hours[current_hour+1] == false then
                -- only refuse to schedule if it's actually set to 'false'.
                -- nil means that the hours list is empty which implicitly
                -- means: "always show".
                log("schedule", "not within the current week hour. can't schedule")
                return false
            else
                return true
            end
        elseif mode == "span" then
            local spans = scheduling.spans or {}

            if #spans == 0 then
                log("schedule", "no spans. always schedule")
                return true
            end

            local since_midnight = clock.since_midnight()
            for span_id, span in ipairs(spans) do
                local dow = clock.day_of_week()
                if span.days[dow+1] then
                    local start_sec = minutes_since_midnight(parse_hour(span.starts)) * 60
                    local end_sec = minutes_since_midnight(parse_hour(span.ends)) * 60 + 60
                    if since_midnight >= start_sec and since_midnight < end_sec then
                        log("schedule", "span %s matches", span_id)
                        return true
                    end
                end
            end
            return false
        end
    end

    local function get_scheduled_pages()
        local pages = {}
        for schedule_id, schedule in ipairs(schedules) do
            log("schedule", "checking schedule %s (%d)", schedule.name, schedule_id)
            if is_scheduled(schedule) and #schedule.pages > 0 then
                local display_mode = schedule.display_mode or "all"
                if display_mode == "all" then
                    log("schedule", "adding all pages")
                    for p = 1, #schedule.pages do
                        pages[#pages+1] = Page(schedule.pages[p])
                    end
                else -- random-1
                    log("schedule", "selecting a random page")
                    local random_page = math.random(1, #schedule.pages)
                    pages[#pages+1] = Page(schedule.pages[random_page])
                end
            end
        end
        return pages
    end

    local function get_page(schedule_id, page_id)
        local schedule = schedules[schedule_id]
        if not schedule then
            return
        end

        local page = schedule.pages[page_id]
        if not page then
            return
        end

        return Page(page)
    end

    local function find_by_key(key)
        for schedule_id, schedule in ipairs(schedules) do
            for page_id, page in ipairs(schedule.pages) do
                if page.interaction.key == key then
                    return Page(page)
                end
            end
        end
    end

    local function find_by_gpio(pin)
        local key = string.format("gpio_%d", pin)
        for schedule_id, schedule in ipairs(schedules) do
            for page_id, page in ipairs(schedule.pages) do
                if page.interaction.key == key then
                    return Page(page)
                end
            end
        end
    end

    local function find_by_remote(remote)
        for schedule_id, schedule in ipairs(schedules) do
            for page_id, page in ipairs(schedule.pages) do
                if page.interaction.key == 'remote' and page.interaction.remote == remote then
                    return Page(page)
                end
            end
        end
    end

    local function get_debug_page()
        if debug_schedule_id and debug_page_id then
            return get_page(debug_schedule_id+1, debug_page_id+1)
        end
    end

    local function get_fallback_cycle()
        return {Page{
            is_fallback = true,
            duration = 5,
            auto_duration = 5,
            layout_id = -1,
            overlap = 0,
            tiles = {{
                x1 = 0,
                y1 = 0,
                x2 = WIDTH,
                y2 = HEIGHT,
                asset = fallback,
                type = 'image',
                config = {
                    fit = true,
                }
            }}
        }}
    end

    local function generate_cycle()
        local debug_page = get_debug_page()

        if debug_page then
            cycle_pages = {debug_page}
        else
            cycle_pages = get_scheduled_pages()
        end

        if #cycle_pages == 0 then
            log("generate_cycle", "no scheduled pages. using fallback")
            cycle_pages = get_fallback_cycle()
        end

        log("generate_cycle", "generated cycle with %d pages", #cycle_pages)
    end

    local function get_prev()
        cycle_offset = cycle_offset - 1
        if cycle_offset < 1 then
            generate_cycle()
            cycle_offset = #cycle_pages
        end
        return cycle_pages[cycle_offset]
    end

    local function get_next()
        cycle_offset = cycle_offset + 1
        if cycle_offset > #cycle_pages then
            generate_cycle()
            cycle_offset = 1
        end
        return cycle_pages[cycle_offset]
    end

    return {
        get_prev = get_prev;
        get_next = get_next;
        get_page = get_page;
        find_by_key = find_by_key;
        find_by_gpio = find_by_gpio;
        find_by_remote = find_by_remote;
    }
end

local page_source = PageSource(clock)
local job_queue = JobQueue()
local scheduler = Scheduler(page_source, job_queue)

util.json_watch("config.json", function(config)
    node.dispatch("config_updated", config)
    node.gc()
end)

util.data_mapper{
    ["event/keyboard"] = function(raw_event)
        local event = json.decode(raw_event)
        dispatch_to_all_tiles("on_keyboard", event)
        return scheduler.handle_keyboard(event)
    end,
    ["event/pad"] = function(raw_event)
        local event = json.decode(raw_event)
        dispatch_to_all_tiles("on_pad", event)
        return scheduler.handle_gamepad(event)
    end,
    ["event/gpio"] = function(raw_event)
        local event = json.decode(raw_event)
        dispatch_to_all_tiles("on_gpio", event)
        return scheduler.handle_gpio(event)
    end,
    ["remote/trigger"] = function(data)
        return scheduler.handle_remote_trigger(data)
    end,
    ["sys/cec/key"] = scheduler.handle_cec,
}

function node.render()
    FontCache.tick()
    ImageCache.tick()
    screen.setup()

    gl.clear(background.r, background.g, background.b, background.a)

    local now = sys.now()
    scheduler.tick(now)

    dispatch_to_all_tiles("each_frame")

    -- local fov = math.atan2(HEIGHT, WIDTH*2) * 360 / math.pi
    -- gl.perspective(fov, WIDTH/2, HEIGHT/2, -WIDTH,
    --                     WIDTH/2, HEIGHT/2, 0)

    job_queue.tick(now)
end
