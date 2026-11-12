#+build freestanding
package web_pong

import "base:runtime"

// The "env.o" name makes the wasm import module "env". The final link
// resolves these against the emscripten libc that the prebuilt host carries.
foreign import env "env.o"

g_temp: runtime.Arena

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
	memalign :: proc(alignment, size: uint) -> rawptr ---
	realloc :: proc(ptr: rawptr, size: uint) -> rawptr ---
	free :: proc(ptr: rawptr) ---
	abort :: proc() -> ! ---
}

// The whole run happens before main returns. It needs no window and no
// animation frames.
@(export, link_name = "rocco_web_main")
web_main :: proc "c" () -> i32 {
	context = runtime.default_context()
	#force_no_inline runtime._startup_runtime()
	context = host_context(&g_temp)
	run_pong(emit_line)
	return 0
}

// emscripten's aligned_alloc returned nil for some Roc allocations. memalign
// has no length rule.
heap_alloc :: proc "contextless" (alignment, size: uint) -> rawptr {
	return memalign(alignment, size)
}

heap_free :: proc "contextless" (ptr: rawptr) {
	free(ptr)
}

heap_realloc :: proc "contextless" (ptr: rawptr, size: uint) -> rawptr {
	return realloc(ptr, size)
}

emit_line :: proc(line: string) {
	text, err := make([]u8, len(line) + 1, context.temp_allocator)
	if err != nil {
		fail("emit_line: the temp allocator failed")
	}
	copy(text, line)
	puts(cstring(raw_data(text)))
}

fail :: proc "contextless" (message: cstring) -> ! {
	puts(message)
	abort()
}
