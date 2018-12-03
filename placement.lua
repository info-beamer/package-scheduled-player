local matrix = require "matrix2d"

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

    local function place(raw, layer, alpha, x1, y1, x2, y2)
        local tx1, ty1 = surface2screen(x1, y1)
        local tx2, ty2 = surface2screen(x2, y2)
        local x1, y1 = math.floor(math.min(tx1, tx2)), math.floor(math.min(ty1, ty2))
        local x2, y2 = math.floor(math.max(tx1, tx2)), math.floor(math.max(ty1, ty2))
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
        setup = setup;
        place = place;
    }
end

return {
    Screen = Screen;
}
