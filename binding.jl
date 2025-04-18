using Libdl

const libminifb = LazyLibrary("$(@dirname)/target/release/libminifb_c.dylib")

mutable struct MiniFBWindow
  ptr::Ptr{Cvoid}
  isclosed::Bool
  function MiniFBWindow(ptr::Ptr{Cvoid})
    window = new(ptr, false)
    finalizer(close, window) # Automatically free memory when garbage collected
    window
  end
end

@enum MinifbScale begin
  MINIFB_SCALE_X1 = 1
  MINIFB_SCALE_X2 = 2
  MINIFB_SCALE_X4 = 4
  MINIFB_SCALE_X8 = 8
  MINIFB_SCALE_FIT_SCREEN = 0
end

@enum MinifbScaleMode begin
  MINIFB_SCALE_MODE_STRETCH = 0
  MINIFB_SCALE_MODE_ASPECT_RATIO = 1
  MINIFB_SCALE_MODE_CENTER = 2
end

function minifb_window_new(title::AbstractString,
                           width::Int,
                           height::Int;
                           borderless::Bool=false,
                           title_bar::Bool=true,
                           resizable::Bool=true,
                           scale::MinifbScale=MINIFB_SCALE_X1,
                           scale_mode::MinifbScaleMode=MINIFB_SCALE_MODE_STRETCH,
                           topmost::Bool=false,
                           none::Bool=false,
                           transparency::Bool=false)
  ptr = ccall((:minifb_window_new, libminifb), Ptr{Cvoid},
              (Cstring, Cuint, Cuint, Cint, Cint, Cint, Cint, Cint, Cint, Cint, Cint),
              title, width, height, borderless, title_bar, resizable, scale, scale_mode, topmost, none, transparency)
  @assert ptr != C_NULL "Failed to create window"
  window = MiniFBWindow(ptr)
  minifb_update_buffer(window, (fill(0xFFFFFFFF, (width, height))))
  window
end

function minifb_update_buffer(window::MiniFBWindow, buffer::Matrix{UInt32})
  width, height = size(buffer)
  status = @ccall libminifb.minifb_window_update_with_buffer(window.ptr::Ptr{Cvoid},
                                                             buffer::Ptr{UInt32},
                                                             width::Cuint,
                                                             height::Cuint)::Cint
  @assert status == 0 "Failed to update buffer"
end

function Base.isopen(window::MiniFBWindow)
  @ccall(libminifb.minifb_window_is_open(window.ptr::Ptr{Cvoid})::Cint) != 0
end

function Base.close(window::MiniFBWindow)
  window.isclosed && return
  @ccall libminifb.minifb_window_destroy(window.ptr::Ptr{Cvoid})::Cvoid
  window.isclosed = true
  minifb_window_update(window) # so that rust will process the close event
  nothing
end

function minifb_window_get_keys(window::MiniFBWindow)
  keys_ptr = Ref{Ptr{Cint}}()
  len_ptr = Ref{Csize_t}()

  @ccall libminifb.minifb_window_get_keys(window.ptr::Ptr{Cvoid}, keys_ptr::Ptr{Ptr{Cint}}, len_ptr::Ptr{Csize_t})::Cvoid
  len = len_ptr[]

  if len > 0
    # Wrap the C array as a Julia array (without taking ownership)
    keys = unsafe_wrap(Array, keys_ptr[], len)
    # Copy the array to avoid issues with the pointer
    keys_copy = copy(keys)
    @ccall libminifb.minifb_free_keys(keys_ptr[]::Ptr{Cint})::Cvoid
    keys_copy
  else
    Int32[]
  end
end

function minifb_window_is_active(window::MiniFBWindow)
  @ccall(libminifb.minifb_window_is_active(window.ptr::Ptr{Cvoid})::Cint) > 0
end

function minifb_window_update(window::MiniFBWindow)
  @ccall(libminifb.minifb_window_update(window.ptr::Ptr{Cvoid})::Cint) == 0
end

function minifb_window_set_target_fps(window::MiniFBWindow, fps::Integer)
  @ccall libminifb.minifb_window_set_target_fps(window.ptr::Ptr{Cvoid}, fps::Cuint)::Cvoid
