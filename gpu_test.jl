# Tests that Skia draws a window that's on the screen with the graphics card,
# and that a window can go back to drawing with the CPU.
#
# It opens a real window for about a second. The window doesn't take the
# keyboard. Run it with `julia --project=. gpu_test.jl`.
@use Test: @test, @testset
@use "./main" => MiniFB
@use "./main" Window Drawn
@use "./skia" => SK
@use "./skia" drawing rectangle
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use Colors: RGB
@use ModernGL: glReadPixels, GL_RGBA, GL_UNSIGNED_BYTE
@use GLFW

const w = Window(title="gpu test", size=Vec2{px}(300px, 200px), position=Vec2{px}(60px, 60px))

"""
The colour of the pixel `x`, `y` points from the top left of window `w`, in
the frame that's about to be shown, as red, green, blue and alpha from 0 to 255
"""
pixel(w, x, y) = begin
  p = zeros(UInt8, 4)
  fb = GLFW.GetFramebufferSize(w.glfw[1])
  s = fb.width / w.size[1].value
  glReadPixels(round(Int, x * s), round(Int, fb.height - y * s), 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, p)
  Tuple(Int.(p))
end

# Every screen can show this blue. A wide-gamut screen such as a Dell U4021QW
# can't show pure sRGB blue, so a picture of it comes back with some green.
const ORANGE, BLUE = (255, 128, 0, 255), (32, 64, 224, 255)

"For each frame: what `drawing` gave back, and the colours at the middle, inside the square, and under it"
const frames = []
"The picture of the window that macOS showed, after it went back to the CPU"
const shown = Ref{Any}(nothing)

"""
The colour of a pixel of the PNG picture at `path`, at `fx` and `fy` of the
way across and down it, as sRGB red, green, blue and alpha from 0 to 255.
A picture of the screen has the screen's colour profile, and macOS converted
the window's sRGB colours for that screen. So Skia converts them back here,
and the test passes on a wide-gamut screen too.
"""
png_pixel(path, fx, fy) = begin
  bytes = read(path)
  data = SK.Skia.sk_data_new_with_copy(pointer(bytes), Csize_t(length(bytes)))
  image = SK.Skia.sk_image_new_from_encoded(data)
  SK.Skia.sk_data_unref(data)
  wide, high = SK.Skia.sk_image_get_width(image), SK.Skia.sk_image_get_height(image)
  info = Ref(SK.Skia.sk_image_info_t(SK.srgb[], SK.Skia.SK_COLOR_TYPE_RGBA_8888, SK.Skia.sk_alpha_type_t(2), 1, 1))   # 2 is unpremultiplied
  p = zeros(UInt8, 4)
  GC.@preserve info p SK.Skia.sk_image_read_pixels(image, pointer_from_objref(info), pointer(p), Csize_t(4),
    Cint(round(Int, fx * wide)), Cint(round(Int, fy * high)), SK.Skia.sk_image_caching_hint_t(0))
  SK.Skia.sk_image_unref(image)
  Tuple(Int.(p))
end

"How many pixels wide and high the PNG picture at `path` is"
png_size(path) = begin
  bytes = read(path)
  data = SK.Skia.sk_data_new_with_copy(pointer(bytes), Csize_t(length(bytes)))
  image = SK.Skia.sk_image_new_from_encoded(data)
  SK.Skia.sk_data_unref(data)
  size = (SK.Skia.sk_image_get_width(image), SK.Skia.sk_image_get_height(image))
  SK.Skia.sk_image_unref(image)
  size
end

sel(name) = ccall(:sel_registerName, Ptr{Cvoid}, (Cstring,), name)

"Take a picture of the window as macOS shows it, then close it"
shoot(_) = begin
  ns = ccall((:glfwGetCocoaWindow, GLFW.libglfw), Ptr{Cvoid}, (GLFW.Window,), w.glfw[1])
  number = ccall(:objc_msgSend, Clong, (Ptr{Cvoid}, Ptr{Cvoid}), ns, sel("windowNumber"))
  path = tempname() * ".png"
  run(`screencapture -x -o -l $number $path`)
  shown[] = path
  close(w)
  GLFW.PostEmptyEvent()
  nothing
end

MiniFB.frame(w::Window) = begin
  # The third frame and later draw with the CPU
  SK.use_gpu[] = length(frames) < 2
  out = drawing(w) do canvas, size
    SK.Skia.sk_canvas_clear(canvas, 0xffff8000)   # orange
    rectangle(canvas, 20, 20, 40, 40, background=RGB(BLUE[1:3] ./ 255...))   # a blue square near the top left
  end
  push!(frames, (out, pixel(w, 150, 100), pixel(w, 40, 40), pixel(w, 40, 160)))
  length(frames) == 3 && ccall(:dispatch_after_f, Cvoid, (UInt64, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
    ccall(:dispatch_time, UInt64, (UInt64, Int64), 0, 300_000_000), cglobal(:_dispatch_main_q), C_NULL,
    @cfunction(shoot, Cvoid, (Ptr{Cvoid},)))
  w.wake = 0.1
  out
end

open(w)
SK.use_gpu[] = true

@testset "a window on the screen draws with the graphics card" begin
  gpu = frames[1:2]
  @test all(f -> f[1] isa Drawn, gpu)
  # The colours are right, and the picture isn't upside down
  @test all(f -> f[2:4] == (ORANGE, BLUE, ORANGE), gpu)
end

@testset "it lets go of what it drew with when it closes" begin
  @test isempty(SK.gpus)
end

@testset "a window that goes back to the CPU shows its picture" begin
  @test !(frames[3][1] isa Drawn)
  @test shown[] !== nothing
  if shown[] !== nothing
    # The picture has the window's title bar above the 300×200 points that the window draws
    wide, high = png_size(shown[])
    scale = wide / 300
    at(x, y) = png_pixel(shown[], x / 300, (high - (200 - y) * scale) / high)
    @test all(abs.(at(150, 100) .- ORANGE) .<= 3)
    @test all(abs.(at(40, 40) .- BLUE) .<= 3)
  end
end
