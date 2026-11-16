# Tests that a window gets a frame at its new size while the loop waits for
# input. A drag of the window's edge keeps the loop in that wait until the
# mouse button goes up, and without a new frame macOS stretches the old one.
#
# The test changes a window's size from a function that macOS runs on the
# main thread while the loop waits, which is where a drag changes it.
#
# It opens three real windows, one after the other, for about a second each.
# They don't take the keyboard. Run it with `julia --project=. resize_test.jl`.
@use Test: @test, @testset
@use "./main" => MiniFB
@use "./main" Window
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use Colors: RGBA, N0f8
@use GLFW

"Run `f` on the main thread in `seconds`, when the loop next lets macOS handle events"
after(f, seconds) =
  ccall(:dispatch_after_f, Cvoid, (UInt64, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
        ccall(:dispatch_time, UInt64, (UInt64, Int64), 0, round(Int64, seconds * 1e9)),
        cglobal(:_dispatch_main_q), C_NULL, f)

size_of(w) = (round(Int, w.size[1].value), round(Int, w.size[2].value))

"""
Each frame: the window, its size, the size of its picture, how many frames
were being drawn when it started, and when it started
"""
const frames = []
const depth = Ref(0)
const deadline = time() + 20

const a = Window(title="resize test", size=Vec2{px}(300px, 200px), position=Vec2{px}(60px, 60px))
const b = Window(title="slow resize test", size=Vec2{px}(300px, 200px), position=Vec2{px}(60px, 60px))
const c = Window(title="slower resize test", size=Vec2{px}(300px, 200px), position=Vec2{px}(60px, 60px))
"How many seconds a frame of `b` or `c` takes, once `squeeze!` makes it slow. `c` is slower than `MiniFB.MOST_REST`."
const SLOW = IdDict{Window,Float64}(b => 0.06, c => 0.3)
"The windows that `squeeze!` made slow"
const slowed = Base.IdSet{Window}()

MiniFB.frame(w::Window) = begin
  depth[] += 1
  try
    now = size_of(w)
    push!(frames, (w, now, size(w.buffer), depth[], time()))
    if w === a
      # The first frame at 360×240 makes the window bigger, as a page that grows might
      now == (360, 240) && (w.size = Vec2{px}(400px, 260px))
      # The loop draws that size when the wait ends, and then the test is done
      now == (400, 260) && close(w)
    else
      w in slowed && Libc.systemsleep(SLOW[w])
      # Only the catch-up draws this size, since nothing wakes the loop
      now == (380, 250) && (close(w); GLFW.PostEmptyEvent())
    end
    time() > deadline && close(w)   # so a test that goes wrong doesn't wait for ever
    fill!(w.buffer, RGBA{N0f8}(0.8, 0.5, 0.2, 1))
  finally
    depth[] -= 1
  end
end

"What `grow` saw: how many frames there were before the new size, and after"
const seen = Ref((0, 0))

grow(_) = begin
  before = length(frames)
  GLFW.SetWindowSize(a.glfw[1], 360, 240)
  seen[] = (before, length(frames))
  GLFW.PostEmptyEvent()
  nothing
end

"What `squeeze!` saw for each window: whether the second size got a frame at once, how long that size took to set, and when"
const squeezed = IdDict{Window,Tuple{Bool,Float64,Float64}}()
"The windows that the test stopped waiting for, since the frame that `squeeze!` skipped never came"
const gave_up = Base.IdSet{Window}()

give_up(_) = begin
  for w in (b, c)
    isopen(w) && (push!(gave_up, w); close(w))
  end
  GLFW.PostEmptyEvent()
  nothing
end

squeeze!(w) = begin
  push!(slowed, w)
  GLFW.SetWindowSize(w.glfw[1], 360, 240)   # drawn at once, since the window has rested since its first frame
  before = length(frames)
  set = @elapsed GLFW.SetWindowSize(w.glfw[1], 380, 250)   # skipped, since the window hasn't rested at all
  squeezed[w] = (length(frames) > before, set, time())
  after(@cfunction(give_up, Cvoid, (Ptr{Cvoid},)), 5)
  nothing
end
squeeze_b(_) = squeeze!(b)
squeeze_c(_) = squeeze!(c)

# Each one waits until the window has rested longer than `MOST_REST`, so that
# its first frame, which Julia compiles, doesn't make the next one skip
MiniFB.onopen(w::Window) =
  after(w === a ? @cfunction(grow, Cvoid, (Ptr{Cvoid},)) :
        w === b ? @cfunction(squeeze_b, Cvoid, (Ptr{Cvoid},)) :
                  @cfunction(squeeze_c, Cvoid, (Ptr{Cvoid},)), 0.3)

a.wake = 0.5
open(a)
# `b` and `c` wait for as long as it takes, so only the catch-up can draw them
open(b)
open(c)

framesof(w) = filter(f -> f[1] === w, frames)

@testset "A window that gets a new size while the loop waits is drawn at once" begin
  before, after = seen[]
  new = frames[before+1:after]
  @test length(new) == 1
  if !isempty(new)
    @test new[1][2] == (360, 240)
    # The picture has the window's new size, in the screen's pixels
    scale = a.screen.content_scale
    @test new[1][3] == (round(Int, 240scale[2]), round(Int, 360scale[1]))
  end
end

@testset "A frame that changes the window's size isn't drawn again inside itself" begin
  @test maximum(f -> f[4], framesof(a)) == 1
  # The loop draws the window at the size that frame gave it, once the wait ends
  @test last(framesof(a))[2] == (400, 260)
end

@testset "A window with slow frames skips a size, and draws it once it has rested" for w in (b, c)
  drew_at_once, set, when = squeezed[w]
  @test !drew_at_once
  # The edge of the window moved without waiting for a frame
  @test set < SLOW[w] / 2
  @test !(w in gave_up)
  late = filter(f -> f[2] == (380, 250), framesof(w))
  @test length(late) == 1
  # It rested as long as its last frame took, but not longer than `MOST_REST`
  rest = min(SLOW[w], MiniFB.MOST_REST)
  isempty(late) || @test rest * 0.9 < late[1][5] - when < rest + 0.15
end
