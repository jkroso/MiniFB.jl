@use ".." Window Keys KeyPress onkey px Vec2 frame mm Screen
@use Colors...
@use GLFW

# Create a window to demonstrate screen information
window = Window(
  title="Screen Info Example",
  size=[500px, 300px],
  position=[100mm, 100mm],
  animating=true)

function format_screen_info(screen::Screen)
  """
  Screen: $(screen.name)
  Size: $(screen.size[1])x$(screen.size[2])
  Position: ($(screen.position[1]), $(screen.position[2]))
  Scale: $(screen.content_scale[1])x, $(screen.content_scale[2])y
  """
end

function draw_text_lines(buffer, text_lines, start_x, start_y, color)
  height, width = size(buffer)
  # This is just a placeholder - in a real application, you would use
  # a proper text rendering library to draw text on the buffer
  # For this example, we'll just visualize different regions

  # Draw a colored rectangle to indicate text area
  rect_height = length(split(text_lines, '\n')) * 20
  rect_width = min(width - start_x, 400)

  for y in start_y:min(start_y + rect_height, height)
    for x in start_x:min(start_x + rect_width, width)
      if y - start_y < rect_height && x - start_x < rect_width
        buffer[y, x] = color
      end
    end
  end
end

function frame(w::Window)
  # Fill background with dark color
  fill!(w.buffer, RGB(0.2, 0.2, 0.3))

  # Get screen information
  primary_screen = Screen()
  current_screen = w.screen
  all_screens = [Screen(m) for m in GLFW.GetMonitors()]

  # Prepare text content
  primary_info = "PRIMARY SCREEN:\n" * format_screen_info(primary_screen)
  current_info = "CURRENT SCREEN:\n" * format_screen_info(current_screen)
  all_info = "ALL SCREENS ($(length(all_screens))):\n" *
             join([format_screen_info(s) for s in all_screens], "\n---\n")

  window_info = """
  WINDOW INFO:
  Position: ($(w.position[1]), $(w.position[2]))
  Size: $(w.size[1])x$(w.size[2])
  """

  # Draw info sections with different colors
  draw_text_lines(w.buffer, primary_info, 20, 20, RGB(0.9, 0.7, 0.7))
  draw_text_lines(w.buffer, current_info, 20, 120, RGB(0.7, 0.9, 0.7))
  draw_text_lines(w.buffer, window_info, 20, 220, RGB(0.7, 0.7, 0.9))

  w.buffer
end

# Event handlers
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

function onkey(w::Window, ::KeyPress{Keys.m})
  screens = [Screen(m) for m in GLFW.GetMonitors()]
  current = w.screen

  # Find current screen index
  current_idx = findfirst(s -> s.name == current.name, screens)
  if isnothing(current_idx)
    current_idx = 1
  end

  # Get next screen
  next_idx = current_idx % length(screens) + 1
  next_screen = screens[next_idx]

  # Center window on next screen
  center_x = next_screen.position[1] + next_screen.size[1]/2 - w.size[1]/2
  center_y = next_screen.position[2] + next_screen.size[2]/2 - w.size[2]/2

  w.position = Vec2{px}(center_x, center_y)
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
