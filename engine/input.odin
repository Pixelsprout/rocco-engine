package engine

import sapp "../sokol-odin/sokol/app"

// Holds key and mouse events until a fixed step takes them. Events arrive
// between frames, so only the first step of a frame sees pressed keys and
// the mouse delta. Later steps in that frame get none.
Input_Latch :: struct {
	held:        #sparse[sapp.Keycode]bool,
	pending:     #sparse[sapp.Keycode]bool,
	mouse:       [2]f32,
	// The debug camera reads the mouse per frame, not per step.
	frame_mouse: [2]f32,
}

Key_Buffers :: struct {
	held:    [len(sapp.Keycode)]u16,
	pressed: [len(sapp.Keycode)]u16,
}

// The keys and mouse delta for one fixed step. The slices point into the
// Key_Buffers passed to input_take.
Step_Keys :: struct {
	held:    []u16,
	pressed: []u16,
	mouse:   [2]f32,
}

input_on_event :: proc(latch: ^Input_Latch, e: ^sapp.Event) {
	#partial switch e.type {
	case .KEY_DOWN:
		if e.key_code == .INVALID {
			return
		}
		latch.held[e.key_code] = true
		if !e.key_repeat {
			latch.pending[e.key_code] = true
		}
	case .KEY_UP:
		latch.held[e.key_code] = false
	case .MOUSE_MOVE:
		latch.mouse += {e.mouse_dx, e.mouse_dy}
		latch.frame_mouse += {e.mouse_dx, e.mouse_dy}
	}
}

input_take :: proc(latch: ^Input_Latch, buf: ^Key_Buffers) -> Step_Keys {
	held, pressed := 0, 0
	for k in sapp.Keycode {
		if latch.held[k] {
			buf.held[held] = u16(k)
			held += 1
		}
		if latch.pending[k] {
			buf.pressed[pressed] = u16(k)
			pressed += 1
		}
	}
	keys := Step_Keys {
		held    = buf.held[:held],
		pressed = buf.pressed[:pressed],
		mouse   = latch.mouse,
	}
	latch.pending = {}
	latch.mouse = {}
	return keys
}

input_end_frame :: proc(latch: ^Input_Latch) {
	latch.frame_mouse = {}
}
