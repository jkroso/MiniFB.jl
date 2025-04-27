@use ".." Window Keys KeyPress onkey onreposition px Vec2 frame mm Screen
@use Colors...
@use GLFW

window = Window(
  title="Screen Info Example",
  size=[500px, 300px],
  position=[100mm, 100mm],
  animating=true)

function format_screen_info(screen::Screen)
  """
  Screen: $(screen.name)
  Size: ($(screen.size[1]), $(screen.size[2]))|($(convert(mm, screen.size[1])), $(convert(mm, screen.size[2])))
  Position: ($(screen.position[1]), $(screen.position[2]))
  Scale: x=$(screen.content_scale[1]), y=$(screen.content_scale[2])\
  """
end

frame(w::Window) = fill!(w.buffer, RGB(0.2, 0.2, 0.3))

previous_screen = nothing
function onreposition(w::Window, _)
  global previous_screen
  if w.screen != previous_screen
    all_screens = [Screen(m) for m in GLFW.GetMonitors()]
    println("# of screens ($(length(all_screens)))")
    println("CURRENT SCREEN:\n" * format_screen_info(w.screen))
    previous_screen = w.screen
  end
end

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

function onkey(w::Window, ::KeyPress{Keys.m})
  screens = [Screen(m) for m in GLFW.GetMonitors()]
  current_idx = findfirst(s -> s.name == w.screen.name, screens)
  next_idx = current_idx % length(screens) + 1
  next_screen = screens[next_idx]

  # Center window on next screen
  w.position = next_screen.position + next_screen.size/2 - w.size/2

  println("Moved to screen: $(next_screen.name)")
end

println("""
Screen Information Example
-------------------------
Controls:
- M: Move to next monitor (if multiple monitors are present)
- ESC: Close window

This example shows how to use the Screen API to get information about monitors.
It displays information about the primary screen, the current screen, and all screens.
Try moving the window between monitors to see the current screen information update.
""")

open(window)
