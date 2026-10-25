#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:encoding/json"
import "core:net"
import "core:slice"
import "core:testing"

KEY_A :: u16(sapp.Keycode.A)
KEY_SPACE :: u16(sapp.Keycode.SPACE)
KEY_W :: u16(sapp.Keycode.W)

// A Lockstep run with the Bridge on and one Driver dialled in.
Step_Run :: struct {
	s:      State,
	driver: net.TCP_Socket,
}

@(private = "file")
step_run_open :: proc(t: ^testing.T, r: ^Step_Run) {
	fake_frame_state_init(&r.s, mode = .Lockstep)
	err := bridge_open(&r.s.bridge, 0, context.allocator)
	testing.expect_value(t, err, nil)
	r.driver = driver_dial(t, bridge_transport_port(&r.s.bridge.transport))
}

@(private = "file")
step_run_close :: proc(r: ^Step_Run) {
	net.close(r.driver)
	bridge_close(&r.s.bridge)
	fake_frame_state_destroy(&r.s)
}

// Sends one request and answers it, as frame_cb's poll does.
@(private = "file")
step_run_send :: proc(t: ^testing.T, r: ^Step_Run, line: string) {
	driver_send(t, r.driver, line)
	driver_send(t, r.driver, "\n")
	bridge_poll(&r.s, wait = true)
}

@(private = "file")
step_run_frame :: proc(r: ^Step_Run) {
	frame_run(&r.s, fake_platform(r.s.clock.fixed_dt))
}

// Runs Frames until the held reply is sent.
@(private = "file")
step_run_until_reply :: proc(r: ^Step_Run) {
	for r.s.bridge.transport.holding {
		step_run_frame(r)
	}
}

@(private = "file")
step_run_request :: proc(t: ^testing.T, r: ^Step_Run, line: string) -> json.Object {
	step_run_send(t, r, line)
	step_run_until_reply(r)
	return driver_read_reply(t, r.driver)
}

@(private = "file")
expect_keys :: proc(t: ^testing.T, got: []u16, want: []u16, loc := #caller_location) {
	testing.expectf(t, slice.equal(got, want), "got keys %v, want %v", got, want, loc = loc)
}

@(test)
test_bridge_step_holds_keys_for_every_step_and_taps_and_moves_the_mouse_in_the_first :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":2,"held":["W","A"],"tap":["Space"],"mouse":[3,-2.5]}`)
	step_run_frame(&r)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A, KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_SPACE, KEY_A, KEY_W})
	testing.expect_value(t, g_fake.mouse, [2]f32{3, -2.5})
	testing.expect(t, r.s.bridge.transport.holding)

	step_run_frame(&r)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A, KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	testing.expect_value(t, g_fake.mouse, [2]f32{})
	testing.expect(t, !r.s.bridge.transport.holding)

	reply := driver_read_reply(t, r.driver)
	testing.expect_value(t, reply["ok"].(json.Boolean), true)
	testing.expect_value(t, reply["steps"].(json.Integer), 2)
	testing.expect_value(t, g_fake.steps, 2)
}

// A key held in the request before is not Pressed again. A request with no
// held lets go of it, so the next one presses it again.
@(test)
test_bridge_step_derives_pressed_from_the_held_of_the_step_before :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})
	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})

	testing.expect_value(t, g_fake.steps, 4)
}

@(test)
test_bridge_step_with_an_unknown_key_fails_before_any_step :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":3,"held":["W","Jump"]}`)
	reply := driver_read_reply(t, r.driver)
	step_run_frame(&r)

	testing.expect_value(t, reply["ok"].(json.Boolean), false)
	testing.expect_value(t, reply["error"].(json.String), `unknown Key "Jump" in "held"`)
	testing.expect_value(t, g_fake.steps, 0)
	testing.expect_value(t, r.s.bridge.owed_steps, 0)
	testing.expect(t, !r.s.bridge.transport.holding)
}

