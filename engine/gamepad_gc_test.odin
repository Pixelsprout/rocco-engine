#+test
package engine

import "core:testing"

@(test)
test_gc_map_gives_each_button_its_position :: proc(t: ^testing.T) {
	cases := []struct {
		snapshot: Gc_Snapshot,
		button:   Gamepad_Button,
	} {
		{{pressed = #partial {.Button_A = true}}, .South},
		{{pressed = #partial {.Button_B = true}}, .East},
		{{pressed = #partial {.Button_X = true}}, .West},
		{{pressed = #partial {.Button_Y = true}}, .North},
		{{pressed = #partial {.Left_Shoulder = true}}, .Left_Shoulder},
		{{pressed = #partial {.Right_Shoulder = true}}, .Right_Shoulder},
		{{pressed = #partial {.Left_Thumbstick_Button = true}}, .Left_Stick},
		{{pressed = #partial {.Right_Thumbstick_Button = true}}, .Right_Stick},
		{{pressed = #partial {.Button_Menu = true}}, .Start},
		{{pressed = #partial {.Button_Options = true}}, .Back},
		{{pressed = #partial {.Dpad_Up = true}}, .Dpad_Up},
		{{pressed = #partial {.Dpad_Down = true}}, .Dpad_Down},
		{{pressed = #partial {.Dpad_Left = true}}, .Dpad_Left},
		{{pressed = #partial {.Dpad_Right = true}}, .Dpad_Right},
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
	testing.expect_value(t, raw.axes.left_stick, [2]f32{0, 1})
	testing.expect_value(t, raw.axes.right_stick, [2]f32{1, 0})
}

@(test)
test_gc_map_gives_the_ends_of_the_axes :: proc(t: ^testing.T) {
	low := gc_map({left_thumbstick = {-1, -1}, right_thumbstick = {-1, -1}}, id = 1)
	testing.expect_value(t, low.axes.left_stick, [2]f32{-1, -1})
	testing.expect_value(t, low.axes.right_stick, [2]f32{-1, -1})
	testing.expect_value(t, low.axes.left_trigger, 0)
	testing.expect_value(t, low.axes.right_trigger, 0)

	high := gc_map(
		{left_thumbstick = {1, 1}, right_thumbstick = {1, 1}, left_trigger = 1, right_trigger = 1},
		id = 1,
	)
	testing.expect_value(t, high.axes.left_stick, [2]f32{1, 1})
	testing.expect_value(t, high.axes.right_stick, [2]f32{1, 1})
	testing.expect_value(t, high.axes.left_trigger, 1)
	testing.expect_value(t, high.axes.right_trigger, 1)
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
	gamepad_latch_poll(&latch, {gc_map({pressed = #partial {.Button_A = true}, right_trigger = 1, left_thumbstick = {0, 1}}, id = 9)})
	pads := gamepad_latch_take(&latch, &buffers)
	testing.expect_value(t, len(pads), 1)
	if len(pads) != 1 {
		return
	}
	testing.expect_value(t, len(pads[0].pressed), 1)
	if len(pads[0].pressed) == 1 {
		testing.expect_value(t, Gamepad_Button(pads[0].pressed[0]), Gamepad_Button.South)
	}
	testing.expect_value(t, pads[0].axes.right_trigger, 1)
	testing.expect_value(t, pads[0].axes.left_stick, [2]f32{0, 1})
}
