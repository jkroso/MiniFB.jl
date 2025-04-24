@use "../cairo" drawing rectangle arc path text px ° Font
@use ".." Window frame onkey Keys KeyPress mm

function draw(ctx, (width,height))
  rectangle(ctx, 0, 0, width, height, background="#282C35")
  pad = width/10
  xw = width-2pad
  yw = height-2pad
  radius = 0.02yw
  path(ctx, color="white", background="rgb(128,128,255)", width=2px) do
    arc(ctx, (pad + xw - radius, pad + radius), radius, -90°, 0°)
    arc(ctx, (pad + xw - radius, pad + yw - radius), radius, 0°, 90°)
    arc(ctx, (pad + radius, pad + yw - radius), radius, 90°, 180°)
    arc(ctx, (pad + radius, pad + radius), radius, 180°, 270°)
  end
  str = "Rounded Rectangle"
  f = Font("Helvetica", 4mm, :light)
  text(ctx, (width/2-textwidth(str, f)/2, f.size/2+pad/2), f, "#54B1BE", str)
end

frame(w::Window) = drawing(draw, w.size)
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Rounded Rectangle", size=(140mm, 80mm), animating=true))
