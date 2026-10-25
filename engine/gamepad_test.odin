#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"
import "core:testing"

BUTTON_ROC :: #load("../platform/Button.roc", string)

pad_raw :: proc(id: u64, buttons: Gamepad_Buttons = {}, left_stick: [2]f32 = {}, right_stick: [2]f32 = {}, left_trigger: f32 = 0, right_trigger: f32 = 0) -> Gamepad_Raw {
	return {id = id, buttons = buttons, left_stick = left_stick, right_stick = right_stick, left_trigger = left_trigger, right_trigger = right_trigger}
}

pad_take :: proc(latch: ^Gamepad_Latch, buf: ^Gamepad_Buffers) -> []Step_Gamepad {
	return gamepad_latch_take(latch, buf)
}

expect_buttons :: proc(t: ^testing.T, got: []u8, want: []Gamepad_Button, loc := #caller_location) {
	codes := make([]u8, len(want), context.temp_allocator)
	for b, i in want {
		codes[i] = u8(b)
	}
	testing.expectf(t, slice.equal(got, codes), "got buttons %v, want %v", got, codes, loc = loc)
}

expect_near :: proc(t: ^testing.T, got, want: f32, loc := #caller_location) {
	testing.expectf(t, abs(got - want) < 1e-5, "got %v, want %v", got, want, loc = loc)
}

@(test)
test_gamepad_stick_inside_the_dead_zone_reads_zero :: proc(t: ^testing.T) {
	inside := f32(GAMEPAD_STICK_DEAD_ZONE * 0.9)
	testing.expect_value(t, gamepad_stick({inside, 0}), [2]f32{})
	testing.expect_value(t, gamepad_stick({inside * 0.7, -inside * 0.7}), [2]f32{})
	testing.expect_value(t, gamepad_stick({}), [2]f32{})
}

// The dead zone is radial, so a diagonal keeps its direction, and the stick
// still reaches the edge of the unit disc.
@(test)
test_gamepad_stick_past_the_dead_zone_rescales_to_the_unit_disc :: proc(t: ^testing.T) {
	expect_near(t, gamepad_stick({1, 0}).x, 1)
	half := f32(GAMEPAD_STICK_DEAD_ZONE + (1 - GAMEPAD_STICK_DEAD_ZONE) / 2)
	expect_near(t, gamepad_stick({-half, 0}).x, -0.5)

	corner := gamepad_stick({1, 1})
	expect_near(t, math.sqrt(corner.x * corner.x + corner.y * corner.y), 1)
	expect_near(t, corner.x, corner.y)
}

// Each backend reports +y up, so up stays up through the dead zone.
@(test)
test_gamepad_stick_up_is_plus_y :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1, left_stick = {0, 1}, right_stick = {0, -1})})
	pads := pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	expect_near(t, pads[0].left_stick.y, 1)
	expect_near(t, pads[0].right_stick.y, -1)
}

@(test)
test_gamepad_trigger_dead_zone_and_range :: proc(t: ^testing.T) {
	testing.expect_value(t, gamepad_trigger(GAMEPAD_TRIGGER_DEAD_ZONE * 0.5), 0)
	testing.expect_value(t, gamepad_trigger(0), 0)
	expect_near(t, gamepad_trigger(1), 1)
	expect_near(t, gamepad_trigger(GAMEPAD_TRIGGER_DEAD_ZONE + (1 - GAMEPAD_TRIGGER_DEAD_ZONE) / 2), 0.5)
	testing.expect_value(t, gamepad_trigger(-0.5), 0)
	expect_near(t, gamepad_trigger(2), 1)
}

@(test)
test_gamepad_with_no_pad_takes_an_empty_list :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {})
	testing.expect_value(t, len(pad_take(&latch, &buf)), 0)
}

// A pad keeps its slot while it stays connected, and a new pad takes the
// lowest free slot.
@(test)
test_gamepad_slots_are_kept_and_the_lowest_free_slot_is_reused :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(10), pad_raw(20)})
	pads := pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 2)
	testing.expect_value(t, pads[0].slot, 0)
	testing.expect_value(t, pads[1].slot, 1)

	gamepad_latch_poll(&latch, {pad_raw(20)})
	pads = pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	testing.expect_value(t, pads[0].slot, 1)

	gamepad_latch_poll(&latch, {pad_raw(30), pad_raw(20)})
	gamepad_latch_poll(&latch, {pad_raw(20), pad_raw(30), pad_raw(40)})
	pads = pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), 3)
	testing.expect_value(t, latch.slots[0].id, 30)
	testing.expect_value(t, latch.slots[1].id, 20)
	testing.expect_value(t, latch.slots[2].id, 40)
}

@(test)
test_gamepad_reports_at_most_the_slot_count :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1), pad_raw(2), pad_raw(3), pad_raw(4), pad_raw(5)})
	testing.expect_value(t, len(pad_take(&latch, &buf)), GAMEPAD_SLOTS)

	// A pad past the slots gets the first slot that frees.
	gamepad_latch_poll(&latch, {pad_raw(2), pad_raw(3), pad_raw(4), pad_raw(5)})
	pads := pad_take(&latch, &buf)
	testing.expect_value(t, len(pads), GAMEPAD_SLOTS)
	testing.expect_value(t, latch.slots[0].id, 5)
}

