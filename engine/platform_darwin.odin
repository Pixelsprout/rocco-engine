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
