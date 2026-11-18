@use "github.com/jkroso/Units.jl" Angle Radian
@use "." AbstractWindow int flt Drawn drop_gpu!
@use Colors...
@use Skia
@use GLFW
@use ModernGL: GLint, glBindFramebuffer, GL_FRAMEBUFFER, glGetFramebufferAttachmentParameteriv, GL_STENCIL,
               GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE

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
    Skia.sk_canvas_scale(canvas, Float32(scalex), Float32(scaley))
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
# How many pixels each window's buffer has room for. A drag of a window's edge
# changes its size many times a second. A new buffer for each size made the
# garbage collector stop the window for 10 to 60 ms many times in a drag.
# So a buffer has room for a window a quarter bigger. It changes size within
# that room without new memory.
const room = Dict{UInt,Int}()

"Draw window `w` with the CPU, into a buffer that it keeps from frame to frame, and return the pixels"
draw_with_cpu(f::Function, w::AbstractWindow, args...) = begin
  scale = w.screen.content_scale
  x, y = int.(w.size)
  n = round(Int, x*scale[1]) * round(Int, y*scale[2])
  id = objectid(w)
  # A window that becomes much smaller gives the memory back
  if n > get(room, id, 0) || n < room[id] ÷ 2
    room[id] = n + n ÷ 4
    buffers[id] = sizehint!(UInt32[], room[id])
  end
  buffer = resize!(buffers[id], n)
  drawing(f, w.size, args..., scale=scale, pixels=buffer)
end

"Give back the buffer that window `w` was drawn into. A window that has closed doesn't need it."
drop_buffer!(w::AbstractWindow) = (delete!(buffers, objectid(w)); delete!(room, objectid(w)); nothing)

# --- drawing with the graphics card ------------------------------------------
#
# A window that's on the screen has an OpenGL context. Skia draws into the
# window's own framebuffer with it, so there are no pixels to copy to the
# graphics card. A window that isn't on the screen, like a test's, draws with
# the CPU into a buffer, as before.

"What Skia draws a window with on the graphics card"
mutable struct GPU
  context::Ptr{Skia.gr_direct_context_t}
  target::Ptr{Skia.gr_backendrendertarget_t}
  surface::Ptr{Skia.sk_surface_t}
  size::Tuple{Int,Int}   # of the window's framebuffer, in the screen's pixels
end

"What Skia draws each window with on the graphics card, by `objectid`"
const gpus = Dict{UInt,GPU}()
"False to draw every window with the CPU. `MINIFB_GPU=0` sets it false when MiniFB loads."
const use_gpu = Ref(true)
"The windows that Skia couldn't draw with the graphics card, by `objectid`. They draw with the CPU."
const no_gpu = Set{UInt}()

"How many bits of stencil the current window's framebuffer has"
stencil_bits() = begin
  bits = Ref{GLint}(0)
  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL, GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, bits)
  Int(bits[])
end

"Let go of the surface that Skia draws window `g` on, so it can make one for a new size"
free_surface!(g::GPU) = begin
  g.surface == C_NULL || Skia.sk_surface_unref(g.surface)
  g.target == C_NULL || Skia.gr_backendrendertarget_delete(g.target)
  g.surface, g.target, g.size = C_NULL, C_NULL, (0, 0)
  nothing
end

"""
What Skia draws window `w` with on the graphics card, at the size it has now.
Nothing when Skia can't. The window's OpenGL context must be the current one.
"""
gpu!(w::AbstractWindow) = begin
  id = objectid(w)
  fb = GLFW.GetFramebufferSize(w.glfw[1])
  size = (Int(fb.width), Int(fb.height))
  g = get(gpus, id, nothing)
  if g === nothing
    interface = Skia.gr_glinterface_create_native_interface()
    interface == C_NULL && return nothing
    context = Skia.gr_direct_context_make_gl(interface)
    Skia.gr_glinterface_unref(interface)   # the context keeps its own reference
    context == C_NULL && return nothing
    g = gpus[id] = GPU(context, C_NULL, C_NULL, (0, 0))
  end
  if g.size != size
    free_surface!(g)
    info = Ref(Skia.gr_gl_framebufferinfo_t(0, 0x8058, false))   # framebuffer 0 is the window's own. 0x8058 is GL_RGBA8.
    g.target = Skia.gr_backendrendertarget_new_gl(Cint(size[1]), Cint(size[2]), Cint(0), Cint(stencil_bits()), info)
    g.surface = Skia.sk_surface_new_backend_render_target(g.context, g.target, Skia.GR_SURFACE_ORIGIN_BOTTOM_LEFT,
                                                           Skia.SK_COLOR_TYPE_RGBA_8888, C_NULL, C_NULL)
    g.surface == C_NULL && return nothing
    g.size = size
  end
  g
