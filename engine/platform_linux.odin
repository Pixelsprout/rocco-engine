#+build linux
package engine

import "core:os"
import sg "../sokol-odin/sokol/gfx"

// sokol links libGL directly, so these names need only the libGL stub.
foreign import gl "system:GL"

EXPECTED_BACKEND :: sg.Backend.GLCORE

GL_READ_FRAMEBUFFER :: 0x8CA8
GL_READ_FRAMEBUFFER_BINDING :: 0x8CAA
GL_FRAMEBUFFER_COMPLETE :: 0x8CD5
GL_COLOR_ATTACHMENT0 :: 0x8CE0
GL_PACK_ALIGNMENT :: 0x0D05
GL_RGBA :: 0x1908
GL_UNSIGNED_BYTE :: 0x1401

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return os.args
}

// sokol's own colour attachment can already be read back on this backend.
platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	return nil
}

@(default_calling_convention = "c")
foreign gl {
	glGenFramebuffers :: proc(n: i32, framebuffers: [^]u32) ---
	glDeleteFramebuffers :: proc(n: i32, framebuffers: [^]u32) ---
	glBindFramebuffer :: proc(target, framebuffer: u32) ---
	glFramebufferTexture2D :: proc(target, attachment, textarget, texture: u32, level: i32) ---
	glCheckFramebufferStatus :: proc(target: u32) -> u32 ---
	glGetIntegerv :: proc(pname: u32, data: [^]i32) ---
	glReadBuffer :: proc(mode: u32) ---
	glPixelStorei :: proc(pname: u32, param: i32) ---
	glReadPixels :: proc(x, y, width, height: i32, format, type: u32, pixels: rawptr) ---
}

// glReadPixels waits for the GPU. GL stores the bottom row first, so the rows
// are flipped after the read.
platform_read_target :: proc(color: sg.Image, size: [2]i32, rgba: []byte) -> (error: string) {
	info := sg.gl_query_image_info(color)
	texture := info.tex[info.active_slot]
	if texture == 0 {
		return "the target has no GL texture"
	}
	previous: i32
	glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previous)
	framebuffer: u32
	glGenFramebuffers(1, &framebuffer)
	glBindFramebuffer(GL_READ_FRAMEBUFFER, framebuffer)
	glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, info.tex_target, texture, 0)
	if glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE {
		glReadBuffer(GL_COLOR_ATTACHMENT0)
		glPixelStorei(GL_PACK_ALIGNMENT, 1)
		glReadPixels(0, 0, size.x, size.y, GL_RGBA, GL_UNSIGNED_BYTE, raw_data(rgba))
	} else {
		error = "the target cannot be read as a framebuffer"
	}
	glBindFramebuffer(GL_READ_FRAMEBUFFER, u32(previous))
	glDeleteFramebuffers(1, &framebuffer)
	// sokol caches GL state, and the read changed some of it.
	sg.reset_state_cache()
	if error == "" {
		rows_flip(rgba, int(size.x) * 4)
	}
	return
}
