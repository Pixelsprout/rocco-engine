#+build darwin
package engine

import "core:os"
import sg "../sokol-odin/sokol/gfx"

EXPECTED_BACKEND :: sg.Backend.METAL_MACOS

platform_program_name :: proc(allocator := context.allocator) -> string {
	return os.args[0] if len(os.args) > 0 else ""
}
