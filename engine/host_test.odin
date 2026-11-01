#+test
package engine

import "core:mem"
import "core:testing"

@(test)
test_host_build_with_a_bad_launch_names_the_field_and_keeps_nothing :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.step_hz = 0
	g_fake = {launch_in = launch}
	s: State
	err := memory_init(&s.mem)
	testing.expect_value(t, err, nil)
	defer memory_shutdown(&s.mem)
	// The test runner only logs a leak, so count what the build keeps here.
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)

	field, rule, ok := build_tracked(&s, &track)

	testing.expect(t, !ok)
	testing.expect_value(t, field, "step_hz")
	testing.expect_value(t, rule, LAUNCH_RULE_ZERO)
	testing.expect_value(t, g_fake.inits, 0)
	testing.expect_value(t, len(track.allocation_map), 0)
}

build_tracked :: proc(s: ^State, track: ^mem.Tracking_Allocator) -> (field, rule: string, ok: bool) {
	context.allocator = mem.tracking_allocator(track)
	return host_build(s, {assets_dir = NO_ASSETS_DIR}, FAKE_GAME, fake_run_command)
}
