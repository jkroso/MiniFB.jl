# Tests for drawing a window with Skia. The window isn't put on the screen.
# Run it with `julia --project=. skia_test.jl`.
@use Test: @test, @testset
@use "./main" Window
@use "./skia" drawing drop_buffer!
@use Skia
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use Colors: ARGB32
@use Base64: base64decode

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

# A PNG of 2×2 pixels of #F38020 with the Display P3 colour profile, as an
# iPhone saves a photo. In P3 the numbers of its pixels are (228,134,59).
const P3_ORANGE = base64decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAABY2lDQ1BrQ0dDb2xvclNwYWNlRGlzcGxheVAzAAAokX2QsUvDUBDGv1aloHUQHRwcMolDlJIKuji0FURxCFXB6pS+pqmQxkeSIgU3/4GC/4EKzm4Whzo6OAiik+jm5KTgouV5L4mkInqP435877vjOCA5bnBu9wOoO75bXMorm6UtJfWMBL0gDObxnK6vSv6uP+P9PvTeTstZv///jcGK6TGqn5QZxl0fSKjE+p7PJe8Tj7m0FHFLshXyieRyyOeBZ71YIL4mVljNqBC/EKvlHt3q4brdYNEOcvu06WysyTmUE1jEDjxw2DDQhAId2T/8s4G/gF1yN+FSn4UafOrJkSInmMTLcMAwA5VYQ4ZSk3eO7ncX3U+NtYMnYKEjhLiItZUOcDZHJ2vH2tQ8MDIEXLW54RqB1EeZrFaB11NguASM3lDPtlfNauH26Tww8CjE2ySQOgS6LSE+joToHlPzA3DpfAEDp2ITpJYOWwAAAARjSUNQDA0AAW4D4+8AAAA4ZVhJZk1NACoAAAAIAAGHaQAEAAAAAQAAABoAAAAAAAKgAgAEAAAAAQAAAAKgAwAEAAAAAQAAAAIAAAAAztCekAAAABNJREFUCB1jfNJmzcDAwATEQAAAFI8Bqa3DfC0AAAAASUVORK5CYII=")

@testset "a picture with a colour profile of its own is drawn in sRGB" begin
  data = Skia.sk_data_new_with_copy(pointer(P3_ORANGE), Csize_t(length(P3_ORANGE)))
  image = Skia.sk_image_new_from_encoded(data)
  Skia.sk_data_unref(data)
  whole = Ref(Skia.sk_rect_t(0f0, 0f0, 2f0, 2f0))
  sampling = Ref(Skia.sk_sampling_options_t(0, false, Skia.sk_cubic_resampler_t(0f0, 0f0), Skia.SK_FILTER_MODE_NEAREST, Skia.SK_MIPMAP_MODE_NONE))
  out = drawing((2, 2); scale=(1.0, 1.0)) do canvas, size
    paint = Skia.sk_paint_new()
    Skia.sk_canvas_draw_image_rect(canvas, image, whole, whole, sampling, paint, Skia.SRC_RECT_CONSTRAINT_FAST)
    Skia.sk_paint_delete(paint)
  end
  Skia.sk_image_unref(image)
  v = reinterpret(UInt32, out[1, 1])
  # Copied as they are, the numbers would be (228,134,59), and the photo would look dull
  @test all(abs.(Int.((v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff)) .- (243, 128, 32)) .<= 1)
end
