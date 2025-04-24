@use ".." Window frame onopen onkey Keys KeyPress mm Cursor
@use "github.com/jkroso/Prospects.jl" @def
@use Colors...
@use GLFW...

# Define the star's vertices
center = (16, 16)  # Center of the 32x32 image
R = 14.0  # Radius of the star
points = [(center[1] + R * cos(pi / 2 + 2 * pi * k / 5), center[2] + R * sin(pi / 2 + 2 * pi * k / 5)) for k in 0:4]
edges = [(points[1], points[3]), (points[3], points[5]), (points[5], points[2]), (points[2], points[4]), (points[4], points[1])]

# Function to check if a pixel is inside the star using ray-casting
function is_inside_star(j, i, edges)
  count = 0
  for edge in edges
    (x1, y1), (x2, y2) = edge
    # Check if the edge crosses the horizontal ray at y=i
    if (y1 < i && y2 > i) || (y1 > i && y2 < i)
      t = (i - y1) / (y2 - y1)
      x_int = x1 + t * (x2 - x1)
      if x_int > j  # Intersection is to the right of the pixel
        count += 1
      end
    end
  end
  count % 2 == 1  # Odd number of intersections means inside
end

const pixels = zeros(HSVA, 32, 32)
for i=1:32, j=1:32
  if is_inside_star(j, i, edges)
    # Rainbow color based on horizontal position
    h = j/32 * 360  # Hue from 0 to 360 degrees
    pixels[i,j] = HSVA(h, 1, 1, 1)
  end
end

frame(w::Window) = fill!(w.buffer, colorant"black")

onkey(w::Window, ::KeyPress{Keys.escape}) = close(w)

open(Window(title="Custom Cursor",
            size=[100mm,100mm],
            cursor=Cursor(pixels, (16, 16))))
