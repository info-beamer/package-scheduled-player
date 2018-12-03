local api, CHILDS, CONTENTS = ...

local font
local weather
local name = ""
local bg = resource.create_colored_texture(0, 0, 0, 0.7)

local M = {}

local function Icons()
    local loaded = {}

    local mapping = {
        Sun=1,
        LightCloud=2,
        PartlyCloud=3,
        Cloud=4,
        LightRainSun=5,
        LightRainThunderSun=6,
        SleetSun=7,
        SnowSun=8,
        LightRain=9,
        Rain=10,
        RainThunder=11,
        Sleet=12,
        Snow=13,
        SnowThunder=14,
        Fog=15,
        SleetSunThunder=20,
        SnowSunThunder=21,
        LightRainThunder=22,
        SleetThunder=23,
        DrizzleThunderSun=24,
        RainThunderSun=25,
        LightSleetThunderSun=26,
        HeavySleetThunderSun=27,
        LightSnowThunderSun=28,
        HeavySnowThunderSun=29,
        DrizzleThunder=30,
        LightSleetThunder=31,
        HeavySleetThunder=32,
        LightSnowThunder=33,
        HeavySnowThunder=34,
        DrizzleSun=40,
        RainSun=41,
        LightSleetSun=42,
        HeavySleetSun=43,
        LightSnowSun=44,
        HeavysnowSun=45,
        Drizzle=46,
        LightSleet=47,
        HeavySleet=48,
        LightSnow=49,
        HeavySnow=50,
    }

    local function get(symbol_name, is_night)
        local is_dark = symbol_name:find("Dark_") == 1
        local symbol
        if is_dark and not is_night then
            symbol = mapping[symbol_name:sub(6)] + 100
        elseif is_night then
            symbol = mapping[symbol_name] + 400
        else
            symbol = mapping[symbol_name]
        end
        if not loaded[symbol] then
            local ok, image = pcall(resource.load_image, api.localized(string.format(
                "icon-%03d.png", symbol
            )))
            if ok then
                print("loaded weather symbol", symbol)
            else
                image = resource.create_colored_texture(0,0,0,0)
            end
            loaded[symbol] = {
                lru = sys.now(),
                img = image,
            }
        end
        local icon = loaded[symbol]
        icon.lru = sys.now()
        return icon.img
    end

    local function flush(max_age)
        max_age = max_age or 60
        for symbol, icon in pairs(loaded) do
            if icon.lru + max_age < sys.now() then
                icon.img:dispose()
                loaded[symbol] = nil
            end
        end
    end

    return {
        get = get,
        flush = flush,
    }
end

local icons = Icons()

function M.updated_config_json(config)
    font = resource.load_font(api.localized(config.font.asset_name))
    name = config.name:gsub("^(.*) %(.*", "%1")
end

function M.updated_weather_json(new_weather)
    weather = new_weather
    -- for offset, info in ipairs(weather.next_24) do
    --     info.temp = info.temp * math.sin(offset/12*math.pi)
    -- end
end

local color_shader = resource.create_shader[[
    uniform vec4 color;
    void main() {
        gl_FragColor = color;
    }
]]

local function centered(x, y, text, size, r,g,b,a)
    local w = font:width(text, size)
    return font:write(x-w/2, y, text, size, r,g,b,a)
end

local function min_max(a, b)
    return math.min(a, b), math.max(a, b)
end

local function clamp(a, b, v)
    return math.max(a, math.min(b, v))
end

local function convert_temp(temp, temp_mode)
    if temp_mode == "celsius" then
        return temp
    else
        return temp * 9 / 5 + 32
    end
end

local function temp_to_string(temp, temp_mode)
    if temp_mode == "celsius" then
        return string.format("%.1f°C", temp)
    else
        return string.format("%.1f°F", convert_temp(temp, temp_mode))
    end
end

local function hour_to_string(hour)
    return string.format("%d:00", hour)
end

local function rgba_bright(r,g,b,a, brightness)
    return {
        r*brightness,
        g*brightness,
        b*brightness,
        a,
    }
end

local function current_line(starts, ends, config, x1, y1, x2, y2)
    local temp_mode = config.temp or "celsius"

    local w = x2 - x1
    local h = y2 - y1
            
    local header_size = math.floor(h)

    for now in api.frame_between(starts, ends) do
        if name ~= "" then
            font:write(x1, y1, name, header_size, 1,1,1,1)
        end
        local current_temp = temp_to_string(weather.next_24[1].temp, temp_mode)
        local w = font:width(current_temp, header_size)
        font:write(x2-w-3, y1, current_temp, header_size, 1,1,1,1)
    end
end

local function forecast_7(starts, ends, config, x1, y1, x2, y2)
    local temp_mode = config.temp or "celsius"

    local w = x2 - x1
    local h = y2 - y1

    local w_7 = w/7
    local label_size = math.floor(w_7/4)

    local days = ({
        en = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"},
        de = {"Mo",  "Di",  "Mi",  "Do",  "Fr",  "Sa",  "So"},
    })[config.locale or "en"]

    for now in api.frame_between(starts, ends) do
        for offset, info in ipairs(weather.next_7) do
            local x = x1 + w_7 * (offset-1)

            bg:draw(x+2, y1, x+w_7-2, y2)
            centered(x+w_7/2, y1 + label_size*0.25, days[info.time.dow+1], label_size*1.5, 1,1,1,1)

            centered(x+w_7/2, y2 - label_size*2.8, temp_to_string(info.max, temp_mode), label_size, .9,.7,.3,.9)
            centered(x+w_7/2, y2 - label_size*1.5, temp_to_string(info.min, temp_mode), label_size, .5,.5,.5,.9)
        end
    end
