@use "github.com/jkroso/Units.jl" Angle Radian
@use "." AbstractWindow int flt
@use Colors...
@use Skia

radians(a::Angle) = radians(convert(Radian, a))
radians(a::Radian) = a.value
radians(x) = x

# Helper to convert color to sk_color_t
function sk_color(c::Colorant)
  (;r, g, b, alpha) = convert(RGBA{Colors.N0f8}, c)
  UInt32(reinterpret(UInt8, alpha)) << 24 | UInt32(reinterpret(UInt8, b)) << 16 | UInt32(reinterpret(UInt8, g)) << 8 | UInt32(reinterpret(UInt8, r))
end

sk_color(s::String) = sk_color(parse(RGBA{Colors.N0f8}, s))

function drawing(f::Function, size, args..., ; scale=(2.0, 2.0))
  (scalex, scaley) = scale
  x,y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)

  # Create image info
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.sk_color_type_t(4), Skia.sk_alpha_type_t(1), scaledx, scaledy))

  # Create surface and canvas
  surface = Skia.sk_surface_make_raster_n32_premul(pointer_from_objref(info), C_NULL)
  canvas = Skia.sk_surface_get_canvas(surface)

  # Scale the canvas
  Skia.sk_canvas_scale(canvas, scalex, scaley)

  # Call the drawing function
  invokelatest(f, canvas, size, args...)

  # Get the image and read pixels
  image = Skia.sk_surface_make_image_snapshot(surface)
  width = Skia.sk_image_get_width(image)
  height = Skia.sk_image_get_height(image)

  # Create buffer and read pixels
  pixels = Array{UInt32}(undef, width * height)

  Skia.sk_image_read_pixels(image, pointer_from_objref(info),
                           pointer(pixels), UInt64(width * 4), Int32(0), Int32(0), Skia.sk_image_caching_hint_t(0))

  # Cleanup
  Skia.sk_image_unref(image)
  Skia.sk_surface_unref(surface)

  # Convert to ARGB32 format compatible with MiniFB
  result = reinterpret(ARGB32, pixels)
  reshape(result, (width, height))' # skia is row major while MiniFB is column major
end

drawing(f::Function, w::AbstractWindow, args...) = drawing(f, w.size, args..., scale=w.screen.content_scale)

function rectangle(canvas, left, top, w, h; background=nothing, stroke=nothing, border=0px)
  rectref = Ref(Skia.sk_rect_t(flt(left), flt(top), flt(left + w), flt(top + h)))

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_rect(canvas, rectref, paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(stroke)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(stroke))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, flt(border))
    Skia.sk_canvas_draw_rect(canvas, rectref, paint)
    Skia.sk_paint_delete(paint)
  end
end

function arc(canvas, center, size, start, stop)
  global current_path
  if current_path === nothing
    # Standalone arc
    path = Skia.sk_path_new()
    cx, cy = int(center[1]), int(center[2])
    radius = int(size)
    rectref = Ref(Skia.sk_rect_t(Float32(cx - radius), Float32(cy - radius), Float32(cx + radius), Float32(cy + radius)))

    start_angle = Float32(radians(start) * 180 / π)
    sweep_angle = Float32(radians(stop - start) * 180 / π)

    Skia.sk_path_add_arc(path, rectref, start_angle, sweep_angle)

    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_canvas_draw_path(canvas, path, paint)

    Skia.sk_paint_delete(paint)
    Skia.sk_path_delete(path)
  else
    # Arc as part of a path
    cx, cy = int(center[1]), int(center[2])
    radius = int(size)
    rectref = Ref(Skia.sk_rect_t(Float32(cx - radius), Float32(cy - radius), Float32(cx + radius), Float32(cy + radius)))

    start_angle = Float32(radians(start) * 180 / π)
    sweep_angle = Float32(radians(stop - start) * 180 / π)

    # Use add_arc to create a proper arc segment
    Skia.sk_path_add_arc(current_path, rectref, start_angle, sweep_angle)
  end
