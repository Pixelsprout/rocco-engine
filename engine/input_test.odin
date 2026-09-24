package engine

import sapp "../sokol-odin/sokol/app"
import "core:testing"

key_down :: proc(latch: ^Input_Latch, k: sapp.Keycode, repeat := false) {
	e := sapp.Event{type = .KEY_DOWN, key_code = k, key_repeat = repeat}
	input_on_event(latch, &e)
}

key_up :: proc(latch: ^Input_Latch, k: sapp.Keycode) {
	e := sapp.Event{type = .KEY_UP, key_code = k}
	input_on_event(latch, &e)
}

mouse_move :: proc(latch: ^Input_Latch, dx, dy: f32) {
	e := sapp.Event{type = .MOUSE_MOVE, mouse_dx = dx, mouse_dy = dy}
	input_on_event(latch, &e)
}

@(test)
test_first_step_takes_pressed_and_mouse :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	key_down(&latch, .SPACE)
	mouse_move(&latch, 3, -2)

	first := input_take(&latch, &buf)
	testing.expect_value(t, len(first.held), 1)
	testing.expect_value(t, first.held[0], 32)
	testing.expect_value(t, len(first.pressed), 1)
	testing.expect_value(t, first.pressed[0], 32)
	testing.expect_value(t, first.mouse, [2]f32{3, -2})

	second := input_take(&latch, &buf)
	testing.expect_value(t, len(second.held), 1)
	testing.expect_value(t, len(second.pressed), 0)
	testing.expect_value(t, second.mouse, [2]f32{0, 0})
}

@(test)
test_a_tap_between_steps_is_pressed_but_not_held :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	key_down(&latch, .W)
	key_up(&latch, .W)

	keys := input_take(&latch, &buf)
	testing.expect_value(t, len(keys.held), 0)
	testing.expect_value(t, len(keys.pressed), 1)
	testing.expect_value(t, keys.pressed[0], 87)
}

@(test)
test_a_key_repeat_is_not_a_press :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	key_down(&latch, .A)
	_ = input_take(&latch, &buf)
	key_down(&latch, .A, repeat = true)

	keys := input_take(&latch, &buf)
	testing.expect_value(t, len(keys.pressed), 0)
	testing.expect_value(t, len(keys.held), 1)
}

@(test)
test_input_waits_for_a_step :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	key_down(&latch, .D)
	mouse_move(&latch, 1, 1)
	input_end_frame(&latch)
	mouse_move(&latch, 2, 0)
	input_end_frame(&latch)

	keys := input_take(&latch, &buf)
	testing.expect_value(t, len(keys.pressed), 1)
	testing.expect_value(t, keys.mouse, [2]f32{3, 1})
}

@(test)
test_keys_come_out_in_key_code_order :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	key_down(&latch, .W)
	key_down(&latch, .ESCAPE)
	key_down(&latch, .A)

	keys := input_take(&latch, &buf)
	testing.expect_value(t, len(keys.held), 3)
	testing.expect_value(t, keys.held[0], 65)
	testing.expect_value(t, keys.held[1], 87)
	testing.expect_value(t, keys.held[2], 256)
	testing.expect_value(t, len(keys.pressed), 3)
}

@(test)
test_frame_mouse_resets_every_frame :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Key_Buffers
	mouse_move(&latch, 4, 5)
	testing.expect_value(t, latch.frame_mouse, [2]f32{4, 5})
	_ = input_take(&latch, &buf)
	testing.expect_value(t, latch.frame_mouse, [2]f32{4, 5})
	input_end_frame(&latch)
	testing.expect_value(t, latch.frame_mouse, [2]f32{0, 0})
}
