# Tests that a cursor that's no longer used is destroyed on the main thread.
# Julia runs a finalizer on whichever thread collects the garbage, and GLFW
# throws if DestroyCursor comes from a thread that isn't the main one. So the
# finalizer puts the cursor on a list, and the loop destroys it between frames.
#
# It opens a small window for a moment. It doesn't take the keyboard. Run it
# with `julia -t 2 --project=. cursor_test.jl`.
@use Test: @test, @testset
@use "./main" => MiniFB
@use "./main" Window
@use "github.com/jkroso/Font.jl/units" px
@use GeometryBasics: Vec2
@use Colors: RGBA, N0f8
@use GLFW

"Run `f` in a task on a thread that isn't the main one, and return what it returns"
elsewhere(f) = begin
  for _ in 1:1000
    r = fetch(Threads.@spawn Threads.threadid() == 1 ? nothing : Some(f()))
    r === nothing || return something(r)
  end
  error("No task ran on another thread. Run the test with `julia -t 2`.")
end

"One frame, which closes the window"
MiniFB.frame(w::Window) = (close(w); fill!(w.buffer, RGBA{N0f8}(0.8, 0.5, 0.2, 1)))

@testset "a cursor that's no longer used is destroyed on the main thread" begin
  @test Threads.nthreads() > 1
  c = MiniFB.Cursor(GLFW.HAND_CURSOR)
  # The garbage collector can run the finalizer on another thread, as it did beside hot_reload.jl's watcher
  @test elsewhere(() -> try MiniFB.destroy(c); true catch e; e end) === true
  @test c.glfw in MiniFB.unused_cursors
  # The loop destroys it on the main thread
  w = Window(title="cursor test", size=Vec2{px}(200px, 100px), position=Vec2{px}(60px, 60px))
  open(w)
  @test isempty(MiniFB.unused_cursors)
end
