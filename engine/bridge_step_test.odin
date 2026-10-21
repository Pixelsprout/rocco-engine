#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:bytes"
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
	dial_err: net.Network_Error
	r.driver, dial_err = net.dial_tcp(net.Endpoint{net.IP4_Loopback, bridge_transport_port(&r.s.bridge.transport)})
	testing.expect_value(t, dial_err, nil)
}

@(private = "file")
step_run_close :: proc(r: ^Step_Run) {
	net.close(r.driver)
	bridge_close(&r.s.bridge)
	fake_frame_state_destroy(&r.s)
}

// Sends one request and answers it, as frame_cb's poll does.
@(private = "file")
step_send :: proc(t: ^testing.T, r: ^Step_Run, line: string) {
	_, err := net.send_tcp(r.driver, transmute([]u8)line)
	testing.expect_value(t, err, nil)
	_, err = net.send_tcp(r.driver, {'\n'})
	testing.expect_value(t, err, nil)
	bridge_poll(&r.s, wait = true)
}

@(private = "file")
step_frame :: proc(r: ^Step_Run) {
	frame_run(&r.s, fake_platform(r.s.clock.fixed_dt))
}

// Runs Frames until the held reply is sent.
@(private = "file")
step_frames_until_reply :: proc(r: ^Step_Run) {
	for r.s.bridge.transport.holding {
		step_frame(r)
	}
}

// Reads one reply line. The Driver sends the next request only after it has
// read a reply, so a read never takes part of the next one.
@(private = "file")
step_reply :: proc(t: ^testing.T, r: ^Step_Run) -> json.Object {
	got := make([dynamic]u8, context.temp_allocator)
	buf: [512]u8
	for bytes.index_byte(got[:], '\n') < 0 {
		n, err := net.recv_tcp(r.driver, buf[:])
		if err != nil || n == 0 {
			testing.fail_now(t, "the host closed before it replied")
		}
		append(&got, ..buf[:n])
	}
	testing.expect_value(t, bytes.index_byte(got[:], '\n'), len(got) - 1)
	value, err := json.parse(got[:len(got) - 1], parse_integers = true, allocator = context.temp_allocator)
	testing.expectf(t, err == nil, "the reply %q is not JSON: %v", string(got[:]), err)
	return value.(json.Object)
}

@(private = "file")
step :: proc(t: ^testing.T, r: ^Step_Run, line: string) -> json.Object {
	step_send(t, r, line)
	step_frames_until_reply(r)
	return step_reply(t, r)
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

	step_send(t, &r, `{"op":"step","n":2,"held":["W","A"],"tap":["Space"],"mouse":[3,-2.5]}`)
	step_frame(&r)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A, KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_SPACE, KEY_A, KEY_W})
	testing.expect_value(t, g_fake.mouse, [2]f32{3, -2.5})
	testing.expect(t, r.s.bridge.transport.holding)

	step_frame(&r)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A, KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	testing.expect_value(t, g_fake.mouse, [2]f32{})
	testing.expect(t, !r.s.bridge.transport.holding)

	reply := step_reply(t, &r)
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

	step(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})
	step(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	step(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	step(t, &r, `{"op":"step","held":["W"]}`)
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

	step_send(t, &r, `{"op":"step","n":3,"held":["W","Jump"]}`)
	reply := step_reply(t, &r)
	step_frame(&r)

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

	step_send(t, &r, `{"op":"step","n":3}`)
	g_fake.next_commands = {fake_unload("first"), fake_unload("second")}
	step_frame(&r)
	step_frame(&r)
	g_fake.next_commands = {fake_unload("third")}
	step_frame(&r)
	reply := step_reply(t, &r)

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

// The reply goes out in the Frame of the Quit, before the window closes.
@(test)
test_bridge_step_that_the_game_quits_replies_and_ends_the_run :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_send(t, &r, `{"op":"step","n":3}`)
	g_fake.commands_out = 1
	step_frame(&r)
	g_fake.commands_out = 0
	reply := step_reply(t, &r)
	step_frame(&r)

	testing.expect_value(t, reply["steps"].(json.Integer), 1)
	testing.expect_value(t, reply["commands"].(json.Array)[0].(json.String), "Quit")
	testing.expect(t, r.s.bridge.quit)
	testing.expect_value(t, g_fake.steps, 1)
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
	step(t, &r, `{"op":"step"}`)

	testing.expect_value(t, g_fake.held_len, 0)
	testing.expect_value(t, g_fake.pressed_len, 0)
	testing.expect_value(t, g_fake.mouse, [2]f32{})
	testing.expect(t, r.s.input.held[.W])
}
