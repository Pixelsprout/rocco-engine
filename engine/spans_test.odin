#+test
package engine

import "core:testing"

@(test)
test_span_csv_has_a_header_then_one_row_per_frame :: proc(t: ^testing.T) {
	rows := []Span_Row{{frame = 1, steps = 1, us = {.Step = 12.5, .View = 3}}, {frame = 2, steps = 0, us = {}}}

	csv := span_csv(rows, context.temp_allocator)

	testing.expect_value(t, csv, "frame,steps,step_us,view_us\n1,1,12.500,3.000\n2,0,0.000,0.000\n")
}

@(test)
test_span_csv_with_no_frames_is_only_the_header :: proc(t: ^testing.T) {
	testing.expect_value(t, span_csv(nil, context.temp_allocator), "frame,steps,step_us,view_us\n")
}
