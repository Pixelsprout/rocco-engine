package engine

import "core:fmt"
import "core:mem"
import "core:os"

Roc_Heap_Counters :: struct {
	allocs:   uint,
	deallocs: uint,
	reallocs: uint,
	live:     uint,
}

// The tracking allocator is load-bearing: roc_realloc gets no old size, and
// the allocation map is the only record of it.
Roc_Heap :: struct {
	track:             mem.Tracking_Allocator,
	allocator:         mem.Allocator,
	roc_alloc_count:   uint,
	roc_dealloc_count: uint,
	roc_realloc_count: uint,
}

// Global because the hooks are exported "c" procs with no user data.
@(private = "file")
g_roc_heap: Roc_Heap

roc_heap_init :: proc(backing: mem.Allocator) {
	g_roc_heap = {}
	mem.tracking_allocator_init(&g_roc_heap.track, backing)
	g_roc_heap.allocator = mem.tracking_allocator(&g_roc_heap.track)
}

roc_heap_shutdown :: proc() {
	h := &g_roc_heap
	if len(h.track.allocation_map) > 0 {
		fmt.eprintfln("roc leaked %v blocks, %v bytes", len(h.track.allocation_map), h.track.current_memory_allocated)
	}
	for ptr in h.track.allocation_map {
		mem.free(ptr, h.track.backing)
	}
	mem.tracking_allocator_destroy(&h.track)
	h^ = {}
}

roc_heap_counters :: proc() -> Roc_Heap_Counters {
	return {
		allocs = g_roc_heap.roc_alloc_count,
		deallocs = g_roc_heap.roc_dealloc_count,
		reallocs = g_roc_heap.roc_realloc_count,
		live = uint(len(g_roc_heap.track.allocation_map)),
	}
}

roc_heap_report_line :: proc(step: u64, before: Roc_Heap_Counters, step_us, view_us: f64) {
	after := roc_heap_counters()
	// scripts/alloc-check.sh parses this line.
	fmt.printfln(
		"alloc step=%v allocs=%v deallocs=%v reallocs=%v live=%v step_us=%.1f view_us=%.1f",
		step,
		after.allocs - before.allocs,
		after.deallocs - before.deallocs,
		after.reallocs - before.reallocs,
		after.live,
		step_us,
		view_us,
	)
}

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_alloc_count += 1

	bytes, err := mem.alloc_bytes_non_zeroed(int(length), int(alignment), g_roc_heap.allocator)

	if err != nil {
		fmt.printfln("roc_alloc failed: %v", err)
		return nil
	}

	return raw_data(bytes)
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	context = g_state.ctx
	g_roc_heap.roc_dealloc_count += 1

	mem.free(ptr, g_roc_heap.allocator)
}

@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_realloc_count += 1

	old_size := 0
	if entry, ok := g_roc_heap.track.allocation_map[ptr]; ok {
		old_size = entry.size
	}

	new_bytes, err := mem.alloc_bytes_non_zeroed(int(new_length), int(alignment), g_roc_heap.allocator)
	if err != nil {
		fmt.printfln("roc_realloc failed: %v", err)
		return nil
	}
	new_ptr := raw_data(new_bytes)

	mem.copy(new_ptr, ptr, min(old_size, int(new_length)))
	mem.free(ptr, g_roc_heap.allocator)
	return new_ptr
}

@(export, link_name = "roc_dbg")
roc_dbg :: proc "c" (bytes: [^]u8, length: uint) {
	context = g_state.ctx

	msg := string(bytes[:length])

	// stderr, so the checks that read Frame Count from stdout never see it.
	fmt.eprintfln("dbg: %v", msg)
}

@(export, link_name = "roc_expect_failed")
roc_expect_failed :: proc "c" (bytes: [^]u8, length: uint) {
	context = g_state.ctx

	msg := string(bytes[:length])

	fmt.printfln("expect failed: %v", msg)
}

@(export, link_name = "roc_crashed")
roc_crashed :: proc "c" (bytes: [^]u8, length: uint) {
	context = g_state.ctx

	msg := string(bytes[:length])

	fmt.printfln("crashed: %v", msg)

	os.exit(1) // prevents undefined behavior
}
