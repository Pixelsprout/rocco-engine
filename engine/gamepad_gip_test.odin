#+test
package engine

import "core:testing"

// The configuration descriptor of a PDP Afterglow (0e6f:0139), as IOKit gave
// it. Interface 0 has the two interrupt pipes. Interface 1 has no pipes in
// alternate setting 0 and two isochronous pipes in setting 1.
@(rodata)
GIP_TEST_PDP_CONFIG := [?]u8 {
	0x09, 0x02, 0x40, 0x00, 0x02, 0x01, 0x00, 0xa0, 0xfa,
	0x09, 0x04, 0x00, 0x00, 0x02, 0xff, 0x47, 0xd0, 0x00,
	0x07, 0x05, 0x81, 0x03, 0x40, 0x00, 0x04,
	0x07, 0x05, 0x01, 0x03, 0x40, 0x00, 0x04,
	0x09, 0x04, 0x01, 0x00, 0x00, 0xff, 0x47, 0xd0, 0x00,
	0x09, 0x04, 0x01, 0x01, 0x02, 0xff, 0x47, 0xd0, 0x00,
	0x07, 0x05, 0x02, 0x01, 0xe0, 0x00, 0x01,
	0x07, 0x05, 0x83, 0x01, 0x80, 0x00, 0x01,
}

// The reports below copy the layout that the GIP probe read from a PDP
// Afterglow (0e6f:0139): 20 00 seq 0e, then 14 bytes of input.

@(test)
test_gip_gives_each_button_its_position :: proc(t: ^testing.T) {
	cases := [Gamepad_Button][2]u8 {
		.Start          = {0x04, 0x00},
		.Back           = {0x08, 0x00},
		.South          = {0x10, 0x00},
		.East           = {0x20, 0x00},
		.West           = {0x40, 0x00},
		.North          = {0x80, 0x00},
		.Dpad_Up        = {0x00, 0x01},
		.Dpad_Down      = {0x00, 0x02},
		.Dpad_Left      = {0x00, 0x04},
		.Dpad_Right     = {0x00, 0x08},
		.Left_Shoulder  = {0x00, 0x10},
		.Right_Shoulder = {0x00, 0x20},
		.Left_Stick     = {0x00, 0x40},
		.Right_Stick    = {0x00, 0x80},
	}
	for bytes, button in cases {
		pad: Gip_Gamepad
		report := gip_test_report(buttons = bytes)
		gip_apply(&pad, report[:])
		raw := gip_poll(&pad, id = 1)
		testing.expectf(t, raw.buttons == {button}, "bytes %2x gave %v, want %v", bytes, raw.buttons, button)
	}
}

// Bits 0 and 1 of byte 4 are not buttons.
@(test)
test_gip_skips_the_unused_bits :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	report := gip_test_report(buttons = {0x03, 0x00})
	gip_apply(&pad, report[:])
	testing.expect_value(t, gip_poll(&pad, id = 1).buttons, Gamepad_Buttons{})
}

@(test)
test_gip_stick_up_and_right_are_plus :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	report := gip_test_report(left_stick = {0, 32767}, right_stick = {32767, 0})
	gip_apply(&pad, report[:])
	raw := gip_poll(&pad, id = 1)
	testing.expect_value(t, raw.axes.left_stick, [2]f32{0, 1})
	testing.expect_value(t, raw.axes.right_stick, [2]f32{1, 0})
}

// -32768 is one step past -32767, so it clamps to -1.
@(test)
test_gip_gives_the_ends_of_the_axes :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	low := gip_test_report(left_stick = {-32768, -32768}, right_stick = {-32768, -32768})
	gip_apply(&pad, low[:])
	raw := gip_poll(&pad, id = 1)
	testing.expect_value(t, raw.axes.left_stick, [2]f32{-1, -1})
	testing.expect_value(t, raw.axes.right_stick, [2]f32{-1, -1})
	testing.expect_value(t, raw.axes.left_trigger, 0)
	testing.expect_value(t, raw.axes.right_trigger, 0)

	high := gip_test_report(left_trigger = 1023, right_trigger = 1023, left_stick = {32767, 32767}, right_stick = {32767, 32767})
	gip_apply(&pad, high[:])
	raw = gip_poll(&pad, id = 1)
	testing.expect_value(t, raw.axes.left_stick, [2]f32{1, 1})
	testing.expect_value(t, raw.axes.right_stick, [2]f32{1, 1})
	testing.expect_value(t, raw.axes.left_trigger, 1)
	testing.expect_value(t, raw.axes.right_trigger, 1)
}

@(test)
test_gip_reads_the_triggers_little_endian :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	report := gip_test_report(left_trigger = 0x0200, right_trigger = 0x0001)
	gip_apply(&pad, report[:])
	raw := gip_poll(&pad, id = 1)
	testing.expect_value(t, raw.axes.left_trigger, f32(0x0200) / 1023)
	testing.expect_value(t, raw.axes.right_trigger, f32(1) / 1023)
}

