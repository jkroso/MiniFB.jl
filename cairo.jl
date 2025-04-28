#This is a simple set of helper functions for working with cairo.jl
@use "github.com/jkroso/Units.jl" Angle Radian °
@use "github.com/jkroso/Font.jl/units" PPI px Length
@use "github.com/jkroso/Font.jl" Font
@use "." AbstractWindow int
@use Colors...
@use Cairo

radians(a::Angle) = radians(convert(Radian, a))
radians(a::Radian) = a.value
radians(x) = x

set_color(ctx, s::String) = set_color(ctx, parse(RGBA{Colors.N0f8}, s))
set_color(ctx, c::Colorant) = Cairo.set_source(ctx, c)
fill(ctx, c) = (set_color(ctx, c); Cairo.fill_preserve(ctx))
stroke(ctx, w, color="black") = (set_color(ctx, color); Cairo.set_line_width(ctx, int(w)); Cairo.stroke_preserve(ctx))
rectangle(ctx, left, top, w, h; background=nothing, stroke=nothing, border=0px) = begin
  Cairo.save(ctx)
  Cairo.rectangle(ctx, int(left), int(top), int(w), int(h))
  isnothing(background) || fill(ctx, background)
  isnothing(stroke) || stroke(ctx, border, stroke)
  Cairo.restore(ctx)
end

path(f::Function, ctx; close=true, background=nothing, color=nothing, width=0) = begin
  Cairo.new_path(ctx)
  f()
  close && Cairo.close_path(ctx)
  isnothing(background) || fill(ctx, background)
  isnothing(color) || stroke(ctx, width, color)
end

function drawing(f::Function, size, args..., ; scale=(2.0, 2.0))
  (scalex, scaley) = scale
  x,y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)
  ctx = Cairo.CairoContext(Cairo.CairoRGBSurface(scaledx, scaledy))
  Cairo.set_antialias(ctx, Cairo.ANTIALIAS_GOOD)
  Cairo.scale(ctx, scalex, scaley)
  invokelatest(f, ctx, size, args...)
  bytes=unsafe_wrap(Array, Cairo.image_surface_get_data(ctx.surface), (scaledx, scaledy))
  reinterpret(ARGB32, permutedims(bytes)) # cairo is row major so we need to swap dimensions
end

drawing(f::Function, w::AbstractWindow, args...) = drawing(f, w.size, args..., scale=w.screen.content_scale)

function arc(ctx, center, size, start, stop)
  Cairo.arc(ctx, int(center[1]), int(center[2]), int(size), radians(start), radians(stop))
end

function text(ctx, pos, font, size, color, str)
  Cairo.save(ctx)
  Cairo.move_to(ctx, int(pos[1]), int(pos[2]))
  set_color(ctx, color)
  Cairo.select_font_face(ctx, font, Cairo.FONT_SLANT_NORMAL, Cairo.FONT_WEIGHT_NORMAL)
  Cairo.set_font_size(ctx, int(size))
  Cairo.show_text(ctx, str)
  Cairo.restore(ctx)
end

text(ctx, pos, font::Font, color, str) = text(ctx, pos, font.family, font.size, color, str)

export text,arc,drawing,path,rectangle,stroke,fill,set_color
