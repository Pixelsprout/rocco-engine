#+test
package engine

import "core:testing"

Evdev_Case :: struct {
	code: u16,
	want: Gamepad_Button,
}

// The ranges xpad gives an Xbox One pad on a cable. An Xbox 360 pad has
// triggers from 0 to 255.
xpad_pad :: proc(trigger_max: i32 = 1023) -> Evdev_Gamepad {
	pad := Evdev_Gamepad {
		xpad = true,
	}
	for axis in ([]Evdev_Axis{.X, .Y, .RX, .RY}) {
		pad.axes[axis] = {minimum = -32768, maximum = 32767, fuzz = 16, flat = 128}
	}
	pad.axes[.Z] = {maximum = trigger_max}
	pad.axes[.RZ] = {maximum = trigger_max}
	pad.axes[.Hat_X] = {minimum = -1, maximum = 1}
	pad.axes[.Hat_Y] = {minimum = -1, maximum = 1}
	return pad
}

// hid-playstation: sticks from 0 to 255 with the centre at 128.
playstation_pad :: proc() -> Evdev_Gamepad {
	pad: Evdev_Gamepad
	for axis in ([]Evdev_Axis{.X, .Y, .RX, .RY}) {
		pad.axes[axis] = {value = 128, maximum = 255}
	}
	pad.axes[.Z] = {maximum = 255}
	pad.axes[.RZ] = {maximum = 255}
	pad.axes[.Hat_X] = {minimum = -1, maximum = 1}
	pad.axes[.Hat_Y] = {minimum = -1, maximum = 1}
	return pad
}

ev_key :: proc(code: u16, value: i32 = 1) -> Evdev_Event {
	return {type = EV_KEY, code = code, value = value}
}

ev_abs :: proc(code: u16, value: i32) -> Evdev_Event {
	return {type = EV_ABS, code = code, value = value}
}

ev_syn :: proc(code: u16 = SYN_REPORT) -> Evdev_Event {
	return {type = EV_SYN, code = code}
}

evdev_pressed :: proc(pad: Evdev_Gamepad, events: []Evdev_Event) -> Gamepad_Buttons {
	pad := pad
	evdev_apply(&pad, events)
	return evdev_map(pad, 1).buttons
}

@(test)
test_evdev_xpad_buttons_map_to_positions :: proc(t: ^testing.T) {
	cases := []Evdev_Case {
		{BTN_SOUTH, .South},
		{BTN_EAST, .East},
		{BTN_NORTH, .West},
		{BTN_WEST, .North},
		{BTN_TL, .Left_Shoulder},
		{BTN_TR, .Right_Shoulder},
		{BTN_THUMBL, .Left_Stick},
		{BTN_THUMBR, .Right_Stick},
		{BTN_START, .Start},
		{BTN_SELECT, .Back},
		{BTN_TRIGGER_HAPPY1, .Dpad_Left},
		{BTN_TRIGGER_HAPPY2, .Dpad_Right},
		{BTN_TRIGGER_HAPPY3, .Dpad_Up},
		{BTN_TRIGGER_HAPPY4, .Dpad_Down},
	}
	for c in cases {
		got := evdev_pressed(xpad_pad(), {ev_key(c.code), ev_syn()})
		testing.expectf(t, got == {c.want}, "code %x gave %v, want %v", c.code, got, c.want)
	}
}

@(test)
test_evdev_xpad_hat_maps_to_the_dpad :: proc(t: ^testing.T) {
	testing.expect_value(t, evdev_pressed(xpad_pad(), {ev_abs(ABS_HAT0Y, -1), ev_syn()}), Gamepad_Buttons{.Dpad_Up})
	testing.expect_value(t, evdev_pressed(xpad_pad(), {ev_abs(ABS_HAT0Y, 1), ev_syn()}), Gamepad_Buttons{.Dpad_Down})
	testing.expect_value(t, evdev_pressed(xpad_pad(), {ev_abs(ABS_HAT0X, -1), ev_syn()}), Gamepad_Buttons{.Dpad_Left})
	testing.expect_value(t, evdev_pressed(xpad_pad(), {ev_abs(ABS_HAT0X, 1), ev_syn()}), Gamepad_Buttons{.Dpad_Right})
	diagonal := evdev_pressed(xpad_pad(), {ev_abs(ABS_HAT0X, 1), ev_abs(ABS_HAT0Y, -1), ev_syn()})
	testing.expect_value(t, diagonal, Gamepad_Buttons{.Dpad_Up, .Dpad_Right})
}