// The probe saw the sticks of a pad at rest within about 0.09 of centre.
@(test)
test_gip_pad_at_rest_gives_no_buttons_and_small_axes :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	report := [?]u8{0x20, 0x00, 0x07, 0x0e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x01, 0x70, 0xfe, 0x00, 0xf9, 0x58, 0x02}
	gip_apply(&pad, report[:])
	raw := gip_poll(&pad, id = 5)
	testing.expect_value(t, raw.id, 5)
	testing.expect_value(t, raw.buttons, Gamepad_Buttons{})
	testing.expect(t, abs(raw.axes.left_stick.x) < 0.1 && abs(raw.axes.left_stick.y) < 0.1)
	testing.expect(t, abs(raw.axes.right_stick.x) < 0.1 && abs(raw.axes.right_stick.y) < 0.1)
	testing.expect_value(t, gamepad_stick(raw.axes.left_stick), [2]f32{})
	testing.expect_value(t, gamepad_stick(raw.axes.right_stick), [2]f32{})
}

@(test)
test_gip_ignores_the_heartbeat_the_guide_button_and_short_reports :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	report := gip_test_report(buttons = {0x10, 0x00}, left_stick = {0, 32767})
	gip_apply(&pad, report[:])
	_ = gip_poll(&pad, id = 1)
	heartbeat := [?]u8{0x03, 0x20, 0x08, 0x04, 0x80, 0x00, 0x00, 0x00}
	guide := [?]u8{0x07, 0x20, 0x09, 0x02, 0x01, 0x5b}
	short := [?]u8{0x20, 0x00, 0x0a, 0x0e, 0x00, 0x00}
	gip_apply(&pad, heartbeat[:])
	gip_apply(&pad, guide[:])
	gip_apply(&pad, short[:])
	gip_apply(&pad, {})
	raw := gip_poll(&pad, id = 1)
	testing.expect_value(t, raw.buttons, Gamepad_Buttons{.South})
	testing.expect_value(t, raw.axes.left_stick, [2]f32{0, 1})
}

// Two reports between two polls: A went down and came up again.
@(test)
test_gip_keeps_a_tap_between_two_polls :: proc(t: ^testing.T) {
	pad: Gip_Gamepad
	gip_poll(&pad, id = 1)
	down := gip_test_report(buttons = {0x10, 0x00})
	up := gip_test_report()
	gip_apply(&pad, down[:])
	gip_apply(&pad, up[:])
	testing.expect_value(t, gip_poll(&pad, id = 1).buttons, Gamepad_Buttons{.South})
	testing.expect_value(t, gip_poll(&pad, id = 1).buttons, Gamepad_Buttons{})
}

// A pad queues the reports that no client read, and gives them to the next
// client that opens it. Found with a PDP Afterglow after a run that quit on
// Start.
@(test)
test_gip_first_poll_drops_a_tap_queued_before_the_open :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buffers: Gamepad_Buffers
	pad: Gip_Gamepad
	down := gip_test_report(buttons = {0x04, 0x00})
	up := gip_test_report()
	gip_apply(&pad, down[:])
	gip_apply(&pad, up[:])
	gamepad_latch_poll(&latch, {gip_poll(&pad, id = 9)})
	pads := gamepad_latch_take(&latch, &buffers)
	testing.expect_value(t, len(pads), 1)
	if len(pads) == 1 {
		testing.expect_value(t, len(pads[0].held), 0)
		testing.expect_value(t, len(pads[0].pressed), 0)
	}
}

@(test)
test_gip_feeds_the_latch :: proc(t: ^testing.T) {
	latch: Gamepad_Latch
	buffers: Gamepad_Buffers
	pad: Gip_Gamepad
	gamepad_latch_poll(&latch, {gip_poll(&pad, id = 9)})
	report := gip_test_report(buttons = {0x04, 0x00}, right_trigger = 1023, left_stick = {0, 32767})
	gip_apply(&pad, report[:])
	gamepad_latch_poll(&latch, {gip_poll(&pad, id = 9)})
	pads := gamepad_latch_take(&latch, &buffers)
	testing.expect_value(t, len(pads), 1)
	if len(pads) != 1 {
		return
	}
	testing.expect_value(t, len(pads[0].pressed), 1)
	if len(pads[0].pressed) == 1 {
		testing.expect_value(t, Gamepad_Button(pads[0].pressed[0]), Gamepad_Button.Start)
	}
	testing.expect_value(t, pads[0].axes.right_trigger, 1)
	testing.expect_value(t, pads[0].axes.left_stick, [2]f32{0, 1})
}

// GameController ids are object addresses, which never set the top bit.
@(test)
test_gip_pad_id_sets_the_top_bit :: proc(t: ^testing.T) {
	testing.expect_value(t, gip_pad_id(0x1_0001_183d), 0x8000_0001_0001_183d)
}

@(test)
test_gip_start_packets_send_power_on_to_every_pad :: proc(t: ^testing.T) {
	packets := gip_start_packets(0x1532)
	testing.expect_value(t, len(packets), 1)
	if len(packets) == 1 {
		testing.expect(t, gip_test_packet_is(packets[0], {0x05, 0x20, 0x00, 0x01, 0x00}))
	}
}

