@use ".." Window Keys KeyPress onkey onreposition onresize px Vec2 frame mm
@use Colors...

# Create a window to demonstrate window position and size control
window = Window(
  title="Window Control",
  size=[300px, 200px],
  position=[200mm, 200mm],
  animating=true)

# Generate a color gradient based on window position and handle continuous key actions
function frame(w::Window)
  # Normalize position (0-1 range)
  x_norm,y_norm = w.position/1000px # should divide be screen width - window width
  r = clamp(x_norm, 0.2, 0.8)
  g = clamp(y_norm, 0.2, 0.8)
  b = 0.5
  fill!(w.buffer, RGB(r, g, b))
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

const SPEED = 20px
onkey(w::Window, ::KeyPress{Keys.left}) = w.position -= Vec2(SPEED, 0px)
onkey(w::Window, ::KeyPress{Keys.right}) = w.position += Vec2(SPEED, 0px)
onkey(w::Window, ::KeyPress{Keys.up}) = w.position -= Vec2(0px, SPEED)
onkey(w::Window, ::KeyPress{Keys.down}) = w.position += Vec2(0px, SPEED)
onkey(w::Window, ::KeyPress{Keys.equal}) = w.size += Vec2(SPEED, SPEED)
onkey(w::Window, ::KeyPress{Keys.minus}) =  begin
  @show w.size-Vec2(SPEED, SPEED), Vec2(100px, 100px)
  w.size = max(w.size-Vec2(SPEED, SPEED), Vec2(100px, 100px))
end

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
