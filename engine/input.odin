package engine

import sapp "../sokol/app"

Input :: struct {
	down: #sparse [sapp.Keycode]bool,
	prev: #sparse [sapp.Keycode]bool,
	mouse_dx: f32,
	mouse_dy: f32,
	mouse_move_events: i32,
}

input_on_event :: proc(in_: ^Input, e: ^sapp.Event) {
	#partial switch e.type {
	case .KEY_DOWN:
		in_.down[e.key_code] = true
	case .KEY_UP:
		in_.down[e.key_code] = false
	case .MOUSE_MOVE:
		in_.mouse_dx += e.mouse_dx
		in_.mouse_dy += e.mouse_dy
		in_.mouse_move_events += 1
	}
}

input_end_frame :: proc(in_: ^Input) {
	in_.prev = in_.down
	in_.mouse_dx = 0
	in_.mouse_dy = 0
	in_.mouse_move_events = 0
}

input_held :: proc(in_: ^Input, k: sapp.Keycode) -> bool {
	return in_.down[k]
}

input_pressed :: proc(in_: ^Input, k: sapp.Keycode) -> bool {
	return in_.down[k] && !in_.prev[k]
}

input_released :: proc(in_: ^Input, k: sapp.Keycode) -> bool {
	return !in_.down[k] && in_.prev[k]
}
