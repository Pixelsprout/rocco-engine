#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:testing"

POINTER_TEST_WINDOW :: Ui_Window{size = {960, 540}, dpi = 1}

pointer_test_move :: proc(p: ^Pointer_Latch, x, y: f32) {
	e := sapp.Event{type = .MOUSE_MOVE, mouse_x = x, mouse_y = y}
	pointer_on_event(p, &e)
}

pointer_test_button :: proc(p: ^Pointer_Latch, type: sapp.Event_Type, button: sapp.Mousebutton) {
	e := sapp.Event{type = type, mouse_button = button}
	pointer_on_event(p, &e)
}

pointer_test_event :: proc(p: ^Pointer_Latch, type: sapp.Event_Type) {
	e := sapp.Event{type = type}
	pointer_on_event(p, &e)
}

@(test)
test_pointer_take_gives_the_position_in_logical_pixels :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_move(&p, 200, 100)

	got := pointer_take(&p, &buf, {size = {1920, 1080}, dpi = 2})

	testing.expect_value(t, got.pos, [2]f32{100, 50})
	testing.expect(t, got.inside)
}

@(test)
test_pointer_buttons_follow_the_key_rules :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_button(&p, .MOUSE_DOWN, .LEFT)

	got := pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	testing.expect_value(t, len(got.held), 1)
	testing.expect_value(t, got.held[0], 0)
	testing.expect_value(t, len(got.pressed), 1)
	testing.expect_value(t, got.pressed[0], 0)
	testing.expect_value(t, len(got.released), 0)

	got = pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	testing.expect_value(t, len(got.held), 1)
	testing.expect_value(t, len(got.pressed), 0)
	testing.expect_value(t, len(got.released), 0)

	pointer_test_button(&p, .MOUSE_UP, .LEFT)
	got = pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	testing.expect_value(t, len(got.held), 0)
	testing.expect_value(t, len(got.released), 1)
	testing.expect_value(t, got.released[0], 0)

	pointer_test_button(&p, .MOUSE_DOWN, .RIGHT)
	pointer_test_button(&p, .MOUSE_UP, .RIGHT)
	got = pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	testing.expect_value(t, len(got.held), 0)
	testing.expect_value(t, len(got.pressed), 1)
	testing.expect_value(t, got.pressed[0], 1)
	testing.expect_value(t, len(got.released), 1)
	testing.expect_value(t, got.released[0], 1)
}

@(test)
test_pointer_ignores_an_invalid_button :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_button(&p, .MOUSE_DOWN, .INVALID)

	got := pointer_take(&p, &buf, POINTER_TEST_WINDOW)

	testing.expect_value(t, len(got.held), 0)
	testing.expect_value(t, len(got.pressed), 0)
}

@(test)
test_pointer_wheel_adds_until_a_take :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	e := sapp.Event{type = .MOUSE_SCROLL, scroll_y = 1}
	pointer_on_event(&p, &e)
	pointer_on_event(&p, &e)

	testing.expect_value(t, pointer_take(&p, &buf, POINTER_TEST_WINDOW).wheel, [2]f32{0, 2})
	testing.expect_value(t, pointer_take(&p, &buf, POINTER_TEST_WINDOW).wheel, [2]f32{0, 0})
}

@(test)
test_pointer_leave_sets_inside_false_and_keeps_the_position :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_move(&p, 10, 10)
	pointer_test_event(&p, .MOUSE_LEAVE)

	got := pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	testing.expect(t, !got.inside)
	testing.expect_value(t, got.pos, [2]f32{10, 10})

	pointer_test_event(&p, .MOUSE_ENTER)
	testing.expect(t, pointer_take(&p, &buf, POINTER_TEST_WINDOW).inside)
}

@(test)
test_pointer_while_locked_keeps_the_position_and_is_not_inside :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_move(&p, 10, 10)
	p.locked = true
	pointer_test_move(&p, 500, 500)
	pointer_test_button(&p, .MOUSE_DOWN, .LEFT)

	got := pointer_take(&p, &buf, POINTER_TEST_WINDOW)

	testing.expect_value(t, got.pos, [2]f32{10, 10})
	testing.expect(t, !got.inside)
	testing.expect_value(t, len(got.held), 1)
	testing.expect_value(t, got.held[0], 0)
}

@(test)
test_pointer_focus_loss_releases_the_held_buttons :: proc(t: ^testing.T) {
	p: Pointer_Latch
	buf: Pointer_Buffers
	pointer_test_button(&p, .MOUSE_DOWN, .LEFT)
	pointer_take(&p, &buf, POINTER_TEST_WINDOW)
	pointer_test_event(&p, .UNFOCUSED)

	got := pointer_take(&p, &buf, POINTER_TEST_WINDOW)

	testing.expect_value(t, len(got.held), 0)
	testing.expect_value(t, len(got.released), 1)
	testing.expect_value(t, got.released[0], 0)
}

@(test)
test_pointer_in_window_is_half_open :: proc(t: ^testing.T) {
	window := [2]f32{960, 540}
	testing.expect(t, pointer_in_window({0, 0}, window))
	testing.expect(t, pointer_in_window({959.9, 539.9}, window))
	testing.expect(t, !pointer_in_window({960, 10}, window))
	testing.expect(t, !pointer_in_window({-1, 10}, window))
	testing.expect(t, !pointer_in_window({10, 540}, window))
}

@(test)
test_mouse_button_from_tag_knows_the_three_names :: proc(t: ^testing.T) {
	button, ok := mouse_button_from_tag("Left")
	testing.expect(t, ok)
	testing.expect_value(t, button, Mouse_Button.Left)
	button, ok = mouse_button_from_tag("Middle")
	testing.expect(t, ok)
	testing.expect_value(t, button, Mouse_Button.Middle)
	_, ok = mouse_button_from_tag("Back")
	testing.expect(t, !ok)
}
