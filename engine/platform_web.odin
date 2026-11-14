#+build freestanding
package engine

import sg "../sokol-odin/sokol/gfx"
import "system"

// scripts/web/rocco_web.c defines these.
foreign import env "env.o"

EXPECTED_BACKEND :: sg.Backend.WGPU

Read_Done :: #type proc "c" (user: rawptr, rgba: [^]u8, width, height: i32, error: cstring)

@(default_calling_convention = "c")
foreign env {
	rocco_web_read_texture :: proc(device, texture: rawptr, width, height: i32, done: Read_Done, user: rawptr) ---
	rocco_web_dispatch_quit :: proc() ---
}

shader_open_file :: proc(path: string) -> (^system.File, system.Error) {
	return system.open(path)
}

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return system.args
}

// WebGPU reads a texture back only through a mapped buffer, which maps
// after the Frame. platform_read_target_later reads it instead.
platform_read_target :: proc(color: sg.Image, size: [2]i32, rgba: []byte) -> (error: string) {
	return "the web host reads the target only after the Frame"
}

// Calls done once the copy of the target maps, from the browser's event loop.
platform_read_target_later :: proc(color: sg.Image, size: [2]i32, done: Read_Done, user: rawptr) -> (error: string) {
	if size.x <= 0 || size.y <= 0 {
		return "no Frame has been drawn yet"
	}
	texture := sg.wgpu_query_image_info(color).tex
	if texture == nil {
		return "the target has no WebGPU texture"
	}
	rocco_web_read_texture(sg.wgpu_device(), texture, size.x, size.y, done, user)
	return ""
}

// The page decides what the player sees after the run.
platform_run_ended :: proc() {
	rocco_web_dispatch_quit()
}
