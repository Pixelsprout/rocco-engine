#+test
package engine

import sapp "../sokol-odin/sokol/app"
import "core:encoding/json"
import "core:net"
import "core:slice"
import "core:strings"
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
devices_run_open :: proc(t: ^testing.T, r: ^Step_Run, ui: []Element = nil) {
	step_run_open(t, r, ui = ui)
	step_run_request(t, r, `{"op":"hello","devices":true}`)
}

// A tagged Panel at the top left, 100 by 100. g_fake keeps the roots past the
// call, so they live in the temp allocator.
@(private = "file")
devices_run_open_pointing :: proc(t: ^testing.T, r: ^Step_Run) {
	devices_run_open(t, r, slice.clone([]Element{ui_panel_of(ui_tagged(7, 100, 100))}, context.temp_allocator))
}

// The fake platform window is 960 by 540 at dpi 1.
@(private = "file")
real_pointer :: proc(r: ^Step_Run, type: sapp.Event_Type, pos: [2]f32 = {}, button := sapp.Mousebutton.LEFT, scroll: [2]f32 = {}) {
	e := sapp.Event {
		type         = type,
		mouse_x      = pos.x,
		mouse_y      = pos.y,
		mouse_button = button,
		scroll_x     = scroll.x,
		scroll_y     = scroll.y,
	}
	input_on_event(&r.s.input, &e)
}

@(private = "file")
expect_pointer_buttons :: proc(t: ^testing.T, held, pressed, released: []u8, loc := #caller_location) {
	p := &g_fake.pointer
	expect_mouse_buttons(t, p.held[:p.held_len], held, loc)
	expect_mouse_buttons(t, p.pressed[:p.pressed_len], pressed, loc)
	expect_mouse_buttons(t, p.released[:p.released_len], released, loc)
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

@(test)
test_bridge_devices_the_real_pointer_passes_through_without_a_request_pointer :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_MOVE, {200, 100})
	step_run_request(t, &r, `{"op":"step"}`)

	testing.expect_value(t, g_fake.pointer.pos, [2]f32{200, 100})
	testing.expect(t, g_fake.pointer.inside)
}

@(test)
test_bridge_devices_the_real_pointer_is_in_logical_pixels :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)
	platform := fake_platform(r.s.clock.fixed_dt)
	platform.window = {size = {1920, 1080}, dpi = 2}

	real_pointer(&r, .MOUSE_MOVE, {400, 200})
	step_run_send(t, &r, `{"op":"step"}`)
	frame_run(&r.s, platform)
	_ = driver_read_reply(t, r.driver)

	testing.expect_value(t, g_fake.pointer.pos, [2]f32{200, 100})
	testing.expect(t, g_fake.pointer.inside)
}

@(test)
test_bridge_devices_a_request_pointer_replaces_the_real_pointer :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_MOVE, {200, 100})
	real_pointer(&r, .MOUSE_SCROLL, scroll = {0, 1})
	step_run_request(t, &r, `{"op":"step","pointer":{"x":40,"y":30}}`)
	testing.expect_value(t, g_fake.pointer.pos, [2]f32{40, 30})
	testing.expect_value(t, g_fake.pointer.wheel, [2]f32{0, 0})

	step_run_request(t, &r, `{"op":"step"}`)
	testing.expect_value(t, g_fake.pointer.pos, [2]f32{200, 100})
	testing.expect_value(t, g_fake.pointer.wheel, [2]f32{0, 0})
}

@(test)
test_bridge_devices_the_real_wheel_passes_through_once :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_SCROLL, scroll = {0, 2})
	step_run_send(t, &r, `{"op":"step","n":2}`)
	step_run_frame(&r)
	testing.expect_value(t, g_fake.pointer.wheel, [2]f32{0, 2})
	step_run_frame(&r)
	testing.expect_value(t, g_fake.pointer.wheel, [2]f32{0, 0})
	_ = driver_read_reply(t, r.driver)
}

@(test)
test_bridge_devices_pointer_buttons_merge_like_keys :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_DOWN)
	step_run_request(t, &r, `{"op":"step","pointer":{"x":1,"y":1,"held":["Left"]}}`)
	expect_pointer_buttons(t, held = {0}, pressed = {0}, released = {})

	real_pointer(&r, .MOUSE_UP)
	step_run_request(t, &r, `{"op":"step","pointer":{"x":1,"y":1,"held":["Left"]}}`)
	expect_pointer_buttons(t, held = {0}, pressed = {}, released = {})

	step_run_request(t, &r, `{"op":"step","pointer":{"x":1,"y":1}}`)
	expect_pointer_buttons(t, held = {}, pressed = {}, released = {0})
}

@(test)
test_bridge_devices_a_real_click_between_steps_is_pressed_and_released :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_MOVE, {50, 50})
	real_pointer(&r, .MOUSE_DOWN)
	real_pointer(&r, .MOUSE_UP)
	step_run_request(t, &r, `{"op":"step"}`)

	expect_pointer_buttons(t, held = {}, pressed = {0}, released = {0})
}

@(test)
test_bridge_devices_the_real_pointer_reaches_the_hit_test :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open_pointing(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_MOVE, {50, 50})
	step_run_request(t, &r, `{"op":"step"}`)
	reply := step_run_request(t, &r, `{"op":"scene"}`)

	over := reply["results"].(json.Object)["ui"].(json.Object)["over"].(json.Array)
	if testing.expect_value(t, len(over), 1) {
		testing.expect_value(t, over[0].(json.Integer), 7)
	}
}