@(test)
test_gamepad_button_down_at_connect_is_held_not_pressed :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1, {.South})})
	pads := pad_take(&latch, &buf)
	expect_buttons(t, pads[0].held, {.South})
	expect_buttons(t, pads[0].pressed, {})

	gamepad_latch_poll(&latch, {pad_raw(1, {.South, .East})})
	pads = pad_take(&latch, &buf)
	expect_buttons(t, pads[0].held, {.South, .East})
	expect_buttons(t, pads[0].pressed, {.East})
}

// Polls run once per frame and steps take the latch, so a frame with no step
// keeps the presses for the next step.
@(test)
test_gamepad_pressed_waits_through_a_frame_with_no_step :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1)})
	_ = pad_take(&latch, &buf)

	gamepad_latch_poll(&latch, {pad_raw(1, {.Start})})
	gamepad_latch_poll(&latch, {pad_raw(1, {.Start})})
	pads := pad_take(&latch, &buf)
	expect_buttons(t, pads[0].pressed, {.Start})
	expect_buttons(t, pads[0].held, {.Start})

	pads = pad_take(&latch, &buf)
	expect_buttons(t, pads[0].pressed, {})
	expect_buttons(t, pads[0].held, {.Start})
}

@(test)
test_gamepad_a_tap_between_steps_is_pressed_but_not_held :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1)})
	gamepad_latch_poll(&latch, {pad_raw(1, {.North})})
	gamepad_latch_poll(&latch, {pad_raw(1)})
	pads := pad_take(&latch, &buf)
	expect_buttons(t, pads[0].pressed, {.North})
	expect_buttons(t, pads[0].held, {})
}

@(test)
test_gamepad_drop_keeps_held_and_drops_pressed :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	gamepad_latch_poll(&latch, {pad_raw(1)})
	gamepad_latch_poll(&latch, {pad_raw(1, {.West})})
	gamepad_latch_drop(&latch)
	pads := pad_take(&latch, &buf)
	expect_buttons(t, pads[0].pressed, {})
	expect_buttons(t, pads[0].held, {.West})
}

// While the window has no focus the pads stay connected but read as idle.
// A button still down when focus returns is held, not pressed.
@(test)
test_gamepad_unfocus_clears_held_and_axes_until_focus_returns :: proc(t: ^testing.T) {
	latch: Input_Latch
	buf: Input_Buffers
	gamepad_latch_poll(&latch.gamepads, {pad_raw(1, {.South}, {0.9, 0}, {0, 0.9}, 0.8, 0.8)})
	unfocused := sapp.Event{type = .UNFOCUSED}
	input_on_event(&latch, &unfocused)

	pads := input_take(&latch, &buf).gamepads
	testing.expect_value(t, len(pads), 1)
	expect_buttons(t, pads[0].held, {})
	testing.expect_value(t, pads[0].left_stick, [2]f32{})
	testing.expect_value(t, pads[0].right_stick, [2]f32{})
	testing.expect_value(t, pads[0].left_trigger, 0)
	testing.expect_value(t, pads[0].right_trigger, 0)

	gamepad_latch_poll(&latch.gamepads, {pad_raw(1, {.South, .East}, {0.9, 0})})
	pads = input_take(&latch, &buf).gamepads
	expect_buttons(t, pads[0].held, {})
	expect_buttons(t, pads[0].pressed, {})
	testing.expect_value(t, pads[0].left_stick, [2]f32{})

	focused := sapp.Event{type = .FOCUSED}
	input_on_event(&latch, &focused)
	gamepad_latch_poll(&latch.gamepads, {pad_raw(1, {.South, .East}, {0.9, 0})})
	pads = input_take(&latch, &buf).gamepads
	expect_buttons(t, pads[0].held, {.South, .East})
	expect_buttons(t, pads[0].pressed, {})
	testing.expect(t, pads[0].left_stick.x > 0)
}

@(test)
test_button_from_tag_finds_the_buttons_and_rejects_an_unknown_name :: proc(t: ^testing.T) {
	button, ok := button_from_tag("South")
	testing.expect(t, ok)
	testing.expect_value(t, button, Gamepad_Button.South)
	button, ok = button_from_tag("DpadRight")
	testing.expect(t, ok)
	testing.expect_value(t, button, Gamepad_Button.Dpad_Right)
	for tag in ([]string{"A", "south", "Guide", "LeftTrigger", ""}) {
		_, ok = button_from_tag(tag)
		testing.expectf(t, !ok, "expected %q to be unknown", tag)
	}
}

// Button.code in platform/Button.roc must give each tag the host's code.
@(test)
test_button_tags_match_the_codes_in_button_roc :: proc(t: ^testing.T) {
	for button in Gamepad_Button {
		line := fmt.tprintf("\t\t%v => %v\n", BUTTON_TAGS[button], u8(button))
		testing.expectf(t, strings.contains(BUTTON_ROC, line), "platform/Button.roc has no line %q", line)
	}
	testing.expect_value(t, strings.count(BUTTON_ROC, " => "), len(Gamepad_Button))
}

// The OS calls get a smoke test only. CI runners have no pad, but a
// developer's machine may have one.
@(test)
test_gamepad_backend_polls_without_a_crash :: proc(t: ^testing.T) {
	backend: Gamepad_Backend
	gamepad_backend_init(&backend)
	defer gamepad_backend_shutdown(&backend)
	raws: [GAMEPAD_RAW_MAX]Gamepad_Raw
	for _ in 0 ..< 3 {
		n := gamepad_backend_poll(&backend, raws[:])
		testing.expectf(t, n >= 0 && n <= GAMEPAD_RAW_MAX, "the backend reported %v pads", n)
	}
}