end

function minifb_window_set_title(window::MiniFBWindow, title::AbstractString)
  @ccall libminifb.minifb_window_set_title(window.ptr::Ptr{Cvoid}, title::Cstring)::Cvoid
  minifb_window_update(window)
end

function minifb_window_set_position(window::MiniFBWindow, (x,y))
  @ccall libminifb.minifb_window_set_position(window.ptr::Ptr{Cvoid}, x::Cint, y::Cint)::Cvoid
  minifb_window_update(window)
end

function minifb_window_topmost(window::MiniFBWindow, topmost::Bool)
  @ccall libminifb.minifb_window_topmost(window.ptr::Ptr{Cvoid}, Cint(topmost)::Cint)::Cvoid
  minifb_window_update(window)
end

function minifb_window_get_scroll_wheel(window::MiniFBWindow)
  vertical = Ref{Cfloat}()
  horizontal = Ref{Cfloat}()
  status = @ccall libminifb.minifb_window_get_scroll_wheel(window.ptr::Ptr{Cvoid},
                                                           vertical::Ptr{Cfloat},
                                                           horizontal::Ptr{Cfloat})::Cint
  status == 0 || return nothing
  (vertical[], horizontal[])
end

function minifb_window_get_mouse_position(window::MiniFBWindow)
  x = Ref{Cint}()
  y = Ref{Cint}()
  @ccall libminifb.minifb_window_get_mouse_pos(window.ptr::Ptr{Cvoid}, x::Ptr{Cint}, y::Ptr{Cint})::Cvoid
  (x[], y[])
end

@enum MinifbCursorStyle begin
  MINIFB_CURSOR_STYLE_ARROW = 0
  MINIFB_CURSOR_STYLE_IBEAM = 1
  MINIFB_CURSOR_STYLE_CROSSHAIR = 2
  MINIFB_CURSOR_STYLE_CLOSEDHAND = 3
  MINIFB_CURSOR_STYLE_OPENHAND = 4
  MINIFB_CURSOR_STYLE_RESIZELEFTRIGHT = 5
  MINIFB_CURSOR_STYLE_RESIZEUPDOWN = 6
  MINIFB_CURSOR_STYLE_RESIZEALL = 7
end

# Doesn't yet work on a mac
function minifb_window_set_cursor_style(window::MiniFBWindow, cursor::MinifbCursorStyle)
  @ccall libminifb.minifb_window_set_cursor_style(window.ptr::Ptr{Cvoid}, cursor::Cint)::Cvoid
  minifb_window_update(window)
end

function minifb_window_get_mouse_down(window::MiniFBWindow, button::Integer)
  @ccall(libminifb.minifb_window_get_mouse_down(window.ptr::Ptr{Cvoid}, button::Cint)::Cint) != 0
end

function minifb_window_set_cursor_visibility(window::MiniFBWindow, visibility::Bool)
  @ccall libminifb.minifb_window_set_cursor_visibility(window.ptr::Ptr{Cvoid}, visibility::Cint)::Cvoid
end

function minifb_window_get_size(window::MiniFBWindow)
  width = Ref{Cuint}()
  height = Ref{Cuint}()
  status = @ccall libminifb.minifb_window_get_size(window.ptr::Ptr{Cvoid}, width::Ref{Cuint}, height::Ref{Cuint})::Cint
  @assert status == 0 "Failed to get window size"
  (Int(width[]), Int(height[]))
end

export minifb_window_set_cursor_visibility, minifb_window_get_mouse_down, minifb_window_set_cursor_style,
       MinifbCursorStyle, minifb_window_get_mouse_position, minifb_window_get_scroll_wheel, minifb_window_topmost,
       minifb_window_set_position, MiniFBWindow,  MinifbScale, MinifbScaleMode, minifb_window_new,minifb_update_buffer,
       minifb_window_get_keys, minifb_window_is_active, minifb_window_update, minifb_window_set_target_fps,
       minifb_window_set_title, minifb_window_set_position, minifb_window_get_size
