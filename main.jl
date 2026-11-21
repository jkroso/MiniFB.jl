@use "github.com/jkroso/Prospects.jl" @def @abstract Field ["BitSet" @BitSet]
@use "github.com/jkroso/Font.jl/units" px mm Length
@use GeometryBasics: Vec2, Vec2i
@use ModernGL...
@use Colors...
@use GLFW...
@use LinearAlgebra: Adjoint

function __init__()
  GLFW.Init()
  GLFW.WindowHint(GLFW.CONTEXT_VERSION_MAJOR, 3)
  GLFW.WindowHint(GLFW.CONTEXT_VERSION_MINOR, 3)
  GLFW.WindowHint(GLFW.OPENGL_PROFILE, GLFW.OPENGL_CORE_PROFILE)
  GLFW.WindowHint(GLFW.TRANSPARENT_FRAMEBUFFER, false)
  GLFW.WindowHint(GLFW.STENCIL_BITS, 8)   # Skia draws some shapes with the stencil when it draws with the graphics card
  GLFW.WindowHint(GLFW.SAMPLES, 0)
  GLFW.WindowHint(GLFW.VISIBLE, false)
  GLFW.WindowHint(GLFW.FOCUSED, false)
  GLFW.WindowHint(GLFW.FOCUS_ON_SHOW, true)
  default_cursor[] = Cursor(GLFW.ARROW_CURSOR)
