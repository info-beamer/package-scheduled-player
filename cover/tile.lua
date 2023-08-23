local api, CHILDS, CONTENTS, PATH = ...

local M = {}

local cover = resource.create_colored_texture(0,0,0,1)
local easing = require "easing"

local function Transition(from, to, duration)
    local starts = sys.now()
    local ends = starts + duration

    return function()
        local offset = sys.now() - starts
        local progress = 1.0 / duration * offset
        progress = math.max(0, math.min(1, progress))
        local eased = easing.inOutQuad(progress, 0, 1, 1)
        return from + eased * (to - from)
    end;
end

local alpha = Transition(0, 0, 1)

function M.data_trigger(path, data)
    if path == "alpha" then
        local new_alpha, duration = data:match "([^,]+),([^,]+)"
        alpha = Transition(alpha(), tonumber(new_alpha), tonumber(duration))
    end
end

function M.task(starts, ends, config, x1, y1, x2, y2)
    for now in api.frame_between(starts, ends) do
        if alpha() > 0 then
            cover:draw(x1, y1, x2, y2, alpha())
        end
    end
end

return M
