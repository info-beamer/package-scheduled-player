local M = {}

local function make_smooth(timeline)
    assert(#timeline >= 1)

    local function find_span(t)
        local lo, hi = 1, #timeline
        while lo <= hi do
            local mid = math.floor((lo+hi)/2)
            if timeline[mid].t > t then
                hi = mid - 1
            else
                lo = mid + 1
            end
        end
        return math.max(1, lo-1)
    end

    local function get_value(t)
        local t1 = find_span(t)
        local t0 = math.max(1, t1-1)
        local t2 = math.min(#timeline, t1+1)
        local t3 = math.min(#timeline, t1+2)

        local p0 = timeline[t0]
        local p1 = timeline[t1]
        local p2 = timeline[t2]
        local p3 = timeline[t3]

        local v0 = p0.val
        local v1 = p1.val
        local v2 = p2.val
        local v3 = p3.val

        local progress = 0.0
        if p1.t ~= p2.t then
            progress = math.min(1, math.max(0, 1.0 / (p2.t - p1.t) * (t - p1.t)))
        end

        if p1.ease == "linear" then 
            return (v1 * (1-progress) + (v2 * progress)) 
        elseif p1.ease == "step" then
            return v1
        elseif p1.ease == "inout" then
            return -(v2-v1) * progress*(progress-2) + v1
        else
            local d1 = p2.t - p1.t
            local d0 = p1.t - p0.t

            local bias = 0.5
            local tension = 0.8
            local mu = progress
            local mu2 = mu * mu
            local mu3 = mu2 * mu
            local m0 = (v1-v0)*(1+bias)*(1-tension)/2 + (v2-v1)*(1-bias)*(1-tension)/2
            local m1 = (v2-v1)*(1+bias)*(1-tension)/2 + (v3-v2)*(1-bias)*(1-tension)/2

            m0 = m0 * (2*d1)/(d0+d1)
            m1 = m1 * (2*d0)/(d0+d1)
            local a0 =  2*mu3 - 3*mu2 + 1
            local a1 =    mu3 - 2*mu2 + mu
            local a2 =    mu3 -   mu2
            local a3 = -2*mu3 + 3*mu2
            return a0*v1+a1*m0+a2*m1+a3*v2
        end
    end

    return get_value
end

local function rotating_entry_exit(S, E, obj)
    local rotate = make_smooth{
        {t = S ,  val =  -5},
        {t = S+.3,val =   0, ease='step'},
        {t = E-.3,val =   0},
        {t = E,   val =   5},
    }

    return function(t)
        gl.rotate(rotate(t), 0, 1, 0)
        return obj(t)
    end
end

local function move_in_move_out(S, E, x, y, obj)
    local x = make_smooth{
        {t = S,   val = x+50},
        {t = S+.3,val = x, ease='step'},
        {t = E-.3,val = x},
        {t = E,   val = x-20},
    }

    local y = make_smooth{
        {t = S,   val = y*1.05},
        {t = S+.3,val = y, ease='step'},
        {t = E-.3,val = y},
        {t = E,   val = y*0.95},
    }

    return function(t)
        gl.translate(x(t), y(t))
        return obj(t)
    end
end

local M = {
    make_smooth = make_smooth;
    rotating_entry_exit = rotating_entry_exit;
    move_in_move_out = move_in_move_out;
}

function M.Area(width, height)
    local anims = {}

    local function add(anim, pos)
        pos = pos or #anims+1
        table.insert(anims, pos, anim)
    end

    local function draw(t, x1, y1, x2, y2)
        local w = x2 - x1
        local h = y2 - y1
        local ax1, ay1, ax2, ay2 = util.scale_into(w, h, width, height)
        local s = (ax2 - ax1) / width
        gl.pushMatrix()
            gl.translate(x1+ax1, y1+ay1)
            gl.scale(s, s)
            for idx = 1, #anims do
                gl.pushMatrix()
                anims[idx](t)
                gl.popMatrix()
            end
        gl.popMatrix()
    end

    return {
        add = add;
        draw = draw;
        width = width;
        height = height;
    }
end

function M.moving_font(S, E, font, x, y, text, size, r, g, b, a)
    local alpha = make_smooth{
        {t = S,   val = 0},
        {t = S+.5,val = 1, ease='step'},
        {t = E-.5,val = 1},
        {t = E,   val = 0},
    }
    return move_in_move_out(S, E, x, y,
        rotating_entry_exit(S, E, function(t)
            return font:write(0, 0, text, size, r, g, b, a * alpha(t))
        end)
    )
end

function M.moving_image_raw(S, E, img, x1, y1, x2, y2, a)
    a = a or 1
    local alpha = make_smooth{
        {t = S,   val = 0},
        {t = S+.5,val = 1, ease='step'},
        {t = E-.5,val = 1},
        {t = E,   val = 0},
    }
    return move_in_move_out(S, E, x1, y1,
        rotating_entry_exit(S, E, function(t)
            return img:draw(0, 0, x2-x1, y2-y1, a * alpha(t))
        end)
    )
end

function M.moving_image(S, E, img, x1, y1, x2, y2, a)
    local alpha = make_smooth{
        {t = S,   val = 0},
        {t = S+.5,val = 1, ease='step'},
        {t = E-.5,val = 1},
        {t = E,   val = 0},
    }
    return move_in_move_out(S, E, x1, y1,
        rotating_entry_exit(S, E, function(t)
            return util.draw_correct(img, 0, 0, x2-x1, y2-y1, a * alpha(t))
        end)
    )
end

function M.logo(S, E, x, y, img, size)
    local alpha = make_smooth{
        {t = S+0,  val = 0},
        {t = S+.5, val = 1, ease='step'},
        {t = E-.5, val = 1},
        {t = E,    val = 0},
    }

    return function(t)
        return util.draw_correct(img, x, y, x+size, y+size, alpha(t))
    end
end

function M.tweet_profile(S, E, x, y, img, size)
    local x = make_smooth{
        {t = S+0, val = 1800},
        {t = S+1, val = 500},
        {t = S+2, val = x, ease='step'},
        {t = E-1, val = x},
        {t = E,   val = -20},
    }
    local y = make_smooth{
        {t = S+0, val = 500},
        {t = S+1, val = 200},
        {t = S+2, val = y, ease='step'},
        {t = E-1, val = y},
        {t = E,   val = 0},
    }
    local scale = make_smooth{
        {t = S ,  val = 0},
        {t = S+1, val = 8},
        {t = S+2, val = 1, ease='step'},
        {t = E-1, val = 1},
        {t = E,   val = 0},
    }
    local alpha = make_smooth{
        {t = S,   val = 0},
        {t = S+1, val = 1, ease='step'},
        {t = E-1, val = 1},
        {t = E,   val = 0},
    }
    return function(t)
        local size = scale(t) * size
        gl.translate(x(t), y(t))
        return util.draw_correct(img, 0, 0, size, size, alpha(t))
    end
end

return M
