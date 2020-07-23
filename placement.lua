local matrix = require "matrix2d"
local scissors = sys.get_ext "scissors"

local Screen = function(target, surface)
    local screen = sys.get_ext "screen"
    local setup, surface2screen

    screen.set_render_target(target.x, target.y, target.width, target.height, true)

    local function perspective(w, h)
        local fov = math.atan2(h, w*2) * 360 / math.pi
        gl.perspective(fov, w/2, h/2, -w,
                            w/2, h/2, 0)
    end

    if target.rotation == 0 then
        gl.setup(surface.width, surface.height)
        setup = function()
            perspective(WIDTH, HEIGHT)
        end
        surface2screen = matrix.trans(target.x, target.y) *
                         matrix.scale(
                             target.width / surface.width,
                             target.height / surface.height
                         )
    elseif target.rotation == 90 then
        gl.setup(surface.height, surface.width)
        WIDTH, HEIGHT = HEIGHT, WIDTH
        setup = function()
            perspective(HEIGHT, WIDTH)
            gl.translate(surface.height, 0)
            gl.rotate(90, 0, 0, 1)
        end
        surface2screen = matrix.trans(target.x + target.width, target.y) *
                         matrix.rotate_deg(target.rotation) *
                         matrix.scale(
                             target.height / surface.width,
                             target.width / surface.height
                         )
     elseif target.rotation == 180 then
        gl.setup(surface.width, surface.height)
        setup = function()
            perspective(WIDTH, HEIGHT)
            gl.translate(surface.width, surface.height)
            gl.rotate(180, 0, 0, 1)
        end
        surface2screen = matrix.trans(target.x + target.width, target.y + target.height) *
                         matrix.rotate_deg(target.rotation) *
                         matrix.scale(
                             target.width / surface.width,
                             target.height / surface.height
                         )
    elseif target.rotation == 270 then
        gl.setup(surface.height, surface.width)
        WIDTH, HEIGHT = HEIGHT, WIDTH
        setup = function()
            perspective(HEIGHT, WIDTH)
            gl.translate(0, surface.width)
            gl.rotate(270, 0, 0, 1)
        end
        surface2screen = matrix.trans(target.x, target.y + target.height) *
                         matrix.rotate_deg(target.rotation) *
                         matrix.scale(
                             target.height / surface.width,
                             target.width / surface.height
                         )
    else
        error(string.format("cannot rotate by %d degree", surface.rotate))
    end

    local function project(x1, y1, x2, y2)
        local tx1, ty1 = surface2screen(x1, y1)
        local tx2, ty2 = surface2screen(x2, y2)
        return math.floor(math.min(tx1, tx2)), math.floor(math.min(ty1, ty2)),
               math.floor(math.max(tx1, tx2)), math.floor(math.max(ty1, ty2))
    end

    local function scissor(x1, y1, x2, y2)
        x1 = x1 or 0
        y1 = y1 or 0
        x2 = x2 or WIDTH
        y2 = y2 or HEIGHT
        x1, y1, x2, y2 = project(x1, y1, x2, y2)
        if x1 == 0 and y1 == 0 and x2 == NATIVE_WIDTH and y2 == NATIVE_HEIGHT and NATIVE_WIDTH ~= WIDTH and NATIVE_HEIGHT ~= HEIGHT then
            -- workaround in case native sizes don't match virtual sizes
            -- info-beamer wrongly disables scissors by matching to the
            -- virtual sizes. So use those here. This can be fixed in the
            -- future by an explicit 'scissor disable' function.
            scissors.set(0, 0, WIDTH, HEIGHT)
        else
            scissors.set(x1, y1, x2, y2)
        end
    end

    local function place(raw, layer, alpha, x1, y1, x2, y2)
        x1, y1, x2, y2 = project(x1, y1, x2, y2)
        local w, h = target.width, target.height
        local outside = (
            (x1 <= 0 and x2 <= 0) or
            (x1 >= w and x2 >= w) or
            (y1 <= 0 and y2 <= 0) or
            (y1 >= h and y2 >= h)
        )
        if outside then
            return raw:target(0, 0, 0, 0):alpha(0)
        else
            return raw:alpha(alpha):layer(layer):place(x1, y1, x2, y2, target.rotation)
        end
    end

    return {
        scissor = scissor;
        setup = setup;
        place = place;
    }
end

return {
    Screen = Screen;
}