end

local function forecast_24(starts, ends, config, x1, y1, x2, y2)
    local temp_mode = config.temp or "celsius"

    local w = x2 - x1
    local h = y2 - y1
    local w_24 = w/25

    local max_temp = -100
    local min_temp = 100
    for offset, info in ipairs(weather.next_24) do
        min_temp = math.min(info.temp, min_temp)
        max_temp = math.max(info.temp, max_temp)
    end


    local grid_size, grid_min, grid_max = 10, 0, 0
    if temp_mode == "fahrenheit" then
        grid_size, grid_min, grid_max = 10, 0, 0
    end
    local graph_min = math.min(grid_min, math.floor((min_temp-grid_size/2)/grid_size)*grid_size)
    local graph_max = math.max(grid_max, math.ceil((max_temp+grid_size/2)/grid_size)*grid_size)

    local spread = graph_max - graph_min
    local function temp_to_graph(temp)
        return (temp - graph_min) / spread
    end

    local label_size = math.floor(w_24/3.5)

    local graph_24_base_y = y2
    local graph_24_height = h
    -- print("GRAPH", graph_min, graph_max)

    local skip = font:width("-xx.x C", label_size)*1.1
    for now in api.frame_between(starts, ends) do
        -- horizontal chart lines
        for temp = graph_min, graph_max, grid_size do
            color_shader:use{color = {1,1,1,.2}}
            local y = graph_24_base_y - temp_to_graph(temp) * graph_24_height
            if temp ~= graph_min and temp ~= graph_max then
                local temp_string = temp_to_string(temp, temp_mode)
                font:write(x1, y-10, temp_string, label_size, 1,1,1,0.7)
                bg:draw(x1+skip, y-1, x2, y+1)
            else
                bg:draw(x1, y-1, x2, y+1)
            end
            color_shader:deactivate()
        end

        -- temperature bars
        for offset, info in ipairs(weather.next_24) do
            local x = x1 + w_24 * offset
            local temp = info.temp
            local bar_top, bar_bottom = min_max(
                graph_24_base_y - temp_to_graph(temp) * graph_24_height,
                graph_24_base_y - temp_to_graph(0) * graph_24_height
            )

            local dark = clamp(0.05, 1, (info.sun / 20) + 0.1)

            if temp < 0 then
                color_shader:use{color = rgba_bright(.2,.75,1,.7, dark)}
            else
                color_shader:use{color = rgba_bright(1,.75,.2,.7, dark)}
            end
            bg:draw(x+.5, bar_top, x+w_24-.5, bar_bottom)
        end
        color_shader:deactivate()

        -- weather icons
        for offset, info in ipairs(weather.next_24) do
            local x = x1 + w_24 * offset
            local temp = info.temp
            local bar_top, bar_bottom = min_max(
                graph_24_base_y - temp_to_graph(temp) * graph_24_height,
                graph_24_base_y - temp_to_graph(0) * graph_24_height
            )

            local is_night = info.sun < 0

            if temp < 0 then
                icons.get(info.symbol, is_night):draw(
                    x, bar_bottom, x+w_24, bar_bottom+w_24
                )
            else
                icons.get(info.symbol, is_night):draw(
                    x, bar_top-w_24, x+w_24, bar_top
                )
            end
        end

        -- precipitation bars
        color_shader:use{color = {.3,.3,1,.4}}
        for offset, info in ipairs(weather.next_24) do
            local x = x1 + w_24 * offset
            local temp = info.temp
            local precip = info.precipitation

            if precip > 0 then
                bg:draw(x+1, graph_24_base_y - precip/20 * graph_24_height, x+w_24-1, graph_24_base_y)
            end
        end
        color_shader:deactivate()

        -- temperature text and time
        for offset, info in ipairs(weather.next_24) do
            local x = x1 + w_24 * offset
            local temp = info.temp
            local bar_top, bar_bottom = min_max(
                graph_24_base_y - temp_to_graph(temp) * graph_24_height,
                graph_24_base_y - temp_to_graph(0) * graph_24_height
            )
            local precip = info.precipitation

            local hour_string = hour_to_string(info.time.hour)
            centered(x+w_24/2, graph_24_base_y-label_size, hour_string, label_size, 1,1,1,1)

            if label_size > 10 and (offset == 1 or offset == 24 or temp == min_temp or temp == max_temp) then
                local temp_string = temp_to_string(temp, temp_mode)
                if temp < 0 then
                    centered(x+w_24/2, bar_bottom-4-label_size, temp_string, label_size, 1,1,1,1)
                else
                    centered(x+w_24/2, bar_top+4, temp_string, label_size, 1,1,1,1)
                end
            end

        end
    end
end


function M.task(starts, ends, config, x1, y1, x2, y2)
    icons.flush(3600)
    return ({
        forecast_24 = forecast_24,
        forecast_7 = forecast_7,
        current_line = current_line,
    })[config.mode or "forecast_24"](starts, ends, config, x1, y1, x2, y2)
end

return M
