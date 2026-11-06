#+build linux
package main

import engine "../../engine"
import "core:os"
import sg "../../sokol-odin/sokol/gfx"
import "core:fmt"

foreign import gl "system:GL"

Clip_Control :: #type proc "system" (origin, depth: u32)

foreign gl {
	@(link_name = "glGetString") gl_string :: proc "system" (name: u32) -> cstring ---
	@(link_name = "glGetStringi") gl_string_i :: proc "system" (name: u32, index: u32) -> cstring ---
	@(link_name = "glGetIntegerv") gl_integer :: proc "system" (name: u32, value: ^i32) ---
	@(link_name = "glXGetProcAddressARB") gl_proc :: proc "system" (name: cstring) -> rawptr ---
	@(link_name = "glGetInternalformativ") gl_internal_format :: proc "system" (target, format, name: u32, count: i32, values: [^]i32) ---
}

supported :: proc(samples: i32) -> bool {
	if samples == 1 { return true }
	for format in ([3]u32{0x881A, 0x8058, 0x8CAD}) {
		count: i32
		gl_internal_format(0x9100, format, 0x9380, 1, &count)
		assert(count > 0 && count <= 32)
		values: [32]i32
		gl_internal_format(0x9100, format, 0x80A9, count, &values[0])
		found := false
		for value in values[:count] { if value == samples { found = true } }
		if !found { return false }
	}
	return true
}

driver_info :: proc() -> Driver_Info {
	major, minor, extensions, subpixel: i32
	gl_integer(0x821B, &major)
	gl_integer(0x821C, &minor)
	gl_integer(0x821D, &extensions)
	gl_integer(0x0D50, &subpixel)
	clip := major > 4 || major == 4 && minor >= 5
	for i in 0 ..< extensions { if string(gl_string_i(0x1F03, u32(i))) == "GL_ARB_clip_control" { clip = true } }
	depth: i32
	if clip { gl_integer(0x935D, &depth) }
	return {backend = fmt.tprintf("%v", sg.query_backend()), clip_depth_mode = u32(depth), vendor = string(gl_string(0x1F00)), renderer = string(gl_string(0x1F01)), version = string(gl_string(0x1F02)), language = string(gl_string(0x8B8C)), clip_control = clip && gl_proc("glClipControl") != nil, subpixel_bits = int(subpixel)}
}

probe_clip_control :: proc(enabled: bool) {
	clip := cast(Clip_Control)gl_proc("glClipControl")
	assert(clip != nil)
	depth := u32(0x935F) if enabled else u32(0x935E)
	clip(0x8CA1, depth)
	actual: i32
	gl_integer(0x935D, &actual)
	assert(u32(actual) == depth)
}

probe_read_depth :: proc(path: string) {
	info := sg.gl_query_image_info(renderer.target.post.scene.depth.image)
	previous: i32
	engine.glGetIntegerv(engine.GL_READ_FRAMEBUFFER_BINDING, &previous)
	framebuffer: u32
	engine.glGenFramebuffers(1, &framebuffer)
	engine.glBindFramebuffer(engine.GL_READ_FRAMEBUFFER, framebuffer)
	engine.glFramebufferTexture2D(engine.GL_READ_FRAMEBUFFER, engine.GL_COLOR_ATTACHMENT0, info.tex_target, info.tex[info.active_slot], 0)
	assert(engine.glCheckFramebufferStatus(engine.GL_READ_FRAMEBUFFER) == engine.GL_FRAMEBUFFER_COMPLETE)
	data := make([]u32, 480*360, context.temp_allocator)
	engine.glReadBuffer(engine.GL_COLOR_ATTACHMENT0)
	engine.glReadPixels(0, 0, 480, 360, 0x1903, 0x1406, raw_data(data))
	engine.glBindFramebuffer(engine.GL_READ_FRAMEBUFFER, u32(previous))
	engine.glDeleteFramebuffers(1, &framebuffer)
	sg.reset_state_cache()
	for y in 0 ..< 180 {
		for x in 0 ..< 480 { data[y*480+x], data[(359-y)*480+x] = data[(359-y)*480+x], data[y*480+x] }
	}
	bytes := ([^]byte)(raw_data(data))[:len(data)*size_of(u32)]
	assert(os.write_entire_file(path, bytes) == nil)
}
