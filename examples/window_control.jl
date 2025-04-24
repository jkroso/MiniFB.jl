@use ".." Window Keys KeyPress onkey onreposition onresize px Vec2 frame
@use Colors...

# Create a window to demonstrate window position and size control
window = Window(
  title="Window Control",
  size=[300px, 200px],
  position=[100px, 100px],
  animating=true)

# Movement and sizing speed (px per frame)
const MOVE_SPEED = 5px
const SIZE_SPEED = 5px

# Generate a color gradient based on window position and handle continuous key actions
function frame(w::Window)
  # Handle continuous movement and resizing based on keys
  Keys.left in w.keys && (w.position -= Vec2(MOVE_SPEED, 0px))
  Keys.right in w.keys && (w.position += Vec2(MOVE_SPEED, 0px))
  Keys.up in w.keys && (w.position -= Vec2(0px, MOVE_SPEED))
  Keys.down in w.keys && (w.position += Vec2(0px, MOVE_SPEED))
  Keys.equal in w.keys && (w.size += Vec2(SIZE_SPEED, SIZE_SPEED))
  if Keys.minus in w.keys
    # Prevent window from getting too small
    if w.size[1] > 100px && w.size[2] > 100px
      w.size -= Vec2(SIZE_SPEED, SIZE_SPEED)
    end
  end

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

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

# Reset controls
function onkey(w::Window, ::KeyPress{Keys.r})
  w.position = Vec2(100px, 100px)
  w.size = Vec2(300px, 200px)
  println("Window reset")
end

println("""
Window Control Example
---------------------
Controls:
- Arrow keys: Move window (hold key for continuous movement)
- Plus/Minus: Resize window (hold key for continuous resizing)
- R: Reset position and size
- ESC: Close window

The background color changes based on window position.
All movement and resize controls work continuously while keys are pressed.
""")

open(window)