// The Commands of every step join in order, and alloc holds the last step's
// alloc line fields.
@(test)
test_bridge_step_replies_the_commands_of_every_step_and_the_last_alloc_fields :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":3}`)
	g_fake.next_commands = {fake_unload("first"), fake_unload("second")}
	step_run_frame(&r)
	step_run_frame(&r)
	g_fake.next_commands = {fake_unload("third")}
	step_run_frame(&r)
	reply := driver_read_reply(t, r.driver)

	commands := reply["commands"].(json.Array)
	testing.expect_value(t, len(commands), 3)
	for want, i in ([]string{"first", "second", "third"}) {
		testing.expect_value(t, commands[i].(json.Object)["Unload"].(json.String), want)
	}
	alloc := reply["alloc"].(json.Object)
	testing.expect_value(t, alloc["step"].(json.Integer), 3)
	for field in ([]string{"allocs", "deallocs", "reallocs", "live", "step_us", "view_us"}) {
		testing.expectf(t, field in alloc, "alloc has no %q", field)
	}
}

@(test)
test_bridge_step_replies_a_play_that_the_game_returns :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":1}`)
	g_fake.next_commands = {fake_play(5, 0.5, 1, {tag = .At, payload = {at = {pos = {1, 2, 3}, range = 8}}})}
	step_run_until_reply(&r)
	reply := driver_read_reply(t, r.driver)

	commands := reply["commands"].(json.Array)
	testing.expect_value(t, len(commands), 1)
	play := commands[0].(json.Object)["Play"].(json.Object)
	testing.expect_value(t, play["sound"].(json.Integer), 5)
	testing.expect_value(t, play["gain"].(json.Float), 0.5)
	at := play["at"].(json.Object)["At"].(json.Object)
	testing.expect_value(t, at["range"].(json.Integer), 8)
	testing.expect_value(t, at["pos"].(json.Object)["z"].(json.Integer), 3)
}

// The reply goes out in the Frame of the Quit, before the window closes.
@(test)
test_bridge_step_that_the_game_quits_replies_and_ends_the_run :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":3}`)
	g_fake.commands_out = 1
	step_run_frame(&r)
	g_fake.commands_out = 0
	reply := driver_read_reply(t, r.driver)
	step_run_frame(&r)

	testing.expect_value(t, reply["steps"].(json.Integer), 1)
	testing.expect_value(t, reply["commands"].(json.Array)[0].(json.String), "Quit")
	testing.expect(t, r.s.bridge.quit)
	testing.expect_value(t, g_fake.steps, 1)
}

@(test)
test_bridge_step_that_the_frame_limit_cuts_short_replies_with_the_steps_so_far :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)
	r.s.exit_after_frames = 2

	step_run_send(t, &r, `{"op":"step","n":5}`)
	step_run_frame(&r)
	step_run_frame(&r)
	if r.s.bridge.transport.holding {
		testing.fail_now(t, "the step reply is still held")
	}
	reply := driver_read_reply(t, r.driver)

	testing.expect_value(t, reply["ok"].(json.Boolean), true)
	testing.expect_value(t, reply["steps"].(json.Integer), 2)
	testing.expect(t, r.s.bridge.quit)
	testing.expect_value(t, g_fake_platform.quits, 1)
}

// The latch still takes the events, because the debug camera reads it.
@(test)
test_bridge_step_ignores_the_real_keyboard_and_mouse :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .W)
	mouse_move(&r.s.input, 4, 5)
	step_run_request(t, &r, `{"op":"step"}`)

	testing.expect_value(t, g_fake.held_len, 0)
	testing.expect_value(t, g_fake.pressed_len, 0)
	testing.expect_value(t, g_fake.mouse, [2]f32{})
	testing.expect(t, r.s.input.held[.W])
}

@(private = "file")
expect_pad_buttons :: proc(t: ^testing.T, pad: ^Fake_Gamepad, held: []Gamepad_Button, pressed: []Gamepad_Button, loc := #caller_location) {
	got_held, got_pressed := pad.held[:pad.held_len], pad.pressed[:pad.pressed_len]
	testing.expectf(t, slice.equal(got_held, button_codes(held)), "got held %v, want %v", got_held, held, loc = loc)
	testing.expectf(t, slice.equal(got_pressed, button_codes(pressed)), "got pressed %v, want %v", got_pressed, pressed, loc = loc)
}