@(test)
test_evdev_other_drivers_follow_the_kernel_positions :: proc(t: ^testing.T) {
	cases := []Evdev_Case {
		{BTN_SOUTH, .South},
		{BTN_EAST, .East},
		{BTN_NORTH, .North},
		{BTN_WEST, .West},
		{BTN_DPAD_UP, .Dpad_Up},
		{BTN_DPAD_DOWN, .Dpad_Down},
		{BTN_DPAD_LEFT, .Dpad_Left},
		{BTN_DPAD_RIGHT, .Dpad_Right},
	}
	for c in cases {
		got := evdev_pressed(playstation_pad(), {ev_key(c.code), ev_syn()})
		testing.expectf(t, got == {c.want}, "code %x gave %v, want %v", c.code, got, c.want)
	}
	// Only xpad sends the D-pad as BTN_TRIGGER_HAPPY. Elsewhere they are other buttons.
	testing.expect_value(t, evdev_pressed(playstation_pad(), {ev_key(BTN_TRIGGER_HAPPY1), ev_syn()}), Gamepad_Buttons{})
}

@(test)
test_evdev_buttons_release_at_the_next_poll_and_ignore_repeats :: proc(t: ^testing.T) {
	pad := xpad_pad()
	evdev_apply(&pad, {ev_key(BTN_SOUTH), ev_key(BTN_EAST), ev_syn()})
	testing.expect_value(t, evdev_poll(&pad, 1).buttons, Gamepad_Buttons{.South, .East})
	evdev_apply(&pad, {ev_key(BTN_SOUTH, 2), ev_key(BTN_EAST, 0), ev_syn()})
	testing.expect_value(t, evdev_poll(&pad, 1).buttons, Gamepad_Buttons{.South})
	evdev_apply(&pad, {ev_key(BTN_SOUTH, 0), ev_syn()})
	testing.expect_value(t, evdev_poll(&pad, 1).buttons, Gamepad_Buttons{})
}

// xpad inverts ABS_Y and ABS_RY, so stick up reads the minimum.
@(test)
test_evdev_stick_up_is_plus_y_and_right_is_plus_x :: proc(t: ^testing.T) {
	pad := xpad_pad()
	evdev_apply(&pad, {ev_abs(ABS_X, 32767), ev_abs(ABS_Y, -32768), ev_abs(ABS_RX, -32768), ev_abs(ABS_RY, 32767), ev_syn()})
	raw := evdev_map(pad, 1)
	expect_near(t, raw.axes.left_stick.x, 1)
	expect_near(t, raw.axes.left_stick.y, 1)
	expect_near(t, raw.axes.right_stick.x, -1)
	expect_near(t, raw.axes.right_stick.y, -1)

	ps := playstation_pad()
	evdev_apply(&ps, {ev_abs(ABS_X, 255), ev_abs(ABS_Y, 0), ev_syn()})
	raw = evdev_map(ps, 1)
	expect_near(t, raw.axes.left_stick.x, 1)
	expect_near(t, raw.axes.left_stick.y, 1)
}

@(test)
test_evdev_trigger_ends_follow_the_abs_range :: proc(t: ^testing.T) {
	one := xpad_pad(trigger_max = 1023)
	evdev_apply(&one, {ev_abs(ABS_Z, 1023), ev_abs(ABS_RZ, 0), ev_syn()})
	raw := evdev_map(one, 1)
	expect_near(t, raw.axes.left_trigger, 1)
	expect_near(t, raw.axes.right_trigger, 0)

	x360 := xpad_pad(trigger_max = 255)
	evdev_apply(&x360, {ev_abs(ABS_RZ, 255), ev_syn()})
	expect_near(t, evdev_map(x360, 1).axes.right_trigger, 1)
}

@(test)
test_evdev_pad_at_rest_reads_nothing :: proc(t: ^testing.T) {
	for pad in ([]Evdev_Gamepad{xpad_pad(), playstation_pad()}) {
		raw := evdev_map(pad, 7)
		testing.expect_value(t, raw.id, 7)
		testing.expect_value(t, raw.buttons, Gamepad_Buttons{})
		for v in ([]f32{raw.axes.left_stick.x, raw.axes.left_stick.y, raw.axes.right_stick.x, raw.axes.right_stick.y, raw.axes.left_trigger, raw.axes.right_trigger}) {
			testing.expectf(t, abs(v) < 0.01, "an axis at rest read %v", v)
		}
	}
}

