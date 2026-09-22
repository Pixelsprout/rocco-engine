package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

Roc_Body :: Roc_Init_Bodies
Script_State :: Roc_Init

roc_alloc_count: uint
roc_dealloc_count: uint
roc_realloc_count: uint

// Memory allocation given to the scripting language
Script :: struct {
	track: mem.Tracking_Allocator,
	heap:  mem.Allocator,
	state: Script_State,
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

script_init :: proc(s: ^Script, count: u64) -> (err: mem.Allocator_Error) {

	mem.tracking_allocator_init(&s.track, context.allocator)
	s.heap = mem.tracking_allocator(&s.track)

	s.state = roc_init(count)
	return
}

script_step :: proc(s: ^Script, dt: f32) {
	s.state = roc_step(s.state, dt)

	fmt.printfln("live=%d blocks=%d, bad_frees=%d",
		s.track.current_memory_allocated,
		len(s.track.allocation_map),
		len(s.track.bad_free_array),
	)
}

script_body :: proc(s: ^Script, i: int) -> Roc_Body {
	// returning a still body when out of range
	if i < 0 || i >= int(s.state.bodies.length) {
		return Roc_Body{}
	}
	return s.state.bodies.elements[i]
}

// x_prev and x are both script-owned. alpha is host-owned. The script
// simulates; the host presents.
script_render_x :: proc(s: ^Script, i: int, alpha: f32) -> f32 {
	b := script_body(s, i)
	return math.lerp(b.x_prev, b.x, alpha)
}

script_shutdown :: proc(s: ^Script) {
	for ptr in s.track.allocation_map {
		mem.free(ptr, s.track.backing)
	}
	mem.tracking_allocator_destroy(&s.track)
}
