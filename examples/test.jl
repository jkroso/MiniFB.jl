@use ".." frame onkey Window Keys KeyPress mm int
@use Colors...

frame(w::Window) = begin
  y,x = w.buffer_size
  center = (x÷2, y÷2)
  pixels = zeros(RGBA, y, x)
  fill!(@view(pixels[1:center[2],1:center[1]]), RGBA(1,1,1,1)) # top left = white
  fill!(@view(pixels[center[2]:y,center[1]:x]), RGBA(1,0,0,1)) # bottom right = red
  fill!(@view(pixels[1:center[2],center[1]:x]), RGBA(0,1,0,1)) # top right green
  fill!(@view(pixels[center[2]:y, 1:center[1]]), RGBA(0,0,1,1)) # bottom left blue
  pixels
end

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Quarters", size=[100mm,50mm], animating=true))
