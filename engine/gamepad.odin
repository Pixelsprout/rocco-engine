package engine

import "core:math"

// The host reports at most this many pads. A Gamepad's slot is below it.
GAMEPAD_SLOTS :: 4
// A Gamepad reader may see more pads than there are slots. A pad past the slots
// takes the first slot that frees.
GAMEPAD_RAW_MAX :: 8
// A stick nearer the centre than this reads 0. The rest of the travel is
// rescaled, so the stick still reaches the edge of the unit disc.
GAMEPAD_STICK_DEAD_ZONE :: 0.2
GAMEPAD_TRIGGER_DEAD_ZONE :: 0.05

// The Bridge reads the Button names of a request from this table.
@(rodata)
BUTTON_TAGS := [Gamepad_Button]string {
	.South          = "South",
	.East           = "East",
	.West           = "West",
	.North          = "North",
	.Left_Shoulder  = "LeftShoulder",
	.Right_Shoulder = "RightShoulder",
	.Left_Stick     = "LeftStick",
	.Right_Stick    = "RightStick",
	.Start          = "Start",
	.Back           = "Back",
	.Dpad_Up        = "DpadUp",
	.Dpad_Down      = "DpadDown",
	.Dpad_Left      = "DpadLeft",
	.Dpad_Right     = "DpadRight",
}

// The value of each button is its code in platform/Button.roc.
Gamepad_Button :: enum u8 {
	South,
	East,
	West,
	North,
	Left_Shoulder,
	Right_Shoulder,
	Left_Stick,
	Right_Stick,
	Start,
	Back,
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
}

Gamepad_Buttons :: bit_set[Gamepad_Button;u16]

// +x is right and +y is up on every OS.
Gamepad_Axes :: struct {
	// Each axis from -1 to 1.
	left_stick:    [2]f32,
	right_stick:   [2]f32,
	// From 0, at rest, to 1.
	left_trigger:  f32,
	right_trigger: f32,
}

// What a Gamepad reader gets from one connected pad in one poll. See
// gamepad_reader_poll.
Gamepad_Raw :: struct {
	// Stays the same while the pad stays connected. The latch keeps the
	// pad's slot by it.
	id:      u64,
	buttons: Gamepad_Buttons,
	// Before the dead zones.
	axes:    Gamepad_Axes,
}

Gamepad_Slot :: struct {
	connected: bool,
	id:        u64,
	// The buttons of the last poll. A button that goes down after it is pressed.
	polled:    Gamepad_Buttons,
	held:      Gamepad_Buttons,
	pressed:   Gamepad_Buttons,
	axes:      Gamepad_Axes,
}

// Holds the pads between the frame's poll and the step that takes them.
// A frame with no step keeps the presses for the next step.
Gamepad_Latch :: struct {
	slots:     [GAMEPAD_SLOTS]Gamepad_Slot,
	// Polls still track the pads, but they read as idle.
	unfocused: bool,
}

// One pad for one step. The button slices point into the Gamepad_Buffers.
Step_Gamepad :: struct {
	slot:    u8,
	held:    []u8,
	pressed: []u8,
	axes:    Gamepad_Axes,
}

Gamepad_Buffers :: struct {
	pads:    [GAMEPAD_SLOTS]Step_Gamepad,
	held:    [GAMEPAD_SLOTS][len(Gamepad_Button)]u8,
	pressed: [GAMEPAD_SLOTS][len(Gamepad_Button)]u8,
}

// Polls the Gamepad reader once. The host calls it once per frame, before the steps.
gamepads_poll :: proc(latch: ^Gamepad_Latch, reader: ^Gamepad_Reader) {
	raws: [GAMEPAD_RAW_MAX]Gamepad_Raw
	n := gamepad_reader_poll(reader, raws[:])
	gamepad_latch_poll(latch, raws[:clamp(n, 0, GAMEPAD_RAW_MAX)])
}

