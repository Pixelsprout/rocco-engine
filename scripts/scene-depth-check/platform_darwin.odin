#+build darwin
package main

import "core:fmt"

import sg "../../sokol-odin/sokol/gfx"
import MTL "vendor:darwin/Metal"
import NS "core:sys/darwin/Foundation"

supported :: proc(samples: i32) -> bool {
	device := (^MTL.Device)(sg.mtl_device())
	return bool(device->supportsTextureSampleCount(NS.UInteger(samples)))
}

driver_info :: proc() -> Driver_Info { return {backend = fmt.tprintf("%v", sg.query_backend())} }

probe_clip_control :: proc(enabled: bool) { assert(!enabled) }

probe_read_depth :: proc(path: string) {}