end

"Draw window `w` with Skia on the graphics card, with `f(canvas, size, args...)`"
draw_with_gpu(f::Function, g::GPU, w::AbstractWindow, args...) = begin
  # MiniFB used OpenGL since Skia last drew, so Skia can't trust what it thinks is set
  Skia.gr_direct_context_reset(g.context)
  canvas = Skia.sk_surface_get_canvas(g.surface)
  saves = Skia.sk_canvas_get_save_count(canvas)
  Skia.sk_canvas_save(canvas)
  try
    Skia.sk_canvas_clear(canvas, 0x00000000)
    scale = w.screen.content_scale
    Skia.sk_canvas_scale(canvas, Float32(scale[1]), Float32(scale[2]))
    invokelatest(f, canvas, w.size, args...)
  finally
    # The canvas lasts from frame to frame, so it mustn't keep this frame's scale or clip
    Skia.sk_canvas_restore_to_count(canvas, saves)
    Skia.gr_direct_context_flush_and_submit(g.context, false)
  end
  Drawn()
end

drop_gpu!(w::AbstractWindow) = begin
  delete!(no_gpu, objectid(w))
  g = pop!(gpus, objectid(w), nothing)
  g === nothing && return
  free_surface!(g)
  Skia.gr_direct_context_release_resources_and_abandon_context(g.context)
  Skia.gr_direct_context_unref(g.context)
  nothing
end

"""
Draw window `w` with `f(canvas, size, args...)`. A window that's on the screen
draws with the graphics card, and this returns `Drawn()`. Otherwise it draws
with the CPU and returns the pixels.
"""
drawing(f::Function, w::AbstractWindow, args...) = begin
  id = objectid(w)
  if use_gpu[] && isopen(w) && !(id in no_gpu)
    GLFW.MakeContextCurrent(w.glfw[1])
    g = try
      gpu!(w)
    catch e
      @warn "Skia couldn't draw the window with the graphics card, so it draws it with the CPU" exception=(e, catch_backtrace())
      nothing
    end
    g === nothing ? push!(no_gpu, id) : return draw_with_gpu(f, g, w, args...)
  end
  draw_with_cpu(f, w, args...)
end

function rectangle(canvas, left, top, w, h; background=nothing, stroke=nothing, border=0)
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

    Skia.sk_path_arc_to_with_oval(path, rectref, start_angle, sweep_angle, true)

    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, true)  # a curve shows steps unless its edge pixels are blended
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

    # A new piece of the path, not joined to the end of the last one
    Skia.sk_path_arc_to_with_oval(current_path, rectref, start_angle, sweep_angle, true)
  end
end

arc(canvas, center, size, range) = arc(canvas, center, size, first(range), last(range))

# Global path for use within drawing functions
current_path = nothing

"""
Fill or stroke the path that `f` draws. `smooth` blends the pixels along its
edges, so that a slant or a curve doesn't show steps.
"""
function path(f::Function, canvas; close=false, background=nothing, color=nothing, width=0, smooth=true)
  path = Skia.sk_path_new()
  f(path) # Call the drawing function
  close && Skia.sk_path_close(path)

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, smooth)
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(color)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, smooth)
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
  use_gpu[] = get(ENV, "MINIFB_GPU", "1") != "0"
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
# A line that goes straight across or straight down stays sharp, like a caret. Blended,
# it would go soft where it starts part way through a pixel. A slanted line is blended.
line(canvas, from, to, width, color) = begin
  slanted = from[1] != to[1] && from[2] != to[2]
  path(canvas, width=width, color=color, smooth=slanted) do path
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
  # A curve needs its edge pixels blended, or it shows steps. A square box stays sharp: two
  # that meet part way through a pixel would each blend it, and leave a faint line between them.
  smooth = r > 0

  if !isnothing(background)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, smooth)
    Skia.sk_paint_set_color(paint, sk_color(background))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(0)) # Fill
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  if !isnothing(color)
    paint = Skia.sk_paint_new()
    Skia.sk_paint_set_antialias(paint, smooth)
    Skia.sk_paint_set_color(paint, sk_color(color))
    Skia.sk_paint_set_style(paint, Skia.sk_paint_style_t(1)) # Stroke
    Skia.sk_paint_set_stroke_width(paint, flt(stroke_width))
    Skia.sk_canvas_draw_path(canvas, path, paint)
    Skia.sk_paint_delete(paint)
  end

  Skia.sk_path_delete(path)
end

rounded_rectangle(canvas, origin, size, radius; kwargs...) = rounded_rectangle(canvas, origin[1], origin[2], size[1], size[2], radius; kwargs...)

export arc, drawing, path, rectangle, line, line_to, move_to, rounded_rectangle, text, measure_text, text_bounds, font_metrics, drop_buffer!
