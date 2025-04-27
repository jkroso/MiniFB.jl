@use ".." @def frame onkey Window Keys KeyPress mm int px AbstractWindow Screen onresize onbuffer_resize
@use Colors...

@def mutable struct FPSTest <: AbstractWindow
  wave::UInt8=0
  direction::Int8=3
  time::Float64=time()
  frames::UInt16=0
end

const window = FPSTest(title="Red and Blue", size=Screen().size, animating=true)

function frame(w::FPSTest)
  w.wave = w.wave + w.direction
  (0 < w.wave < 255) || (w.direction = @fastmath -w.direction)
  w.frames += 1%UInt16
  newtime = time()
  if newtime - w.time > 1
    println("FPS: $(w.frames)")
    w.frames = 0%UInt16
    w.time = newtime
  end
  fill!(w.buffer, RGBA{Colors.N0f8}(w.wave/256, 64/256, (256-w.wave)/256, 1))
end

# close when esc is pressed
onkey(w::FPSTest, ::KeyPress{Keys.escape}) = close(w)

onresize(w::FPSTest, size) = println("New size is: $(size[1]), $(size[2])")
onbuffer_resize(w::FPSTest, size) = println("New buffer size is: $(size[1]), $(size[2])")

println("""
Press ESC to close the window. Resize the window to see how it affects the frame rate.
Note: `isinteractive()` will have a big impact on FPS so don't run this example from
a REPL
""")

open(window)
