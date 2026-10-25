package engine

// The evdev mapping has no OS calls and no build tag, so every runner tests
// it. The codes are copied from linux/input-event-codes.h.

EV_SYN :: 0x00
EV_KEY :: 0x01
EV_ABS :: 0x03

SYN_REPORT :: 0
SYN_DROPPED :: 3

BTN_GAMEPAD :: BTN_SOUTH
BTN_SOUTH :: 0x130
BTN_EAST :: 0x131
BTN_NORTH :: 0x133
BTN_WEST :: 0x134
BTN_TL :: 0x136
BTN_TR :: 0x137
BTN_SELECT :: 0x13a
BTN_START :: 0x13b
BTN_THUMBL :: 0x13d
BTN_THUMBR :: 0x13e
BTN_DPAD_UP :: 0x220
BTN_DPAD_DOWN :: 0x221
BTN_DPAD_LEFT :: 0x222
BTN_DPAD_RIGHT :: 0x223
BTN_TRIGGER_HAPPY1 :: 0x2c0
BTN_TRIGGER_HAPPY2 :: 0x2c1
BTN_TRIGGER_HAPPY3 :: 0x2c2
BTN_TRIGGER_HAPPY4 :: 0x2c3

ABS_X :: 0x00
ABS_Y :: 0x01
ABS_Z :: 0x02
ABS_RX :: 0x03
ABS_RY :: 0x04
ABS_RZ :: 0x05
ABS_HAT0X :: 0x10
ABS_HAT0Y :: 0x11

// KEY_CNT / 8: the size of the key bit arrays that EVIOCGBIT and EVIOCGKEY fill.
EVDEV_KEY_BYTES :: 0x300 / 8

@(rodata)
EVDEV_AXIS_CODES := [Evdev_Axis]u16 {
	.X     = ABS_X,
	.Y     = ABS_Y,
	.Z     = ABS_Z,
	.RX    = ABS_RX,
	.RY    = ABS_RY,
	.RZ    = ABS_RZ,
	.Hat_X = ABS_HAT0X,
	.Hat_Y = ABS_HAT0Y,
}

// struct input_event on 64-bit Linux. The Linux reader copies an event node
// straight into an array of these.
Evdev_Event :: struct {
	time_sec:  i64,
	time_usec: i64,
	type:      u16,
	code:      u16,
	value:     i32,
}
#assert(size_of(Evdev_Event) == 24)

// struct input_absinfo, as EVIOCGABS fills it.
Evdev_Absinfo :: struct {
	value:      i32,
	minimum:    i32,
	maximum:    i32,
	fuzz:       i32,
	flat:       i32,
	resolution: i32,
}
#assert(size_of(Evdev_Absinfo) == 24)

Evdev_Axis :: enum u8 {
	X,
	Y,
	Z,
	RX,
	RY,
	RZ,
	Hat_X,
	Hat_Y,
}

// One pad's state, built from its evdev events.
Evdev_Gamepad :: struct {
	// xpad reports the Xbox X button as BTN_NORTH and Y as BTN_WEST, by
	// label and not by position. It also may send the D-pad as
	// BTN_TRIGGER_HAPPY1 to 4.
	xpad:     bool,
	// The key buttons down now. The hat adds the D-pad in evdev_map.
	buttons:  Gamepad_Buttons,
	// The buttons that went down since the last evdev_poll, so that a tap
	// shorter than one frame still reads as down in one poll.
	latched:  Gamepad_Buttons,
	// An axis the pad lacks keeps maximum == minimum and reads 0.
	axes:     [Evdev_Axis]Evdev_Absinfo,
	// After SYN_DROPPED the events up to the next SYN_REPORT are stale.
	dropping: bool,
	// Set when a drop ends. The Linux reader loads the key and axis state again
	// and clears it.
	resync:   bool,
}

evdev_apply :: proc(pad: ^Evdev_Gamepad, events: []Evdev_Event) {
	for e in events {
		if pad.dropping {
			if e.type == EV_SYN && e.code == SYN_REPORT {
				pad.dropping = false
				pad.resync = true
			}
			continue
		}
		switch e.type {
		case EV_SYN:
			pad.dropping = e.code == SYN_DROPPED
		case EV_KEY:
			if b, ok := evdev_button(e.code, pad.xpad); ok {
				// A value of 2 is a key repeat, so the button stays down.
				if e.value == 0 {
					pad.buttons -= {b}
				} else {
					pad.buttons += {b}
					pad.latched += {b}
				}
			}
		case EV_ABS:
			for code, axis in EVDEV_AXIS_CODES {
				if code == e.code {
					pad.axes[axis].value = e.value
				}
			}
			pad.latched += evdev_hat(pad^)
		}
	}
}

