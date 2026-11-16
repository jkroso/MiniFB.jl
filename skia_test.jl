# Tests for drawing a window with Skia. The window isn't put on the screen.
# Run it with `julia --project=. skia_test.jl`.
@use Test: @test, @testset
@use "./main" Window
@use "./skia" drawing drop_buffer!
@use Skia
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use Colors: ARGB32

const w = Window(title="skia test", size=Vec2{px}(400px, 300px))

"Draw `w` filled with orange, and return its picture and the place of its pixels in memory"
picture() = begin
  image = drawing(w) do canvas, size
    Skia.sk_canvas_clear(canvas, 0xffff8000)   # orange, as 0xAARRGGBB
  end
  image, pointer(parent(parent(parent(image))))
end

@testset "a window that grows a little at a time keeps its buffer" begin
  places = Set{Ptr{UInt32}}()
  for i in 1:30
    w.size = Vec2{px}(px(400 + i), px(300 + i))
    image, place = picture()
    push!(places, place)
    scale = w.screen.content_scale
    @test size(image) == (round(Int, (300 + i)scale[2]), round(Int, (400 + i)scale[1]))
    @test image[end, end] == reinterpret(ARGB32, 0xffff8000)
  end
  # 30 sizes, up to 18% more pixels than the first, and its buffer has room for 25% more
  @test length(places) == 1
end

@testset "a window that becomes much smaller gives the memory back" begin
  _, before = picture()
  w.size = Vec2{px}(200px, 150px)
  image, after = picture()
  @test after != before
  @test image[1, 1] == reinterpret(ARGB32, 0xffff8000)
  drop_buffer!(w)
end
