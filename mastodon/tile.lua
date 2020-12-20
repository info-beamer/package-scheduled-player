local api, CHILDS, CONTENTS = ...

local json = require "json"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local show_logo = true
local char_per_sec = 7
local include_in_scroller = true
local shading
local toot_color, profile_color
local font
local font_size
local margin = 10
local text_over_under
local profile_over_under
local logo = resource.load_image{
    file = api.localized "mastodon-logo.png"
}

local playlist = {}

local M = {}

local function wrap(str, font, size, max_w)
    local lines = {}
    local space_w = font:width(" ", size)

    local remaining = max_w
    local line = {}
    for non_space in str:gmatch("%S+") do
        local w = font:width(non_space, size)
        if remaining - w < 0 then
            lines[#lines+1] = table.concat(line, "")
            line = {}
            remaining = max_w
        end
        line[#line+1] = non_space
        line[#line+1] = " "
        remaining = remaining - w - space_w
    end
    if #line > 0 then
        lines[#lines+1] = table.concat(line, "")
    end
    return lines
end

function M.updated_tootlist_json(toots)
    playlist = {}

    local scroller = {}
    for idx = 1, #toots do
        local toot = toots[idx]

        local ok, profile, image

        ok, profile = pcall(resource.open_file, api.localized(toot.account.avatar_static))
        if not ok then
            print("cannot use this toot. profile image missing", profile)
            profile = nil
        end

        if toot.media_attachment ~= '' then
            -- TODO: load more than only the first image
            ok, image = pcall(resource.open_file, api.localized(toot.media_attachment))
            if not ok then
                print("cannot open image", image)
                image = nil
            end
        end

        if profile then
            playlist[#playlist+1] = {
                acct = toot.account.acct,
                display_name = toot.account.display_name,
                text = toot.content,
                profile = profile,
                image = image,
                created_at = toot.created_at,
            }
            print("toot created at" .. toot.created_at)
            if include_in_scroller then
                scroller[#scroller+1] = {
                    text = "@" .. toot.account.acct .. ": " .. toot.content,
                    image = profile,
                }
            end
        end
    end

    api.update_data("scroller", scroller)
end

function M.updated_config_json(config)
    print "config updated"

    include_in_scroller = config.include_in_scroller
    show_logo = config.show_logo
    font = resource.load_font(api.localized(config.font.asset_name))
    toot_color = config.toot_color
    profile_color = config.profile_color
    font_size = config.font_size
    margin = config.margin
    text_over_under = config.text_over_under
    profile_over_under = config.profile_over_under

    if config.shading > 0.0 then
        shading = resource.create_colored_texture(0,0,0,config.shading)
    else
        shading = nil
    end

    node.gc()
end

local toot_gen = util.generator(function()
    return playlist
end)

function M.task(starts, ends, config, x1, y1, x2, y2)
    local boundingbox_height = y2-y1
    local boundingbox_width = x2-x1

    print("ACTUAL SCREEN SIZE " .. boundingbox_width .. "x" .. boundingbox_height)

    local toot = toot_gen.next()

    local profile = resource.load_image{
        file = toot.profile:copy(),
        mipmap = true,
    }

    api.wait_t(starts-2.5)

    local image, video

    if toot.image then
        image = resource.load_image{
            file = toot.image:copy(),
        }
    end
    api.wait_t(starts-0.3)

    local age = api.clock.unix() - toot.created_at
    if age < 100 then
        age = string.format("%ds", age)
    elseif age < 3600 then
        age = string.format("%dm", age/60)
    elseif age < 86400 then
        age = string.format("%dh", age/3600)
    else
        age = string.format("%dd", age/86400)
    end

    local a = anims.Area(boundingbox_width, boundingbox_height)

    local S = starts
    local E = ends

    local function mk_profile_box(x, y)
        local name = toot.acct
        if toot.display_name ~= '' then
            name = toot.display_name
        end
        local info = "@"..toot.acct..", "..age.." ago"

        local profile_image_size = font_size*1.6

        if shading then
            local profile_width = math.max(
                font:width(name, font_size),
                font:width(info, font_size*0.6)
            )
            a.add(anims.moving_image_raw(S,E, shading,
                x, y, x+profile_image_size+profile_width+2*margin+10, y+profile_image_size+2*margin+5, 1
            ))
        end
        a.add(anims.moving_font(S, E, font, x+profile_image_size+10+margin, y+margin, name, font_size,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a
        ))
        a.add(anims.moving_font(S, E, font, x+profile_image_size+10+margin, y+font_size+5+margin, info, font_size*0.6,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a*0.8
        )); S=S+0.1;
        -- a.add(anims.toot_profile(S, E, x+margin, y+margin, profile, 120))
        a.add(anims.moving_image_raw(S,E, profile,
            x+margin, y+margin, x+margin+profile_image_size+5, y+margin+profile_image_size+5, 1
        ))
    end

    local lines = wrap(
        toot.text, font, font_size, boundingbox_width-2*margin
    )

    local function mk_content_box(x, y)
        if shading then
            local text_width = 0
            for idx = 1, #lines do
                local line = lines[idx]
                text_width = math.max(text_width, font:width(line, font_size))
            end
            a.add(anims.moving_image_raw(S,E, shading,
                x, y, x+text_width+2*margin, y+#lines*font_size+2*margin, 1
            ))
        end
        y = y + margin
        for idx = 1, #lines do
            local line = lines[idx]
            a.add(anims.moving_font(S, E, font, x+margin, y, line, font_size,
                toot_color.r, toot_color.g, toot_color.b, toot_color.a
            )); S=S+0.1; y=y+font_size
        end
    end

    local obj = image
    local text_height = #lines*font_size + 2*margin
    local profile_height = font_size*1.6 + 2*margin

    print(boundingbox_width, boundingbox_height, text_height, text_over_under)

    if obj then
        local width, height = obj:size()
        print("ASSET SIZE", width, height, obj)
        local remaining_height_for_image = boundingbox_height
        local profile_y

        if text_over_under == "under" then
            remaining_height_for_image = remaining_height_for_image - text_height - margin
        end

        if profile_over_under == "under" or profile_over_under == "over" then
            remaining_height_for_image = remaining_height_for_image - profile_height - margin
        end

        local x1, y1, x2, y2 = util.scale_into(boundingbox_width, remaining_height_for_image, width, height)

        if profile_over_under == "over" then
            y1 = y1 + profile_height + margin
            y2 = y2 + profile_height + margin
        end

        print(x1, y1, x2, y2)
        a.add(anims.moving_image_raw(S,E, obj,
            x1, y1, x2, y2, 1
        ))
        mk_content_box(0, boundingbox_height - text_height)

        if profile_over_under == "under" then
            profile_y = boundingbox_height - text_height - profile_height - margin
        elseif profile_over_under == "over" then
            profile_y = 0
        else
            profile_y = 10
        end

        mk_profile_box(0, profile_y)
    else
        local text_y = math.min(
            math.max(
                font_size*1.6+3*margin,
                130
            ),
            boundingbox_height-text_height
        )
        mk_content_box(0, text_y)
        mk_profile_box(0, 0)
    end

    if show_logo then
        a.add(anims.logo(S, E, boundingbox_width-130, boundingbox_height-130, logo, 100))
    end

    for now in api.frame_between(starts, ends) do
        a.draw(now, x1, y1, x2, y2)
    end

    profile:dispose()

    if image then
        image:dispose()
    end
end

return M
