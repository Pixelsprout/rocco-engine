#+build darwin, linux
package web_pong

import "base:runtime"
import "core:c/libc"
import "core:fmt"

// macOS malloc returns 16-byte aligned blocks. The platform's libSystem stub
// has no posix_memalign.
MALLOC_ALIGNMENT :: 16

g_temp: runtime.Arena

main :: proc() {
	context = host_context(&g_temp)
	run_pong(emit_line)
}

heap_alloc :: proc "contextless" (alignment, size: uint) -> rawptr {
	if alignment > MALLOC_ALIGNMENT {
		fail("heap_alloc: alignment over 16")
	}
	return libc.malloc(max(size, 1))
}

heap_free :: proc "contextless" (ptr: rawptr) {
	libc.free(ptr)
}

heap_realloc :: proc "contextless" (ptr: rawptr, size: uint) -> rawptr {
	return libc.realloc(ptr, size)
}

emit_line :: proc(line: string) {
	fmt.println(line)
}

fail :: proc "contextless" (message: cstring) -> ! {
	context = runtime.default_context()
	fmt.eprintln(message)
	libc.abort()
}
