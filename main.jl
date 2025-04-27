@use "github.com/jkroso/Prospects.jl" @def @abstract Field ["BitSet" @BitSet setinstances!]
@use "github.com/jkroso/Font.jl/units" px mm Length
@use GeometryBasics: Vec2, Vec2i
@use ModernGL...
@use Colors...
@use GLFW...

GLFW.Init()
GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 3)
GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
GLFW.WindowHint(GLFW.TRANSPARENT_FRAMEBUFFER, false)
GLFW.WindowHint(GLFW.VISIBLE, false)
GLFW.WindowHint(GLFW.FOCUSED, false)
GLFW.WindowHint(GLFW.FOCUS_ON_SHOW, true)

const vertexShaderSource = """
#version 330 core
layout (location = 0) in vec2 aPos;
layout (location = 1) in vec2 aTexCoord;
out vec2 TexCoord;
void main() {
    gl_Position = vec4(aPos, 0.0, 1.0);
    TexCoord = vec2(aTexCoord.x, 1.0 - aTexCoord.y);
}
"""

const fragmentShaderSource = """
#version 330 core
in vec2 TexCoord;
out vec4 FragColor;
uniform sampler2D texture1;
void main() {
    FragColor = texture(texture1, vec2(TexCoord.y, TexCoord.x));
}
"""

# Define quad vertices and indices (position and texture coordinates)
const vertices = Float32[
  -1.0, -1.0,  0.0, 0.0,  # Bottom-left
   1.0, -1.0,  1.0, 0.0,  # Bottom-right
   1.0,  1.0,  1.0, 1.0,  # Top-right
  -1.0,  1.0,  0.0, 1.0   # Top-left
]

const indices = UInt32[0, 1, 2, 2, 3, 0]

"""
A very efficient way of representing every possible keyboard and mouse button combination.
To test if the user did a cmd+click you write:

  key_state == Keys.cmd|Keys.mouse_left
"""
@BitSet Keys::UInt128
let syntax = "tilde minus equal left_bracket right_bracket semicolon apostrophe comma period slash backslash times plus"
    specials = "tab capslock enter shft cmd opt ctrl escape delete backspace space fn home pageup pagedown end clear eject insert left right up down"
  setinstances!(Keys, map(Symbol, vcat(split(syntax),
                                      'a':'z',
                                      0:9,
                                      ["num$n" for n in 0:9],
                                      ["f$n" for n in 1:25],
                                      split(specials),
                                      [:mouse_left, :mouse_right, :mouse_middle])))
end

const keymap = Dict(GLFW.KEY_ENTER => Keys.enter,
                    GLFW.KEY_PAGE_UP => Keys.pageup,
                    GLFW.KEY_PAGE_DOWN => Keys.pagedown,
                    GLFW.KEY_CAPS_LOCK => Keys.capslock,
                    GLFW.KEY_KP_0 => Keys.num0,
                    GLFW.KEY_KP_1 => Keys.num1,
                    GLFW.KEY_KP_2 => Keys.num2,
                    GLFW.KEY_KP_3 => Keys.num3,
                    GLFW.KEY_KP_4 => Keys.num4,
                    GLFW.KEY_KP_5 => Keys.num5,
                    GLFW.KEY_KP_6 => Keys.num6,
                    GLFW.KEY_KP_7 => Keys.num7,
                    GLFW.KEY_KP_8 => Keys.num8,
                    GLFW.KEY_KP_9 => Keys.num9,
                    GLFW.KEY_KP_ADD => Keys.plus,
                    GLFW.KEY_KP_MULTIPLY => Keys.times,
                    GLFW.KEY_KP_DIVIDE => Keys.slash,
                    GLFW.KEY_KP_SUBTRACT => Keys.minus,
                    GLFW.KEY_KP_ENTER => Keys.enter,
                    GLFW.KEY_KP_EQUAL => Keys.equal,
                    GLFW.KEY_KP_DECIMAL => Keys.period,
                    GLFW.KEY_LEFT_SHIFT => Keys.shft,
                    GLFW.KEY_RIGHT_SHIFT => Keys.shft,
                    GLFW.KEY_RIGHT_ALT => Keys.opt,
                    GLFW.KEY_LEFT_ALT => Keys.opt,
                    GLFW.KEY_LEFT_CONTROL => Keys.ctrl,
                    GLFW.KEY_RIGHT_CONTROL => Keys.ctrl,
                    GLFW.KEY_RIGHT_SUPER => Keys.cmd,
                    GLFW.KEY_LEFT_SUPER => Keys.cmd,
                    GLFW.KEY_GRAVE_ACCENT => Keys.tilde)

