#+build windows
package main

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
