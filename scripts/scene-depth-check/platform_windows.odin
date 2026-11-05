#+build windows
package main

import "core:fmt"

import sg "../../sokol-odin/sokol/gfx"
import d3d11 "vendor:directx/d3d11"
import dxgi "vendor:directx/dxgi"

supported :: proc(samples: i32) -> bool {
	if samples == 1 { return true }
	device := (^d3d11.IDevice)(sg.d3d11_device())
	for format in ([3]dxgi.FORMAT{.R16G16B16A16_FLOAT, .R8G8B8A8_UNORM, .D32_FLOAT_S8X24_UINT}) {
		count: u32
		if device->CheckMultisampleQualityLevels(format, u32(samples), &count) < 0 || count == 0 { return false }
	}
	return true
}

driver_info :: proc() -> Driver_Info { return {backend = fmt.tprintf("%v", sg.query_backend())} }

probe_clip_control :: proc(enabled: bool) { assert(!enabled) }

probe_read_depth :: proc(path: string) {}
