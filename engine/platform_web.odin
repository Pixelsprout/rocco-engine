#+build freestanding
package engine

import sg "../sokol-odin/sokol/gfx"
import "system"

EXPECTED_BACKEND :: sg.Backend.WGPU

shader_open_file :: proc(path: string) -> (^system.File, system.Error) {
	return system.open(path)
}

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return system.args
}

platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	return nil
}

// WebGPU reads a texture back only through a mapped buffer, which resolves
// after the frame. The web host has no Bridge, so nothing asks for a read.
platform_read_target :: proc(color: sg.Image, size: [2]i32, rgba: []byte) -> (error: string) {
	return "the web host cannot read the target"
}
