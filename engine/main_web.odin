#+build freestanding
package engine

import "core:mem"

import "base:runtime"

// The "env.o" name makes the wasm import module "env". emcc resolves these
// against emscripten's libc.
foreign import libc "env.o"

@(default_calling_convention = "c")
foreign libc {
	@(link_name = "memalign")
	libc_memalign :: proc(alignment, size: uint) -> rawptr ---
	@(link_name = "free")
	libc_free :: proc(ptr: rawptr) ---
}

// Odin reserves the link name main, so platform/web/main.c calls this. On
// emscripten sapp.run starts the requestAnimationFrame loop and returns, so
// this returns while the game runs.
@(export, link_name = "rocco_web_main")
web_main :: proc "c" () -> i32 {
	context = runtime.default_context()
	#force_no_inline runtime._startup_runtime()
	// Odin's own wasm allocator grows memory beside emscripten's sbrk, so
	// every allocation goes through libc.
	context.allocator = {libc_allocator_proc, nil}
	run(ROC_GAME)
	return 0
}

// libc's realloc does not keep the alignment, so a resize allocates and copies.
libc_allocator_proc :: proc(
	data: rawptr,
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
		ptr := libc_memalign(uint(max(alignment, size_of(rawptr))), uint(size))
		if ptr == nil {
			return nil, .Out_Of_Memory
		}
		if mode == .Alloc {
			mem.zero(ptr, size)
		}
		return mem.byte_slice(ptr, size), nil
	case .Free:
		libc_free(old_memory)
		return nil, nil
	case .Resize, .Resize_Non_Zeroed:
		return mem.default_resize_bytes_align(mem.byte_slice(old_memory, old_size), size, alignment, {libc_allocator_proc, nil}, loc)
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