end

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
uniform bool by_column;
void main() {
    FragColor = texture(texture1, by_column ? vec2(TexCoord.y, TexCoord.x) : TexCoord);
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
@BitSet Keys """
  tilde minus equal left_bracket right_bracket semicolon apostrophe comma period slash backslash times plus
  a:z 0:9 num(0:9) f(1:25) tab capslock enter shft cmd opt ctrl escape delete backspace space fn home pageup
  pagedown _end clear eject insert left right up down mouse_left mouse_right mouse_middle mouse_back mouse_forward
"""

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
# The fourth and fifth buttons are the two at the side of a mouse, which go back and forward in a web
# browser. Any other button counts as the middle one.
Base.convert(::Type{Keys}, b::GLFW.MouseButton) = begin
  b == GLFW.MOUSE_BUTTON_1 ? Keys.mouse_left :
  b == GLFW.MOUSE_BUTTON_2 ? Keys.mouse_right :
  b == GLFW.MOUSE_BUTTON_4 ? Keys.mouse_back :
  b == GLFW.MOUSE_BUTTON_5 ? Keys.mouse_forward : Keys.mouse_middle
end

"Adds auto memory management to GLFW's Cursor type"
mutable struct Cursor
  image::AbstractMatrix
  hotspot::Vec2{px}
  glfw::GLFW.Cursor
  Cursor(image, hotspot=Vec2{px}(0,0)) = begin
    finalizer(destroy, new(image, hotspot, GLFW.CreateCursor(unpack(image), (int(hotspot[1]), int(hotspot[2])))))
  end
  Cursor(e::GLFW.StandardCursorShape) = begin
    finalizer(destroy, new(Matrix{NTuple{4, RGBA{Colors.N0f8}}}(undef, 0, 0),
                           Vec2{px}(0,0),
                           GLFW.CreateStandardCursor(e)))
  end
end

"The cursors that nothing uses any more, which the loop destroys between frames"
const unused_cursors = GLFW.Cursor[]
const unused_lock = Threads.SpinLock()   # a SpinLock, since a finalizer can't wait for a lock that yields

"""
The finalizer of a Cursor. Julia runs it on whichever thread collects the
garbage, such as hot_reload.jl's watcher, and maybe while GLFW calls a handler.
GLFW destroys a cursor only on the main thread and outside its handlers, so
this puts the cursor on a list for the loop.
"""
destroy(c::Cursor) = (lock(() -> push!(unused_cursors, c.glfw), unused_lock); nothing)

"Destroy the cursors that nothing uses any more. Only the loop calls this, on the main thread, between frames."
destroy_unused_cursors!() = begin
  gone = lock(unused_lock) do
    list = copy(unused_cursors)
    empty!(unused_cursors)
    list
  end
  GLFW.is_initialized() && foreach(GLFW.DestroyCursor, gone)
  nothing
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

const default_cursor = Ref{Cursor}()

@abstract struct AbstractWindow
  glfw::Vector=[] # everything needed by GLFW to manage the window
  title::String=""
  size::Vec2{px}=Vec2(0px, 0px)
  position::Vec2{px}=Vec2(0px, 0px)
  mouse::Vec2{px}=Vec2(0px, 0px)
  keys::Keys=Keys(0)
  animating::Bool=false
  # While it isn't animating, the window is only drawn again when something
  # happens to it. Set `wake` to draw it again after that many seconds anyway,
  # e.g. to blink a caret. 0 means wait for as long as it takes.
  wake::Float64=0.0
  cursor::Cursor=default_cursor[]
  screen::Screen=Screen()
  focus::Any=nothing
  ui::Any=nothing
end

Base.setproperty!(w::AbstractWindow, ::Field{:cursor}, cursor) = begin
  c = cursor isa GLFW.StandardCursorShape ? Cursor(cursor) : cursor
  setfield!(w, :cursor, c)
  GLFW.SetCursor(w.glfw[1], c.glfw)
  cursor
end

Base.setproperty!(w::AbstractWindow, ::Field{:position}, position) = begin
  position == w.position && return position
  invokelatest(onreposition, w, position)
  setfield!(w, :position, position)
  isempty(w.glfw) || GLFW.SetWindowPos(w.glfw[1], int(position[1]), int(position[2]))
  w.screen = getscreen(w)
  position
end

Base.setproperty!(w::AbstractWindow, ::Field{:size}, size) = begin
  size == w.size && return size
  invokelatest(onresize, w, Vec2{px}(convert(px, size[1]), convert(px, size[2])))
  setfield!(w, :size, size)
  isempty(w.glfw) || GLFW.SetWindowSize(w.glfw[1], int(size[1]), int(size[2]))
  w.screen = getscreen(w)
  size
end

int(p::px) = int(p.value)
int(p::Length) = int(convert(px, p))
int(x::AbstractFloat) = round(Int, x)
int(x) = x

flt(p::px) = flt(p.value)
flt(p::Length) = flt(convert(px, p))
flt(x) = Float32(x)

"Called whenever the window is resized (internal buffer size change)"
onbuffer_resize(window, newsize) = nothing

"Called whenever the window is resized (window size change)"
onresize(window, newsize) = nothing

"If your app only has one kind of window then you may as well just use this type"
@def mutable struct Window <: AbstractWindow
  buffer::Matrix{RGBA{Colors.N0f8}}=Matrix{RGBA{Colors.N0f8}}(undef, 0, 0)
end

onbuffer_resize(w::Window, (x, y)) = w.buffer = Matrix{RGBA{Colors.N0f8}}(undef, int(y), int(x))

abstract type KeyEvent{key} end
struct KeyPress{key} <: KeyEvent{key}
  keycode::Int
  is_repeat::Bool
  window
end
KeyPress{key}(keycode, window) where key = KeyPress{key}(Int(keycode), false, window)
struct KeyRelease{key} <: KeyEvent{key}
  keycode::Int
  is_repeat::Bool
  window
end
KeyRelease{key}(keycode, window) where key = KeyRelease{key}(Int(keycode), false, window)

struct MouseMove
  position::Vec2{px}
  window
end

"""
The user typed `char`. A key press says which key went down. This says which
character that made on the user's keyboard layout, after Shift, Option and
dead keys: `?` from Shift and `/` on a US keyboard, or `é` from Option-E then E.
Keys held with Cmd don't type anything.
"""
struct Typed
  char::Char
  window
end

"Called on any keyboard/mouse button press or release"
onkey(w::AbstractWindow, event) = w.focus !== nothing ? onkey(w.focus, event) : nothing
onkey(target, event) = nothing

"""
Called when the mouse moves. Even if it's outside the window. The position is given relative
to the window so it can be negative in either x or y direction
"""
onmouse(w::AbstractWindow, event::MouseMove) = w.focus !== nothing ? onmouse(w.focus, event) : nothing
onmouse(target, event) = nothing

"Called with each character the user types, as a `Typed`"
ontype(w::AbstractWindow, event::Typed) = w.focus !== nothing ? ontype(w.focus, event) : nothing
ontype(target, event) = nothing

"Called when either scroll wheel is moved. `delta` is a `Vec{2,px}` with horizontal,vertical order"
onscroll(window, delta) = nothing

"Called when the window position changes. `pos` is the new window position as a `Vec2{px}`"
onreposition(window, pos) = nothing

"Called when files are dropped onto the window. `paths` is an array of file paths"
onfiledrop(window, paths) = nothing

"Called once when the window first opens"
onopen(window) = nothing

"Called once when the window has closed"
onclose(window) = nothing

"Generate a pixel buffer to display. If the size doesn't match the window then it will be stretched"
frame(w) = nothing

# --- the loop that draws the windows -----------------------------------------
#
# An app can have more than one window open. One loop draws them all, on the
# thread that opened the first one. `open` gives the loop a window. The first
# `open` runs the loop, and returns when the last window has closed. An `open`
# after that returns at once, and the loop puts the window on the screen on its
# next turn.
#
# On each turn the loop draws the windows that need it, then waits for input.
# A window needs drawing when:
#   - it got input since it was drawn: a key, the mouse, a scroll, a file, a new size
#   - it's animating
#   - its `wake` time has passed
#   - `stale!` was called for it
#   - the loop woke and none of those is true of any window, as it does after
#     `GLFW.PostEmptyEvent()`. Then every window is drawn.
# So a window isn't drawn again each time the mouse moves over another one.
# A window that gets a new size while the loop waits is drawn then, by
# `draw_now!`, since the wait lasts as long as the user drags its edge. When
# its frames are slow, it skips some sizes so the edge keeps up with the mouse.

"The windows that are on the screen, in the order they opened"
const windows = AbstractWindow[]
"The windows that `open` was given, which the loop hasn't put on the screen yet"
const waiting = AbstractWindow[]
"The windows that show something old, by `objectid`. The loop draws them on its next turn."
const stale = Set{UInt}()
"When each window on the screen was last drawn, by `objectid`"
const drawn = Dict{UInt,Float64}()
"How many seconds each window's last frame took to draw, by `objectid`"
const took = Dict{UInt,Float64}()
"The windows whose newest size has no frame yet, by `objectid`. `draw_now!` skipped it."
const behind = Set{UInt}()
"True while the loop runs"
const looping = Ref(false)

"Say that window `w` shows something old, so the loop draws it again on its next turn"
stale!(w::AbstractWindow) = (push!(stale, objectid(w)); nothing)

"True while window `w` is on the screen"
Base.isopen(w::AbstractWindow) = !isempty(w.glfw)

"""
Open window `w`. The first window that's opened runs the loop that draws every
window, so this returns when the last window has closed. While that loop
runs, this returns at once, and the window is on the screen a moment later.
"""
Base.open(w::AbstractWindow) = begin
  # GLFW can't make a window while it calls one of the handlers, and that's when an app opens
  # its second window. So the loop makes it.
  any(o -> o === w, waiting) || isopen(w) || push!(waiting, w)
  looping[] && return nothing
  looping[] = true
  try
    while true
      destroy_unused_cursors!()
      while !isempty(waiting)
        show!(popfirst!(waiting))
      end
      isempty(windows) && break
      due = to_draw()
      for w in copy(windows)
        if GLFW.WindowShouldClose(w.glfw[1])
          shut!(w)
        elseif any(o -> o === w, due)
          delete!(stale, objectid(w))
          draw!(w)
        end
      end
      yield()
      # A window that opened or closed, or went stale, while the others were drawn is seen to first
      isempty(waiting) && !isempty(windows) && !any(w -> objectid(w) in stale, windows) && wait_for_input()
    end
  finally
    # An error from a window ends the loop, and takes every window off the screen
    foreach(shut!, copy(windows))
    empty!(waiting)
    destroy_unused_cursors!()
    looping[] = false
  end
  nothing
end

"The windows that the loop should draw on this turn"
to_draw() = begin
  due = filter(w -> w.animating || objectid(w) in stale || overdue(w), windows)
  # The loop woke, and no window has a reason of its own to be drawn. So something else changed, and they all are.
  isempty(due) ? copy(windows) : due
end

"True when window `w` asked to be drawn again after its `wake`, and that time has passed"
overdue(w::AbstractWindow) = w.wake > 0 && time() - get(drawn, objectid(w), 0.0) >= w.wake

"True while the loop waits for input. No frame is being drawn then, so a handler that GLFW calls can draw one."
const idle = Ref(false)

"Wait until a window gets input, or until the first window's `wake` time. While a window animates, don't wait."
wait_for_input() = begin
  idle[] = true
  try
    any(w -> w.animating, windows) && return GLFW.PollEvents()
    now = time()
    left = minimum((get(drawn, objectid(w), now) + w.wake - now for w in windows if w.wake > 0), init=Inf)
    left == Inf ? wait_events() : left > 0 ? wait_events(left) : GLFW.PollEvents()
  finally
    idle[] = false
  end
end

"""
Wait for input, as GLFW's `WaitEvents` does, for no more than `seconds`.
Julia's garbage collector can run while this waits. Without that, a task in
another thread waits at each of its collections until the main thread stops
waiting here. Code that made a lot of garbage ran 19 times slower that way.
A handler that GLFW calls while it waits runs as usual.
"""
wait_events(seconds=Inf) = begin
  # GLFW's input functions are only for the main thread
  Threads.threadid() == 1 || error("MiniFB waits for input on the main thread only")
  isinf(seconds) ? @ccall(gc_safe=true, GLFW.libglfw.glfwWaitEvents()::Cvoid) :
                   @ccall(gc_safe=true, GLFW.libglfw.glfwWaitEventsTimeout(seconds::Cdouble)::Cvoid)
end

"The most seconds that `draw_now!` waits between frames, while the user drags the edge of a window"
const MOST_REST = 0.1

"Draw window `w`, and note when its frame started and how long it took"
draw!(w::AbstractWindow) = begin
  id = objectid(w)
  start = drawn[id] = time()
  delete!(behind, id)
  invokelatest(redraw, w)
  took[id] = time() - start
  nothing
end

"""
Draw window `w` now, if the loop is waiting for input. While the user drags an
edge of a window, macOS keeps the loop in that wait until the mouse button
goes up. Until then it stretches the window's last frame to fit the new size.
The handler for a new size calls this, so the window gets a frame at its new size.

The edge of the window can't move while a frame is drawn. So when the window
hasn't rested since its last frame for as long as that frame took, this skips
the frame, and the window draws its newest size when it has rested that long.
Then a slow frame slows the edge down by half at most. It rests `MOST_REST`
seconds at most, since one frame can be far slower than the rest, like the
first one, which Julia compiles.
"""
draw_now!(w::AbstractWindow) = begin
  idle[] || return
  id = objectid(w)
  rested = time() - get(drawn, id, 0.0) - get(took, id, 0.0)   # since its last frame ended
  rest = min(get(took, id, 0.0), MOST_REST)
  if rested < rest && later!(rest - rested)
    push!(behind, id)
    return
  end
  # A frame that changes the window's size calls the handler again. This stops that from drawing a frame inside a frame.
  idle[] = false
  try
    draw!(w)
    idle[] = true
  catch
    # The window is still stale, so the loop draws it again when the wait ends. That draw reports the error.
  end
  nothing
end

"True while `catch_up` is queued to run"
const queued = Ref(false)

"Draw each window whose newest size has no frame yet"
catch_up(_) = begin
  queued[] = false
  for w in copy(windows)
    objectid(w) in behind && draw_now!(w)
  end
  nothing
end

"""
Ask macOS to run `catch_up` in `seconds`, on this thread. macOS runs it while
the user still drags the window's edge, since it handles the drag on this
thread too. False where there's no way to ask, and then `draw_now!` draws at once.
"""
later!(seconds) = begin
  Sys.isapple() || return false
  queued[] && return true
  queued[] = true
  when = ccall(:dispatch_time, UInt64, (UInt64, Int64), 0, round(Int64, seconds * 1e9))   # 0 is now
  ccall(:dispatch_after_f, Cvoid, (UInt64, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
        when, cglobal(:_dispatch_main_q), C_NULL, @cfunction(catch_up, Cvoid, (Ptr{Cvoid},)))
  true
end

const modifiers = ((GLFW.MOD_SHIFT, Keys.shft), (GLFW.MOD_CONTROL, Keys.ctrl), (GLFW.MOD_ALT, Keys.opt), (GLFW.MOD_SUPER, Keys.cmd))

"""
Make the Shift, Control, Option and Command keys of `w` the ones that GLFW says
are down. A window that opens while ⌘ is down never sees it go down, so
without this the next key wouldn't count as a ⌘ shortcut there.
"""
modifiers!(w::AbstractWindow, mods) =
  for (bit, key) in modifiers
    mods & bit != 0 ? (w.keys |= key) : release!(w, key)
  end

"Note that `key` is up in window `w`"
release!(w::AbstractWindow, key) = (key in w.keys && (w.keys ⊻= key); nothing)

"""
Tell macOS that the pixels in `window` are sRGB, the colour space of CSS colours,
hex colours and most pictures. macOS then converts them for each screen, as
browsers do. Without this, macOS sends the numbers to the screen as they are, and
on a wide-gamut screen (a MacBook's, or a Dell U4021QW) every colour looks more
saturated than in a browser: `#F38020` shows as (243,128,32) on the Dell where
WebKit shows (226,137,54).
"""
srgb!(window::GLFW.Window) = begin
  Sys.isapple() || return window
  sel(name) = ccall(:sel_registerName, Ptr{Cvoid}, (Cstring,), name)
  nswindow = ccall((:glfwGetCocoaWindow, GLFW.libglfw), Ptr{Cvoid}, (GLFW.Window,), window)
  NSColorSpace = ccall(:objc_getClass, Ptr{Cvoid}, (Cstring,), "NSColorSpace")
  srgb = ccall(:objc_msgSend, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}), NSColorSpace, sel("sRGBColorSpace"))
  ccall(:objc_msgSend, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), nswindow, sel("setColorSpace:"), srgb)
  window