@(test)
test_gip_start_packets_add_the_pdp_led_and_auth :: proc(t: ^testing.T) {
	packets := gip_start_packets(GIP_VENDOR_PDP)
	testing.expect_value(t, len(packets), 3)
	if len(packets) == 3 {
		testing.expect(t, gip_test_packet_is(packets[0], {0x05, 0x20, 0x00, 0x01, 0x00}))
		testing.expect(t, gip_test_packet_is(packets[1], {0x0a, 0x20, 0x00, 0x03, 0x00, 0x01, 0x14}))
		testing.expect(t, gip_test_packet_is(packets[2], {0x06, 0x20, 0x00, 0x02, 0x01, 0x00}))
	}
}

// The probe sent its start packets with sequence numbers 1, 2 and 3.
@(test)
test_gip_sequence_counts_from_one_and_skips_zero :: proc(t: ^testing.T) {
	sequence: u8
	testing.expect_value(t, gip_next_sequence(&sequence), 1)
	testing.expect_value(t, gip_next_sequence(&sequence), 2)
	sequence = 255
	testing.expect_value(t, gip_next_sequence(&sequence), 1)
}

// An official pad asks for an ack of its Guide report with option 0x30.
@(test)
test_gip_acks_a_packet_that_asks_for_one :: proc(t: ^testing.T) {
	guide := [?]u8{0x07, 0x30, 0x2a, 0x02, 0x01, 0x5b}
	ack, needed := gip_ack(guide[:])
	testing.expect(t, needed)
	testing.expect_value(t, ack, [13]u8{0x01, 0x20, 0x2a, 0x09, 0x00, 0x07, 0x20, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00})
}

@(test)
test_gip_acks_no_packet_that_does_not_ask :: proc(t: ^testing.T) {
	heartbeat := [?]u8{0x03, 0x20, 0x08, 0x04, 0x80, 0x00, 0x00, 0x00}
	_, needed := gip_ack(heartbeat[:])
	testing.expect(t, !needed)
	_, needed = gip_ack({0x07, 0x30})
	testing.expect(t, !needed)
}

@(test)
test_gip_config_finds_the_gip_interface :: proc(t: ^testing.T) {
	testing.expect(t, gip_config_has_interface(GIP_TEST_PDP_CONFIG[:]))
}

@(test)
test_gip_config_skips_other_interfaces :: proc(t: ^testing.T) {
	// A keyboard: one HID interface, class 03.
	keyboard := [?]u8 {
		0x09, 0x02, 0x22, 0x00, 0x01, 0x01, 0x00, 0xa0, 0x32,
		0x09, 0x04, 0x00, 0x00, 0x01, 0x03, 0x01, 0x01, 0x00,
		0x09, 0x21, 0x11, 0x01, 0x00, 0x01, 0x22, 0x3f, 0x00,
		0x07, 0x05, 0x81, 0x03, 0x08, 0x00, 0x0a,
	}
	testing.expect(t, !gip_config_has_interface(keyboard[:]))
}

// A zero bLength would loop forever, and a length past the end reads
// outside the descriptor.
@(test)
test_gip_config_stops_at_a_bad_length :: proc(t: ^testing.T) {
	zero := [?]u8{0x09, 0x02, 0x12, 0x00, 0x01, 0x01, 0x00, 0x80, 0xfa, 0x00, 0x04, 0x00, 0x00, 0x02, 0xff, 0x47, 0xd0, 0x00}
	testing.expect(t, !gip_config_has_interface(zero[:]))
	cut := [?]u8{0x09, 0x02, 0x12, 0x00, 0x01, 0x01, 0x00, 0x80, 0xfa, 0x09, 0x04, 0x00, 0x00, 0x02, 0xff}
	testing.expect(t, !gip_config_has_interface(cut[:]))
	testing.expect(t, !gip_config_has_interface({}))
}

gip_test_report :: proc(
	buttons := [2]u8{},
	left_trigger: u16 = 0,
	right_trigger: u16 = 0,
	left_stick := [2]i16{},
	right_stick := [2]i16{},
) -> [18]u8 {
	report := [18]u8{0x20, 0x00, 0x01, 0x0e, buttons[0], buttons[1], 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}
	gip_test_put(report[:], 6, left_trigger)
	gip_test_put(report[:], 8, right_trigger)
	gip_test_put(report[:], 10, u16(left_stick.x))
	gip_test_put(report[:], 12, u16(left_stick.y))
	gip_test_put(report[:], 14, u16(right_stick.x))
	gip_test_put(report[:], 16, u16(right_stick.y))
	return report
}

gip_test_put :: proc(report: []u8, offset: int, value: u16) {
	report[offset] = u8(value)
	report[offset + 1] = u8(value >> 8)
}

gip_test_packet_is :: proc(packet: Gip_Start_Packet, want: []u8) -> bool {
	bytes := packet.bytes
	return string(bytes[:packet.len]) == string(want)
}
