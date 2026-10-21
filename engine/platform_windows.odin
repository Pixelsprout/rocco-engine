#+build windows
package engine

import "core:os"
import win32 "core:sys/windows"
import sg "../sokol-odin/sokol/gfx"
import d3d11 "vendor:directx/d3d11"

EXPECTED_BACKEND :: sg.Backend.D3D11

// The host links with -no-crt, and Odin's no-CRT entry point leaves os.args
// empty. Windows still keeps the command line, so read the words from it.
platform_command_line :: proc(allocator := context.allocator) -> []string {
	if len(os.args) > 0 {
		return os.args
	}
	count: i32
	argv := win32.CommandLineToArgvW(win32.GetCommandLineW(), &count)
	if argv == nil || count <= 0 {
		return nil
	}
	defer win32.LocalFree(argv)
	words := make([]string, count, allocator)
	for &word, i in words {
		w, err := win32.wstring_to_utf8(argv[i], -1, allocator)
		if err != nil {
			return nil
		}
		word = w
	}
	return words
}

// sokol's own colour attachment can already be read back on this backend.
platform_readable_color_texture :: proc(width, height: i32) -> rawptr {
	return nil
}

// The read copies the target into a staging texture that the CPU can map.
// Map waits for the GPU. D3D11 stores the top row first.
platform_read_target :: proc(color: sg.Image, size: [2]i32, rgba: []byte) -> (error: string) {
	source := (^d3d11.ITexture2D)(sg.d3d11_query_image_info(color).tex2d)
	if source == nil {
		return "the target has no D3D11 texture"
	}
	device := (^d3d11.IDevice)(sg.d3d11_device())
	device_context := (^d3d11.IDeviceContext)(sg.d3d11_device_context())
	desc: d3d11.TEXTURE2D_DESC
	source->GetDesc(&desc)
	desc.Usage = .STAGING
	desc.BindFlags = {}
	desc.CPUAccessFlags = {.READ}
	desc.MiscFlags = {}
	staging: ^d3d11.ITexture2D
	if device->CreateTexture2D(&desc, nil, &staging) < 0 {
		return "the host cannot make a staging texture"
	}
	defer staging->Release()
	device_context->CopyResource(staging, source)
	mapped: d3d11.MAPPED_SUBRESOURCE
	if device_context->Map(staging, 0, .READ, {}, &mapped) < 0 {
		return "the host cannot map the staging texture"
	}
	defer device_context->Unmap(staging, 0)
	row := int(size.x) * 4
	pitch := int(mapped.RowPitch)
	src := ([^]byte)(mapped.pData)
	for y in 0 ..< int(size.y) {
		copy(rgba[y * row:][:row], src[y * pitch:][:row])
	}
	return ""
}
