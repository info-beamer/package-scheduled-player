local api, CHILDS, CONTENTS, PATH = ...

local md5 = require "md5"
local json = require "json"

local M = {}

local fallback = resource.create_colored_texture(1,1,1,1)

function M.task(starts, ends, config, x1, y1, x2, y2)
    local url = config.url or ""
    local selector = config.selector or ""
    local scale = config.scale or 100
    local max_age = config.max_age or 180
    local condition = config.condition or "networkidle2"

    local width = x2 - x1
    local height = y2 - y1

    if selector ~= "" then
        -- selector set? Then render with full width as
        -- the returned image doesn't satisfy the requested
        -- width/height anyway.
        width = 1920
        height = 1080
    end

    local localfile = "browser-" .. md5.sumhexa(string.format(
        "%s:%s:%d:%d:%d", url, selector, width, height, scale
    ))

    api.tcp_clients.send(PATH, json.encode{
        url = url;
        max_age = max_age,
        selector = selector;
        target = localfile;
        width = width,
        height = height,
        scale = scale,
        condition = condition,
    })
    local ok, img = pcall(resource.load_image, api.localized(localfile))
    if not ok then
        img = fallback
    end

    api.wait_t(starts - 2)

    for now in api.frame_between(starts, ends) do
        if img == fallback then
            img:draw(x1, y1, x2, y2)
        else
            util.draw_correct(img, x1, y1, x2, y2)
        end
    end

    if img ~= fallback then
        img:dispose()
    end
end

return M
