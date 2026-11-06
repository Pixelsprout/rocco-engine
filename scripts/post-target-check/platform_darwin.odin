#+build darwin
package main

import sg "../../sokol-odin/sokol/gfx"
import MTL "vendor:darwin/Metal"
import NS "core:sys/darwin/Foundation"

supported :: proc(samples: i32) -> bool {
	device := (^MTL.Device)(sg.mtl_device())
	return bool(device->supportsTextureSampleCount(NS.UInteger(samples)))
}
