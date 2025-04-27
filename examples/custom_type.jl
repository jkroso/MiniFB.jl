@use ".." AbstractWindow frame onmouse onkey onscroll Vec2 px Keys KeyPress mm int
@use "github.com/jkroso/Prospects.jl" @def
@use Colors...

"Here we define our own window type which means we don't have to worry
about overwriting other methods"
@def mutable struct GradientAnimation <: AbstractWindow
  time::Float64=0.0
  from::RGB24=RGB24(1, .2, 0)
  to::RGB24=RGB24(0, 0.2, 1)
end

function interpolate(t::Float64, a::RGB24, b::RGB24)
  RGB24(red(a) * (1 - t) + red(b) * t,
        green(a) * (1 - t) + green(b) * t,
        blue(a) * (1 - t) + blue(b) * t,)
end

function frame(w::GradientAnimation)
  x, y = int.(w.size*w.screen.content_scale)
  w.time += 9
  w.time > x && (w.time = 0.0)
  row = map(1:x) do i
    phase = mod((i + w.time) / (x/2), 2.0)
    t = phase <= 1.0 ? phase : 2.0 - phase
    interpolate(t, w.from, w.to)
  end
  repeat(row', y, 1)
end

function onmouse(w::GradientAnimation, pos::Vec2{px})
  @show pos
end

function onscroll(w::GradientAnimation, delta::Vec2{px})
  @show delta
end

onkey(w::GradientAnimation, ::KeyPress{Keys.escape}) = close(w)
onkey(w::GradientAnimation, ::KeyPress{Keys.mouse_left}) = println("click!")

open(GradientAnimation(title="Gradient", animating=true, size=[200mm,200mm]))
