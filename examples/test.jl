@use ".." frame onkey Window Keys KeyPress mm int
@use Colors...

frame(w::Window) = begin
  height,width = size(w.buffer)
  center = (width÷2, height÷2)
  fill!(@view(w.buffer[1:center[2],1:width]), RGBA(1,1,1,1)) # top left = white
  fill!(@view(w.buffer[center[2]:height,1:width]), RGBA(1,0,0,1)) # bottom right = red
  fill!(@view(w.buffer[1:center[2],center[1]:width]), RGBA(0,1,0,1)) # top right green
  fill!(@view(w.buffer[center[2]:height, 1:center[1]]), RGBA(0,0,1,1)) # bottom left blue
  w.buffer
end

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Quarters", size=[100mm,50mm], animating=true))
