local api, CHILDS, CONTENTS = ...

local json = require "json"
local utils = require(api.localized "utils")
local anims = require(api.localized "anims")

local show_logo = true
local char_per_sec = 7
local include_in_scroller = true
local shading
local tweet_color, profile_color
local font
local margin = 10
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
    show_logo = config.show_logo
    font = resource.load_font(api.localized(config.font.asset_name))
    tweet_color = config.tweet_color
    profile_color = config.profile_color
    margin = config.margin

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

    local a = anims.Area(1920, 1080)

    local S = starts
    local E = ends

    local function mk_profile_box(x, y)
        local name = tweet.name
        local info = "@"..tweet.screen_name..", "..age.." ago"

        if shading then
            local profile_width = math.max(
                font:width(name, 70),
                font:width(info, 40)
            )
            a.add(anims.moving_image_raw(S,E, shading,
                x, y, x+140+profile_width+2*margin, y+80+40+2*margin, 1
            ))
        end
        a.add(anims.moving_font(S, E, font, x+140+margin, y+margin, name, 70,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a
        ))
        a.add(anims.moving_font(S, E, font, x+140+margin, y+75+margin, info, 40,
            profile_color.r, profile_color.g, profile_color.b, profile_color.a*0.8
        )); S=S+0.1;
        -- a.add(anims.tweet_profile(S, E, x+margin, y+margin, profile, 120))
        a.add(anims.moving_image_raw(S,E, profile,
            x+margin, y+margin, x+margin+120, y+margin+120, 1
        ))
    end

    local tweet_size = 80
    local lines = wrap(
        tweet.text, font, tweet_size, x2-x1-2*margin
    )

    local function mk_content_box(x, y)
        if shading then
            local text_width = 0
            for idx = 1, #lines do
                local line = lines[idx]
                text_width = math.max(text_width, font:width(line, tweet_size))
            end
            a.add(anims.moving_image_raw(S,E, shading,
                x, y, x+text_width+2*margin, y+#lines*tweet_size+2*margin, 1
            ))
        end
        y = y + margin
        for idx = 1, #lines do
            local line = lines[idx]
            a.add(anims.moving_font(S, E, font, x+margin, y, line, tweet_size,
                tweet_color.r, tweet_color.g, tweet_color.b, tweet_color.a
            )); S=S+0.1; y=y+tweet_size
        end
    end

    local obj = video or image

    if obj then
        local width, height = obj:size()
        print("ASSET SIZE", width, height, obj)
        local x1, y1, x2, y2 = util.scale_into(1920, 1080, width, height)
        print(x1, y1, x2, y2)
        a.add(anims.moving_image_raw(S,E, obj,
            x1, y1, x2, y2, 1
        ))
        mk_content_box(10, 1080 - #lines * tweet_size - 10 - 2*margin)
        mk_profile_box(10, 10)
    else
        mk_content_box(10, 300)
        mk_profile_box(10, 10)
    end

    if show_logo then
        a.add(anims.logo(S, E, 1920-130, 1080-130, logo, 100))
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
