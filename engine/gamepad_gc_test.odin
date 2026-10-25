#+test
package engine

import "core:testing"

@(test)
test_gc_map_gives_each_button_its_position :: proc(t: ^testing.T) {
	cases := []struct {
		snapshot: Gc_Snapshot,
		button:   Gamepad_Button,
	} {
		{{button_a = true}, .South},
		{{button_b = true}, .East},
		{{button_x = true}, .West},
		{{button_y = true}, .North},
		{{left_shoulder = true}, .Left_Shoulder},
		{{right_shoulder = true}, .Right_Shoulder},
		{{left_thumbstick_button = true}, .Left_Stick},
		{{right_thumbstick_button = true}, .Right_Stick},
		{{button_menu = true}, .Start},
		{{button_options = true}, .Back},
		{{dpad_up = true}, .Dpad_Up},
		{{dpad_down = true}, .Dpad_Down},
		{{dpad_left = true}, .Dpad_Left},
		{{dpad_right = true}, .Dpad_Right},
	}
	testing.expect_value(t, len(cases), len(Gamepad_Button))
	for c in cases {
		raw := gc_map(c.snapshot, id = 7)
		testing.expect_value(t, raw.buttons, Gamepad_Buttons{c.button})
	}
}

@(test)
test_gc_map_keeps_the_id :: proc(t: ^testing.T) {
	raw := gc_map({}, id = 0x6000_1234_5678)
	testing.expect_value(t, raw.id, 0x6000_1234_5678)
}

@(test)
test_gc_map_keeps_plus_y_up_and_plus_x_right :: proc(t: ^testing.T) {
	raw := gc_map({left_thumbstick = {0, 1}, right_thumbstick = {1, 0}}, id = 1)
	testing.expect_value(t, raw.left_stick, [2]f32{0, 1})
	testing.expect_value(t, raw.right_stick, [2]f32{1, 0})
}

@(test)
test_gc_map_gives_the_ends_of_the_axes :: proc(t: ^testing.T) {
	low := gc_map({left_thumbstick = {-1, -1}, right_thumbstick = {-1, -1}}, id = 1)
	testing.expect_value(t, low.left_stick, [2]f32{-1, -1})
	testing.expect_value(t, low.right_stick, [2]f32{-1, -1})
	testing.expect_value(t, low.left_trigger, 0)
	testing.expect_value(t, low.right_trigger, 0)

	high := gc_map(
		{left_thumbstick = {1, 1}, right_thumbstick = {1, 1}, left_trigger = 1, right_trigger = 1},
		id = 1,
	)
	testing.expect_value(t, high.left_stick, [2]f32{1, 1})
	testing.expect_value(t, high.right_stick, [2]f32{1, 1})
	testing.expect_value(t, high.left_trigger, 1)
	testing.expect_value(t, high.right_trigger, 1)
}

@(test)
test_gc_map_gives_a_pad_at_rest_no_buttons_and_no_axes :: proc(t: ^testing.T) {
	raw := gc_map({}, id = 3)
	testing.expect_value(t, raw, Gamepad_Raw{id = 3})
}

@(test)
test_gc_map_feeds_the_latch :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buffers: Gamepad_Buffers
	gamepad_latch_poll(&latch, {gc_map({}, id = 9)})
	gamepad_latch_poll(&latch, {gc_map({button_a = true, right_trigger = 1, left_thumbstick = {0, 1}}, id = 9)})
	pads := gamepad_latch_take(&latch, &buffers)
	testing.expect_value(t, len(pads), 1)
	if len(pads) != 1 {
		return
	}
	testing.expect_value(t, len(pads[0].pressed), 1)
	if len(pads[0].pressed) == 1 {
		testing.expect_value(t, Gamepad_Button(pads[0].pressed[0]), Gamepad_Button.South)
	}
	testing.expect_value(t, pads[0].right_trigger, 1)
	testing.expect_value(t, pads[0].left_stick, [2]f32{0, 1})
}