end

"Put window `w` on the screen, and tell it with `onopen`"
show!(w::AbstractWindow) = begin
  width, height = int.(w.size)
  window = srgb!(GLFW.CreateWindow(width, height, w.title))
  GLFW.MakeContextCurrent(window)
  GLFW.SwapInterval(1)
  GLFW.SetWindowPos(window, int.(w.position)...)
  glViewport(0, 0, GLFW.GetFramebufferSize(window)...)
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

  # `redraw` sets the size of the picture for each frame. Another window's may be the one that OpenGL draws to now.
  GLFW.SetFramebufferSizeCallback(window, function(window, width, height)
    stale!(w)
    invokelatest(onbuffer_resize, w, (width, height))
  end)

  GLFW.SetKeyCallback(window, function(window, keyenum, keycode, action, mods)
    stale!(w)
    key = convert(Keys, keyenum)
    modifiers!(w, mods)
    if action == GLFW.RELEASE
      release!(w, key)
      invokelatest(onkey, w, KeyRelease{key}(keycode, w))
    else
      is_repeat = action == GLFW.REPEAT
      is_repeat || (w.keys |= key)
      invokelatest(onkey, w, KeyPress{key}(keycode, is_repeat, w))
    end
  end)

  GLFW.SetCharCallback(window, (_, char) -> (stale!(w); invokelatest(ontype, w, Typed(Char(char), w))))

  GLFW.SetCursorPosCallback(window, function(window, x::Float64, y::Float64)
    stale!(w)
    newpos = Vec2{px}(x, y)
    invokelatest(onmouse, w, MouseMove(newpos, w))
    w.mouse = newpos
  end)

  GLFW.SetMouseButtonCallback(window, function(window, button, action, mods)
    stale!(w)
    key = convert(Keys, button)
    modifiers!(w, mods)
    if action == GLFW.PRESS
      w.keys |= key
      invokelatest(onkey, w, KeyPress{key}(0, w))
    else
      release!(w, key)
      invokelatest(onkey, w, KeyRelease{key}(0, w))
    end
  end)

  GLFW.SetWindowSizeCallback(window, function(_, width, height)
    stale!(w)
    w.size = Vec2{px}(px(width), px(height))
    draw_now!(w)
  end)
  GLFW.SetWindowPosCallback(window, (_, x, y) -> (stale!(w); w.position = Vec2{px}(px(x), px(y))))
  GLFW.SetScrollCallback(window, (_, x, y) -> (stale!(w); invokelatest(onscroll, w, Vec2{px}(x, y))))
  GLFW.SetDropCallback(window, (_, paths) -> (stale!(w); invokelatest(onfiledrop, w, paths)))

  w.glfw = [window, texture, shaderProgram, VAO, VBO, EBO]

  # When the size asked for doesn't fit on the screen, macOS moves the window
  # and makes it smaller as it's placed and shown. That happens before the
  # callbacks above are set, so they don't tell `w`. Without this, each frame
  # is drawn at the size asked for and squeezed into the smaller window, which
  # leaves out a row of pixels every so often, and text loses part of a letter.
  place, room = GLFW.GetWindowPos(window), GLFW.GetWindowSize(window)
  w.position = Vec2{px}(px(place.x), px(place.y))
  w.size = Vec2{px}(px(room.width), px(room.height))
  glViewport(0, 0, GLFW.GetFramebufferSize(window)...)

  isnothing(w.cursor) || GLFW.SetCursor(window, w.cursor.glfw)
  w.screen = getscreen(w)
  push!(windows, w)
  stale!(w)
  invokelatest(onopen, w)
  invokelatest(onbuffer_resize, w, GLFW.GetFramebufferSize(window))
  w
