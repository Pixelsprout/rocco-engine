#+test
package engine

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:strings"
import "core:testing"

@(test)
test_bridge_port_unset_is_off :: proc(t: ^testing.T) {
	port, ok := bridge_port_parse("")
	testing.expect(t, ok)
	testing.expect_value(t, port, 0)
}

@(test)
test_bridge_port_takes_1_to_65535 :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for want in ([]int{1, 7878, 65535}) {
		port, ok := bridge_port_parse(fmt.tprint(want))
		testing.expectf(t, ok, "expected %v to parse", want)
		testing.expect_value(t, port, want)
	}
}

@(test)
test_bridge_port_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"0", "-1", "65536", "+80", "080", "port", " 80", "80 ", "1_000"}) {
		_, ok := bridge_port_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}

@(test)
test_run_mode_with_the_bridge_is_lockstep :: proc(t: ^testing.T) {
	mode, ok := run_mode_make(lockstep = false, headless = false, exit_after_frames = 0, bridge = true)
	testing.expect(t, ok)
	testing.expect_value(t, mode, Run_Mode.Lockstep)
}

@(test)
test_run_mode_headless_with_the_bridge_needs_no_frame_count :: proc(t: ^testing.T) {
	mode, ok := run_mode_make(lockstep = false, headless = true, exit_after_frames = 0, bridge = true)
	testing.expect(t, ok)
	testing.expect_value(t, mode, Run_Mode.Headless)
}

@(test)
test_frame_run_with_the_bridge_and_no_owed_step_runs_zero_steps :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)
	s.bridge.on = true

	for _ in 0 ..< 5 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
	}

	testing.expect_value(t, g_fake.steps, 0)
	testing.expect_value(t, s.steps, 0)
	testing.expect_value(t, s.frame_count, 5)
	testing.expect_value(t, g_fake_platform.commits, 5)
}

@(test)
test_frame_run_with_the_bridge_runs_one_step_per_frame_while_steps_are_owed :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)
	s.bridge.on = true
	s.bridge.owed_steps = 3

	frame_run(&s, fake_platform(s.clock.fixed_dt))
	testing.expect_value(t, g_fake.steps, 1)
	for _ in 0 ..< 4 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
	}

	testing.expect_value(t, g_fake.steps, 3)
	testing.expect_value(t, s.bridge.owed_steps, 0)
	testing.expect_value(t, s.frame_count, 5)
}

// The Driver's requests arrive before the run, so headless_run answers them
// and the quit ends it with no Frame.
@(test)
test_headless_run_with_the_bridge_answers_hello_and_ends_on_quit :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	s: State
	fake_frame_state_init(&s, mode = .Headless)
	defer fake_frame_state_destroy(&s)
	err := bridge_transport_open(&s.bridge.transport, 0, context.allocator)
	testing.expect_value(t, err, nil)
	s.bridge.on = true
	defer bridge_close(&s.bridge)
	driver := driver_dial(t, bridge_transport_port(&s.bridge.transport))
	defer net.close(driver)
	driver_send(t, driver, "{\"op\":\"hello\"}\n{\"op\":\"quit\"}\n")

	headless_run(&s)

	testing.expect(t, s.bridge.quit)
	testing.expect_value(t, s.frame_count, 0)
	testing.expect_value(t, g_fake.steps, 0)
	lines := strings.split_lines(driver_read_lines(t, driver, 2), context.temp_allocator)
	hello := driver_parse(t, lines[0])
	testing.expect_value(t, hello["headless"].(json.Boolean), true)
	testing.expect_value(t, lines[1], `{"ok":true}`)
}
