@use "github.com/jkroso/Units.jl" Angle Radian
@use "." AbstractWindow int flt
@use Colors...
@use Skia

radians(a::Angle) = radians(convert(Radian, a))
radians(a::Radian) = a.value
radians(x) = x

# Helper to convert color to sk_color_t, which Skia reads as 0xAARRGGBB
function sk_color(c::Colorant)
  (;r, g, b, alpha) = convert(RGBA{Colors.N0f8}, c)
  UInt32(reinterpret(UInt8, alpha)) << 24 | UInt32(reinterpret(UInt8, r)) << 16 | UInt32(reinterpret(UInt8, g)) << 8 | UInt32(reinterpret(UInt8, b))
end

sk_color(s::String) = sk_color(parse(RGBA{Colors.N0f8}, s))

"""
Draw with Skia and return the pixels. `f(canvas, size, args...)` does the
drawing. Give it `pixels`, a buffer of the right length from an earlier call,
and it draws into that rather than making a new one.
"""
function drawing(f::Function, size, args..., ; scale=(2.0, 2.0), pixels=nothing)
  (scalex, scaley) = scale
  x,y = int.(size)
  scaledx = round(Int, x*scalex)
  scaledy = round(Int, y*scaley)
  reuse = pixels !== nothing && length(pixels) == scaledx * scaledy
  buffer = reuse ? pixels : zeros(UInt32, scaledx * scaledy)

  # Create image info. BGRA bytes read as a little-endian UInt32 are 0xAARRGGBB,
  # which is the layout of ARGB32
  info = Ref(Skia.sk_image_info_t(C_NULL, Skia.SK_COLOR_TYPE_BGRA_8888, Skia.sk_alpha_type_t(1), scaledx, scaledy))

  # `pointer_from_objref` doesn't keep `info` alive, and newer Julia versions
  # elide the Ref entirely, so Skia would read garbage without the preserve
  GC.@preserve info buffer begin
    # Skia draws straight into `buffer`, so there's nothing to copy out afterwards
    surface = Skia.sk_surface_make_raster_direct(pointer_from_objref(info), pointer(buffer), Csize_t(scaledx * 4), C_NULL)
    surface == C_NULL && error("Skia could not create a $(scaledx)×$(scaledy) surface")
    canvas = Skia.sk_surface_get_canvas(surface)
    reuse && Skia.sk_canvas_clear(canvas, 0x00000000)
    Skia.sk_canvas_scale(canvas, scalex, scaley)
    invokelatest(f, canvas, size, args...)
    Skia.sk_surface_unref(surface)
  end

  # Convert to ARGB32 format compatible with MiniFB
  result = reinterpret(ARGB32, buffer)
  reshape(result, (scaledx, scaledy))' # skia is row major while MiniFB is column major
end

# The buffer each window was last drawn into. A window is drawn many times a
# second, and a new 14MB buffer each time keeps the garbage collector busy.
const buffers = Dict{UInt,Vector{UInt32}}()

drawing(f::Function, w::AbstractWindow, args...) = begin
  scale = w.screen.content_scale
  x, y = int.(w.size)
  n = round(Int, x*scale[1]) * round(Int, y*scale[2])
  buffer = get(buffers, objectid(w), nothing)
  (buffer === nothing || length(buffer) != n) && (buffer = buffers[objectid(w)] = zeros(UInt32, n))
  drawing(f, w.size, args..., scale=scale, pixels=buffer)
end

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

"Vertical font metrics from Skia, in the same units as `font.size`. `ascent` is
negative (above baseline), `descent` is positive (below baseline)."
function font_metrics(font::SkiaFont)
  m = Ref{Skia.sk_font_metrics_t}()
  Skia.sk_font_get_metrics(font.raw, m)
  metrics = m[]
  (ascent=Float64(metrics.ascent), descent=Float64(metrics.descent),
   capHeight=Float64(metrics.capHeight), xHeight=Float64(metrics.xHeight))
end

"Tight visual bounds of `str` rendered with `font`. Coordinates are relative
to the draw position passed to `text()` — i.e. baseline at y=0, glyph origin at
x=0. Side bearings show up as nonzero `left`/right whitespace inside the box."
function text_bounds(font::SkiaFont, str::AbstractString)
  bounds = Ref{Skia.sk_rect_t}()
  GC.@preserve bounds begin
    Skia.sk_font_measure_text(font.raw, pointer(str), UInt64(ncodeunits(str)),
                              Skia.SK_TEXT_ENCODING_UTF8, pointer_from_objref(bounds), C_NULL)
  end
  r = bounds[]
  (left=Float64(r.left), top=Float64(r.top), right=Float64(r.right), bottom=Float64(r.bottom))
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

export arc, drawing, path, rectangle, line, line_to, move_to, rounded_rectangle, text, measure_text, text_bounds, font_metrics
