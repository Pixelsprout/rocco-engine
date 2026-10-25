package engine

import sapp "../sokol-odin/sokol/app"

// Holds pressed keys, the mouse delta and the pads' presses until a fixed
// step takes them. Events and polls arrive between frames, so the first step
// of a frame takes them, and a frame with no step leaves them for the next
// step. See DESIGN section 3.
Input_Latch :: struct {
	held:        #sparse[sapp.Keycode]bool,
	pressed:     #sparse[sapp.Keycode]bool,
	mouse:       [2]f32,
	// The debug camera reads the mouse per frame, not per step.
	frame_mouse: [2]f32,
	gamepads:    Gamepad_Latch,
}

Input_Buffers :: struct {
	held:     [len(sapp.Keycode)]u16,
	pressed:  [len(sapp.Keycode)]u16,
	gamepads: Gamepad_Buffers,
}

// The Input for one fixed step. The slices point into the Input_Buffers
// passed to input_take.
Step_Input :: struct {
	held:     []u16,
	pressed:  []u16,
	mouse:    [2]f32,
	gamepads: []Step_Gamepad,
}

input_on_event :: proc(latch: ^Input_Latch, e: ^sapp.Event) {
	#partial switch e.type {
	case .KEY_DOWN:
		if e.key_code == .INVALID {
			return
		}
		latch.held[e.key_code] = true
		if !e.key_repeat {
			latch.pressed[e.key_code] = true
		}
	case .KEY_UP:
		latch.held[e.key_code] = false
	case .UNFOCUSED:
		// The key-up events of held keys go to the window that took focus.
		latch.held = {}
		gamepad_latch_focus(&latch.gamepads, false)
	case .FOCUSED:
		gamepad_latch_focus(&latch.gamepads, true)
	case .MOUSE_MOVE:
		latch.mouse += {e.mouse_dx, e.mouse_dy}
		latch.frame_mouse += {e.mouse_dx, e.mouse_dy}
	}
}

input_take :: proc(latch: ^Input_Latch, buf: ^Input_Buffers) -> Step_Input {
	n_held, n_pressed := 0, 0
	for k in sapp.Keycode {
		if latch.held[k] {
			buf.held[n_held] = u16(k)
			n_held += 1
		}
		if latch.pressed[k] {
			buf.pressed[n_pressed] = u16(k)
			n_pressed += 1
		}
	}
	keys := Step_Input {
		held    = buf.held[:n_held],
		pressed = buf.pressed[:n_pressed],
		mouse   = latch.mouse,
	}
	keys.gamepads = gamepad_latch_take(&latch.gamepads, &buf.gamepads)
	input_drop(latch)
	return keys
}

// Drops the pressed keys and buttons and the mouse delta. The held keys and
// buttons stay.
input_drop :: proc(latch: ^Input_Latch) {
	latch.pressed = {}
	latch.mouse = {}
	gamepad_latch_drop(&latch.gamepads)
}

input_end_frame :: proc(latch: ^Input_Latch) {
	latch.frame_mouse = {}
}
