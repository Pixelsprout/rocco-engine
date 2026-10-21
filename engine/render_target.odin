package engine

import sg "../sokol-odin/sokol/gfx"

// Every backend can read RGBA8 back to the CPU.
TARGET_COLOR_FORMAT :: sg.Pixel_Format.RGBA8
// The swapchain's depth format, so the depth test gives the same result.
TARGET_DEPTH_FORMAT :: sg.Pixel_Format.DEPTH_STENCIL
// An MSAA colour image, the colour image it resolves into, and a depth image.
TARGET_IMAGES :: 3
// The colour image has an attachment view and a texture view.
TARGET_VIEWS :: TARGET_IMAGES + 1

// The Main pass draws into the target, then a copy pass writes the colour
// image to the swapchain. The colour image has the swapchain's physical size,
// one sample and a readable format, so a screenshot can read it back. With
// one sample the Main pass draws into it directly and msaa stays empty.
Render_Target :: struct {
	size:        [2]i32,
	samples:     i32,
	color:       sg.Image,
	msaa:        sg.Image,
	depth:       sg.Image,
	attachments: sg.Attachments,
	texture:     sg.View,
	sampler:     sg.Sampler,
	pip:         sg.Pipeline,
	copy_action: sg.Pass_Action,
}

// Makes no image. render_target_fit makes them at the first Main pass.
render_target_init :: proc(t: ^Render_Target, samples: i32) {
	t.samples = samples
	t.sampler = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "target"})
	// The copy covers every swapchain pixel, so nothing needs a clear.
	t.copy_action = {colors = {0 = {load_action = .DONTCARE}}, depth = {load_action = .DONTCARE}, stencil = {load_action = .DONTCARE}}
	// The swapchain has one sample. Its formats are the pipeline defaults.
	t.pip = sg.make_pipeline(
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
	msaa := t.samples > 1

	color_desc := sg.Image_Desc {
		usage        = {resolve_attachment = msaa, color_attachment = !msaa},
		width        = size.x,
		height       = size.y,
		pixel_format = TARGET_COLOR_FORMAT,
		sample_count = 1,
		label        = "target-color",
	}
	color_desc.mtl_textures[0] = platform_readable_color_texture(size.x, size.y)
	t.color = sg.make_image(color_desc)
	t.texture = sg.make_view({texture = {image = t.color}})
	t.depth = sg.make_image({usage = {depth_stencil_attachment = true}, width = size.x, height = size.y, pixel_format = TARGET_DEPTH_FORMAT, sample_count = t.samples, label = "target-depth"})
	t.attachments = {depth_stencil = sg.make_view({depth_stencil_attachment = {image = t.depth}})}
	if msaa {
		t.msaa = sg.make_image({usage = {color_attachment = true}, width = size.x, height = size.y, pixel_format = TARGET_COLOR_FORMAT, sample_count = t.samples, label = "target-msaa"})
		t.attachments.colors[0] = sg.make_view({color_attachment = {image = t.msaa}})
		t.attachments.resolves[0] = sg.make_view({resolve_attachment = {image = t.color}})
	} else {
		t.attachments.colors[0] = sg.make_view({color_attachment = {image = t.color}})
	}
}

// Must run outside a pass.
render_target_copy :: proc(t: ^Render_Target, swapchain: sg.Swapchain) {
	sg.begin_pass({action = t.copy_action, swapchain = swapchain, label = "blit"})
	sg.apply_pipeline(t.pip)
	sg.apply_bindings({views = {VIEW_blit_tex = t.texture}, samplers = {SMP_blit_smp = t.sampler}})
	sg.draw(0, 3, 1)
	sg.end_pass()
}

// Destroys the images and their views. sokol skips an invalid id, so this
// is safe before the first fit. sg.shutdown destroys the rest.
render_target_destroy :: proc(t: ^Render_Target) {
	sg.destroy_view(t.attachments.colors[0])
	sg.destroy_view(t.attachments.resolves[0])
	sg.destroy_view(t.attachments.depth_stencil)
	sg.destroy_view(t.texture)
	sg.destroy_image(t.msaa)
	sg.destroy_image(t.color)
	sg.destroy_image(t.depth)
	t.attachments = {}
	t.texture = {}
	t.msaa = {}
	t.color = {}
	t.depth = {}
	t.size = {}
}
