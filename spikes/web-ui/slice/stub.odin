package engine

import sg "rocco:sokol-odin/sokol/gfx"

// Stand-ins for the renderer parts that ui_render.odin touches. The web UI
// spike draws the UI straight to the swapchain, so the pipeline takes the
// swapchain's colour format.
TARGET_COLOR_FORMAT :: sg.Pixel_Format.DEFAULT

Renderer :: struct {
	ui:     Ui_Gpu,
	images: Image_Table,
}

Image :: struct {
	width:  int,
	height: int,
	view:   sg.View,
}

Image_Table :: struct {
	linear:  sg.Sampler,
	nearest: sg.Sampler,
}

Mesh_Texture :: struct {
	image:   sg.Image,
	view:    sg.View,
	sampler: sg.Sampler,
}

renderer_apply_pipeline :: proc(r: ^Renderer, pip: sg.Pipeline) {
	sg.apply_pipeline(pip)
}

// The spike has no Images, so every Image Panel shows the checker.
image_lookup :: proc(t: ^Image_Table, id: u32) -> (image: ^Image, ok: bool) {
	return nil, false
}

image_resolve :: proc(t: ^Image_Table, id: u32) -> (image: ^Image, ok: bool) {
	return image_lookup(t, id)
}

// A copy of engine/roc_runtime.odin's, which the slice leaves out.
roc_str_string :: proc(s: ^Roc_Str) -> string {
	if int(s.length) < 0 {
		raw := ([^]u8)(s)
		return string(raw[:raw[size_of(Roc_Str) - 1] & 0x7f])
	}
	return string(s.bytes[:s.length])
}

// The glue's Roc_Str and Roc_List helpers call these. The spike builds its
// strings in place, so neither runs.
roc_alloc :: proc "c" (length: uint, alignment: uint) -> rawptr {
	return nil
}

roc_dealloc :: proc "c" (ptr: rawptr, alignment: uint) {
}
