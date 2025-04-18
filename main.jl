@use "github.com/jkroso/Prospects.jl" @def @property
@use "github.com/jkroso/Font.jl/units" px mm Length
@use "./binding"...

@def struct Window
  window::MiniFBWindow
  task::Task
  title::String=""
  width::px=0px
  height::px=0px
end

function Window(f::Function, title::String, (x,y))
  window = minifb_window_new(title, int(x), int(y), resizable=true)
  t = errormonitor(@async begin
    while isopen(window)
      buffer = invokelatest(f, self)
      minifb_update_buffer(window, buffer)
      yield()
    end
    close(window)
  end)
  self = Window(window=window, task=t, title=title, width=x, height=y)
end

# Gets the window size in pixels
@property Window.size = px.(minifb_window_get_size(self.window))

int(p::px) = int(p.value)
int(p::Length) = int(convert(px, p))
int(x::AbstractFloat) = round(Int, x)
int(x) = x
