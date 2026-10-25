package engine

// The wButtons bits of XINPUT_GAMEPAD. core:sys/windows declares them only
// on Windows, and the mapping tests run on every OS.
XINPUT_DPAD_UP :: 0x0001
XINPUT_DPAD_DOWN :: 0x0002
XINPUT_DPAD_LEFT :: 0x0004
XINPUT_DPAD_RIGHT :: 0x0008
XINPUT_START :: 0x0010
XINPUT_BACK :: 0x0020
XINPUT_LEFT_THUMB :: 0x0040
XINPUT_RIGHT_THUMB :: 0x0080
XINPUT_LEFT_SHOULDER :: 0x0100
XINPUT_RIGHT_SHOULDER :: 0x0200
XINPUT_A :: 0x1000
XINPUT_B :: 0x2000
XINPUT_X :: 0x4000
XINPUT_Y :: 0x8000

@(rodata)
XINPUT_BUTTON_BITS := [Gamepad_Button]u16 {
	.South          = XINPUT_A,
	.East           = XINPUT_B,
	.West           = XINPUT_X,
	.North          = XINPUT_Y,
	.Left_Shoulder  = XINPUT_LEFT_SHOULDER,
	.Right_Shoulder = XINPUT_RIGHT_SHOULDER,
	.Left_Stick     = XINPUT_LEFT_THUMB,
	.Right_Stick    = XINPUT_RIGHT_THUMB,
	.Start          = XINPUT_START,
	.Back           = XINPUT_BACK,
	.Dpad_Up        = XINPUT_DPAD_UP,
	.Dpad_Down      = XINPUT_DPAD_DOWN,
	.Dpad_Left      = XINPUT_DPAD_LEFT,
	.Dpad_Right     = XINPUT_DPAD_RIGHT,
}

// A copy of XINPUT_GAMEPAD, field for field. gamepad_windows.odin asserts
// that the sizes match.
Xinput_Gamepad :: struct {
	buttons:       u16,
	left_trigger:  u8,
	right_trigger: u8,
	thumb_lx:      i16,
	thumb_ly:      i16,
	thumb_rx:      i16,
	thumb_ry:      i16,
}

// XInput reports +y up, as Gamepad_Raw does.
xinput_map :: proc(pad: Xinput_Gamepad, id: u64) -> Gamepad_Raw {
	raw := Gamepad_Raw {
		id   = id,
		axes = {
			left_stick    = {xinput_axis(pad.thumb_lx), xinput_axis(pad.thumb_ly)},
			right_stick   = {xinput_axis(pad.thumb_rx), xinput_axis(pad.thumb_ry)},
			left_trigger  = f32(pad.left_trigger) / 255,
			right_trigger = f32(pad.right_trigger) / 255,
		},
	}
	for bit, button in XINPUT_BUTTON_BITS {
		if pad.buttons & bit != 0 {
			raw.buttons += {button}
		}
	}
	return raw
}

@(private = "file")
xinput_axis :: proc(value: i16) -> f32 {
	return max(f32(value) / 32767, -1)
}
