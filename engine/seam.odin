package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

roc_alloc_count: uint
roc_dealloc_count: uint
roc_realloc_count: uint

// The tracking allocator is load-bearing: roc_realloc gets no old size, and
// the allocation map is the only record of it.
Seam :: struct {
	track: mem.Tracking_Allocator,
	heap:  mem.Allocator,
	model: rawptr,
	// prev is the Scene before curr. The host interpolates between them.
	prev:     Scene,
	curr:     Scene,
	has_prev: bool,
	pairing:  Pairing,
	report:   bool,
	steps:    u64,
}

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	roc_alloc_count += 1

	bytes, err := mem.alloc_bytes_non_zeroed(
		int(length),
		int(alignment),
		g_state.seam.heap,
	)

	if err != nil {
		fmt.printfln("roc_alloc failed: %v", err)
		return nil
	}

	return raw_data(bytes)
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	context = g_state.ctx
	roc_dealloc_count += 1

	mem.free(ptr, g_state.seam.heap)
}

@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	roc_realloc_count += 1

	old_size := 0
	if entry, ok := g_state.seam.track.allocation_map[ptr]; ok {
		old_size = entry.size
	}

	new_bytes, err := mem.alloc_bytes_non_zeroed(int(new_length), int(alignment), g_state.seam.heap)
	if err != nil {
		fmt.printfln("roc_realloc failed: %v", err)
		return nil
	}
	new_ptr := raw_data(new_bytes)

	mem.copy(new_ptr, ptr, min(old_size, int(new_length)))
	mem.free(ptr, g_state.seam.heap)
	return new_ptr
}

@(export, link_name = "roc_dbg")
roc_dbg :: proc "c" (bytes: [^]u8, length: uint) {
	context = g_state.ctx

	msg := string(bytes[:length])

	fmt.printfln("dbg: %v", msg)
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

// Owns the one reference to the Model and the last two Scenes. See the call
// protocol in docs/DESIGN.md section 5: Roc consumes every argument it gets.
seam_init :: proc(s: ^Seam, seed: u64, perm: mem.Allocator, report: bool) {
	s.report = report
	mem.tracking_allocator_init(&s.track, context.allocator)
	s.heap = mem.tracking_allocator(&s.track)
	pairing_init(&s.pairing, perm)

	s.model = roc_init(config_make(seed))
	s.curr = seam_view(s)
}

seam_step :: proc(s: ^Seam, keys: Step_Keys, dt: f32) {
	allocs, deallocs, reallocs := roc_alloc_count, roc_dealloc_count, roc_realloc_count
	start := time.tick_now()

	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	// roc_step frees the old box. Never touch the old pointer again.
	s.model = roc_step(s.model, input, dt)
	stepped := time.tick_now()
	if s.has_prev {
		roc_decref(s.prev)
	}
	s.prev = s.curr
	s.has_prev = true
	s.curr = seam_view(s)
	viewed := time.tick_now()
	pairing_build(&s.pairing, s.prev.draws.elements[:s.prev.draws.length])

	s.steps += 1
	if s.report {
		// scripts/alloc-check.sh parses this line.
		fmt.printfln(
			"alloc step=%v allocs=%v deallocs=%v reallocs=%v live=%v step_us=%.1f view_us=%.1f",
			s.steps,
			roc_alloc_count - allocs,
			roc_dealloc_count - deallocs,
			roc_realloc_count - reallocs,
			len(s.track.allocation_map),
			time.duration_microseconds(time.tick_diff(start, stepped)),
			time.duration_microseconds(time.tick_diff(stepped, viewed)),
		)
	}
}

// Before the first step there is one Scene, and it pairs with itself.
seam_prev :: proc(s: ^Seam) -> Scene {
	return s.prev if s.has_prev else s.curr
}

// roc_view consumes one reference, so give it one and keep ours.
@(private = "file")
seam_view :: proc(s: ^Seam) -> Scene {
	roc_incref_box(s.model)
	return roc_view(s.model)
}

seam_shutdown :: proc(s: ^Seam) {
	if s.has_prev {
		roc_decref(s.prev)
	}
	roc_decref(s.curr)
	roc_drop_model(s.model)

	if len(s.track.allocation_map) > 0 {
		fmt.eprintfln("roc leaked %v blocks, %v bytes", len(s.track.allocation_map), s.track.current_memory_allocated)
	}
	for ptr in s.track.allocation_map {
		mem.free(ptr, s.track.backing)
	}
	mem.tracking_allocator_destroy(&s.track)
}