// A pad with no ABS axis, such as one with digital triggers only.
@(test)
test_evdev_missing_axis_reads_zero :: proc(t: ^testing.T) {
	pad: Evdev_Gamepad
	evdev_apply(&pad, {ev_abs(ABS_Z, 1), ev_abs(ABS_X, 1), ev_syn()})
	raw := evdev_map(pad, 1)
	testing.expect_value(t, raw.axes.left_trigger, 0)
	testing.expect_value(t, raw.axes.left_stick, [2]f32{})
}

@(test)
test_evdev_drop_skips_to_the_next_report_and_asks_for_a_resync :: proc(t: ^testing.T) {
	pad := xpad_pad()
	evdev_apply(&pad, {ev_key(BTN_SOUTH), ev_syn(SYN_DROPPED), ev_key(BTN_EAST)})
	testing.expect_value(t, evdev_map(pad, 1).buttons, Gamepad_Buttons{.South})
	testing.expect(t, !pad.resync)

	evdev_apply(&pad, {ev_key(BTN_SOUTH, 0), ev_syn(), ev_key(BTN_START), ev_syn()})
	testing.expect_value(t, evdev_map(pad, 1).buttons, Gamepad_Buttons{.South, .Start})
	testing.expect(t, pad.resync)
}

@(test)
test_evdev_key_bits_give_the_buttons_down :: proc(t: ^testing.T) {
	bits: [EVDEV_KEY_BYTES]u8
	bits[BTN_SOUTH / 8] |= 1 << (BTN_SOUTH % 8)
	bits[BTN_NORTH / 8] |= 1 << (BTN_NORTH % 8)
	bits[BTN_TRIGGER_HAPPY3 / 8] |= 1 << (BTN_TRIGGER_HAPPY3 % 8)
	testing.expect(t, evdev_has_key(bits[:], BTN_GAMEPAD))
	testing.expect(t, !evdev_has_key(bits[:], BTN_EAST))

	pad := xpad_pad()
	pad.buttons = {.Start}
	evdev_set_keys(&pad, bits[:])
	testing.expect_value(t, evdev_map(pad, 1).buttons, Gamepad_Buttons{.South, .West, .Dpad_Up})

	other := playstation_pad()
	evdev_set_keys(&other, bits[:])
	testing.expect_value(t, evdev_map(other, 1).buttons, Gamepad_Buttons{.South, .North})
}

// A button down when the pad connects is held, not pressed.
@(test)
test_evdev_pad_through_the_latch :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	pad := xpad_pad()
	evdev_apply(&pad, {ev_key(BTN_SOUTH), ev_abs(ABS_Y, -32768), ev_syn()})
	gamepad_latch_poll(&latch, {evdev_poll(&pad, 3)})
	pads := gamepad_latch_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	expect_buttons(t, pads[0].held, {.South})
	expect_buttons(t, pads[0].pressed, {})
	expect_near(t, pads[0].axes.left_stick.y, 1)

	evdev_apply(&pad, {ev_key(BTN_NORTH), ev_syn()})
	gamepad_latch_poll(&latch, {evdev_poll(&pad, 3)})
	pads = gamepad_latch_take(&latch, &buf)
	expect_buttons(t, pads[0].pressed, {.West})
}

// A tap shorter than one frame goes down and up between two polls. The
// poll still reports it, so the step gets a press.
@(test)
test_evdev_poll_keeps_a_tap_between_two_polls :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buf: Gamepad_Buffers
	pad := xpad_pad()
	gamepad_latch_poll(&latch, {evdev_poll(&pad, 3)})

	evdev_apply(&pad, {ev_key(BTN_SOUTH), ev_syn(), ev_key(BTN_SOUTH, 0), ev_syn()})
	evdev_apply(&pad, {ev_abs(ABS_HAT0Y, -1), ev_syn(), ev_abs(ABS_HAT0Y, 0), ev_syn()})
	testing.expect_value(t, evdev_map(pad, 3).buttons, Gamepad_Buttons{.South, .Dpad_Up})
	gamepad_latch_poll(&latch, {evdev_poll(&pad, 3)})
	pads := gamepad_latch_take(&latch, &buf)
	testing.expect_value(t, len(pads), 1)
	expect_buttons(t, pads[0].pressed, {.South, .Dpad_Up})

	testing.expect_value(t, evdev_poll(&pad, 3).buttons, Gamepad_Buttons{})
}