evdev_map :: proc(pad: Evdev_Gamepad, id: u64) -> Gamepad_Raw {
	return {
		id      = id,
		buttons = pad.buttons + pad.latched + evdev_hat(pad),
		axes    = {
			left_stick    = {evdev_stick(pad.axes[.X]), -evdev_stick(pad.axes[.Y])},
			right_stick   = {evdev_stick(pad.axes[.RX]), -evdev_stick(pad.axes[.RY])},
			left_trigger  = evdev_unit(pad.axes[.Z]),
			right_trigger = evdev_unit(pad.axes[.RZ]),
		},
	}
}

// Maps the pad for one poll and clears the latched buttons.
evdev_poll :: proc(pad: ^Evdev_Gamepad, id: u64) -> Gamepad_Raw {
	raw := evdev_map(pad^, id)
	pad.latched = {}
	return raw
}

// Sets the buttons from an EVIOCGKEY bit array.
evdev_set_keys :: proc(pad: ^Evdev_Gamepad, bits: []u8) {
	pad.buttons = {}
	for byte, i in bits {
		if byte == 0 {
			continue
		}
		for bit in 0 ..< 8 {
			if byte & (1 << u8(bit)) == 0 {
				continue
			}
			if b, ok := evdev_button(u16(i * 8 + bit), pad.xpad); ok {
				pad.buttons += {b}
			}
		}
	}
}

evdev_has_key :: proc(bits: []u8, code: u16) -> bool {
	i := int(code / 8)
	return i < len(bits) && bits[i] & (1 << (code % 8)) != 0
}

evdev_button :: proc(code: u16, xpad: bool) -> (Gamepad_Button, bool) {
	switch code {
	case BTN_SOUTH:
		return .South, true
	case BTN_EAST:
		return .East, true
	case BTN_NORTH:
		return .West if xpad else .North, true
	case BTN_WEST:
		return .North if xpad else .West, true
	case BTN_TL:
		return .Left_Shoulder, true
	case BTN_TR:
		return .Right_Shoulder, true
	case BTN_THUMBL:
		return .Left_Stick, true
	case BTN_THUMBR:
		return .Right_Stick, true
	case BTN_START:
		return .Start, true
	case BTN_SELECT:
		return .Back, true
	case BTN_DPAD_UP:
		return .Dpad_Up, true
	case BTN_DPAD_DOWN:
		return .Dpad_Down, true
	case BTN_DPAD_LEFT:
		return .Dpad_Left, true
	case BTN_DPAD_RIGHT:
		return .Dpad_Right, true
	}
	if xpad {
		switch code {
		case BTN_TRIGGER_HAPPY1:
			return .Dpad_Left, true
		case BTN_TRIGGER_HAPPY2:
			return .Dpad_Right, true
		case BTN_TRIGGER_HAPPY3:
			return .Dpad_Up, true
		case BTN_TRIGGER_HAPPY4:
			return .Dpad_Down, true
		}
	}
	return {}, false
}

// From 0 at the minimum to 1 at the maximum.
@(private = "file")
evdev_unit :: proc(a: Evdev_Absinfo) -> f32 {
	if a.maximum <= a.minimum {
		return 0
	}
	t := (f64(a.value) - f64(a.minimum)) / (f64(a.maximum) - f64(a.minimum))
	return f32(clamp(t, 0, 1))
}

@(private = "file")
evdev_stick :: proc(a: Evdev_Absinfo) -> f32 {
	if a.maximum <= a.minimum {
		return 0
	}
	return evdev_unit(a) * 2 - 1
}

// The D-pad of a pad that sends it as ABS_HAT0X and ABS_HAT0Y. -1 on y is up.
@(private = "file")
evdev_hat :: proc(pad: Evdev_Gamepad) -> Gamepad_Buttons {
	buttons: Gamepad_Buttons
	hat_x := pad.axes[.Hat_X].value
	hat_y := pad.axes[.Hat_Y].value
	if hat_x < 0 do buttons += {.Dpad_Left}
	if hat_x > 0 do buttons += {.Dpad_Right}
	if hat_y < 0 do buttons += {.Dpad_Up}
	if hat_y > 0 do buttons += {.Dpad_Down}
	return buttons
}
