#+test
package engine

import "core:testing"

@(test)
test_exit_after_frames_unset_runs_forever :: proc(t: ^testing.T) {
	limit, ok := exit_after_frames_parse("")
	testing.expect(t, ok)
	testing.expect_value(t, limit, 0)
}

@(test)
test_exit_after_frames_reads_a_count :: proc(t: ^testing.T) {
	limit, ok := exit_after_frames_parse("120")
	testing.expect(t, ok)
	testing.expect_value(t, limit, 120)
}

@(test)
test_exit_after_frames_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"0", "-5", "abc", "12x", " 12", "1.5"}) {
		_, ok := exit_after_frames_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}

@(test)
test_exit_after_frames_reached_at_the_limit :: proc(t: ^testing.T) {
	testing.expect(t, !exit_after_frames_reached(0, 5))
	testing.expect(t, !exit_after_frames_reached(2, 1))
	testing.expect(t, exit_after_frames_reached(2, 2))
	testing.expect(t, exit_after_frames_reached(2, 3))
}
