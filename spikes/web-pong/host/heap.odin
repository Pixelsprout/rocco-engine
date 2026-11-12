package web_pong

import "base:runtime"

// The Roc hooks and the Odin allocator both use libc. The web host has no
// other heap, because Odin's wasm allocator would grow memory beside
// emscripten's sbrk.

@(export, link_name = "roc_alloc")
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	ptr := heap_alloc(max(alignment, size_of(rawptr)), length)
	if ptr == nil {
		fail("roc_alloc: out of memory")
	}
	return ptr
}

@(export, link_name = "roc_dealloc")
roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
	heap_free(ptr)
}

// realloc keeps only malloc's alignment: 8 bytes on wasm32, 16 on macOS.
// Pong allocates nothing with a larger alignment.
@(export, link_name = "roc_realloc")
roc_realloc :: proc "c" (ptr: rawptr, new_length: uint, alignment: uint) -> rawptr {
	return heap_realloc(ptr, new_length)
}

@(export, link_name = "roc_dbg")
roc_dbg :: proc "c" (bytes: [^]u8, length: uint) {
	context = runtime.default_context()
	emit_line(string(bytes[:length]))
}

@(export, link_name = "roc_expect_failed")
roc_expect_failed :: proc "c" (bytes: [^]u8, length: uint) {
	fail("roc_expect_failed")
}

@(export, link_name = "roc_crashed")
roc_crashed :: proc "c" (bytes: [^]u8, length: uint) {
	fail("roc_crashed")
}

libc_allocator :: proc() -> runtime.Allocator {
	return {procedure = libc_allocator_proc}
}

libc_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		return libc_block(size, alignment, mode == .Alloc)
	case .Free:
		heap_free(old_memory)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		block, err := libc_block(size, alignment, mode == .Resize)
		if err == nil && old_memory != nil {
			runtime.mem_copy_non_overlapping(raw_data(block), old_memory, min(size, old_size))
			heap_free(old_memory)
		}
		return block, err
	}
	return nil, .Mode_Not_Implemented
}

libc_block :: proc(size, alignment: int, zeroed: bool) -> ([]byte, runtime.Allocator_Error) {
	ptr := heap_alloc(uint(max(alignment, size_of(rawptr))), uint(size))
	if ptr == nil {
		return nil, .Out_Of_Memory
	}
	if zeroed {
		runtime.mem_zero(ptr, size)
	}
	return ([^]byte)(ptr)[:size], nil
}

// Sets a libc heap and a temp arena on it, so the web host and the native
// twin run the harness with the same allocators. Freestanding Odin has no
// default temp allocator.
host_context :: proc "contextless" (temp: ^runtime.Arena) -> runtime.Context {
	ctx := runtime.default_context()
	context = ctx
	ctx.allocator = libc_allocator()
	if runtime.arena_init(temp, 4 << 20, ctx.allocator) != nil {
		fail("host_context: no memory for the temp arena")
	}
	ctx.temp_allocator = runtime.arena_allocator(temp)
	return ctx
}