// raws holds every connected pad. A pad that is not in it has disconnected.
gamepad_latch_poll :: proc(latch: ^Gamepad_Latch, raws: []Gamepad_Raw) {
	for &slot in latch.slots {
		if slot.connected && !gamepad_raws_have(raws, slot.id) {
			slot = {}
		}
	}
	for raw in raws {
		slot := gamepad_slot_for(latch, raw)
		if slot == nil {
			continue
		}
		if latch.unfocused {
			gamepad_slot_idle(slot)
		} else {
			slot.pressed += raw.buttons - slot.polled
			slot.held = raw.buttons
			slot.axes = {
				left_stick    = gamepad_stick(raw.axes.left_stick),
				right_stick   = gamepad_stick(raw.axes.right_stick),
				left_trigger  = gamepad_trigger(raw.axes.left_trigger),
				right_trigger = gamepad_trigger(raw.axes.right_trigger),
			}
		}
		slot.polled = raw.buttons
	}
}

// The key-up events of held keys go to the window that took focus, and a
// pad keeps reporting to an unfocused window on some OSes.
gamepad_latch_focus :: proc(latch: ^Gamepad_Latch, focused: bool) {
	latch.unfocused = !focused
	if !focused {
		for &slot in latch.slots {
			gamepad_slot_idle(&slot)
		}
	}
}

// The connected pads in slot order. The pressed buttons go to this step.
gamepad_latch_take :: proc(latch: ^Gamepad_Latch, b: ^Gamepad_Buffers) -> []Step_Gamepad {
	n := 0
	for &slot, i in latch.slots {
		if !slot.connected {
			continue
		}
		b.pads[n] = {
			slot    = u8(i),
			held    = gamepad_button_codes(slot.held, b.held[n][:]),
			pressed = gamepad_button_codes(slot.pressed, b.pressed[n][:]),
			axes    = slot.axes,
		}
		n += 1
	}
	gamepad_latch_drop(latch)
	return b.pads[:n]
}

// Drops the pressed buttons. The held buttons and the axes stay.
gamepad_latch_drop :: proc(latch: ^Gamepad_Latch) {
	for &slot in latch.slots {
		slot.pressed = {}
	}
}

// The radial dead zone. A stick outside the unit disc, as on a square gate,
// is pulled back to its edge.
gamepad_stick :: proc(raw: [2]f32) -> [2]f32 {
	length := math.sqrt(raw.x * raw.x + raw.y * raw.y)
	if !(length > GAMEPAD_STICK_DEAD_ZONE) {
		return {}
	}
	scaled := min((length - GAMEPAD_STICK_DEAD_ZONE) / (1 - GAMEPAD_STICK_DEAD_ZONE), 1)
	return raw * (scaled / length)
}

gamepad_trigger :: proc(raw: f32) -> f32 {
	if !(raw > GAMEPAD_TRIGGER_DEAD_ZONE) {
		return 0
	}
	return min((raw - GAMEPAD_TRIGGER_DEAD_ZONE) / (1 - GAMEPAD_TRIGGER_DEAD_ZONE), 1)
}

button_from_tag :: proc(tag: string) -> (button: Gamepad_Button, ok: bool) {
	for name, b in BUTTON_TAGS {
		if name == tag {
			return b, true
		}
	}
	return {}, false
}

@(private = "file")
gamepad_raws_have :: proc(raws: []Gamepad_Raw, id: u64) -> bool {
	for raw in raws {
		if raw.id == id {
			return true
		}
	}
	return false
}

// A new pad takes the lowest free slot, with its buttons already down, so
// they are held and not pressed. Returns nil when every slot is taken.
@(private = "file")
gamepad_slot_for :: proc(latch: ^Gamepad_Latch, raw: Gamepad_Raw) -> ^Gamepad_Slot {
	for &slot in latch.slots {
		if slot.connected && slot.id == raw.id {
			return &slot
		}
	}
	for &slot in latch.slots {
		if !slot.connected {
			slot = {connected = true, id = raw.id, polled = raw.buttons}
			return &slot
		}
	}
	return nil
}

@(private = "file")
gamepad_slot_idle :: proc(slot: ^Gamepad_Slot) {
	slot.held = {}
	slot.axes = {}
}

@(private = "file")
gamepad_button_codes :: proc(buttons: Gamepad_Buttons, out: []u8) -> []u8 {
	n := 0
	for b in buttons {
		out[n] = u8(b)
		n += 1
	}
	return out[:n]
}
