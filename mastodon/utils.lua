local M = {}

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

function M.cycled(items, offset)
    offset = offset % #items + 1
    return items[offset], offset
end

function M.easeInOut(t, b, c)
    c = c - b
    return -c * math.cos(t * (math.pi/2)) + c + b;
end

return M
