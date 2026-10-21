#+build darwin
package engine

import "core:os"
import NS "core:sys/darwin/Foundation"
import sg "../sokol-odin/sokol/gfx"
import MTL "vendor:darwin/Metal"

EXPECTED_BACKEND :: sg.Backend.METAL_MACOS

platform_command_line :: proc(allocator := context.allocator) -> []string {
	return os.args
}

// sokol gives every attachment Private storage, and getBytes cannot read a
// Private texture. Shared storage is valid for a render target on Apple
// silicon, the only macOS target. sokol takes ownership of the texture.
platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	desc := MTL.TextureDescriptor.alloc()->init()
	defer desc->release()
	desc->setTextureType(.Type2D)
	desc->setPixelFormat(.RGBA8Unorm)
	desc->setWidth(NS.UInteger(width))
	desc->setHeight(NS.UInteger(height))
	desc->setStorageMode(.Shared)
	desc->setUsage({.ShaderRead, .RenderTarget})
	device := (^MTL.Device)(sg.mtl_device())
	return device->newTextureWithDescriptor(desc)
}

// Called between Frames. The queue runs its command buffers in order, so an
// empty one that has completed means the last Frame has completed too.
// Metal stores the top row first.
platform_read_target :: proc(color: sg.Image, size: [2]i32, rgba: []byte) -> (error: string) {
	info := sg.mtl_query_image_info(color)
	texture := (^MTL.Texture)(info.tex[info.active_slot])
	if texture == nil {
		return "the target has no Metal texture"
	}
	queue := (^MTL.CommandQueue)(sg.mtl_command_queue())
	fence := queue->commandBuffer()
	fence->commit()
	fence->waitUntilCompleted()
	region := MTL.Region {
		origin = {0, 0, 0},
		size   = {NS.Integer(size.x), NS.Integer(size.y), 1},
	}
	texture->getBytes(raw_data(rgba), NS.UInteger(size.x * 4), region, 0)
	return ""
}
