#+test
package engine

import "core:strings"
import "core:testing"

@(test)
test_gpu_timing_keeps_busy_slots_until_their_queries_finish :: proc(t: ^testing.T) {
	p: Gpu_Timing_Protocol
	gpu_timing_protocol_init(&p, 20, context.allocator)
	defer delete(p.rows)
	for frame in 1 ..= GPU_TIMING_SLOTS {
		testing.expect_value(t, gpu_timing_protocol_begin(&p, frame), frame-1)
	}
	owners := p.slots
	testing.expect_value(t, gpu_timing_protocol_begin(&p, 9), -1)
	testing.expect_value(t, p.slots, owners)
	testing.expect_value(t, p.rows[8].status, Gpu_Timing_Status.Missing_Busy)
	p.rows[0].status = .Valid
	p.slots[0] = 0
	testing.expect_value(t, gpu_timing_protocol_begin(&p, 10), 0)
	testing.expect_value(t, p.slots[0], 10)
	gpu_timing_protocol_shutdown(&p)
	testing.expect_value(t, p.rows[0].status, Gpu_Timing_Status.Valid)
	testing.expect_value(t, p.rows[1].status, Gpu_Timing_Status.Missing_Shutdown)
	testing.expect_value(t, p.rows[8].status, Gpu_Timing_Status.Missing_Busy)
	testing.expect_value(t, p.rows[9].status, Gpu_Timing_Status.Missing_Shutdown)
}

@(test)
test_gpu_timing_bounds_rows_and_passes :: proc(t: ^testing.T) {
	p: Gpu_Timing_Protocol
	gpu_timing_protocol_init(&p, 1, context.allocator)
	defer delete(p.rows)
	gpu_timing_protocol_begin(&p, 1)
	row := &p.rows[0]
	for i in 0 ..< GPU_TIMING_PASSES { testing.expect_value(t, gpu_timing_protocol_pass(row, Gpu_Timing_Pass.Game_Post), i) }
	testing.expect_value(t, gpu_timing_protocol_pass(row, Gpu_Timing_Pass.Game_Post), -1)
	testing.expect_value(t, row.count, GPU_TIMING_PASSES)
	testing.expect(t, row.overflow)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Pending)
	gpu_timing_result(row, 1000, false)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Overflow)
	testing.expect_value(t, gpu_timing_protocol_begin(&p, 2), -1)
	testing.expect_value(t, len(p.rows), 1)
}

@(test)
test_gpu_timing_rejects_disjoint_frequency_and_order_failures :: proc(t: ^testing.T) {
	row := Gpu_Timing_Row{start = 100, end = 300, count = 1, passes = {0 = {kind = .Main, start = 120, end = 280}}}
	gpu_timing_result(&row, 1000, false)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Valid)
	gpu_timing_result(&row, 1000, true)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Disjoint)
	gpu_timing_result(&row, 0, false)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Invalid)
	row.passes[0].end = 301
	gpu_timing_result(&row, 1000, false)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Invalid)
	row.passes[0].end = 110
	gpu_timing_result(&row, 1000, false)
	testing.expect_value(t, row.status, Gpu_Timing_Status.Invalid)
}

@(test)
test_gpu_timing_csv_keeps_missing_values_blank :: proc(t: ^testing.T) {
	rows := []Gpu_Timing_Row{{frame = 1, status = .Valid, frequency = 1000, start = 100, end = 300, count = 1, passes = {0 = {kind = .Main, start = 120, end = 280}}}, {frame = 2, status = .Disjoint}, {frame = 3, status = .Missing_Busy}, {frame = 4, status = .Missing_Shutdown}}
	csv := gpu_timing_csv(rows, context.temp_allocator)
	testing.expect(t, strings.contains(csv, "1,frame,-1,,Valid,1000,100,300,200.000000\n"))
	testing.expect(t, strings.contains(csv, "1,pass,0,Main,Valid,1000,120,280,160.000000\n"))
	testing.expect(t, strings.contains(csv, "2,frame,-1,,Disjoint,,,,\n"))
	testing.expect(t, strings.contains(csv, "3,frame,-1,,Missing_Busy,,,,\n"))
	testing.expect(t, strings.contains(csv, "4,frame,-1,,Missing_Shutdown,,,,\n"))
}
