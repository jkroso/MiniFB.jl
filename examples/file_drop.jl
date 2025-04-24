@use ".." => MiniFB Window onfiledrop onkey KeyPress Keys px Vec2 int
@use Colors...

# Create a window with a welcoming message
window = Window(
  title="File Drop Example",
  size=[400px, 300px],
  position=[100px, 100px],
  animating=true
)

# Store dropped files
dropped_files = String[]
drop_time = 0.0
animation_end_time = 0.0

# Generate a display with dropped files info
function MiniFB.frame(w::Window)
  # Create a blank canvas
  width, height = int.(w.size)
  img = fill(colorant"white", height, width)

  # Draw header
  header = "Drag and drop files here"
  text_color = colorant"black"

  # Highlight the canvas when files are dropped (briefly)
  global drop_time, animation_end_time
  current_time = time()

  # Check if we're in the animation timeframe
  if drop_time > 0 && current_time < animation_end_time
    # Calculate how far into the animation we are (0.0 to 1.0)
    progress = (current_time - drop_time) / 1.0

    # Apply a blue-to-white gradient based on progress
    highlight_color = RGB(0.8 - 0.2 * progress, 0.9 - 0.1 * progress, 1.0)
    img .= highlight_color
  else
    # Reset animation state if we've passed the end time
    if drop_time > 0 && current_time >= animation_end_time
      drop_time = 0.0
    end
  end

  # Draw drop zone border
  border_width = 2
  for i in 1:height
    for j in 1:width
      if i <= border_width || i > height - border_width ||
         j <= border_width || j > width - border_width
        img[i, j] = colorant"steelblue"
      end
    end
  end

  return img
end

# Process dropped files
function MiniFB.onfiledrop(w::Window, paths)
  global dropped_files, drop_time, animation_end_time

  # Update the list of dropped files
  dropped_files = paths

  # Set the time of the drop to create highlight effect
  drop_time = time()
  animation_end_time = drop_time + 1.0  # Animation lasts 1 second

  # Display information about dropped files
  println("\nFiles dropped: $(length(paths))")
  for (i, path) in enumerate(paths)
    filename = basename(path)
    filesize = stat(path).size
    println("$i. $filename ($(format_size(filesize)))")
  end

  MiniFB.redraw(w)
end

# Helper function to format file size
function format_size(bytes)
  if bytes < 1024
    return "$bytes B"
  elseif bytes < 1024^2
    return "$(round(bytes/1024, digits=1)) KB"
  elseif bytes < 1024^3
    return "$(round(bytes/1024^2, digits=1)) MB"
  else
    return "$(round(bytes/1024^3, digits=1)) GB"
  end
end

# Handle escape key to exit
onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

println("""
File Drop Example
----------------
- Drag and drop files onto the window
- File information will be displayed in the terminal
- Press ESC to exit
""")

open(window)
