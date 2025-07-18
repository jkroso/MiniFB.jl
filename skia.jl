#This is a simple set of helper functions for working with Skia.jl
@use "github.com/jkroso/Units.jl" Angle Radian °
@use "github.com/jkroso/Font.jl/units" PPI px Length
@use "github.com/jkroso/Font.jl" Font
@use "." AbstractWindow int
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
  rect = Skia.sk_rect_t(Float32(int(left)), Float32(int(top)), Float32(int(left + w)), Float32(int(top + h)))

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_rect(canvas, Ptr{Skia.sk_rect_t}(pointer_from_objref(Ref(rect))), paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(stroke)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_color(paint, sk_color(stroke))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, Float32(int(border)))
    Skia.sk_canvas_draw_rect(canvas, Ptr{Skia.sk_rect_t}(pointer_from_objref(Ref(rect))), paint)
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
    rect = Skia.sk_rect_t(Float32(cx - radius), Float32(cy - radius), Float32(cx + radius), Float32(cy + radius))

    start_angle = Float32(radians(start) * 180 / π)
    sweep_angle = Float32(radians(stop - start) * 180 / π)

    Skia.sk_path_add_arc(path, Ptr{Skia.sk_rect_t}(pointer_from_objref(Ref(rect))),
                         start_angle, sweep_angle)

    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_canvas_draw_path(canvas, path, paint)

    Skia.sk_paint_delete(paint)
    Skia.sk_path_delete(path)
  else
    # Arc as part of a path
    cx, cy = int(center[1]), int(center[2])
    radius = int(size)
    rect = Skia.sk_rect_t(Float32(cx - radius), Float32(cy - radius), Float32(cx + radius), Float32(cy + radius))

    start_angle = Float32(radians(start) * 180 / π)
    sweep_angle = Float32(radians(stop - start) * 180 / π)

    # Use add_arc to create a proper arc segment
    Skia.sk_path_add_arc(current_path, Ptr{Skia.sk_rect_t}(pointer_from_objref(Ref(rect))),
                         start_angle, sweep_angle)
  end
end

arc(canvas, center, size, range) = arc(canvas, center, size, first(range), last(range))

# Global path for use within drawing functions
current_path = nothing

function path(f::Function, canvas; close=true, background=nothing, color=nothing, width=0)
  global current_path
  path = Skia.sk_path_new()
  current_path = path

  # Call the drawing function
  f()

  if close
    Skia.sk_path_close(path)
  end

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
    Skia.sk_paint_set_stroke_width(paint, Float32(int(width)))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  Skia.sk_path_delete(path)
  current_path = nothing
end

function text(canvas, pos, font, size, color, str)
  fontmgr = Skia.sk_fontmgr_ref_default()
  weight = Int32(Skia.SK_FONT_STYLE_WEIGHT_LIGHT)
  width = Int32(Skia.SK_FONT_STYLE_WIDTH_NORMAL)
  fontStyle = Skia.sk_fontstyle_new(weight, width, Skia.SK_FONT_STYLE_SLANT_UPRIGHT)
  typeface = Skia.sk_fontmgr_match_family_style(fontmgr, font, fontStyle)
  paint = Skia.sk_paint_new()
  Skia.sk_paint_set_antialias(paint, true)
  Skia.sk_paint_set_color(paint, sk_color(color))
  Skia.sk_paint_set_style(paint, Skia.SK_PAINT_STYLE_FILL)
  skfont = Skia.sk_font_new_with_values(typeface, Float32(int(size)), 1.0f0, 0.0f0)
  blob = Skia.sk_textblob_make_from_string(str, skfont, Skia.SK_TEXT_ENCODING_UTF8)
  Skia.sk_canvas_draw_text_blob(canvas, blob, Float32(int(pos[1])), Float32(int(pos[2])), paint)
  # Cleanup
  Skia.sk_paint_delete(paint)
end

text(canvas, pos, font::Font, color, str) = text(canvas, pos, font.family, font.size, color, str)

function measure_text(font, size, str)
  fontmgr = Skia.sk_fontmgr_ref_default()
  weight = Int32(Skia.SK_FONT_STYLE_WEIGHT_LIGHT)
  width = Int32(Skia.SK_FONT_STYLE_WIDTH_NORMAL)
  fontStyle = Skia.sk_fontstyle_new(weight, width, Skia.SK_FONT_STYLE_SLANT_UPRIGHT)
  typeface = Skia.sk_fontmgr_match_family_style(fontmgr, font, fontStyle)
  skfont = Skia.sk_font_new_with_values(typeface, Float32(int(size)), 1.0f0, 0.0f0)
  
  # Measure text width
  text_width = Skia.sk_font_measure_text(skfont, pointer(str), UInt64(ncodeunits(str)), Skia.SK_TEXT_ENCODING_UTF8, C_NULL, C_NULL)
  
  # Get font metrics for height
  metrics = Ref{Skia.sk_font_metrics_t}()
  Skia.sk_font_get_metrics(skfont, metrics)
  text_height = metrics[].descent - metrics[].ascent
  
  # Cleanup
  Skia.sk_font_delete(skfont)
  Skia.sk_fontstyle_delete(fontStyle)
  
  return (text_width, text_height)
end

measure_text(font::Font, str) = measure_text(font.family, font.size, str)

function line_to(canvas, pt)
  global current_path
  if current_path !== nothing
    Skia.sk_path_line_to(current_path, Float32(int(pt[1])), Float32(int(pt[2])))
  end
end

function move_to(canvas, pt)
  global current_path
  if current_path !== nothing
    Skia.sk_path_move_to(current_path, Float32(int(pt[1])), Float32(int(pt[2])))
  end
end

function rounded_rectangle(canvas, x, y, width, height, radius; background=nothing, color=nothing, stroke_width=0)
  path = Skia.sk_path_new()

  # Create a rounded rectangle using Skia's built-in function
  rect = Skia.sk_rect_t(Float32(int(x)), Float32(int(y)), Float32(int(x + width)), Float32(int(y + height)))
  Skia.sk_path_add_rounded_rect(path, Ptr{Skia.sk_rect_t}(pointer_from_objref(Ref(rect))),
                                Float32(int(radius)), Float32(int(radius)),
                                Skia.sk_path_direction_t(0)) # Clockwise

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
    Skia.sk_paint_set_stroke_width(paint, Float32(int(stroke_width)))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  Skia.sk_path_delete(path)
end

export arc, drawing, path, rectangle, line_to, move_to, rounded_rectangle, text, measure_text
