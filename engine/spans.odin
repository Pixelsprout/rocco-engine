package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

SPANS :: #config(ROCCO_SPANS, false)
SPANS_CSV_ENV :: "ROCCO_SPANS_CSV"

// The CSV columns follow this order.
SPAN_NAMES :: [Span]string {
	.Step = "step",
	.View = "view",
}

Span :: enum u8 {
	Step,
	View,
}

// One Frame. A Span sums over the fixed steps of the Frame.
Span_Row :: struct {
	frame: int,
	steps: int,
	us:    [Span]f64,
}

// A build without Spans has an empty sink, so the Span calls compile to nothing.
when SPANS {
	Span_Sink :: struct {
		path: string,
		row:  Span_Row,
		rows: [dynamic]Span_Row,
	}
} else {
	Span_Sink :: struct {}
}

// Exits the process when the path and the build disagree, so a bench run
// cannot end with no CSV.
spans_csv_from_env :: proc() -> string {
	path := os.get_env(SPANS_CSV_ENV, context.temp_allocator)
	when SPANS {
		if path == "" {
			fmt.eprintfln("this build records Spans, so set %v to the CSV path", SPANS_CSV_ENV)
			os.exit(1)
		}
	} else {
		if path != "" {
			fmt.eprintfln("%v is set, but this build has no Spans. Build the host with --spans.", SPANS_CSV_ENV)
			os.exit(1)
		}
	}
	return path
}

// Reserves one row per Frame, so recording does not allocate during the run.
span_sink_init :: proc(sink: ^Span_Sink, path: string, frames: int, allocator: mem.Allocator) {
	when SPANS {
		sink.path = strings.clone(path, allocator)
		sink.rows = make([dynamic]Span_Row, 0, frames, allocator)
	}
}

span_sink_destroy :: proc(sink: ^Span_Sink) {
	when SPANS {
		delete(sink.path, sink.rows.allocator)
		delete(sink.rows)
	}
}

span_add :: #force_inline proc(sink: ^Span_Sink, span: Span, duration: time.Duration) {
	when SPANS {
		sink.row.us[span] += time.duration_microseconds(duration)
	}
}

span_frame_end :: #force_inline proc(sink: ^Span_Sink, frame, steps: int) {
	when SPANS {
		sink.row.frame = frame
		sink.row.steps = steps
		append(&sink.rows, sink.row)
		sink.row = {}
	}
}

span_rows :: proc(sink: ^Span_Sink) -> []Span_Row {
	when SPANS {
		return sink.rows[:]
	} else {
		return nil
	}
}

// Writes nothing in a build without Spans.
span_sink_write :: proc(sink: ^Span_Sink) -> os.Error {
	when SPANS {
		return os.write_entire_file(sink.path, span_csv(span_rows(sink), context.temp_allocator))
	} else {
		return nil
	}
}

span_csv :: proc(rows: []Span_Row, allocator: mem.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "frame,steps")
	for name in SPAN_NAMES {
		fmt.sbprintf(&b, ",%v_us", name)
	}
	strings.write_byte(&b, '\n')
	for row in rows {
		fmt.sbprintf(&b, "%v,%v", row.frame, row.steps)
		for us in row.us {
			fmt.sbprintf(&b, ",%.3f", us)
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}