for k in instances(GLFW.Key)
  haskey(keymap, k) && continue # already mapped
  s = Symbol(lowercase(string(k)[5:end]))
  hasproperty(Keys, s) && (keymap[k] = getproperty(Keys, s))
end

Base.convert(::Type{Keys}, k::GLFW.Key) = keymap[k]
Base.convert(::Type{Keys}, b::GLFW.MouseButton) = begin
  b == GLFW.MOUSE_BUTTON_1 ? Keys.mouse_left : b == GLFW.MOUSE_BUTTON_2 ? Keys.mouse_right : Keys.mouse_middle
end

@def struct Cursor
  image::AbstractMatrix
  hotspot::Vec2{px}=Vec2{px}(0, 0)
end

"""
Represents the screen/monitor where the window is displayed.
Provides access to screen size, resolution, DPI scale factors
"""
struct Screen
  monitor::GLFW.Monitor
  size::Vec2{px}      # Physical size in pixels
  position::Vec2{px}  # Position in virtual screen coordinates
  content_scale::Vec2{Float32}  # DPI scaling factors
  name::String
end

Screen(monitor::GLFW.Monitor=GLFW.GetPrimaryMonitor()) = begin
  mode = GLFW.GetVideoMode(monitor)
  width, height = mode.width, mode.height
  xpos, ypos = GLFW.GetMonitorPos(monitor)
  xscale, yscale = GLFW.GetMonitorContentScale(monitor)
  name = GLFW.GetMonitorName(monitor)
  Screen(monitor, Vec2{px}(px(width), px(height)), Vec2{px}(px(xpos), px(ypos)), Vec2{Float32}(xscale, yscale), name)
end

@abstract struct AbstractWindow
  glfw::Vector=[] # everything needed by GLFW to manage the window
  title::String=""
  size::Vec2{px}=Vec2(0px, 0px)
  buffer::Matrix{RGBA{Colors.N0f8}}=Matrix{RGBA{Colors.N0f8}}(undef, 0, 0)
  position::Vec2{px}=Vec2(0px, 0px)
  mouse::Vec2{px}=Vec2(0px, 0px)
  keys::Keys=Keys(0)
  animating::Bool=false
  cursor::Union{Nothing,Cursor,GLFW.Cursor}=nothing
  screen::Screen=Screen()
end

Base.setproperty!(w::AbstractWindow, ::Field{:cursor}, cursor) = begin
  c = tocursor(cursor)
  setfield!(w, :cursor, c)
  change_cursor(w, c)
  cursor
end

Base.setproperty!(w::AbstractWindow, ::Field{:position}, position) = begin
  isempty(w.glfw) || GLFW.SetWindowPos(w.glfw[1], int(position[1]), int(position[2]))
  position == w.position || invokelatest(onreposition, w, position)
  setfield!(w, :position, position)
  w.screen = getscreen(w)
  position
end

Base.setproperty!(w::AbstractWindow, ::Field{:size}, size) = begin
  isempty(w.glfw) || GLFW.SetWindowSize(w.glfw[1], int(size[1]), int(size[2]))
  newsize = Vec2{px}(convert(px, size[1]), convert(px, size[2]))
  newsize == w.size || invokelatest(onresize, w, newsize)
  setfield!(w, :size, size)
  w.screen = getscreen(w)
  size
end

tocursor(c::GLFW.StandardCursorShape) = GLFW.CreateStandardCursor(c)
tocursor(c) = c

change_cursor(w::AbstractWindow, c::GLFW.Cursor) = GLFW.SetCursor(w.glfw[1], c)
change_cursor(w::AbstractWindow, c::Cursor) = begin
  hotspot = (int(c.hotspot[1]), int(c.hotspot[2]))
  img = map(p->reinterpret(NTuple{4,UInt8}, RGBA{Colors.N0f8}(p)), c.image)
  change_cursor(w, GLFW.CreateCursor(img, hotspot))
