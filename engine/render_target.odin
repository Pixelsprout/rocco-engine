package engine

import sg "../sokol-odin/sokol/gfx"

// The Main pass draws linear colour above 1, so the tone map can roll it off.
HDR_COLOR_FORMAT :: sg.Pixel_Format.RGBA16F
// Every backend can read RGBA8 back to the CPU.
TARGET_COLOR_FORMAT :: sg.Pixel_Format.RGBA8
// The swapchain's depth format, so the depth test gives the same result.
TARGET_DEPTH_FORMAT :: sg.Pixel_Format.DEPTH_STENCIL
// Each of the two Target_Layers has two images. The depth image is the fifth.
TARGET_IMAGES :: 5
// Each Target_Layer adds a texture view to the attachment view of each image.
TARGET_VIEWS :: TARGET_IMAGES + 2

// One pass's colour: the image it resolves into, the MSAA image it draws
// into, a texture view of the resolved image, and the pass attachments. With
// one sample the pass draws into the resolved image and msaa stays empty.
Target_Layer :: struct {
	image:       sg.Image,
	msaa:        sg.Image,
	texture:     sg.View,
	attachments: sg.Attachments,
}

// The colour image has the swapchain's physical size and a readable format,
// so a screenshot can read it back. The Main pass's depth image has the
// sample count of the Launch.
Render_Target :: struct {
	size:        [2]i32,
	samples:     i32,
	hdr:         Target_Layer,
	color:       Target_Layer,
	depth:       sg.Image,
	sampler:     sg.Sampler,
	tone_map:    sg.Pipeline,
	blit:        sg.Pipeline,
	post_action: sg.Pass_Action,
	copy_action: sg.Pass_Action,
}

// Makes no image. render_target_fit makes them at the first Main pass.
render_target_init :: proc(t: ^Render_Target, samples: i32) {
	t.samples = samples
	t.sampler = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "target"})
	// The tone map and the copy each cover every pixel, so nothing needs a clear.
	t.post_action = {colors = {0 = {load_action = .DONTCARE}}}
	t.copy_action = {colors = {0 = {load_action = .DONTCARE}}, depth = {load_action = .DONTCARE}, stencil = {load_action = .DONTCARE}}
	t.tone_map = sg.make_pipeline(
		{
			shader = sg.make_shader(tone_map_shader_desc(sg.query_backend())),
			sample_count = samples,
			colors = {0 = {pixel_format = TARGET_COLOR_FORMAT}},
			depth = {pixel_format = .NONE},
			cull_mode = .NONE,
			label = "tone-map",
		},
	)
	// The swapchain has one sample. Its formats are the pipeline defaults.
	t.blit = sg.make_pipeline(
		{
			shader = sg.make_shader(blit_shader_desc(sg.query_backend())),
			sample_count = 1,
			depth = {compare = .ALWAYS},
			cull_mode = .NONE,
			label = "blit",
		},
	)
}

// Remakes the images when the swapchain changes size, such as on a window
// resize, so the copy stays one texel per pixel.
render_target_fit :: proc(t: ^Render_Target, size: [2]i32) {
	if size == t.size || size.x <= 0 || size.y <= 0 {
		return
	}
	render_target_destroy(t)
	t.size = size
	t.hdr = target_layer_make(size, t.samples, HDR_COLOR_FORMAT, "target-hdr", "target-hdr-msaa")
	t.color = target_layer_make(size, t.samples, TARGET_COLOR_FORMAT, "target-color", "target-msaa", platform_readable_color_texture(size.x, size.y))
	t.depth = sg.make_image({usage = {depth_stencil_attachment = true}, width = size.x, height = size.y, pixel_format = TARGET_DEPTH_FORMAT, sample_count = t.samples, label = "target-depth"})
	t.hdr.attachments.depth_stencil = sg.make_view({depth_stencil_attachment = {image = t.depth}})
}

// mtl_texture is a Metal texture that sokol takes for the resolved image, or nil.
target_layer_make :: proc(size: [2]i32, samples: i32, format: sg.Pixel_Format, label, msaa_label: cstring, mtl_texture: rawptr = nil) -> (l: Target_Layer) {
	msaa := samples > 1
	desc := sg.Image_Desc {
		usage        = {resolve_attachment = msaa, color_attachment = !msaa},
		width        = size.x,
		height       = size.y,
		pixel_format = format,
		sample_count = 1,
		label        = label,
	}
	desc.mtl_textures[0] = mtl_texture
	l.image = sg.make_image(desc)
	l.texture = sg.make_view({texture = {image = l.image}})
	if msaa {
		l.msaa = sg.make_image({usage = {color_attachment = true}, width = size.x, height = size.y, pixel_format = format, sample_count = samples, label = msaa_label})
		l.attachments.colors[0] = sg.make_view({color_attachment = {image = l.msaa}})
		l.attachments.resolves[0] = sg.make_view({resolve_attachment = {image = l.image}})
	} else {
		l.attachments.colors[0] = sg.make_view({color_attachment = {image = l.image}})
	}
	return
}

// Must run outside a pass. Leaves the Post pass open for the UI.
render_target_begin_post :: proc(t: ^Render_Target) {
	sg.begin_pass({action = t.post_action, attachments = t.color.attachments, label = "post"})
	sg.apply_pipeline(t.tone_map)
	sg.apply_bindings({views = {VIEW_hdr_tex = t.hdr.texture}, samplers = {SMP_hdr_smp = t.sampler}})
	sg.draw(0, 3, 1)
}

// Must run outside a pass.
render_target_copy :: proc(t: ^Render_Target, swapchain: sg.Swapchain) {
	sg.begin_pass({action = t.copy_action, swapchain = swapchain, label = "blit"})
	sg.apply_pipeline(t.blit)
	sg.apply_bindings({views = {VIEW_blit_tex = t.color.texture}, samplers = {SMP_blit_smp = t.sampler}})
	sg.draw(0, 3, 1)
	sg.end_pass()
}

// Destroys the images and their views. sokol skips an invalid id, so this
// is safe before the first fit. sg.shutdown destroys the rest.
render_target_destroy :: proc(t: ^Render_Target) {
	target_layer_destroy(&t.hdr)
	target_layer_destroy(&t.color)
	sg.destroy_image(t.depth)
	t.depth = {}
	t.size = {}
}

// Also destroys a depth view in the attachments.
target_layer_destroy :: proc(l: ^Target_Layer) {
	sg.destroy_view(l.attachments.colors[0])
	sg.destroy_view(l.attachments.resolves[0])
	sg.destroy_view(l.attachments.depth_stencil)
	sg.destroy_view(l.texture)
	sg.destroy_image(l.msaa)
	sg.destroy_image(l.image)
	l^ = {}
}
