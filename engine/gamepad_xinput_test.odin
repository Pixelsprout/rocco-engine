#+test
package engine

import "core:testing"

@(test)
test_xinput_map_gives_each_button_its_position :: proc(t: ^testing.T) {
	cases := [Gamepad_Button]u16 {
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
	for bit, button in cases {
		raw := xinput_map({buttons = bit}, id = 0)
		testing.expectf(t, raw.buttons == {button}, "bit %4x gave %v, want %v", bit, raw.buttons, button)
	}
}

@(test)
test_xinput_map_sets_the_id :: proc(t: ^testing.T) {
	testing.expect_value(t, xinput_map({}, id = 2).id, 2)
}

@(test)
test_xinput_map_gives_every_held_button :: proc(t: ^testing.T) {
	raw := xinput_map({buttons = XINPUT_A | XINPUT_DPAD_UP | XINPUT_START}, id = 0)
	testing.expect_value(t, raw.buttons, Gamepad_Buttons{.South, .Dpad_Up, .Start})
}

// The hidden XInputGetStateEx sets 0x0400 for the Guide button.
@(test)
test_xinput_map_skips_the_unused_bits :: proc(t: ^testing.T) {
	testing.expect_value(t, xinput_map({buttons = 0x0400 | 0x0800}, id = 0).buttons, Gamepad_Buttons{})
}

@(test)
test_xinput_map_stick_up_and_right_are_plus :: proc(t: ^testing.T) {
	raw := xinput_map({thumb_ly = 32767, thumb_rx = 32767}, id = 0)
	expect_near(t, raw.left_stick.y, 1)
	expect_near(t, raw.left_stick.x, 0)
	expect_near(t, raw.right_stick.x, 1)
	expect_near(t, raw.right_stick.y, 0)
}

// -32768 is one step past -32767, so it clamps to -1.
@(test)
test_xinput_map_stick_ends_are_minus_one_and_one :: proc(t: ^testing.T) {
	low := xinput_map({thumb_lx = -32768, thumb_ly = -32768, thumb_rx = -32768, thumb_ry = -32768}, id = 0)
	testing.expect_value(t, low.left_stick, [2]f32{-1, -1})
	testing.expect_value(t, low.right_stick, [2]f32{-1, -1})
	high := xinput_map({thumb_lx = 32767, thumb_ly = 32767, thumb_rx = 32767, thumb_ry = 32767}, id = 0)
	testing.expect_value(t, high.left_stick, [2]f32{1, 1})
	testing.expect_value(t, high.right_stick, [2]f32{1, 1})
}

@(test)
test_xinput_map_trigger_ends_are_zero_and_one :: proc(t: ^testing.T) {
	pulled := xinput_map({left_trigger = 255, right_trigger = 255}, id = 0)
	testing.expect_value(t, pulled.left_trigger, 1)
	testing.expect_value(t, pulled.right_trigger, 1)
	half := xinput_map({left_trigger = 51}, id = 0)
	expect_near(t, half.left_trigger, 0.2)
	testing.expect_value(t, half.right_trigger, 0)
}

@(test)
test_xinput_map_pad_at_rest_is_idle :: proc(t: ^testing.T) {
	raw := xinput_map({thumb_lx = 120, thumb_ly = -90, thumb_rx = -30, thumb_ry = 64}, id = 0)
	testing.expect_value(t, raw.buttons, Gamepad_Buttons{})
	testing.expect(t, abs(raw.left_stick.x) < 0.01 && abs(raw.left_stick.y) < 0.01)
	testing.expect(t, abs(raw.right_stick.x) < 0.01 && abs(raw.right_stick.y) < 0.01)
	testing.expect_value(t, raw.left_trigger, 0)
	testing.expect_value(t, raw.right_trigger, 0)
}

@(test)
test_xinput_map_feeds_the_latch :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {xinput_map({thumb_lx = 2000, left_trigger = 5}, id = 3)})
	pads := pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	testing.expect_value(t, pads[0].left_stick, [2]f32{})
	testing.expect_value(t, pads[0].left_trigger, 0)

	gamepad_latch_poll(&latch, {xinput_map({buttons = XINPUT_A, thumb_ly = 32767, right_trigger = 255}, id = 3)})
	pads = pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	expect_buttons(t, pads[0].held, {.South})
	expect_buttons(t, pads[0].pressed, {.South})
	expect_near(t, pads[0].left_stick.y, 1)
	expect_near(t, pads[0].left_stick.x, 0)
	expect_near(t, pads[0].right_trigger, 1)
}