end

"If your app only has one kind of window then you may as well just use this type"
@def mutable struct Window <: AbstractWindow end

int(p::px) = int(p.value)
int(p::Length) = int(convert(px, p))
int(x::AbstractFloat) = round(Int, x)
int(x) = x

"Called whenever the window is resized (internal buffer size change)"
onbuffer_resize(window, newsize) = nothing

"Called whenever the window is resized (window size change)"
onresize(window, newsize) = nothing

abstract type KeyEvent{key} end
struct KeyPress{key} <: KeyEvent{key}
  keycode::Int
end
struct KeyRelease{key} <: KeyEvent{key}
  keycode::Int
end

"Called on any keyboard/mouse button press or release"
onkey(window, event) = nothing

"""
Called when the mouse moves. Even if it's outside the window. The position is given relative
to the window so it can be negative in either x or y direction
"""
onmouse(window, pos) = nothing

"Called when either scroll wheel is moved. `delta` is a `Vec{2,px}` with horizontal,vertical order"
onscroll(window, delta) = nothing

"Called when the window position changes. `pos` is the new window position as a `Vec2{px}`"
onreposition(window, pos) = nothing

"Called when files are dropped onto the window. `paths` is an array of file paths"
onfiledrop(window, paths) = nothing

"Called once when the window first opens"
onopen(window) = nothing

"Generate a pixel buffer to display. If the size doesn't match the window then it will be stretched"
frame(w::AbstractWindow) = w.buffer

Base.open(w::AbstractWindow) = begin
  width, height = int.(w.size)
  window = GLFW.CreateWindow(width, height, w.title)
  GLFW.MakeContextCurrent(window)
  GLFW.SwapInterval(1)
  GLFW.SetWindowPos(window, int.(w.position)...)
  bx,by = GLFW.GetFramebufferSize(window)
  w.buffer = Matrix{RGBA{Colors.N0f8}}(undef, by, bx)
  glViewport(0, 0, bx, by)
  GLFW.ShowWindow(window)

  # Compile shaders
  vertexShader = glCreateShader(GL_VERTEX_SHADER)
  glShaderSource(vertexShader, 1, [vertexShaderSource], C_NULL)
  glCompileShader(vertexShader)

  fragmentShader = glCreateShader(GL_FRAGMENT_SHADER)
  glShaderSource(fragmentShader, 1, [fragmentShaderSource], C_NULL)
  glCompileShader(fragmentShader)

  # Create and link shader program
  shaderProgram = glCreateProgram()
  glAttachShader(shaderProgram, vertexShader)
  glAttachShader(shaderProgram, fragmentShader)
  glLinkProgram(shaderProgram)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)
  # Set up VAO, VBO, and EBO
  VAO = Ref{GLuint}(0)
  glGenVertexArrays(1, VAO)
  glBindVertexArray(VAO[])

  VBO = Ref{GLuint}(0)
  glGenBuffers(1, VBO)
  glBindBuffer(GL_ARRAY_BUFFER, VBO[])
  glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW)

  EBO = Ref{GLuint}(0)
  glGenBuffers(1, EBO)
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, EBO[])
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(indices), indices, GL_STATIC_DRAW)

  # Set vertex attribute pointers
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), C_NULL)
  glEnableVertexAttribArray(0)
  glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(Float32), Ptr{Cvoid}(2 * sizeof(Float32)))
  glEnableVertexAttribArray(1)
  glBindVertexArray(0)

  # Create and configure texture
  texture = Ref{GLuint}(0) # Define a reference to hold the texture ID
  glGenTextures(1, texture) # Generate one texture and store the ID in texture
  # Use the texture ID in subsequent calls, e.g., binding the texture
  glBindTexture(GL_TEXTURE_2D, texture[])
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)

  GLFW.SetFramebufferSizeCallback(window, function(window, width, height)
    glViewport(0, 0, width, height)
    newsize = (width, height)
    invokelatest(onbuffer_resize, w, newsize)
    w.buffer = Matrix{RGBA{Colors.N0f8}}(undef, height, width)
  end)

  GLFW.SetWindowSizeCallback(window, function(window, width, height)
    w.size = Vec2{px}(px(width), px(height))
  end)

  GLFW.SetKeyCallback(window, function(window, keyenum, keycode, action, _)
    key = convert(Keys, keyenum)
    if action == GLFW.PRESS
      w.keys |= key
      invokelatest(onkey, w, KeyPress{key}(keycode))
    else
      w.keys ⊻= key
      invokelatest(onkey, w, KeyRelease{key}(keycode))
    end
  end)

  GLFW.SetCursorPosCallback(window, function(window, x::Float64, y::Float64)
    newpos = Vec2{px}(x, y)
    invokelatest(onmouse, w, newpos)
    w.mouse = newpos
  end)

  GLFW.SetMouseButtonCallback(window, function(window, button, action, _)
    key = convert(Keys, button)
    if action == GLFW.PRESS
      w.keys |= key
      invokelatest(onkey, w, KeyPress{key}(0))
    else
      w.keys ⊻= key
      invokelatest(onkey, w, KeyRelease{key}(0))
    end
  end)

  GLFW.SetScrollCallback(window, function(window, x, y)
    invokelatest(onscroll, w, Vec2{px}(x, y))
  end)

  GLFW.SetWindowPosCallback(window, function(window, x, y)
    w.position = Vec2{px}(px(x), px(y))
  end)

  GLFW.SetDropCallback(window, function(window, paths)
    invokelatest(onfiledrop, w, paths)
  end)

  w.glfw = [window, texture, shaderProgram, VAO, VBO, EBO]

  onopen(w)
  isnothing(w.cursor) || change_cursor(w, w.cursor)
  w.screen = getscreen(w)

  wait(@async begin
    while !GLFW.WindowShouldClose(window)
      invokelatest(redraw, w)
      yield()
      w.animating ? GLFW.PollEvents() : GLFW.WaitEvents()
    end
    cleanup(w)
  end)
