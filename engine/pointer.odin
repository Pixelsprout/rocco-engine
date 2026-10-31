package engine

import sapp "../sokol-odin/sokol/app"

// The Bridge reads the MouseButton names of a request from this table.
@(rodata)
MOUSE_BUTTON_TAGS := [Mouse_Button]string {
	.Left   = "Left",
	.Right  = "Right",
	.Middle = "Middle",
}

// The value of each button is its code in platform/MouseButton.roc, which is
// sokol's.
Mouse_Button :: enum u8 {
	Left,
	Right,
	Middle,
}

Mouse_Buttons :: bit_set[Mouse_Button;u8]

// Holds the pointer between steps, with the rules of the keys. pos is in
// physical pixels, as sokol gives it.
Pointer_Latch :: struct {
	pos:      [2]f32,
	// A MOUSE_MOVE or MOUSE_ENTER sets it, and a MOUSE_LEAVE clears it.
	entered:  bool,
	// sokol leaves mouse_x and mouse_y undefined while the mouse is locked.
	// frame_run sets this each Frame.
	locked:   bool,
	held:     Mouse_Buttons,
	pressed:  Mouse_Buttons,
	released: Mouse_Buttons,
	wheel:    [2]f32,
}

Pointer_Buffers :: struct {
	held:     [len(Mouse_Button)]u8,
	pressed:  [len(Mouse_Button)]u8,
	released: [len(Mouse_Button)]u8,
}

// The pointer for one fixed step. pos is in logical pixels. The slices point
// into the Pointer_Buffers passed to pointer_take.
Step_Pointer :: struct {
	pos:      [2]f32,
	inside:   bool,
	held:     []u8,
	pressed:  []u8,
	released: []u8,
	wheel:    [2]f32,
}

pointer_on_event :: proc(p: ^Pointer_Latch, e: ^sapp.Event) {
	#partial switch e.type {
	case .MOUSE_MOVE:
		if !p.locked {
			p.pos = {e.mouse_x, e.mouse_y}
			p.entered = true
		}
	case .MOUSE_ENTER:
		p.entered = true
	case .MOUSE_LEAVE:
		p.entered = false
	case .MOUSE_DOWN:
		if button, ok := pointer_button(e.mouse_button); ok {
			p.held += {button}
			p.pressed += {button}
		}
	case .MOUSE_UP:
		if button, ok := pointer_button(e.mouse_button); ok {
			p.held -= {button}
			p.released += {button}
		}
	case .MOUSE_SCROLL:
		p.wheel += {e.scroll_x, e.scroll_y}
	case .UNFOCUSED:
		// The button-up events of held buttons go to the window that took focus.
		p.released += p.held
		p.held = {}
	}
}

pointer_take :: proc(p: ^Pointer_Latch, buf: ^Pointer_Buffers, window: Ui_Window) -> Step_Pointer {
	pos, inside := pointer_logical(p, window)
	step := Step_Pointer {
		pos      = pos,
		inside   = inside,
		held     = pointer_buttons(p.held, &buf.held),
		pressed  = pointer_buttons(p.pressed, &buf.pressed),
		released = pointer_buttons(p.released, &buf.released),
		wheel    = p.wheel,
	}
	pointer_drop(p)
	return step
}

pointer_logical :: proc(p: ^Pointer_Latch, window: Ui_Window) -> (pos: [2]f32, inside: bool) {
	return p.pos / window.dpi, p.entered && !p.locked
}

pointer_buttons :: proc(set: Mouse_Buttons, out: ^[len(Mouse_Button)]u8) -> []u8 {
	n := 0
	for button in Mouse_Button {
		if button in set {
			out[n] = u8(button)
			n += 1
		}
	}
	return out[:n]
}

// Drops the pressed and released buttons and the wheel. The held buttons stay.
pointer_drop :: proc(p: ^Pointer_Latch) {
	p.pressed = {}
	p.released = {}
	p.wheel = {}
}

pointer_in_window :: proc(pos, window: [2]f32) -> bool {
	return pos.x >= 0 && pos.y >= 0 && pos.x < window.x && pos.y < window.y
}

mouse_button_from_tag :: proc(tag: string) -> (button: Mouse_Button, ok: bool) {
	for name, b in MOUSE_BUTTON_TAGS {
		if name == tag {
			return b, true
		}
	}
	return {}, false
}

@(private = "file")
pointer_button :: proc(button: sapp.Mousebutton) -> (Mouse_Button, bool) {
	#partial switch button {
	case .LEFT:
		return .Left, true
	case .RIGHT:
		return .Right, true
	case .MIDDLE:
		return .Middle, true
	}
	return {}, false
}
