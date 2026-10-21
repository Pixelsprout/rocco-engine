#+build linux
package engine

import "core:os"
import sg "../sokol-odin/sokol/gfx"

EXPECTED_BACKEND :: sg.Backend.GLCORE

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return os.args
}

// sokol's own colour attachment can already be read back on this backend.
platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	return nil
}
