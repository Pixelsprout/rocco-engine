package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:mem"
import "core:strings"

GPU_TIMING :: #config(ROCCO_D3D_GPU_TIMING, false) && ODIN_OS == .Windows
GPU_TIMING_SLOTS :: 8
GPU_TIMING_PASSES :: 64
GPU_TIMING_STAMPS :: 2 + 2 * GPU_TIMING_PASSES
GPU_TIMING_CSV_ENV :: "ROCCO_D3D_GPU_CSV"

Gpu_Timing_Status :: enum { Pending, Valid, Disjoint, Invalid, Overflow, Missing_Busy, Missing_Shutdown, Query_Error }
Gpu_Timing_Pass :: enum { Unlabelled, Shadow, Main, Scene_Depth, Selection, Game_Post, Game_Post_HDR, Game_Post_LDR, Bloom, Bloom_Prefilter, Bloom_Down, Bloom_Up, Post, Blit }
Gpu_Timing_Pass_Row :: struct { kind: Gpu_Timing_Pass, start, end: u64 }
Gpu_Timing_Row :: struct {
	frame: int,
	status: Gpu_Timing_Status,
	frequency, start, end: u64,
	passes: [GPU_TIMING_PASSES]Gpu_Timing_Pass_Row,
	count: int,
	overflow: bool,
}
Gpu_Timing_Protocol :: struct {
	rows: [dynamic]Gpu_Timing_Row,
	// A nonzero slot owns its row until every issued query is ready.
	slots: [GPU_TIMING_SLOTS]int,
	current: int,
	limit: int,
}

gpu_timing_protocol_init :: proc(p: ^Gpu_Timing_Protocol, limit: int, allocator: mem.Allocator) {
	p.current = -1
	p.limit = limit
	p.rows = make([dynamic]Gpu_Timing_Row, 0, limit, allocator)
}

gpu_timing_protocol_begin :: proc(p: ^Gpu_Timing_Protocol, frame: int) -> int {
	p.current = -1
	if len(p.rows) == p.limit { return -1 }
	row := Gpu_Timing_Row{frame = frame, status = .Missing_Busy}
	for owner, slot in p.slots {
		if owner != 0 { continue }
		row.status = .Pending
		p.current = slot
		p.slots[slot] = len(p.rows) + 1
		break
	}
	append(&p.rows, row)
	return p.current
}

gpu_timing_protocol_pass :: proc(row: ^Gpu_Timing_Row, kind: Gpu_Timing_Pass) -> int {
	if row.count == GPU_TIMING_PASSES { row.overflow = true; return -1 }
	index := row.count
	row.passes[index].kind = kind
	row.count += 1
	return index
}

gpu_timing_result :: proc(row: ^Gpu_Timing_Row, frequency: u64, disjoint: bool) {
	row.frequency = frequency
	if disjoint { row.status = .Disjoint; return }
	if frequency == 0 || row.end < row.start { row.status = .Invalid; return }
	for pass in row.passes[:row.count] {
		if pass.end < pass.start || pass.start < row.start || pass.end > row.end { row.status = .Invalid; return }
	}
	row.status = .Overflow if row.overflow else .Valid
}

gpu_timing_protocol_shutdown :: proc(p: ^Gpu_Timing_Protocol) {
	for owner in p.slots {
		if owner != 0 {
			row := &p.rows[owner - 1]
			if row.status == .Pending { row.status = .Missing_Shutdown }
		}
	}
	p.slots = {}
	p.current = -1
}

gpu_timing_pass_kind :: proc(label: cstring) -> Gpu_Timing_Pass {
	switch string(label) {
	case "shadow": return .Shadow
	case "main": return .Main
	case "scene-depth": return .Scene_Depth
	case "selection": return .Selection
	case "game-post": return .Game_Post
	case "game-post-hdr": return .Game_Post_HDR
	case "game-post-ldr": return .Game_Post_LDR
	case "bloom": return .Bloom
	case "bloom-prefilter": return .Bloom_Prefilter
	case "bloom-down": return .Bloom_Down
	case "bloom-up": return .Bloom_Up
	case "post": return .Post
	case "blit": return .Blit
	}
	return .Unlabelled
}

gpu_timing_csv :: proc(rows: []Gpu_Timing_Row, allocator: mem.Allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "frame,scope,pass_index,pass,status,frequency_hz,start_tick,end_tick,gpu_ms\n")
	for &row in rows {
		fmt.sbprintf(&b, "%v,frame,-1,,%v,", row.frame, row.status)
		if row.status == .Valid { fmt.sbprintf(&b, "%v,%v,%v,%.6f", row.frequency, row.start, row.end, f64(row.end-row.start)*1000/f64(row.frequency)) } else { strings.write_string(&b, ",,,") }
		strings.write_byte(&b, '\n')
		for pass, i in row.passes[:row.count] {
			fmt.sbprintf(&b, "%v,pass,%v,%v,%v,", row.frame, i, pass.kind, row.status)
			if row.status == .Valid { fmt.sbprintf(&b, "%v,%v,%v,%.6f", row.frequency, pass.start, pass.end, f64(pass.end-pass.start)*1000/f64(row.frequency)) } else { strings.write_string(&b, ",,,") }
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

gfx_begin_pass :: #force_inline proc(pass: sg.Pass) {
	when GPU_TIMING { gpu_timing_native_pass_begin(&g_gpu_timing, gpu_timing_pass_kind(pass.label)) }
	sg.begin_pass(pass)
	if g_state.capture.on {
		label := capture_pass_label(&g_state.capture, pass.label)
		when ODIN_OS == .Darwin {
			if g_state.capture.label_passes { capture_metal_label(label) }
		} else {
			_ = label
		}
	}
}

gfx_end_pass :: #force_inline proc() {
	sg.end_pass()
	when GPU_TIMING { gpu_timing_native_pass_end(&g_gpu_timing) }
}

gpu_timing_app_init :: #force_inline proc() {
	when GPU_TIMING { gpu_timing_native_open_from_env(&g_gpu_timing, g_state.exit_after_frames) }
}

gpu_timing_app_frame :: #force_inline proc() {
	when GPU_TIMING { gpu_timing_native_begin(&g_gpu_timing, g_state.frame_count + 1) }
}

gpu_timing_app_commit :: #force_inline proc() {
	when GPU_TIMING { gpu_timing_native_end(&g_gpu_timing) }
}

gpu_timing_app_shutdown :: #force_inline proc() {
	when GPU_TIMING {
		err := gpu_timing_native_close(&g_gpu_timing)
		fmt.assertf(err == nil, "GPU timing CSV did not write: %v", err)
	}
}
