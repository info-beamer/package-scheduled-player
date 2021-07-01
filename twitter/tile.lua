local api, CHILDS, CONTENTS = ...

local json = require "json"
local utf8 = require "utf8"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local show_logo = true
local char_per_sec = 7
local include_in_scroller = true
local shading
local tweet_color, profile_color
local font
local font_size
local margin = 10
local text_over_under
local profile_over_under
local logo = resource.load_image{
    file = api.localized "twitter-logo.png"
}

local playlist = {}

local M = {}

local function wrap(str, font, size, max_w)
    local lines = {}
    local space_w = font:width(" ", size)

    local remaining = max_w
    local line = {}
    local tokens = {}
    for token in utf8.gmatch(str, "%S+") do
        local w = font:width(token, size)
        if w >= max_w then
            while #token > 0 do
                local cut = #token
                for take = 1, #token do
                    local sub_token = utf8.sub(token, 1, take)
                    w = font:width(sub_token, size)
                    if w >= max_w then
                        cut = take-1
                        break
                    end
                end
                tokens[#tokens+1] = utf8.sub(token, 1, cut)
                token = utf8.sub(token, cut+1)
            end
        else
            tokens[#tokens+1] = token
        end
    end
    for _, token in ipairs(tokens) do
        local w = font:width(token, size)
        if remaining - w < 0 then
            lines[#lines+1] = table.concat(line, "")
            line = {}
            remaining = max_w
        end
        line[#line+1] = token
        line[#line+1] = " "
        remaining = remaining - w - space_w
    end
    if #line > 0 then
        lines[#lines+1] = table.concat(line, "")
    end
    return lines
end

function M.updated_tweets_json(tweets)
    playlist = {}

    local scroller = {}
    for idx = 1, #tweets do
        local tweet = tweets[idx]

        local ok, profile, image, video, media_time

        ok, profile = pcall(resource.open_file, api.localized(tweet.profile_image))
        if not ok then
            print("cannot use this tweet. profile image missing", profile)
            profile = nil
        end

        if #tweet.images > 0 then
            -- TODO: load more than only the first image
            ok, image = pcall(resource.open_file, api.localized(tweet.images[1]))
            if not ok then
                print("cannot open image", image)
                image = nil
            end
        end

        if tweet.video then
            ok, video = pcall(resource.open_file, api.localized(tweet.video.filename))
            if ok then
                media_time = tweet.video.duration
            else
                print("cannot open video", video)
                video = nil
            end
        end

        if profile then
            playlist[#playlist+1] = {
                screen_name = tweet.screen_name,
                name = tweet.name,
                text = tweet.text,
                profile = profile,
                image = image,
                video = video,
                media_time = media_time,
                created_at = tweet.created_at,
            }

            if include_in_scroller then
                scroller[#scroller+1] = {
                    text = "@" .. tweet.screen_name .. ": " .. tweet.text,
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
    font = resource.load_font(api.localized(config.font.asset_name))
    tweet_color = config.tweet_color
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

local tweet_gen = util.generator(function()
    return playlist
end)

function M.task(starts, ends, config, x1, y1, x2, y2)
    local boundingbox_height = y2-y1
    local boundingbox_width = x2-x1

    print("ACTUAL SCREEN SIZE " .. boundingbox_width .. "x" .. boundingbox_height)

    local tweet = tweet_gen.next()

    local profile = resource.load_image{
        file = tweet.profile:copy(),
        mipmap = true,
    }

    api.wait_t(starts-2.5)

    local image, video

    if tweet.image then
        image = resource.load_image{
            file = tweet.image:copy(),
            fastload = true,
        }
    end

    if tweet.video then
        video = resource.load_video{
            file = tweet.video:copy(),
            looped = true,
            paused = true,
        }
    end

    api.wait_t(starts-0.3)

    local age = api.clock.unix() - tweet.created_at
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
        local name = tweet.name
        local info = "@"..tweet.screen_name..", "..age.." ago"

        local profile_image_size = font_size*1.6

        if shading then
            local profile_width = math.max(
                font:width(name, font_size),
                font:width(info, font_size*0.6)
            )
            a.add(anims.moving_image_raw(S,E, shading,
                x, y, x+profile_image_size+profile_width+2*margin+20, y+profile_image_size+2*margin+5, 1
            ))
        end
        a.add(anims.moving_font(S, E, font, x+profile_image_size+20+margin, y+margin, name, font_size,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a
        ))
        a.add(anims.moving_font(S, E, font, x+profile_image_size+20+margin, y+font_size+5+margin, info, font_size*0.6,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a*0.8
        )); S=S+0.1;
        -- a.add(anims.tweet_profile(S, E, x+margin, y+margin, profile, 120))
        a.add(anims.moving_image_raw(S,E, profile,
            x+margin, y+margin, x+margin+profile_image_size+5, y+margin+profile_image_size+5, 1
        ))
    end

    local lines = wrap(
        tweet.text, font, font_size, boundingbox_width-2*margin
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
                tweet_color.r, tweet_color.g, tweet_color.b, tweet_color.a
            )); S=S+0.1; y=y+font_size
        end
    end

    local obj = video or image
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
        a.add(anims.logo(S, E, boundingbox_width-105, boundingbox_height-95, logo, 100))
    end

    for now in api.frame_between(starts, ends) do
        if video then
            video:start()
        end
        a.draw(now, x1, y1, x2, y2)
    end

    profile:dispose()

    if image then
        image:dispose()
    end

    if video then
        video:dispose()
    end
end

return M
