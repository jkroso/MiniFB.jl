@use ".." Window frame onmouse onkey onscroll Vec2 px Keys KeyPress mm
@use Colors...
@use GLFW...

const cursors = reshape(collect(instances(GLFW.StandardCursorShape)), 5, 2)
const colors = rand(RGB, size(cursors))

function gentiles(width, height)
  yl, xl = size(colors)
  sx, sy = (width÷xl, height÷yl)
  buffer = zeros(RGB24, height, width)
  for xi=0:(xl-1), yi=0:(yl-1)
    xstart = xi*sx
    ystart = yi*sy
    colrange = (ystart+1):ystart+sy
    rowrange = (xstart+1):xstart+sx
    fill!(@view(buffer[colrange,rowrange]), convert(RGB24, colors[yi+1, xi+1]))
  end
  buffer
end

bucket(r::AbstractRange, num::Number) = (num - first(r)) ÷ step(r)
inwindow((width,height), (x,y)) = (0 < x < width) && (0 < y < height)

function onmouse(w::Window, pos::Vec2{px})
  inwindow(w.size, pos) || return
  width, height = w.size
  y,x = size(colors)
  xi = bucket(0px:(width÷x):width, pos[1])
  yi = bucket(0px:(height÷y):height, pos[2])
  w.cursor = cursors[yi+1,xi+1]
end

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)
frame(w::Window) = gentiles(reverse(size(w.buffer))...)

open(Window(title="Cursors", size=[100mm,200mm]))
