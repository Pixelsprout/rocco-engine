package engine

import "core:fmt"
import "core:mem"
import "core:os"

roc_alloc_count: uint
roc_dealloc_count: uint
roc_realloc_count: uint

// The tracking allocator is load-bearing: roc_realloc gets no old size, and
// the allocation map is the only record of it.
Script :: struct {
	track: mem.Tracking_Allocator,
	heap:  mem.Allocator,
	model: rawptr,
	scene: Scene,
}

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	roc_alloc_count += 1

	bytes, err := mem.alloc_bytes_non_zeroed(
		int(length),
		int(alignment),
		g_state.script.heap,
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

	mem.free(ptr, g_state.script.heap)
}

@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	context = g_state.ctx
	roc_realloc_count += 1

	old_size := 0
	if entry, ok := g_state.script.track.allocation_map[ptr]; ok {
		old_size = entry.size
	}

	new_ptr := roc_alloc(new_length, alignment)
	if new_ptr == nil {
		return nil
	}

	mem.copy(new_ptr, ptr, min(old_size, int(new_length)))
	mem.free(ptr, g_state.script.heap)
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

// Owns the one reference to the Model and the current Scene. See the call
// protocol in docs/DESIGN.md section 5: Roc consumes every argument it gets.
script_init :: proc(s: ^Script, seed: u64) {
	mem.tracking_allocator_init(&s.track, context.allocator)
	s.heap = mem.tracking_allocator(&s.track)

	s.model = roc_init(config_make(seed))
	s.scene = script_view(s)
}

script_step :: proc(s: ^Script, keys: Step_Keys, dt: f32) {
	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	// roc_step frees the old box. Never touch the old pointer again.
	s.model = roc_step(s.model, input, dt)
	roc_decref(s.scene)
	s.scene = script_view(s)
}

// roc_view consumes one reference, so give it one and keep ours.
@(private = "file")
script_view :: proc(s: ^Script) -> Scene {
	roc_incref_box(s.model)
	return roc_view(s.model)
}

script_shutdown :: proc(s: ^Script) {
	roc_decref(s.scene)
	roc_drop_model(s.model)

	if len(s.track.allocation_map) > 0 {
		fmt.eprintfln("roc leaked %v blocks, %v bytes", len(s.track.allocation_map), s.track.current_memory_allocated)
	}
	for ptr in s.track.allocation_map {
		mem.free(ptr, s.track.backing)
	}
	mem.tracking_allocator_destroy(&s.track)
}
