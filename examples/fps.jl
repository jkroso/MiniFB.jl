@use ".." frame onkey Window Keys KeyPress mm int px
@use Colors...

const window = Window(title="Red and Blue", size=[200mm,300mm], animating=true)

wave=0
direction=4
t = time()
frames = 0

# animates between 2 colors and fills the buffer with just that color
function frame(w::Window)
  global wave, direction, t, frames
  wave = clamp(wave+direction, 0, 256)
  (0 < wave < 255) || (direction *= -1)
  frames += 1
  newtime = time()
  if time() - t > 1
    println("fsp: $frames")
    frames=0
    t = newtime
  end
  fill!(w.buffer, RGBA{Colors.N0f8}(wave/256, 64/256, (256-wave)/256, 1))
end

# close when esc is pressed
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(window)
