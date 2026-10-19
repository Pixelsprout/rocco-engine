#+build linux
package engine

import "core:os"
import sg "../sokol-odin/sokol/gfx"

EXPECTED_BACKEND :: sg.Backend.GLCORE

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return os.args
}