end

unpack(c::Colorant) = reinterpret(NTuple{4,UInt8}, RGBA{Colors.N0f8}(c))
unpack(c::UInt32) = reinterpret(NTuple{4,UInt8}, c)
unpack(m::AbstractMatrix) = unpack.(m)
unpack(m::AbstractMatrix{RGBA{Colors.N0f8}}) = reinterpret(NTuple{4,UInt8}, m)

redraw(w::AbstractWindow) = begin
  window, texture, shaderProgram, VAO, VBO, EBO = w.glfw
  GLFW.MakeContextCurrent(window)
  image = invokelatest(frame, w)
  y,x = size(image)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, y, x, 0, GL_RGBA, GL_UNSIGNED_BYTE, unpack(image))
  glUseProgram(shaderProgram)
  glBindTexture(GL_TEXTURE_2D, texture[])
  glBindVertexArray(VAO[])
  glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, C_NULL)
  glBindVertexArray(0)
  glBindTexture(GL_TEXTURE_2D, texture[])
  GLFW.SwapBuffers(window)
end

cleanup(w::AbstractWindow) = begin
  window, texture, shaderProgram, VAO, VBO, EBO = w.glfw
  glDeleteTextures(1, [texture[]])
  glDeleteVertexArrays(1, [VAO[]])
  glDeleteBuffers(1, [VBO[]])
  glDeleteBuffers(1, [EBO[]])
  glDeleteProgram(shaderProgram)
  GLFW.DestroyWindow(window)
end

Base.close(w::AbstractWindow) = GLFW.SetWindowShouldClose(w.glfw[1], true)

"""
Get the screen where a specific window is located.
If the window spans multiple screens, returns the screen with the largest overlap.
"""
function getscreen(w::AbstractWindow)
  isempty(w.glfw) && return Screen() # primary screen

  win_pos = w.position
  win_size = w.size
  screens = [Screen(m) for m in GLFW.GetMonitors()]

  maxoverlap, i = findmax(screens) do screen
    left = max(win_pos[1], screen.position[1])
    right = min(win_pos[1] + win_size[1], screen.position[1] + screen.size[1])
    top = max(win_pos[2], screen.position[2])
    bottom = min(win_pos[2] + win_size[2], screen.position[2] + screen.size[2])
    (right - left) * (bottom - top)
  end
  screens[i]
end

export Window, AbstractWindow, frame, redraw, onkey, KeyPress, KeyRelease, Keys, onopen, onmouse, onresize,
       onreposition, Cursor, Screen
