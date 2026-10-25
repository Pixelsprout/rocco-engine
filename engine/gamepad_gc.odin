package engine

@(rodata)
GC_BUTTON_SELECTORS := [Gamepad_Button]Gc_Button_Selector {
	.South          = .Button_A,
	.East           = .Button_B,
	.West           = .Button_X,
	.North          = .Button_Y,
	.Left_Shoulder  = .Left_Shoulder,
	.Right_Shoulder = .Right_Shoulder,
	.Left_Stick     = .Left_Thumbstick_Button,
	.Right_Stick    = .Right_Thumbstick_Button,
	.Start          = .Button_Menu,
	.Back           = .Button_Options,
	.Dpad_Up        = .Dpad_Up,
	.Dpad_Down      = .Dpad_Down,
	.Dpad_Left      = .Dpad_Left,
	.Dpad_Right     = .Dpad_Right,
}

// The GCExtendedGamepad button selectors. The D-pad ones are the up, down,
// left and right of its dpad.
Gc_Button_Selector :: enum u8 {
	Button_A,
	Button_B,
	Button_X,
	Button_Y,
	Left_Shoulder,
	Right_Shoulder,
	Left_Thumbstick_Button,
	Right_Thumbstick_Button,
	Button_Menu,
	Button_Options,
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
}

// The values the macOS reader takes from one GCExtendedGamepad. The snapshot
// keeps the GameController labels, and gc_map gives the positions.
Gc_Snapshot :: struct {
	pressed:          [Gc_Button_Selector]bool,
	// GameController reports +y up, as Gamepad_Raw does.
	left_thumbstick:  [2]f32,
	right_thumbstick: [2]f32,
	left_trigger:     f32,
	right_trigger:    f32,
}

gc_map :: proc(snapshot: Gc_Snapshot, id: u64) -> Gamepad_Raw {
	raw := Gamepad_Raw {
		id   = id,
		axes = {
			left_stick    = snapshot.left_thumbstick,
			right_stick   = snapshot.right_thumbstick,
			left_trigger  = snapshot.left_trigger,
			right_trigger = snapshot.right_trigger,
		},
	}
	for selector, button in GC_BUTTON_SELECTORS {
		if snapshot.pressed[selector] {
			raw.buttons += {button}
		}
	}
	return raw
}
