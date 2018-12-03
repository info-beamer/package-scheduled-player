local M = {}

local easing = require "easing"

local min, max, abs, floor = math.min, math.max, math.abs, math.floor

function M.in_epsilon(a, b, e)
    return abs(a - b) <= e
end

function M.ramp(t_s, t_e, t_c, ramp_time)
    if ramp_time == 0 then return 1 end
    local delta_s = t_c - t_s
    local delta_e = t_e - t_c
    return min(1, delta_s * 1/ramp_time, delta_e * 1/ramp_time)
end

function M.wait_frame()
    return coroutine.yield(true)
end

function M.wait_t(t)
    local now = sys.now()
    if now >= t then
        return now
    end
    while true do
        local now = M.wait_frame()
        if now >= t then
            return now
        end
    end
end

function M.frame_between(starts, ends)
    return function()
        local now
        while true do
            now = M.wait_frame()
            if now >= starts then
                break
            end
        end
        if now < ends then
            return now
        end
    end
end


function M.mktween(fn)
    return function(sx1, sy1, sx2, sy2, ex1, ey1, ex2, ey2, progress)
        return fn(progress, sx1, ex1-sx1, 1),
               fn(progress, sy1, ey1-sy1, 1),
               fn(progress, sx2, ex2-sx2, 1),
               fn(progress, sy2, ey2-sy2, 1)
    end
end

M.movements = {
    linear = M.mktween(easing.linear),
    smooth = M.mktween(easing.inOutQuint),
}

function M.trim(s)
    return s:match "^%s*(.-)%s*$"
end

function M.split(str, delim)
    local result, pat, last = {}, "(.-)" .. delim .. "()", 1
    for part, pos in string.gmatch(str, pat) do
        result[#result+1] = part
        last = pos
    end
    result[#result+1] = string.sub(str, last)
    return result
end

function M.wrap(str, limit, indent, indent1)
    limit = limit or 72
    local here = 1
    local wrapped = str:gsub("(%s+)()(%S+)()", function(sp, st, word, fi)
        if fi-here > limit then
            here = st
            return "\n"..word
        end
    end)
    local splitted = {}
    for token in string.gmatch(wrapped, "[^\n]+") do
        splitted[#splitted + 1] = token 
    end
    return splitted
end 

function M.parse_rgb(hex)
    hex = hex:gsub("#","")
    return tonumber("0x"..hex:sub(1,2))/255, tonumber("0x"..hex:sub(3,4))/255, tonumber("0x"..hex:sub(5,6))/255
end

return M