@(test)
test_bridge_devices_a_locked_real_pointer_is_not_inside :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)
	platform := fake_platform(r.s.clock.fixed_dt)
	platform.mouse_locked = true

	real_pointer(&r, .MOUSE_MOVE, {50, 50})
	real_pointer(&r, .MOUSE_DOWN)
	step_run_send(t, &r, `{"op":"step"}`)
	frame_run(&r.s, platform)
	_ = driver_read_reply(t, r.driver)

	testing.expect(t, !g_fake.pointer.inside)
	expect_pointer_buttons(t, held = {0}, pressed = {0}, released = {})
}

@(test)
test_bridge_devices_an_unfocused_window_releases_the_real_pointer_buttons :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	real_pointer(&r, .MOUSE_DOWN)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_pointer_buttons(t, held = {0}, pressed = {0}, released = {})

	real_pointer(&r, .UNFOCUSED)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_pointer_buttons(t, held = {}, pressed = {}, released = {0})
}

@(test)
test_bridge_inject_feeds_the_real_latch_as_the_window_does :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	reply := step_run_request(t, &r, `{"op":"inject","events":[{"type":"key_down","key":"W"},{"type":"mouse_move","x":884,"y":36},{"type":"mouse_down","button":"Left"}]}`)

	testing.expect_value(t, reply["ok"].(json.Boolean), true)
	testing.expect_value(t, reply["events"].(json.Integer), 3)
	testing.expect(t, r.s.input.held[.W])
	testing.expect_value(t, r.s.input.pointer.pos, [2]f32{884, 36})
	testing.expect(t, .Left in r.s.input.pointer.held)
	testing.expect_value(t, r.s.input.mouse, [2]f32{0, 0})
}

@(test)
test_bridge_inject_scales_the_position_by_the_window_dpi :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)
	platform := fake_platform(r.s.clock.fixed_dt)
	platform.window = {size = {1920, 1080}, dpi = 2}
	frame_run(&r.s, platform)

	step_run_request(t, &r, `{"op":"inject","events":[{"type":"mouse_move","x":100,"y":50}]}`)

	testing.expect_value(t, r.s.input.pointer.pos, [2]f32{200, 100})
}

@(test)
test_bridge_inject_needs_devices_on :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)
	inject := `{"op":"inject","events":[{"type":"key_down","key":"W"}]}`

	reply := step_run_request(t, &r, inject)
	testing.expect_value(t, reply["error"].(json.String), "inject needs devices on in hello")
	step_run_request(t, &r, `{"op":"hello"}`)
	reply = step_run_request(t, &r, inject)
	testing.expect_value(t, reply["error"].(json.String), "inject needs devices on in hello")
	testing.expect(t, !r.s.input.held[.W])
}

@(test)
test_bridge_inject_with_a_bad_event_feeds_none :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open(t, &r)
	defer step_run_close(&r)

	cases := []struct {
		events, error: string,
	} {
		{`7`, `"events" must be a list of objects`},
		{`[7]`, `"events" must be a list of objects`},
		{`[{"type":"key_down","key":"W"},{"type":"wave"}]`, `unknown event type "wave"`},
		{`[{"type":"key_down","key":"W"},{"key":"W"}]`, `unknown event type ""`},
		{`[{"type":"key_down","key":"W"},{"type":"key_down","key":"Nope"}]`, `unknown Key "Nope" in "key"`},
		{`[{"type":"key_down","key":"W"},{"type":"key_up","key":3}]`, `"key" must be a Key name`},
		{`[{"type":"key_down","key":"W"},{"type":"mouse_move","x":1}]`, `"x" and "y" must be numbers`},
		{`[{"type":"key_down","key":"W"},{"type":"mouse_down","button":"Back"}]`, `unknown MouseButton "Back" in "button"`},
		{`[{"type":"key_down","key":"W"},{"type":"mouse_up"}]`, `"button" must be a MouseButton name`},
	}
	for c in cases {
		line := strings.concatenate({`{"op":"inject","events":`, c.events, "}"}, context.temp_allocator)
		reply := step_run_request(t, &r, line)
		testing.expect_value(t, reply["ok"].(json.Boolean), false)
		testing.expect_value(t, reply["error"].(json.String), c.error)
		testing.expect(t, !r.s.input.held[.W])
	}
}

@(test)
test_bridge_inject_a_click_reaches_the_game_through_the_merge :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	devices_run_open_pointing(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"inject","events":[{"type":"mouse_move","x":50,"y":50}]}`)
	step_run_request(t, &r, `{"op":"step"}`)
	testing.expect(t, g_fake.pointer.inside)

	step_run_request(t, &r, `{"op":"inject","events":[{"type":"mouse_down","button":"Left"},{"type":"mouse_up","button":"Left"}]}`)
	step_run_request(t, &r, `{"op":"step"}`)
	expect_pointer_buttons(t, held = {}, pressed = {0}, released = {0})
	if testing.expect_value(t, g_fake.over_len, 1) {
		testing.expect_value(t, g_fake.over[0], 7)
	}
}
