package engine

import "core:fmt"
import "core:mem"
import "core:os"

// The header size and the block length fill the last 16 bytes of the header.
ROC_HEAP_HEADER_MIN :: 16

ROC_GAME :: Game_Calls {
	launch     = roc_game_launch,
	init       = roc_game_init,
	step       = roc_game_step,
	loaded     = roc_game_loaded,
	view       = roc_game_view,
	drop_model = roc_game_drop_model,
}

Roc_Heap_Counters :: struct {
	allocs:   uint,
	deallocs: uint,
	reallocs: uint,
	live:     uint,
}

// The fields of the alloc line for one step. The counts are this step's,
// except live, which is the run's total.
Alloc_Report :: struct {
	step:     u64,
	allocs:   uint,
	deallocs: uint,
	reallocs: uint,
	live:     uint,
	step_us:  f64,
	view_us:  f64,
}

// roc_realloc gets no old size, so each block carries its length in a header
// before it. Realloc resizes in the backing allocator, so a block can grow in
// place.
Roc_Heap :: struct {
	backing:           mem.Allocator,
	roc_alloc_count:   uint,
	roc_dealloc_count: uint,
	roc_realloc_count: uint,
}

Roc_Heap_Header :: struct {
	base:   rawptr,
	size:   int,
	length: int,
}

// Global because the hooks are exported "c" procs with no user data.
@(private = "file")
g_roc_heap: Roc_Heap

roc_heap_init :: proc(backing: mem.Allocator) {
	g_roc_heap = {}
	g_roc_heap.backing = backing
}

// A block Roc never freed stays in the backing allocator. A host built with
// ROCCO_TRACK_ALLOC reports it.
roc_heap_shutdown :: proc() {
	g_roc_heap = {}
}

roc_heap_counters :: proc() -> Roc_Heap_Counters {
	return {
		allocs = g_roc_heap.roc_alloc_count,
		deallocs = g_roc_heap.roc_dealloc_count,
		reallocs = g_roc_heap.roc_realloc_count,
		live = g_roc_heap.roc_alloc_count - g_roc_heap.roc_dealloc_count,
	}
}

roc_heap_report :: proc(step: u64, before: Roc_Heap_Counters, step_us, view_us: f64) -> Alloc_Report {
	after := roc_heap_counters()
	return {
		step = step,
		allocs = after.allocs - before.allocs,
		deallocs = after.deallocs - before.deallocs,
		reallocs = after.reallocs - before.reallocs,
		live = after.live,
		step_us = step_us,
		view_us = view_us,
	}
}

// scripts/alloc-check.sh parses this line.
alloc_report_print :: proc(r: Alloc_Report) {
	fmt.printfln(
		"alloc step=%v allocs=%v deallocs=%v reallocs=%v live=%v step_us=%.1f view_us=%.1f",
		r.step,
		r.allocs,
		r.deallocs,
		r.reallocs,
		r.live,
		r.step_us,
		r.view_us,
	)
}

// A view of the bytes, valid while s lives. A short string lives inside the Roc_Str itself.
roc_str_string :: proc(s: ^Roc_Str) -> string {
	if int(s.length) < 0 {
		raw := ([^]u8)(s)
		return string(raw[:raw[size_of(Roc_Str) - 1] & 0x7f])
	}
	return string(s.bytes[:s.length])
}

@(private = "file")
roc_game_launch :: proc(config: Config) -> Launch {return roc_launch(config)}

@(private = "file")
roc_game_init :: proc(config: Config) -> Init_Result {return roc_init(config)}

@(private = "file")
roc_game_step :: proc(model: rawptr, input: Input, results: Query_Results, dt: f32) -> Step_Result {
	return roc_step(model, input, results, dt)
}

@(private = "file")
roc_game_loaded :: proc(model: rawptr, pack: Roc_Str, manifest: Roc_List(Manifest_Entry)) -> rawptr {
	return roc_loaded(model, pack, manifest)
}

@(private = "file")
roc_game_view :: proc(model: rawptr) -> Scene {return roc_view(model)}

@(private = "file")
roc_game_drop_model :: proc(model: rawptr) {roc_drop_model(model)}

// The backing alignment is at least the int alignment, so the header words
// are aligned for any Roc alignment.
@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_alloc_count += 1

	size := roc_heap_header_size(int(alignment))
	bytes, err := mem.alloc_bytes_non_zeroed(size + int(length), max(int(alignment), align_of(int)), g_roc_heap.backing)
	if err != nil {
		fmt.printfln("roc_alloc failed: %v", err)
		return nil
	}
	return roc_heap_header_write(raw_data(bytes), size, int(length))
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	context = g_state.ctx
	g_roc_heap.roc_dealloc_count += 1

	header := roc_heap_header(ptr)
	mem.free_with_size(header.base, header.size + header.length, g_roc_heap.backing)
}

@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_realloc_count += 1

	header := roc_heap_header(ptr)
	base, err := mem.resize_non_zeroed(
		header.base,
		header.size + header.length,
		header.size + int(new_length),
		max(int(alignment), align_of(int)),
		g_roc_heap.backing,
	)
	if err != nil {
		fmt.printfln("roc_realloc failed: %v", err)
		return nil
	}
	return roc_heap_header_write(base, header.size, int(new_length))
}

// The header size is a multiple of the alignment, so the block keeps the
// alignment of the backing block, also after a resize moves it.
@(private = "file")
roc_heap_header_size :: proc "contextless" (alignment: int) -> int {
	return max(ROC_HEAP_HEADER_MIN, alignment)
}

@(private = "file")
roc_heap_header :: proc "contextless" (ptr: rawptr) -> (header: Roc_Heap_Header) {
	words := ([^]int)(ptr)
	header.size = words[-2]
	header.length = words[-1]
	header.base = rawptr(uintptr(ptr) - uintptr(header.size))
	return
}

@(private = "file")
roc_heap_header_write :: proc "contextless" (base: rawptr, size, length: int) -> rawptr {
	ptr := rawptr(uintptr(base) + uintptr(size))
	words := ([^]int)(ptr)
	words[-2] = size
	words[-1] = length
	return ptr
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
