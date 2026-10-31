#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:net"
import "core:testing"

@(test)
test_bridge_devices_are_on_only_for_the_driver_that_said_hello :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	testing.expect(t, bridge_devices_on(&r.s.bridge))
	step_run_request(t, &r, `{"op":"hello"}`)
	testing.expect(t, !bridge_devices_on(&r.s.bridge))
	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	testing.expect(t, bridge_devices_on(&r.s.bridge))
}

@(test)
test_bridge_devices_end_when_the_driver_disconnects :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	net.close(r.driver)
	r.driver = driver_dial(t, bridge_transport_port(&r.s.bridge.transport))
	step_run_request(t, &r, `{"op":"scene"}`)

	testing.expect(t, !bridge_devices_on(&r.s.bridge))
	testing.expect_value(t, r.s.bridge.transport.drivers, 2)
}

@(private = "file")
devices_run_open :: proc(t: ^testing.T, r: ^Step_Run) {
	step_run_open(t, r)
	step_run_request(t, r, `{"op":"hello","devices":true}`)
}

@(test)
test_bridge_devices_held_keys_are_the_union_of_real_and_request :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step","held":["A"]}`)

	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A, KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_A, KEY_W})
}

@(test)
test_bridge_devices_a_key_held_really_and_by_the_request_is_pressed_once :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})

	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})

	key_up(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})

	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
}

@(test)
test_bridge_devices_pressed_follows_the_union_across_steps :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"step","held":["W"]}`)
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})

	// W was held in the step before, so the real press is not new.
	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})

	key_up(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})

	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_W})
}

@(test)
test_bridge_devices_a_real_tap_while_paused_reaches_the_next_step :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .SPACE)
	key_up(&r.s.input, .SPACE)
	mouse_move(&r.s.input, 4, 5)
	for _ in 0 ..< 3 {
		step_run_frame(&r)
	}
	testing.expect_value(t, g_fake.steps, 0)

	step_run_request(t, &r, `{"op":"step","mouse":[1,-2]}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {KEY_SPACE})
	testing.expect_value(t, g_fake.mouse, [2]f32{5, 3})

	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	testing.expect_value(t, g_fake.mouse, [2]f32{0, 0})
}

@(test)
test_bridge_devices_a_request_pad_replaces_the_real_pad_in_its_slot :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	gamepad_latch_poll(&r.s.input.gamepads, {{id = 1, buttons = {.South}}, {id = 2, buttons = {.East}}})
	step_run_request(t, &r, `{"op":"step","gamepads":[{"slot":0,"held":["North"]}]}`)
	if testing.expect_value(t, g_fake.gamepads_len, 2) {
		expect_pad_buttons(t, &g_fake.gamepads[0], {.North}, {.North})
		testing.expect_value(t, g_fake.gamepads[1].slot, 1)
		expect_pad_buttons(t, &g_fake.gamepads[1], {.East}, {})
	}

	step_run_request(t, &r, `{"op":"step"}`)
	if testing.expect_value(t, g_fake.gamepads_len, 2) {
		expect_pad_buttons(t, &g_fake.gamepads[0], {.South}, {})
		expect_pad_buttons(t, &g_fake.gamepads[1], {.East}, {})
	}
}

@(test)
test_bridge_devices_a_driver_that_reconnects_without_devices_gets_no_real_input :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})

	net.close(r.driver)
	r.driver = driver_dial(t, bridge_transport_port(&r.s.bridge.transport))
	step_run_request(t, &r, `{"op":"step"}`)
	expect_keys(t, g_fake.held[:g_fake.held_len], {})
	expect_keys(t, g_fake.pressed[:g_fake.pressed_len], {})
	testing.expect(t, r.s.input.held[.W])
}

@(test)
test_bridge_devices_an_unfocused_window_lets_go_of_the_real_keys_and_pads :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	key_down(&r.s.input, .W)
	gamepad_latch_poll(&r.s.input.gamepads, {{id = 1, buttons = {.South}}})
	unfocused := sapp.Event{type = .UNFOCUSED}
	input_on_event(&r.s.input, &unfocused)
	step_run_request(t, &r, `{"op":"step","held":["A"]}`)

	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_A})
	if testing.expect_value(t, g_fake.gamepads_len, 1) {
		expect_pad_buttons(t, &g_fake.gamepads[0], {}, {})
	}
}

@(test)
test_bridge_devices_the_debug_camera_and_the_game_both_get_the_real_keys :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)
	r.s.use_debug_camera = true
	camera_init(&r.s.debug_camera)
	eye := r.s.debug_camera.eye

	key_down(&r.s.input, .W)
	step_run_request(t, &r, `{"op":"step"}`)

	expect_keys(t, g_fake.held[:g_fake.held_len], {KEY_W})
	testing.expect(t, r.s.debug_camera.eye != eye)
}
