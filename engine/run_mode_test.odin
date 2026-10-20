#+test
package engine

import "core:testing"

@(test)
test_run_switch_unset_or_zero_is_off :: proc(t: ^testing.T) {
	for value in ([]string{"", "0"}) {
		on, ok := run_switch_parse(value)
		testing.expectf(t, ok, "expected %q to parse", value)
		testing.expectf(t, !on, "expected %q to be off", value)
	}
}

@(test)
test_run_switch_one_is_on :: proc(t: ^testing.T) {
	on, ok := run_switch_parse("1")
	testing.expect(t, ok)
	testing.expect(t, on)
}

@(test)
test_run_switch_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"2", "-1", "true", "yes", "on", " 1", "1 ", "01"}) {
		_, ok := run_switch_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}

@(test)
test_run_mode_defaults_to_the_real_clock :: proc(t: ^testing.T) {
	mode, ok := run_mode_make(lockstep = false, headless = false, exit_after_frames = 0)
	testing.expect(t, ok)
	testing.expect_value(t, mode, Run_Mode.Real_Clock)
}

@(test)
test_run_mode_lockstep_runs_with_or_without_a_frame_count :: proc(t: ^testing.T) {
	for frames in ([]int{0, 10}) {
		mode, ok := run_mode_make(lockstep = true, headless = false, exit_after_frames = frames)
		testing.expect(t, ok)
		testing.expect_value(t, mode, Run_Mode.Lockstep)
	}
}

@(test)
test_run_mode_headless_wins_over_lockstep :: proc(t: ^testing.T) {
	for lockstep in ([]bool{false, true}) {
		mode, ok := run_mode_make(lockstep = lockstep, headless = true, exit_after_frames = 10)
		testing.expect(t, ok)
		testing.expect_value(t, mode, Run_Mode.Headless)
	}
}

@(test)
test_run_mode_rejects_headless_without_a_frame_count :: proc(t: ^testing.T) {
	_, ok := run_mode_make(lockstep = false, headless = true, exit_after_frames = 0)
	testing.expect(t, !ok)
}
