// core:fmt has no eprint procedures on freestanding wasm, because it has no
// os. The slice imports this package as fmt, so the engine's log lines reach
// the browser console through puts.
package webfmt

import "core:fmt"

foreign import env "env.o"

@(default_calling_convention = "c")
foreign env {
	puts :: proc(s: cstring) -> i32 ---
}

eprintfln :: proc(format: string, args: ..any) {
	puts(fmt.ctprintf(format, ..args))
}

eprintln :: proc(args: ..any) {
	puts(fmt.ctprint(..args))
}
