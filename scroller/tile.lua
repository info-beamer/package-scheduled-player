local api, CHILDS, CONTENTS = ...

local json = require "json"

local font
local color
local speed

local M = {}

-- { source: { text1, text2, text3, ...} }
local content = {__myself__ = {}}

local function mix_content()
    local out = {}
    local offset = 1
    while true do
        local added = false
        for tile, items in pairs(content) do
            if items[offset] then
                out[#out+1] = items[offset]
                added = true
            end
        end
        if not added then
            break
        end
        offset = offset + 1
    end
    return out
end

local feed = util.generator(mix_content).next

api.add_listener("scroller", function(tile, value)
    print("got new scroller content from " .. tile)
    content[tile] = value
end)

local items = {}
local current_left = 0
local last = sys.now()

local function draw_scroller(x, y, w, h)
    local now = sys.now()
    local delta = now - last
    last = now
    local advance = delta * speed

    local idx = 1
    local x = math.floor(current_left+0.5)

    local function prepare_image(obj)
        if not obj then
            return
        end
        local ok, obj_copy = pcall(obj.copy, obj)
        if ok then
            return resource.load_image{
                file = obj_copy,
                mipmap = true,
            }
        else
            return obj
        end
    end

    while x < WIDTH do
        if idx > #items then
            local ok, item = pcall(feed)
            if ok and item then
                items[#items+1] = {
                    text = item.text,
                    image = prepare_image(item.image),
                    color = item.color or color,
                    blink = item.blink,
                }
                items[#items+1] = {
                    text = "    -    ",
                    color = color,
                }
            else
                print "no scroller item. showing blanks"
                items[#items+1] = {
                    text = "                      ",
                    color = color,
                }
            end
        end

        local item = items[idx]

        if item.image then
            local state, img_w, img_h = item.image:state()
            if state == "loaded" then
                local img_max_height = h
                local proportional_width = img_max_height / img_h * img_w
                item.image:draw(x, y, x+proportional_width, y+img_max_height)
                x = x + proportional_width + 30
            end
        end

        local a = item.color.a
        if item.blink then
            a = math.min(1, 1-math.sin(sys.now()*10)) * a
        end
        local text_width = font:write(
            x, y+4, item.text, h-8, 
            item.color.r, item.color.g, item.color.b, a
        )
        x = x + text_width

        if x < 0 then
            assert(idx == 1)
            if item.image then
                item.image:dispose()
            end
            table.remove(items, idx)
            current_left = x
        else
            idx = idx + 1
        end
    end

    current_left = current_left - advance
end

function M.updated_config_json(config)
    font = resource.load_font(api.localized(config.font.asset_name))
    color = config.color
    speed = config.speed

    content.__myself__ = {}
    local items = content.__myself__
    for idx = 1, #config.texts do
        local item = config.texts[idx]
        local color
        if item.color.a ~= 0 then
            color = item.color
        end

        -- 'show' either absent or true?
        if item.show ~= false then
            items[#items+1] = {
                text = item.text,
                blink = item.blink,
                color = color,
            }
        end
    end
    print("configured scroller content")
    pp(items)
end

function M.task(starts, ends, config, x1, y1, x2, y2)
    for now in api.frame_between(starts, ends) do
        api.screen.set_scissor(x1, y1, x2, y2)
        draw_scroller(x1, y1, x2-x1, y2-y1)
        api.screen.set_scissor()
    end
end

return M
