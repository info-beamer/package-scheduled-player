local api, CHILDS, CONTENTS, PATH = ...

local md5 = require "md5"
local json = require "json"

local M = {}

local fallback = resource.create_colored_texture(1,1,1,1)

local function Snapshot(filename)
    local fullpath = api.localized(filename)

    local cur, cur_version = fallback, nil
    local nxt, nxt_version

    local function check_reload()
        local fs_version = CONTENTS[fullpath]
        if not fs_version then
            -- no snapshot to load available
            return
        end

        if cur_version == fs_version then
            -- already loaded up-to-date version
            return
        end

        if nxt then
            local state = nxt:state() 
            if state == "loaded" then
                if cur ~= fallback then
                    cur:dispose()
                end
                cur, cur_version = nxt, nxt_version
                nxt, nxt_version = nil, nil
                print("loading", fullpath, "complete. version", cur_version)
            elseif state == "error" then
                nxt:dispose()
                cur, cur_version = fallback, nxt_version
                nxt, nxt_version = nil, nil
                print("loading", fullpath, "failed. using fallback")
            end
        end

        if fs_version ~= cur_version then
            if nxt_version and nxt_version == fs_version then
                -- already loading
                return
            end

            if nxt then
                print("abort current loading process")
                nxt:dispose()
                nxt, nxt_version = nil, nil
            end

            local ok
            ok, nxt = pcall(resource.load_image, fullpath)
            if not ok then
                print("cannot open snapshot", nxt)
                nxt, nxt_version = nil, nil
                return
            end
            nxt_version = fs_version
            print("now loading", fullpath, fs_version)
        end
    end

    local function draw(x1, y1, x2, y2)
        check_reload()

        if cur == fallback then
            cur:draw(x1, y1, x2, y2)
        else
            util.draw_correct(cur, x1, y1, x2, y2)
        end
    end

    local function dispose()
        if nxt then
            nxt:dispose()
            nxt = nil
        end
        if cur ~= fallback then
            cur:dispose()
            cur = nil
        end
    end

    return {
        check_reload = check_reload,
        draw = draw,
        dispose = dispose,
    }
end

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

    local snapshot_filename = "browser-" .. md5.sumhexa(string.format(
        "%s:%s:%d:%d:%d:%s", url, selector, width, height, scale, condition
    ))

    api.tcp_clients.send(PATH, json.encode{
        target = snapshot_filename,
        url = url,
        max_age = max_age,
        selector = selector,
        width = width,
        height = height,
        scale = scale,
        condition = condition,
    })

    local snapshot = Snapshot(snapshot_filename)

    api.wait_t(starts - 2)
    snapshot.check_reload()

    api.wait_t(starts - 1)
    snapshot.check_reload()

    for now in api.frame_between(starts, ends) do
        snapshot.draw(x1, y1, x2, y2)
    end

    snapshot.dispose()
end

return M
