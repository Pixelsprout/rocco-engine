#+build windows
package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import d3d11 "vendor:directx/d3d11"

GPU_TIMING_DONOTFLUSH :: u32(1)

Gpu_Timing_Queries :: struct {
	disjoint: ^d3d11.IQuery,
	stamps: [GPU_TIMING_STAMPS]^d3d11.IQuery,
	started: bool,
}
Gpu_Timing_Native :: struct {
	protocol: Gpu_Timing_Protocol,
	queries: [GPU_TIMING_SLOTS]Gpu_Timing_Queries,
	// The context is borrowed. Release queries before Sokol destroys its device.
	device_context: ^d3d11.IDeviceContext,
	path: string,
	allocator: mem.Allocator,
	active, failed: bool,
	pass: int,
	created, released: int,
}

when GPU_TIMING { g_gpu_timing: Gpu_Timing_Native }

gpu_timing_native_open_from_env :: proc(t: ^Gpu_Timing_Native, frames: int) {
	path := os.get_env(GPU_TIMING_CSV_ENV, context.temp_allocator)
	if path == "" || frames <= 0 {
		fmt.eprintln("GPU timing requires ROCCO_D3D_GPU_CSV and ROCCO_EXIT_AFTER_FRAMES")
		os.exit(1)
	}
	ok := gpu_timing_native_open(t, path, frames, (^d3d11.IDevice)(sg.d3d11_device()), (^d3d11.IDeviceContext)(sg.d3d11_device_context()), context.allocator)
	if !ok { fmt.eprintln("D3D11 timestamp query creation failed"); os.exit(1) }
}

gpu_timing_native_open :: proc(t: ^Gpu_Timing_Native, path: string, frames: int, device: ^d3d11.IDevice, device_context: ^d3d11.IDeviceContext, allocator: mem.Allocator) -> bool {
	if device == nil || device_context == nil || frames <= 0 { return false }
	t.allocator = allocator
	t.path = strings.clone(path, allocator)
	t.device_context = device_context
	gpu_timing_protocol_init(&t.protocol, frames, allocator)
	for &slot in t.queries {
		desc := d3d11.QUERY_DESC{Query = .TIMESTAMP_DISJOINT}
		if device->CreateQuery(&desc, &slot.disjoint) < 0 { gpu_timing_native_release(t); return false }
		t.created += 1
		desc.Query = .TIMESTAMP
		for &stamp in slot.stamps {
			if device->CreateQuery(&desc, &stamp) < 0 { gpu_timing_native_release(t); return false }
			t.created += 1
		}
	}
	t.active = true
	return true
}

gpu_timing_native_release :: proc(t: ^Gpu_Timing_Native) {
	for &slot in t.queries {
		for &stamp in slot.stamps {
			if stamp != nil { stamp->Release(); stamp = nil; t.released += 1 }
		}
		if slot.disjoint != nil { slot.disjoint->Release(); slot.disjoint = nil; t.released += 1 }
		slot.started = false
	}
	if t.path != "" { delete(t.path, t.allocator); t.path = "" }
	delete(t.protocol.rows)
	t.protocol = {}
	t.device_context = nil
	t.active = false
}

gpu_timing_native_poll :: proc(t: ^Gpu_Timing_Native) {
	for owner, index in t.protocol.slots {
		if owner == 0 || index == t.protocol.current { continue }
		queries := &t.queries[index]
		row := &t.protocol.rows[owner-1]
		if row.status == .Query_Error { continue }
		disjoint: d3d11.QUERY_DATA_TIMESTAMP_DISJOINT
		// DONOTFLUSH preserves ownership when the driver has not submitted this batch.
		result := t.device_context->GetData(queries.disjoint, &disjoint, size_of(disjoint), GPU_TIMING_DONOTFLUSH)
		if result == 1 { continue }
		if result < 0 { row.status = .Query_Error; t.failed = true; continue }
		ready := true
		ticks: [GPU_TIMING_STAMPS]u64
		for &tick, i in ticks[:2+2*row.count] {
			result = t.device_context->GetData(queries.stamps[i], &tick, size_of(tick), GPU_TIMING_DONOTFLUSH)
			if result != 0 { ready = false }
			if result < 0 { row.status = .Query_Error; t.failed = true }
		}
		if !ready { continue }
		row.start, row.end = ticks[0], ticks[1]
		for &pass, i in row.passes[:row.count] { pass.start, pass.end = ticks[2+2*i], ticks[3+2*i] }
		gpu_timing_result(row, disjoint.Frequency, bool(disjoint.Disjoint))
		queries.started = false
		t.protocol.slots[index] = 0
	}
}

gpu_timing_native_begin :: proc(t: ^Gpu_Timing_Native, frame: int) {
	if !t.active { return }
	t.protocol.current = -1
	gpu_timing_native_poll(t)
	gpu_timing_protocol_begin(&t.protocol, frame)
	t.pass = -1
	if t.failed && t.protocol.current >= 0 {
		t.protocol.rows[len(t.protocol.rows)-1].status = .Query_Error
		t.protocol.slots[t.protocol.current] = 0
		t.protocol.current = -1
	}
}

gpu_timing_native_pass_begin :: proc(t: ^Gpu_Timing_Native, kind: Gpu_Timing_Pass) {
	if !t.active || t.protocol.current < 0 { return }
	queries := &t.queries[t.protocol.current]
	row := &t.protocol.rows[t.protocol.slots[t.protocol.current]-1]
	if !queries.started {
		t.device_context->Begin(queries.disjoint)
		t.device_context->End(queries.stamps[0])
		queries.started = true
	}
	t.pass = gpu_timing_protocol_pass(row, kind)
	if t.pass >= 0 { t.device_context->End(queries.stamps[2+2*t.pass]) }
}

gpu_timing_native_pass_end :: proc(t: ^Gpu_Timing_Native) {
	if !t.active || t.protocol.current < 0 || t.pass < 0 { return }
	t.device_context->End(t.queries[t.protocol.current].stamps[3+2*t.pass])
	t.pass = -1
}

gpu_timing_native_end :: proc(t: ^Gpu_Timing_Native) {
	if !t.active || t.protocol.current < 0 { return }
	queries := &t.queries[t.protocol.current]
	if queries.started {
		t.device_context->End(queries.stamps[1])
		t.device_context->End(queries.disjoint)
	} else {
		t.protocol.rows[t.protocol.slots[t.protocol.current]-1].status = .Invalid
		t.protocol.slots[t.protocol.current] = 0
	}
	t.protocol.current = -1
}

gpu_timing_native_close :: proc(t: ^Gpu_Timing_Native) -> os.Error {
	if !t.active { return nil }
	gpu_timing_native_poll(t)
	gpu_timing_protocol_shutdown(&t.protocol)
	csv := gpu_timing_csv(t.protocol.rows[:], context.temp_allocator)
	err := os.write_entire_file(t.path, csv)
	gpu_timing_native_release(t)
	return err
}