end

unpack(c::Colorant) = reinterpret(NTuple{4,UInt8}, RGBA{Colors.N0f8}(c))
unpack(c::UInt32) = reinterpret(NTuple{4,UInt8}, c)
unpack(m::AbstractMatrix) = unpack.(m)
unpack(m::AbstractMatrix{RGBA{Colors.N0f8}}) = reinterpret(NTuple{4,UInt8}, m)

"""
Send a frame's pixels to the graphics card. Returns true when they were sent a
column at a time, the way Julia stores a matrix, and false when they were sent
a row at a time.
"""
upload(image) = begin
  y, x = size(image)
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, y, x, 0, GL_RGBA, GL_UNSIGNED_BYTE, unpack(image))
  true
end

# What `drawing` in skia.jl returns: Skia's own buffer, wrapped but not copied
const SkiaFrame = Adjoint{ARGB32,<:Base.ReshapedArray{ARGB32,2,<:Base.ReinterpretArray{ARGB32,1,UInt32,Vector{UInt32}}}}

# Skia's buffer is already rows of BGRA bytes, which the graphics card takes as
# it is. Converting it to a matrix of RGBA colours first took about 10ms a frame
# for a 1100×800 window on a Retina screen.
upload(image::SkiaFrame) = begin
  height, width = size(image)
  pixels = parent(parent(parent(image)))::Vector{UInt32}
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, pixels)
  false
