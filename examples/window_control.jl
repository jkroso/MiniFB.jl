@use ".." Window Keys KeyPress onkey onreposition onresize px Vec2 frame
@use Colors...

# Create a window to demonstrate window position and size control
window = Window(
  title="Window Control",
  size=[300px, 200px],
  position=[100px, 100px],
  animating=true)

# Generate a color gradient based on window position
function frame(w::Window)
  # Normalize position (0-1 range)
  x_norm,y_norm = w.position/1000px # should divide be screen width - window width
  r = clamp(x_norm, 0.2, 0.8)
  g = clamp(y_norm, 0.2, 0.8)
  b = 0.5
  fill(RGB(r, g, b), w.buffer_size)
end

# Called when window position changes
function onreposition(w::Window, pos::Vec2{px})
  delta = pos - w.position # the windows position property is updated after the callback
  println("Window moved by: $(delta[1]), $(delta[2])")
end

# Called when window is resized
function onresize(w::Window, size::Vec2{px})
  delta = w.size - size # the windows size property is updated after the callback
  println("Window resized by: $(delta[1]), $(delta[2])")
end

# Keyboard controls
function onkey(w::Window, event)
  if event isa KeyPress{Keys.escape}
    close(w)
  elseif event isa KeyPress{Keys.left}
    w.position -= Vec2(20px, 0px) # Move left 20px
  elseif event isa KeyPress{Keys.right}
    w.position += Vec2(20px, 0px) # Move right 20px
  elseif event isa KeyPress{Keys.up}
    w.position -= Vec2(0px, 20px) # Move up 20px
  elseif event isa KeyPress{Keys.down}
    w.position += Vec2(0px, 20px) # Move down 20px
  elseif event isa KeyPress{Keys.equal}
    w.size += Vec2(20px, 20px) # Increase size
  elseif event isa KeyPress{Keys.minus}
    w.size -= Vec2(20px, 20px) # Decrease size
  elseif event isa KeyPress{Keys.r}
    # Reset position and size
    w.position = Vec2(100px, 100px)
    w.size = Vec2(300px, 200px)
    println("Window reset")
  end
end

println("""
Window Control Example
---------------------
Controls:
- Arrow keys: Move window
- Plus/Minus: Resize window
- R: Reset position and size
- ESC: Close window

The background color changes based on window position.
""")

open(window)
