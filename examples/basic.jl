@use ".." frame onkey Window Keys KeyPress mm int
@use Colors...

wave=0
direction=4

# animates between 2 colors and fills the buffer with just that color
function frame(w::Window)
  global wave, direction
  wave = clamp(wave+direction, 0, 256)
  (0 < wave < 255) || (direction *= -1)
  fill(RGB24(wave/256, 64/256, (256-wave)/256), w.buffer_size)
end

# close when esc is pressed
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Red and Blue", size=[100mm,100mm], animating=true))
