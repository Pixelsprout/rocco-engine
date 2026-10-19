package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

SPANS :: #config(ROCCO_SPANS, false)
SPANS_CSV_ENV :: "ROCCO_SPANS_CSV"
// Enough closes that the clock resolution does not dominate the mean.
SPAN_COST_SAMPLES :: 100_000

// Only the Span code uses time, so -vet needs this when Spans are off.
_ :: time

// The CSV columns follow this order, which is the order of a Frame.
SPAN_NAMES :: [Span]string {
	.Input         = "input",
	.Step          = "step",
	.Commands      = "commands",
	.View          = "view",
	.Queries       = "queries",
	.Query_Results = "query_results",
	.Interpolation = "interpolation",
	.Ui_Layout     = "ui_layout",
	.Render_Submit = "render_submit",
	.Commit        = "commit",
}

// Input to Query_Results run once per fixed step. The rest run once per Frame.
Span :: enum u8 {
	Input,
	Step,
	Commands,
	View,
	Queries,
	Query_Results,
	Interpolation,
	Ui_Layout,
	Render_Submit,
	Commit,
}

// One Frame. A Span sums over the fixed steps of the Frame. closes is not in
// the CSV; it shows which Spans the Frame ran.
Span_Row :: struct {
	frame:  int,
	steps:  int,
	us:     [Span]f64,
	closes: [Span]int,
}

// A build without Spans has an empty sink and an empty tick, so the Span calls
// compile to nothing.
when SPANS {
	Span_Sink :: struct {
		path:    string,
		row:     Span_Row,
		rows:    [dynamic]Span_Row,
		cost_us: f64,
	}
	Span_Tick :: time.Tick
} else {
	Span_Sink :: struct {}
	Span_Tick :: struct {}
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
		sink.cost_us = span_cost_measure()
	}
}

span_sink_destroy :: proc(sink: ^Span_Sink) {
	when SPANS {
		delete(sink.path, sink.rows.allocator)
		delete(sink.rows)
	}
}

span_open :: #force_inline proc() -> Span_Tick {
	when SPANS {
		return time.tick_now()
	} else {
		return {}
	}
}

// Returns the close time, which opens the next Span. A nil sink records nothing.
span_close :: #force_inline proc(sink: ^Span_Sink, span: Span, opened: Span_Tick) -> Span_Tick {
	when SPANS {
		now := time.tick_now()
		if sink != nil {
			sink.row.us[span] += time.duration_microseconds(time.tick_diff(opened, now))
			sink.row.closes[span] += 1
		}
		return now
	} else {
		return {}
	}
}

// Moves the open time of a Span forward by the time since waited, so a wait
// between waited and now does not count in the Span.
span_skip :: #force_inline proc(opened, waited: Span_Tick) -> Span_Tick {
	when SPANS {
		return time.tick_add(opened, time.tick_since(waited))
	} else {
		return {}
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

// The time one span_close adds to a Frame: the mean over back-to-back closes
// of an empty Span.
span_cost_us :: proc(sink: ^Span_Sink) -> f64 {
	when SPANS {
		return sink.cost_us
	} else {
		return 0
	}
}

// Writes nothing in a build without Spans.
span_sink_write :: proc(sink: ^Span_Sink) -> os.Error {
	when SPANS {
		return os.write_entire_file(sink.path, span_csv(span_rows(sink), sink.cost_us, context.temp_allocator))
	} else {
		return nil
	}
}

// Every row repeats the Span cost of the run, so one file holds the run.
span_csv :: proc(rows: []Span_Row, cost_us: f64, allocator: mem.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "frame,steps")
	for name in SPAN_NAMES {
		fmt.sbprintf(&b, ",%v_us", name)
	}
	strings.write_string(&b, ",span_cost_us\n")
	for row in rows {
		fmt.sbprintf(&b, "%v,%v", row.frame, row.steps)
		for us in row.us {
			fmt.sbprintf(&b, ",%.3f", us)
		}
		fmt.sbprintf(&b, ",%.4f\n", cost_us)
	}
	return strings.to_string(b)
}

@(private = "file")
span_cost_measure :: proc() -> f64 {
	when SPANS {
		scratch: Span_Sink
		start := span_open()
		t := start
		for _ in 0 ..< SPAN_COST_SAMPLES {
			t = span_close(&scratch, .Step, t)
		}
		return time.duration_microseconds(time.tick_diff(start, t)) / SPAN_COST_SAMPLES
	} else {
		return 0
	}
}
