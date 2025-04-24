@use ".." => MiniFB Window onfiledrop onkey KeyPress Keys px Vec2 int
@use Colors...

window = Window(
  title="File Drop Example",
  size=[400px, 300px],
  position=[100px, 100px],
  animating=true)

drop_time = 0.0
border_width = 20
easeout(t) = 1 - (1 - t)^3

# Generate a display with dropped files info
function MiniFB.frame(w::Window)
  img = fill!(w.buffer, colorant"white")

  # Highlight the canvas when files are dropped (briefly)
  current_time = time()

  # Check if we're in the animation timeframe
  if current_time - drop_time < 1
    progress = easeout(current_time - drop_time)
    # Apply a blue-to-white gradient based on progress
    highlight_color = RGB(progress, progress, 1)
    fill!(@view(img[border_width:end-border_width, border_width:end-border_width]), highlight_color)
  end

  # Draw drop zone border
  fill!(@view(img[begin:border_width, :]), colorant"steelblue")
  fill!(@view(img[end-border_width:end, :]), colorant"steelblue")
  fill!(@view(img[:, begin:border_width]), colorant"steelblue")
  fill!(@view(img[:, end-border_width:end]), colorant"steelblue")
  img
end

# Process dropped files
function onfiledrop(w::Window, paths)
  # Set the time of the drop to create highlight effect
  global drop_time = time()

  println("\nFiles dropped: $(length(paths))")
  for (i, path) in enumerate(paths)
    println("$i. $(basename(path)) ($(format_size(stat(path).size)))")
  end
end

# Helper function to format file size
function format_size(bytes)
  if bytes < 1024
    "$bytes B"
  elseif bytes < 1024^2
    "$(round(bytes/1024, digits=1)) KB"
  elseif bytes < 1024^3
    "$(round(bytes/1024^2, digits=1)) MB"
  else
    "$(round(bytes/1024^3, digits=1)) GB"
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