@(private = "file")
button_codes :: proc(buttons: []Gamepad_Button) -> []u8 {
	out := make([]u8, len(buttons), context.temp_allocator)
	for b, i in buttons {
		out[i] = u8(b)
	}
	return out
}

// The pad buttons follow the Input rules of the keys. The axes hold for every
// step, as the request gives them.
@(test)
test_bridge_step_gives_the_pads_of_the_request :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_send(t, &r, `{"op":"step","n":2,"gamepads":[{"slot":2,"held":["South"],"tap":["Start"],"left_stick":[0.5,-0.25],"right_trigger":1},{"held":["DpadUp"]}]}`)
	step_run_frame(&r)
	testing.expect_value(t, g_fake.gamepads_len, 2)
	first, third := g_fake.gamepads[0], g_fake.gamepads[1]
	testing.expect_value(t, first.slot, 0)
	expect_pad_buttons(t, &first, {.Dpad_Up}, {.Dpad_Up})
	testing.expect_value(t, third.slot, 2)
	expect_pad_buttons(t, &third, {.South}, {.South, .Start})
	testing.expect_value(t, third.axes.left_stick, [2]f32{0.5, -0.25})
	testing.expect_value(t, third.axes.right_stick, [2]f32{})
	testing.expect_value(t, third.axes.left_trigger, 0)
	testing.expect_value(t, third.axes.right_trigger, 1)

	step_run_frame(&r)
	third = g_fake.gamepads[1]
	expect_pad_buttons(t, &third, {.South}, {})
	testing.expect_value(t, third.axes.left_stick, [2]f32{0.5, -0.25})
	_ = driver_read_reply(t, r.driver)
}

// A request with no gamepads has no pad connected, so the next hold presses
// the button again.
@(test)
test_bridge_step_with_no_gamepads_has_no_pad :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"step","gamepads":[{"held":["East"]}]}`)
	step_run_request(t, &r, `{"op":"step","gamepads":[{"held":["East"]}]}`)
	expect_pad_buttons(t, &g_fake.gamepads[0], {.East}, {})
	step_run_request(t, &r, `{"op":"step"}`)
	testing.expect_value(t, g_fake.gamepads_len, 0)
	step_run_request(t, &r, `{"op":"step","gamepads":[{"held":["East"]}]}`)
	expect_pad_buttons(t, &g_fake.gamepads[0], {.East}, {.East})
}

@(test)
test_bridge_step_ignores_the_real_pads :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	gamepad_latch_poll(&r.s.input.gamepads, {{id = 1, buttons = {.South}}})
	step_run_request(t, &r, `{"op":"step"}`)

	testing.expect_value(t, g_fake.gamepads_len, 0)
}

@(test)
test_bridge_step_with_a_bad_gamepad_fails_before_any_step :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	cases := []struct {
		request, error: string,
	} {
		{`{"op":"step","gamepads":[{"held":["South","Jump"]}]}`, `unknown Button "Jump" in "held"`},
		{`{"op":"step","gamepads":[{"tap":["A"]}]}`, `unknown Button "A" in "tap"`},
		{`{"op":"step","gamepads":[{"slot":4}]}`, `"slot" must be a whole number from 0 to 3`},
		{`{"op":"step","gamepads":[{"slot":1},{"slot":1}]}`, `two gamepads have slot 1`},
		{`{"op":"step","gamepads":[{"left_stick":[1,1]}]}`, `"left_stick" must be [x, y] inside the unit disc`},
		{`{"op":"step","gamepads":[{"right_trigger":1.5}]}`, `"right_trigger" must be a number from 0 to 1`},
		{`{"op":"step","gamepads":{"slot":0}}`, `"gamepads" must be a list of objects`},
	}
	for c in cases {
		step_run_send(t, &r, c.request)
		reply := driver_read_reply(t, r.driver)
		step_run_frame(&r)
		testing.expect_value(t, reply["ok"].(json.Boolean), false)
		testing.expect_value(t, reply["error"].(json.String), c.error)
	}
	testing.expect_value(t, g_fake.steps, 0)
	testing.expect_value(t, r.s.bridge.owed_steps, 0)
}
