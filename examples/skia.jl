@use "../skia" drawing rectangle rounded_rectangle text
@use "github.com/jkroso/Font.jl" Font textwidth
@use ".." Window frame onkey Keys KeyPress mm px

function draw(ctx, (width,height))
  # Draw background
  rectangle(ctx, 0, 0, width, height, background="#282C35")
  pad = width/10
  xw = width-2pad
  yw = height-2pad
  radius = 0.02yw
  rounded_rectangle(ctx, pad, pad, xw, yw, radius,
                   background="rgb(128,128,255)", color="white", stroke_width=1px)

  # f = Font("Helvetica", 4mm, :light)
  text(ctx, (10, 10), "Helvetica", 4mm, "#54B1BE", "Rounded Rectangle")
end

frame(w::Window) = drawing(draw, w)
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Rounded Rectangle", size=(140mm, 80mm), animating=true))
