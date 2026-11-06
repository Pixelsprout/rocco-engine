#+test
package engine

import "core:mem"
import "core:strings"
import "core:testing"

Capture_Count_Case :: struct { id: u64, kind: Capture_Draw_Kind }

@(test)
test_capture_requires_explicit_bounded_real_clock_options :: proc(t: ^testing.T) {
	testing.expect_value(t, capture_problem("", 0, .Headless, true, true, false), "")
	testing.expect(t, capture_problem("", 10, .Real_Clock, false, true, true) != "")
	testing.expect(t, capture_problem("relative.csv", 10, .Real_Clock, false, false, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 0, .Real_Clock, false, false, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 30_001, .Real_Clock, false, false, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 10, .Lockstep, false, false, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 10, .Real_Clock, true, false, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 10, .Real_Clock, false, true, false) != "")
	testing.expect(t, capture_problem("/missing/capture.csv", 10, .Real_Clock, false, false, true) != "")
	path := "/missing/rocco-debug-camera-capture.csv"
	when ODIN_OS == .Windows { path = "C:\\RoccoDebugCaptureMissing\\capture.csv" }
	testing.expect_value(t, capture_problem(path, 10, .Real_Clock, false, true, true), "")
}

@(test)
test_capture_without_a_path_allocates_nothing :: proc(t: ^testing.T) {
	c: Capture_Sink
	capture_sink_init(&c, "", 0, mem.panic_allocator())
	defer capture_sink_destroy(&c)
	testing.expect(t, !c.on)
	testing.expect_value(t, len(c.rows), 0)
	testing.expect_value(t, len(c.commands), 0)
}

@(test)
test_capture_copies_commands_before_builder_reuse_and_bounds_storage :: proc(t: ^testing.T) {
	c: Capture_Sink
	capture_sink_init(&c, "unused", 1, context.allocator)
	defer capture_sink_destroy(&c)
	capture_frame_begin(&c, 1, 7, 0.01, {size = {1920, 1080}, dpi = 1})
	strings.write_string(&c.builder, `{"Tell":{"port":"example","msg":"first"}}`)
	capture_step_end(&c, 8)
	strings.write_string(&c.builder, "second")
	capture_step_end(&c, 9)
	testing.expect_value(t, c.command_count, 2)
	testing.expect_value(t, c.commands[0].step, 8)
	testing.expect_value(t, string(c.commands[0].bytes[:c.commands[0].length]), `{"Tell":{"port":"example","msg":"first"}}`)
	for _ in 0 ..< CAPTURE_COMMANDS {
		strings.write_byte(&c.builder, 'x')
		capture_step_end(&c, 10)
	}
	testing.expect_value(t, c.command_count, CAPTURE_COMMANDS)
	testing.expect_value(t, c.failed, "command record overflow")
}

@(test)
test_capture_builder_detects_failed_growth_without_allocating :: proc(t: ^testing.T) {
	c: Capture_Sink
	capture_sink_init(&c, "unused", 1, context.allocator)
	defer capture_sink_destroy(&c)
	for _ in 0 ..< CAPTURE_COMMAND_BYTES+1 { strings.write_byte(&c.builder, 'x') }
	testing.expect_value(t, strings.builder_cap(c.builder), CAPTURE_COMMAND_BYTES)
	testing.expect_value(t, c.failed, "command buffer overflow")
}

@(test)
test_capture_records_zero_multiple_steps_and_skips_after_the_frame_limit :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init(&s, exit_after_frames = 3)
	defer fake_host_destroy(&s)
	capture_sink_init(&s.capture, "unused", 3, context.allocator)
	frame_run(&s, fake_platform(3*s.clock.fixed_dt))
	frame_run(&s, fake_platform(s.clock.fixed_dt/2))
	frame_run(&s, fake_platform(1.0))
	frame_run(&s, fake_platform(1.0))
	rows := s.capture.rows[:]
	testing.expect_value(t, len(rows), 3)
	testing.expect_value(t, rows[0].frame, 1)
	testing.expect_value(t, rows[0].before, 0)
	testing.expect_value(t, rows[0].after, 3)
	testing.expect_value(t, rows[0].prev, 2)
	testing.expect_value(t, rows[1].steps, 0)
	testing.expect_value(t, rows[1].after, 3)
	testing.expect_value(t, rows[1].prev, 2)
	testing.expect_value(t, rows[2].delta, 1.0)
	testing.expect(t, rows[2].steps > 1)
	testing.expect(t, rows[2].commit_end >= rows[2].commit_start)
}

@(test)
test_capture_frame_overflow_preserves_existing_rows :: proc(t: ^testing.T) {
	c: Capture_Sink
	capture_sink_init(&c, "unused", 1, context.allocator)
	defer capture_sink_destroy(&c)
	capture_frame_begin(&c, 1, 0, 0.01, {})
	capture_frame_end(&c, 1, 1, 0, {}, true)
	capture_frame_begin(&c, 2, 1, 0.01, {})
	capture_frame_end(&c, 2, 1, 0, {}, true)
	testing.expect_value(t, len(c.rows), 1)
	testing.expect_value(t, c.rows[0].frame, 1)
	testing.expect_value(t, c.failed, "frame overflow")
}

@(test)
test_capture_counts_source_field_and_supplement_ranges_separately :: proc(t: ^testing.T) {
	cases := []Capture_Count_Case{
		{1, .Other}, {99, .Other}, {100, .Source}, {11_435, .Source}, {11_436, .Other},
		{99_999, .Other}, {100_000, .Field}, {121_999, .Field}, {122_000, .Other},
		{199_999, .Other}, {200_000, .Supplement}, {200_122, .Supplement},
		{200_159, .Supplement}, {200_160, .Other},
	}
	contents: Capture_Contents
	for item in cases {
		testing.expect_value(t, capture_draw_kind(item.id), item.kind)
		capture_count_draw(&contents, item.id)
	}
	testing.expect_value(t, contents.source_draws, 2)
	testing.expect_value(t, contents.field_draws, 2)
	testing.expect_value(t, contents.supplement_draws, 3)
	testing.expect_value(t, contents.other_draws, 7)
}
