package engine

// The values the macOS reader takes from one GCExtendedGamepad. Each field
// is named after its GameController selector, so the snapshot keeps the
// labels and gc_map gives the positions.
Gc_Snapshot :: struct {
	button_a:                bool,
	button_b:                bool,
	button_x:                bool,
	button_y:                bool,
	left_shoulder:           bool,
	right_shoulder:          bool,
	left_thumbstick_button:  bool,
	right_thumbstick_button: bool,
	button_menu:             bool,
	button_options:          bool,
	dpad_up:                 bool,
	dpad_down:               bool,
	dpad_left:               bool,
	dpad_right:              bool,
	// GameController reports +y up, as Gamepad_Raw does.
	left_thumbstick:         [2]f32,
	right_thumbstick:        [2]f32,
	left_trigger:            f32,
	right_trigger:           f32,
}

gc_map :: proc(snapshot: Gc_Snapshot, id: u64) -> Gamepad_Raw {
	buttons: Gamepad_Buttons
	if snapshot.button_a {buttons += {.South}}
	if snapshot.button_b {buttons += {.East}}
	if snapshot.button_x {buttons += {.West}}
	if snapshot.button_y {buttons += {.North}}
	if snapshot.left_shoulder {buttons += {.Left_Shoulder}}
	if snapshot.right_shoulder {buttons += {.Right_Shoulder}}
	if snapshot.left_thumbstick_button {buttons += {.Left_Stick}}
	if snapshot.right_thumbstick_button {buttons += {.Right_Stick}}
	if snapshot.button_menu {buttons += {.Start}}
	if snapshot.button_options {buttons += {.Back}}
	if snapshot.dpad_up {buttons += {.Dpad_Up}}
	if snapshot.dpad_down {buttons += {.Dpad_Down}}
	if snapshot.dpad_left {buttons += {.Dpad_Left}}
	if snapshot.dpad_right {buttons += {.Dpad_Right}}
	return {
		id = id,
		buttons = buttons,
		left_stick = snapshot.left_thumbstick,
		right_stick = snapshot.right_thumbstick,
		left_trigger = snapshot.left_trigger,
		right_trigger = snapshot.right_trigger,
	}
}