end

arc(canvas, center, size, range) = arc(canvas, center, size, first(range), last(range))

# Global path for use within drawing functions
current_path = nothing

function path(f::Function, canvas; close=false, background=nothing, color=nothing, width=0)
  path = Skia.sk_path_new()
  f(path) # Call the drawing function
  close && Skia.sk_path_close(path)

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(color)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(color))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, flt(width))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  Skia.sk_path_delete(path)
end

const fontmgr = Ref{Ptr{Skia.sk_font_mgr_t}}()

function __init__()
  fontmgr[] = Skia.sk_fontmgr_ref_default()
end

mutable struct SkiaFont
  family::String
  weight::Skia.sk_font_style_weight_t
  slant::Skia.sk_font_style_slant_t
  size::Float32
  raw::Ptr{Skia.sk_font_t}
end

cleanup(f::SkiaFont) = Skia.sk_font_delete(f.raw)

function SkiaFont(family=Skia.getDefaultFont(), size=5mm, weight=Skia.SK_FONT_STYLE_WEIGHT_NORMAL, slant=Skia.SK_FONT_STYLE_SLANT_UPRIGHT)
  fontStyle = Skia.sk_fontstyle_new(Int32(weight), Int32(Skia.SK_FONT_STYLE_WIDTH_NORMAL), Skia.SK_FONT_STYLE_SLANT_UPRIGHT)
  typeface = Skia.sk_fontmgr_match_family_style(fontmgr[], family, fontStyle)
  size = flt(size)
  skfont = Skia.sk_font_new_with_values(typeface, size, 1.0f0, 0.0f0)
  f = SkiaFont(family, weight, slant, size, skfont)
  finalizer(cleanup, f)
  f
end

function text(canvas, pos, font, color, str)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(color))
  Skia.sk_paint_set_style(paint, Skia.SK_PAINT_STYLE_FILL)
  blob = Skia.sk_textblob_make_from_string(str, font.raw, Skia.SK_TEXT_ENCODING_UTF8)
  Skia.sk_canvas_draw_text_blob(canvas, blob, flt(pos[1]), flt(pos[2]), paint)
  Skia.sk_paint_delete(paint)
end

function measure_text(font::SkiaFont, str::AbstractString)
  text_width = Skia.sk_font_measure_text(font.raw, pointer(str), UInt64(ncodeunits(str)), Skia.SK_TEXT_ENCODING_UTF8, C_NULL, C_NULL)
  metrics = Ref{Skia.sk_font_metrics_t}()
  Skia.sk_font_get_metrics(font.raw, metrics)
  (;descent, ascent)= metrics[]
  return (text_width, descent - ascent)
end

move_to(path, pt) = Skia.sk_path_move_to(path, flt(pt[1]), flt(pt[2]))
line_to(path, pt) = Skia.sk_path_line_to(path, flt(pt[1]), flt(pt[2]))
line(canvas, from, to, width, color) = begin
  path(canvas, width=width, color=color) do path
    move_to(path, from)
    line_to(path, to)
  end
end

function rounded_rectangle(canvas, x, y, width, height, radius; background=nothing, color=nothing, stroke_width=0)
  path = Skia.sk_path_new()

  # Create a rounded rectangle using Skia's built-in function
  rectref = Ref(Skia.sk_rect_t(flt(x), flt(y), flt(x + width), flt(y + height)))
  r = flt(radius)
  Skia.sk_path_add_rounded_rect(path, rectref, r, r, Skia.SK_PATH_DIRECTION_CW)

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(color)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(color))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, flt(stroke_width))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  Skia.sk_path_delete(path)
end

rounded_rectangle(canvas, origin, size, radius; kwargs...) = rounded_rectangle(canvas, origin[1], origin[2], size[1], size[2], radius; kwargs...)

export arc, drawing, path, rectangle, line, line_to, move_to, rounded_rectangle, text, measure_text