end

"""
What `frame` returns when it drew the window itself, with the graphics card,
like `drawing` in skia.jl does. Then there are no pixels to send to the card.
"""
struct Drawn end

redraw(w::AbstractWindow) = begin
  window, texture, shaderProgram, VAO, VBO, EBO = w.glfw
  GLFW.MakeContextCurrent(window)
  glViewport(0, 0, GLFW.GetFramebufferSize(window)...)
  image = invokelatest(frame, w)
  if !(image isa Drawn)
    # Skia may have drawn an earlier frame, and left these on
    glDisable(GL_SCISSOR_TEST); glDisable(GL_STENCIL_TEST); glDisable(GL_BLEND)
    glBindTexture(GL_TEXTURE_2D, texture[])
    by_column = upload(image)
    glUseProgram(shaderProgram)
    glUniform1i(glGetUniformLocation(shaderProgram, "by_column"), by_column)
    glBindVertexArray(VAO[])
    glDrawElements(GL_TRIANGLES, 6, GL_UNSIGNED_INT, C_NULL)
  end
  GLFW.SwapBuffers(window)
end

"""
Called just before window `w` leaves the screen, while its OpenGL context is
the current one. skia.jl lets go of what it drew the window with.
"""
drop_gpu!(w) = nothing

"Take window `w` off the screen, and tell it with `onclose`"
shut!(w::AbstractWindow) = begin
  window, texture, shaderProgram, VAO, VBO, EBO = w.glfw
  # What a window drew with belongs to that window
  GLFW.MakeContextCurrent(window)
  glDeleteTextures(1, [texture[]])
  glDeleteVertexArrays(1, [VAO[]])
  glDeleteBuffers(1, [VBO[]])
  glDeleteBuffers(1, [EBO[]])
  glDeleteProgram(shaderProgram)
  invokelatest(drop_gpu!, w)
  GLFW.DestroyWindow(window)
  empty!(w.glfw)
  filter!(o -> o !== w, windows)
  delete!(stale, objectid(w))
  delete!(drawn, objectid(w))
  delete!(took, objectid(w))
  delete!(behind, objectid(w))
  invokelatest(onclose, w)
  nothing
end

"""
Close window `w`. The loop takes it off the screen on its next turn, and then
tells it with `onclose`. A window that isn't on the screen, like one a test
makes, is told now.
"""
Base.close(w::AbstractWindow) = begin
  if isopen(w)
    GLFW.SetWindowShouldClose(w.glfw[1], true)
  else
    filter!(o -> o !== w, waiting)
    invokelatest(onclose, w)
  end
  nothing
end

"Bring window `w` to the front, and give it the keyboard. One that's in the Dock comes out of it."
front!(w::AbstractWindow) = begin
  isopen(w) || return w
  GLFW.GetWindowAttrib(w.glfw[1], GLFW.ICONIFIED) != 0 && GLFW.RestoreWindow(w.glfw[1])
  ccall((:glfwFocusWindow, GLFW.libglfw), Cvoid, (GLFW.Window,), w.glfw[1])
  stale!(w)
  w
end

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

export Window, AbstractWindow, frame, redraw, onkey, KeyPress, KeyRelease, Keys, MouseMove, Typed, ontype, onopen, onclose, onmouse, onresize,
       onreposition, Cursor, Screen, stale!, front!
