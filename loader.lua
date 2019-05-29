assert(sys.provides "nested-nodes", "nested nodes feature missing")

local GLOBAL_CONTENTS, GLOBAL_CHILDS = node.make_nested()
local json = require "json"

local function setup(module_name)
    local M = {}

    local modules = {}
    local modules_content_versions = {}

    local function log(msg)
        print(string.format("MODULE[%s]: %s", module_name, msg))
    end

    local function event_handler(child, event_name)
        if not modules[child] then
            return
        end
        return modules[child][event_name]
    end

    local function module_event(child, event_name, content, ...)
        if not modules[child] then
            return
        end
        local handler = event_handler(child, event_name)
        if handler then
            -- print('-> event', event_name, content)
            return handler(content, ...)
        end
    end

    local function module_unload(child)
        log(child .. " is unloading")
        for content, version in pairs(modules_content_versions[child]) do
            module_event(child, 'content_remove', content)
        end
        module_event(child, 'unload')
        modules[child] = nil
        M.unload(child)
        node.gc()
    end

    local function content_update_event(child, content, obj)
        log(string.format("%s/%s updated", child, content))
        if content:sub(-5) == ".json" then
            local event_name = "updated_" .. content:gsub("[.]", "_")
            local handler = event_handler(child, event_name)
            if handler then
                local data = json.decode(resource.load_file(
                    obj and obj:copy() or (child .. "/" .. content)
                ))
                module_event(child, event_name, data)
            end
        end
        return module_event(child, 'content_update', content)
    end

    local function module_load(child, module_func)
        if modules[child] then
            log("about to replace ".. child)
            module_unload(child)
        end
        log("loading ".. child)
        local api = {}

        -- prepare exported API
        api.localized = function(name)
            return child .. "/" .. name
        end

        api.pinned_asset = function(asset)
            log("localizing asset " .. asset.asset_name)
            asset.file = resource.open_file(child .. "/" .. asset.asset_name)
            return asset
        end

        M.before_load(child, api)

        local module = module_func(
            api,
            GLOBAL_CHILDS[child],
            GLOBAL_CONTENTS[child],
            PATH .. "/" .. child
        )
        modules[child] = module
        module_event(child, 'load')

        local contents = {}
        for content, version in pairs(modules_content_versions[child]) do
            contents[#contents+1] = content
        end
        table.sort(contents)
        for n, content in ipairs(contents) do
            content_update_event(child, content)
        end
        node.gc()
    end

    local function module_update_content(child, content, version, obj)
        local mcv = modules_content_versions[child]
        if not mcv[content] or mcv[content] < version then
            mcv[content] = version
            return content_update_event(child, content, obj)
        end
    end

    local function module_delete_content(child, content)
        local mcv = modules_content_versions[child]
        modules_content_versions[child][content] = nil
        return module_event(child, 'content_remove', content)
    end

    node.event("child_add", function(child)
        modules_content_versions[child] = {}
    end)

    node.event("child_remove", function(child)
        modules_content_versions[child] = nil
    end)

    node.event("content_update", function(name, obj)
        local child, content = util.splitpath(name)

        if child == '' then -- not interested in top level events
            return
        elseif content == module_name then
            return module_load(child, assert(
                loadstring(resource.load_file(obj), "=" .. name)
            ))
        else
            return module_update_content(child, content, GLOBAL_CONTENTS[child][name], obj)
        end
    end)

    node.event("content_remove", function(name)
        local child, content = util.splitpath(name)

        if child == '' then -- not interested in top level events
            return
        elseif content == module_name then
            return module_unload(child)
        else
            return module_delete_content(child, content)
        end
    end)

    M.modules = modules
    M.before_load = function() end
    M.unload = function() end

    return M
end

return {
    setup = setup;
}
