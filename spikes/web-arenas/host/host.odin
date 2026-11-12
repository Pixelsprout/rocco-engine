package web_arenas

import "../../../engine/arenas"
import "base:runtime"
import "core:mem"

// The "env.o" name makes the wasm import module "env". emcc resolves these
// against emscripten's libc.
foreign import env "env.o"

// engine/memory.odin uses the same frame size.
FRAME_ARENA_RESERVE :: 64 * mem.Megabyte
STEP_COUNT :: 3

Main_Loop_Proc :: #type proc "c" ()

g_perm, g_frame: arenas.Arena
g_step: int
g_context: runtime.Context

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
	memalign :: proc(alignment, size: uint) -> rawptr ---
	free :: proc(ptr: rawptr) ---
	emscripten_set_main_loop :: proc(loop: Main_Loop_Proc, fps: i32, simulate_infinite_loop: b32) ---
	emscripten_cancel_main_loop :: proc() ---
}

@(export, link_name = "rocco_web_main")
web_main :: proc "c" () -> i32 {
	context = runtime.default_context()
	#force_no_inline runtime._startup_runtime()
	context.allocator = {libc_allocator_proc, nil}
	g_context = context

	perm := arenas.allocator(&g_perm)
	if _, err := mem.alloc_bytes(256 * mem.Kilobyte, 16, perm); err != nil {
		report("perm: allocation failed", int(err))
		return 1
	}
	report("perm: used bytes", int(g_perm.total_used))

	if err := arenas.init_static(&g_frame, FRAME_ARENA_RESERVE); err != nil {
		report("frame: init_static failed", int(err))
		return 1
	}
	report("frame: reserved bytes", int(g_frame.total_capacity))
	emscripten_set_main_loop(step_frame, 0, false)
	return 0
}

step_frame :: proc "c" () {
	context = g_context
	g_step += 1
	frame := arenas.allocator(&g_frame)
	data, err := mem.alloc_bytes(8 * mem.Megabyte, 16, frame)
	if err != nil {
		report("frame: allocation failed", int(err))
		emscripten_cancel_main_loop()
		return
	}
	data[len(data) - 1] = u8(g_step)

	scratch: arenas.Arena
	_, scratch_err := mem.alloc_bytes(12 * mem.Megabyte, 16, arenas.allocator(&scratch))
	report("scratch: used bytes", int(scratch.total_used), int(scratch_err))
	arenas.destroy(&scratch)

	report("step: frame used bytes", g_step, int(g_frame.total_used))
	arenas.check_temp(&g_frame)
	arenas.free_all(&g_frame)
	report("step: frame used after free_all", g_step, int(g_frame.total_used))
	if g_step >= STEP_COUNT {
		arenas.destroy(&g_frame)
		arenas.destroy(&g_perm)
		puts("done: the arenas freed their blocks")
		emscripten_cancel_main_loop()
	}
}

// Prints the label and each value on one line. The host has no fmt.
report :: proc "contextless" (label: string, values: ..int) {
	buf: [256]u8
	n := copy(buf[:], label)
	for v in values {
		buf[n] = ' '
		n += 1
		digits: [24]u8
		i := len(digits)
		x := v if v >= 0 else -v
		for {
			i -= 1
			digits[i] = u8('0' + x % 10)
			x /= 10
			if x == 0 {
				break
			}
		}
		if v < 0 {
			i -= 1
			digits[i] = '-'
		}
		n += copy(buf[n:], digits[i:])
	}
	buf[n] = 0
	puts(cstring(&buf[0]))
}

// Odin's own wasm allocator grows memory beside emscripten's sbrk, so the
// host allocates through libc.
libc_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		ptr := memalign(uint(max(alignment, size_of(rawptr))), uint(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		if mode == .Alloc {
			mem.zero(ptr, size)
		}
		return ([^]byte)(ptr)[:size], nil
	case .Free:
		free(old_memory)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		return mem.default_resize_bytes_align(([^]byte)(old_memory)[:old_size], size, alignment, {libc_allocator_proc, nil}, loc)
	case .Free_All:
		return nil, .Mode_Not_Implemented
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, nil
}
