@use "./binding"... MINIFB_CURSOR_STYLE_CROSSHAIR

const window = minifb_window_new("My Window", 800, 600, title_bar=true)

minifb_window_set_position(window, (1000,500))
minifb_window_set_target_fps(window, 0)

let wave = Int8(0)
    direction = 1
    buffer = fill(0x00ff0000, (800, 600))
    tick = time()
    frames = 0
  while isopen(window)
    red = UInt32(wave<<16)
    green = UInt32(64<<8)
    blue = UInt32(255-wave)
    color = UInt32(0xff000000|red|green|blue)
    minifb_update_buffer(window, fill!(buffer, color))
    scroll = minifb_window_get_scroll_wheel(window)
    isnothing(scroll) || @show scroll
    mouse = minifb_window_get_mouse_position(window)
    # isnothing(mouse) || @show mouse
    keys = minifb_window_get_keys(window)
    # isempty(keys) || @show keys
    lb = minifb_window_get_mouse_down(window, 0)
    # lb && println("left down")
    rb = minifb_window_get_mouse_down(window, 2)
    # rb && println("right down")
    minifb_window_set_cursor_style(window, MINIFB_CURSOR_STYLE_CROSSHAIR)
    wave += direction
    wave == 255 && (direction = -1)
    wave == 0 && (direction = 1)
    frames += 1
    if !isapprox(tick, time(), atol=1)
      println("FPS: $frames")
      tick = time()
      frames = 0
    end
  end
end

close(window)

@use "." Window mm int

let wave = Int8(0),
    direction = 1,
    size = (100mm,100mm),
    buffer = fill(0x00000000, int.(size))
  Window("My Window", size) do _
    red = UInt32(wave<<16)
    green = UInt32(64<<8)
    blue = UInt32(255-wave)
    color = UInt32(0xff000000|red|green|blue)
    wave += direction
    (0 < wave < 255) || (direction *= -1)
    fill!(buffer, color)
  end
end
