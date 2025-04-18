use minifb::{Window, WindowOptions, MouseButton, MouseMode, Scale, ScaleMode, CursorStyle};
use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_uint, c_float};
use std::ptr;

#[repr(C)]
pub struct MiniFBWindow(Window);

#[no_mangle]
pub extern "C" fn minifb_window_new(
    title: *const c_char,
    width: c_uint,
    height: c_uint,
    borderless: c_int,
    title_bar: c_int,
    resizable: c_int,
    scale: c_int,
    scale_mode: c_int,
    topmost: c_int,
    none: c_int,
    transparency: c_int,
) -> *mut MiniFBWindow {
    let title_str = unsafe { CStr::from_ptr(title).to_str().unwrap_or("Window") };

    // Map scale enum
    let scale = match scale {
        1 => Scale::X1,
        2 => Scale::X2,
        4 => Scale::X4,
        8 => Scale::X8,
        0 => Scale::FitScreen,
        _ => Scale::X1,
    };

    // Map scale_mode enum (fixed AspectRatio to AspectRatioStretch)
    let scale_mode = match scale_mode {
        0 => ScaleMode::Stretch,
        1 => ScaleMode::AspectRatioStretch,
        2 => ScaleMode::Center,
        3 => ScaleMode::UpperLeft,
        _ => ScaleMode::Stretch,
    };

    // Create WindowOptions with all fields
    let options = WindowOptions {
        borderless: borderless != 0,
        title: title_bar != 0,
        resize: resizable != 0,
        scale,
        scale_mode,
        topmost: topmost != 0,
        none: none != 0,
        transparency: transparency != 0,
    };

    // Create the window
    let window = Window::new(title_str, width as usize, height as usize, options);
    match window {
        Ok(w) => Box::into_raw(Box::new(MiniFBWindow(w))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_destroy(window: *mut MiniFBWindow) {
    if !window.is_null() { unsafe { drop(Box::from_raw(window)); } }
}

#[no_mangle]
pub extern "C" fn minifb_window_is_open(window: *mut MiniFBWindow) -> c_int {
    if window.is_null() { 0 } else { unsafe { (*window).0.is_open() as c_int } }
}

#[no_mangle]
pub extern "C" fn minifb_window_update_with_buffer(window: *mut MiniFBWindow, buffer: *const u32, width: c_uint, height: c_uint) -> c_int {
    if window.is_null() || buffer.is_null() { return -1 }
    let buffer_slice = unsafe { std::slice::from_raw_parts(buffer, (width * height) as usize) };
    unsafe {
        match (*window).0.update_with_buffer(buffer_slice, width as usize, height as usize) {
            Ok(_) => 0,
            Err(_) => -1,
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_get_mouse_pos(window: *mut MiniFBWindow, x: *mut c_int, y: *mut c_int) {
    if !window.is_null() {
        if let Some((mx, my)) = unsafe { (*window).0.get_mouse_pos(MouseMode::Pass) } {
            unsafe {
                *x = mx as c_int;
                *y = my as c_int;
            }
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_set_title(window: *mut MiniFBWindow, title: *const c_char) {
    if !window.is_null() {
        let title_str = unsafe { CStr::from_ptr(title).to_str().unwrap_or("") };
        unsafe { (*window).0.set_title(title_str); }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_set_position(window: *mut MiniFBWindow, x: c_int, y: c_int) {
    if !window.is_null() { unsafe { (*window).0.set_position(x as isize, y as isize); } }
}

#[no_mangle]
pub extern "C" fn minifb_window_get_keys(window: *mut MiniFBWindow, out_keys: *mut *mut c_int, out_len: *mut usize) {
    if window.is_null() || out_keys.is_null() || out_len.is_null() { return; }

    unsafe {
        // Access the underlying Window object
        let window = &(*window).0;
        // Get the vector of pressed keys
        let keys = window.get_keys();
        let len = keys.len();

        // Allocate memory for the keys array if there are any pressed keys
        let keys_array = if len > 0 {
            // Allocate memory using libc's malloc
            let array = libc::malloc(len * std::mem::size_of::<c_int>()) as *mut c_int;
            if array.is_null() {
                *out_len = 0;
                *out_keys = ptr::null_mut();
                return;
            }
            // Copy key codes into the array
            for (i, key) in keys.iter().enumerate() {
                *array.add(i) = *key as c_int; // Cast Key enum to integer
            }
            array
        } else {
            ptr::null_mut() // Return null if no keys are pressed
        };

        // Set output parameters
        *out_keys = keys_array;
        *out_len = len;
    }
}

#[no_mangle]
pub extern "C" fn minifb_free_keys(keys: *mut c_int) {
    if !keys.is_null() { unsafe { libc::free(keys as *mut libc::c_void); } }
}

#[no_mangle]
pub extern "C" fn minifb_window_is_active(window: *mut MiniFBWindow) -> c_int {
    unsafe {
        if let Some(w) = window.as_mut() {
            w.0.is_active() as c_int
        } else {
            0
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_update(window: *mut MiniFBWindow) -> c_int {
    if window.is_null() {
        return -1; // Return failure if the window pointer is null
    }
    unsafe {
        let w = &mut (*window).0; // Dereference the window pointer to get the Window
        w.update(); // Process events
        if w.is_open() {
            0 // Success: window is still open
        } else {
            -1 // Failure: window is closed
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_set_target_fps(window: *mut MiniFBWindow, fps: usize) {
    if !window.is_null() {
        unsafe {
            let window_ref = &mut (*window).0;  // Access the inner Window
            window_ref.set_target_fps(fps);    // Call the original method
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_topmost(window: *mut MiniFBWindow, topmost: c_int) {
    if !window.is_null() {
        unsafe {
            let w = &mut (*window).0;
            w.topmost(topmost != 0);
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_get_scroll_wheel(
    window: *mut MiniFBWindow,
    vertical: *mut c_float,
    horizontal: *mut c_float
) -> c_int {
    if window.is_null() || vertical.is_null() || horizontal.is_null() {
        return -1; // Error if any pointer is null
    }
    unsafe {
        let w = &(*window).0; // Access the inner Window
        if let Some((v, h)) = w.get_scroll_wheel() {
            *vertical = v;
            *horizontal = h;
            0                 // Success
        } else {
            -1                // Failure (no scroll data)
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_set_cursor_style(window: *mut MiniFBWindow, cursor: c_int) {
    if window.is_null() { return; }
    unsafe {
        let w = &mut (*window).0; // Access the inner Window
        let cursor_style = match cursor {
            0 => CursorStyle::Arrow,
            1 => CursorStyle::Ibeam,
            2 => CursorStyle::Crosshair,
            3 => CursorStyle::ClosedHand,
            4 => CursorStyle::OpenHand,
            5 => CursorStyle::ResizeLeftRight,
            6 => CursorStyle::ResizeUpDown,
            7 => CursorStyle::ResizeAll,
            _ => CursorStyle::Arrow, // Default on invalid input
        };
        w.set_cursor_style(cursor_style);
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_get_mouse_down(window: *const MiniFBWindow, button: c_int) -> c_int {
    if window.is_null() { return -1 };

    unsafe {
        let w = &(*window).0;

        // Map the C integer to the MouseButton enum
        let mouse_button = match button {
            0 => MouseButton::Left,
            1 => MouseButton::Middle,
            2 => MouseButton::Right,
            _ => return -1, // Invalid button value
        };

        if w.get_mouse_down(mouse_button) {
            1 // True
        } else {
            0 // False
        }
    }
}

pub extern "C" fn minifb_window_get_mouse_buttons(window: *const MiniFBWindow) -> c_int {
    if window.is_null() { return -1; }
    unsafe {
        let w = &(*window).0;
        let mut state = 0;
        if w.get_mouse_down(MouseButton::Left) { state |= 1 << 0; }
        if w.get_mouse_down(MouseButton::Right) { state |= 1 << 1; }
        if w.get_mouse_down(MouseButton::Middle) { state |= 1 << 2; }
        state as c_int
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_set_cursor_visibility(window: *mut MiniFBWindow, visibility: c_int) {
    if !window.is_null() {
        unsafe {
            let w = &mut (*window).0;
            w.set_cursor_visibility(visibility != 0);
        }
    }
}

#[no_mangle]
pub extern "C" fn minifb_window_get_size(
    window: *const MiniFBWindow,
    width: *mut c_uint,
    height: *mut c_uint,
) -> c_int {
    if window.is_null() || width.is_null() || height.is_null() { return -1; }
    unsafe {
        let w = &(*window).0; // Access the inner Window
        let (w_size, h_size) = w.get_size();
        *width = w_size as c_uint;
        *height = h_size as c_uint;
        0 // Success
    }
}
