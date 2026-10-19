#+test
package engine

import "core:testing"

SPAN_CSV_HEADER :: "frame,steps,input_us,step_us,commands_us,view_us,queries_us,query_results_us,interpolation_us,ui_layout_us,render_submit_us,commit_us,span_cost_us\n"

@(test)
test_span_csv_has_a_header_then_one_row_per_frame_in_frame_order :: proc(t: ^testing.T) {
	rows := []Span_Row{{frame = 1, steps = 1, us = #partial {.Input = 1, .Step = 12.5, .View = 3, .Commit = 0.25}}, {frame = 2, steps = 0, us = {}}}

	csv := span_csv(rows, 0.0215, context.temp_allocator)

	testing.expect_value(
		t,
		csv,
		SPAN_CSV_HEADER +
		"1,1,1.000,12.500,0.000,3.000,0.000,0.000,0.000,0.000,0.000,0.250,0.0215\n" +
		"2,0,0.000,0.000,0.000,0.000,0.000,0.000,0.000,0.000,0.000,0.000,0.0215\n",
	)
}

@(test)
test_span_csv_with_no_frames_is_only_the_header :: proc(t: ^testing.T) {
	testing.expect_value(t, span_csv(nil, 0, context.temp_allocator), SPAN_CSV_HEADER)
}

@(test)
test_span_cost_is_measured_once_per_run_only_in_a_spans_build :: proc(t: ^testing.T) {
	sink: Span_Sink
	span_sink_init(&sink, "", 0, context.allocator)
	defer span_sink_destroy(&sink)

	when SPANS {
		testing.expect(t, span_cost_us(&sink) > 0)
	} else {
		testing.expect_value(t, span_cost_us(&sink), 0)
	}
}
