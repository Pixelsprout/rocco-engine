package engine

import "core:fmt"
import "core:mem"
import "core:os"

// "map" or "header". See Roc_Heap.
ROC_HEAP :: #config(ROCCO_ROC_HEAP, "map")
#assert(ROC_HEAP == "map" || ROC_HEAP == "header")

// The header version keeps the header size and the block length in the 16
// bytes before the block.
ROC_HEAP_HEADER_MIN :: 16

ROC_GAME :: Game_Calls {
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

// roc_realloc gets no old size. The map version finds it in the tracking
// allocator's allocation map and always copies. The header version stores it
// in a header before each block and resizes in the backing allocator, so a
// block can grow in place. track is used only by the map version.
Roc_Heap :: struct {
	backing:           mem.Allocator,
	track:             mem.Tracking_Allocator,
	allocator:         mem.Allocator,
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
	when ROC_HEAP == "map" {
		mem.tracking_allocator_init(&g_roc_heap.track, backing)
		g_roc_heap.allocator = mem.tracking_allocator(&g_roc_heap.track)
	} else {
		g_roc_heap.allocator = backing
	}
}

roc_heap_shutdown :: proc() {
	h := &g_roc_heap
	when ROC_HEAP == "map" {
		if len(h.track.allocation_map) > 0 {
			fmt.eprintfln("roc leaked %v blocks, %v bytes", len(h.track.allocation_map), h.track.current_memory_allocated)
		}
		for ptr in h.track.allocation_map {
			mem.free(ptr, h.track.backing)
		}
		mem.tracking_allocator_destroy(&h.track)
	}
	h^ = {}
}

roc_heap_counters :: proc() -> Roc_Heap_Counters {
	return {
		allocs = g_roc_heap.roc_alloc_count,
		deallocs = g_roc_heap.roc_dealloc_count,
		reallocs = g_roc_heap.roc_realloc_count,
		live = g_roc_heap.roc_alloc_count - g_roc_heap.roc_dealloc_count,
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

// A view of the bytes, valid while s lives. A short string lives inside the Roc_Str itself.
roc_str_string :: proc(s: ^Roc_Str) -> string {
	if int(s.length) < 0 {
		raw := ([^]u8)(s)
		return string(raw[:raw[size_of(Roc_Str) - 1] & 0x7f])
	}
	return string(s.bytes[:s.length])
}

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

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_alloc_count += 1

	when ROC_HEAP == "header" {
		return roc_heap_header_alloc(int(length), int(alignment))
	} else {
		bytes, err := mem.alloc_bytes_non_zeroed(int(length), int(alignment), g_roc_heap.allocator)
		if err != nil {
			fmt.printfln("roc_alloc failed: %v", err)
			return nil
		}
		return raw_data(bytes)
	}
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	context = g_state.ctx
	g_roc_heap.roc_dealloc_count += 1

	when ROC_HEAP == "header" {
		header := roc_heap_header(ptr)
		mem.free_with_size(header.base, header.size + header.length, g_roc_heap.backing)
	} else {
		mem.free(ptr, g_roc_heap.allocator)
	}
}

@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	g_roc_heap.roc_realloc_count += 1

	when ROC_HEAP == "header" {
		return roc_heap_header_realloc(ptr, int(new_length), int(alignment))
	} else {
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
}

// The header size is a multiple of the alignment, so the block keeps the
// alignment of the backing block, also after a resize moves it.
@(private = "file")
roc_heap_header_size :: proc(alignment: int) -> int {
	return max(ROC_HEAP_HEADER_MIN, alignment)
}

@(private = "file")
roc_heap_header :: proc(ptr: rawptr) -> (header: Roc_Heap_Header) {
	words := ([^]int)(ptr)
	header.size = words[-2]
	header.length = words[-1]
	header.base = rawptr(uintptr(ptr) - uintptr(header.size))
	return
}

@(private = "file")
roc_heap_header_write :: proc(base: rawptr, size, length: int) -> rawptr {
	ptr := rawptr(uintptr(base) + uintptr(size))
	words := ([^]int)(ptr)
	words[-2] = size
	words[-1] = length
	return ptr
}

// The backing alignment is at least the int alignment, so the header words
// are aligned for any Roc alignment.
@(private = "file")
roc_heap_header_alloc :: proc(length, alignment: int) -> rawptr {
	size := roc_heap_header_size(alignment)
	bytes, err := mem.alloc_bytes_non_zeroed(size + length, max(alignment, align_of(int)), g_roc_heap.backing)
	if err != nil {
		fmt.printfln("roc_alloc failed: %v", err)
		return nil
	}
	return roc_heap_header_write(raw_data(bytes), size, length)
}

@(private = "file")
roc_heap_header_realloc :: proc(ptr: rawptr, new_length, alignment: int) -> rawptr {
	header := roc_heap_header(ptr)
	base, err := mem.resize_non_zeroed(
		header.base,
		header.size + header.length,
		header.size + new_length,
		max(alignment, align_of(int)),
		g_roc_heap.backing,
	)
	if err != nil {
		fmt.printfln("roc_realloc failed: %v", err)
		return nil
	}
	return roc_heap_header_write(base, header.size, new_length)
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
