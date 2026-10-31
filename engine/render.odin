package engine

import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"

// Metal on macOS starts each uniform block on a 256 byte boundary.
UNIFORM_ALIGN :: 256
// The uniform buffer holds skin blocks for at most this many skinned Draws
// per Frame. The host drops the rest.
SKINNED_DRAW_LIMIT :: 256
// sokol takes the uniform buffer size as a C int, so uniform_buffer_size must fit one.
DRAW_LIMIT :: ((1 << 31 - 1) / UNIFORM_ALIGN - 16 - 2 * SKINNED_DRAW_LIMIT * size_of(Skin_Params) / UNIFORM_ALIGN) / 3

#assert(size_of(Vs_Params) <= UNIFORM_ALIGN && size_of(Fs_Params) <= UNIFORM_ALIGN && size_of(Shadow_Vs_Params) <= UNIFORM_ALIGN)
// The skin block is the one block above UNIFORM_ALIGN.
#assert(size_of(Skin_Params) % UNIFORM_ALIGN == 0)

SHADOW_DEPTH_BIAS :: f32(0)
// Reversed-Z, so a negative bias pushes the stored depth away from the Sun.
SHADOW_SLOPE_BIAS :: f32(-2)

@(rodata)
WHITE_TEXEL := [4]byte{255, 255, 255, 255}

Renderer :: struct {
	pip:                sg.Pipeline,
	skinned_pip:        sg.Pipeline,
	sky_pip:            sg.Pipeline,
	shadow_pip:         sg.Pipeline,
	skinned_shadow_pip: sg.Pipeline,
	// The pipeline the pass applied last. sokol drops the applied
	// fs_lights at each apply_pipeline, so the Main pass keeps them to apply
	// again.
	applied:            sg.Pipeline,
	lights:             Fs_Lights,
	meshes:             Mesh_Table,
	skies:              Sky_Table,
	white:              Mesh_Texture,
	shadow:             Shadow_Map,
	ui:                 Ui_Gpu,
	target:             Render_Target,
	// Taken when the Main pass begins, where the wait for the drawable is
	// outside the render Span. The copy pass after it reuses it.
	swapchain:          sg.Swapchain,
	pass:               Pass,
}

// One layer per shadow view. With no Sun the main pass still binds it, and
// the shader does not read it.
Shadow_Map :: struct {
	image:   sg.Image,
	texture: sg.View,
	layers:  [MAX_CASCADES]sg.View,
	sampler: sg.Sampler,
}

// Each loaded mesh can own a base colour and a metallic-roughness texture,
// each with its own image, view and sampler. The white image, each sky, the
// shadow map and the font atlas need one more. The render target adds its
// images.
texture_pool_size :: proc(capacity: Capacity) -> i32 {
	return i32(2 * capacity.meshes + 1 + capacity.skies + 1 + 1 + TARGET_IMAGES)
}

// The shadow map adds one depth view per cascade to its texture view, and
// the target's colour image has two views.
view_pool_size :: proc(capacity: Capacity) -> i32 {
	return texture_pool_size(capacity) + MAX_CASCADES + TARGET_VIEWS - TARGET_IMAGES
}

// A Draw applies three blocks: shadow, vertex and fragment. A skinned Draw
// also applies a skin block in each pass. The spare blocks cover the lights,
// the lights again after the switch to the skinned pipeline, the sky and the
// UI.
uniform_buffer_size :: proc(capacity: Capacity) -> i32 {
	skins := 2 * skinned_draw_capacity(int(capacity.draws)) * size_of(Skin_Params)
	return i32((3 * int(capacity.draws) + 16) * UNIFORM_ALIGN + skins)
}

skinned_draw_capacity :: proc(draws: int) -> int {
	return min(draws, SKINNED_DRAW_LIMIT)
}

// The render target and the pipelines that draw into it must agree on the
// sample count and the formats, or sokol rejects the pipelines. The sample
// count comes from the Launch.
renderer_init :: proc(r: ^Renderer, launch: Launch) {
	sample_count := msaa_sample_count(launch.window.samples)
	render_target_init(&r.target, sample_count)
	mesh_table_upload(&r.meshes)
	sky_table_upload(&r.skies)
	r.white = texture_upload(
		{
			levels = {{width = 1, height = 1, pixels = WHITE_TEXEL[:]}},
			sampler = {min_filter = .NEAREST, mag_filter = .NEAREST, mipmap_filter = .NEAREST, wrap_u = .REPEAT, wrap_v = .REPEAT},
		},
	)

	r.shadow = shadow_map_make(launch.shadow_map)

	shader := sg.make_shader(basic_shader_desc(sg.query_backend()))

	// Reversed-Z: the depth buffer clears to 0 and nearer is greater.
	desc := sg.Pipeline_Desc {
		shader = shader,
		sample_count = sample_count,
		colors = {0 = {pixel_format = TARGET_COLOR_FORMAT}},
		depth = {pixel_format = TARGET_DEPTH_FORMAT, compare = .GREATER_EQUAL, write_enabled = true},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CCW,
		layout = {
			attrs = {
				ATTR_basic_pos = {format = sg.Vertex_Format.FLOAT3},
				ATTR_basic_col = {format = sg.Vertex_Format.FLOAT4},
				ATTR_basic_nrm = {format = sg.Vertex_Format.FLOAT3},
				ATTR_basic_uv = {format = sg.Vertex_Format.FLOAT2},
			},
		},
	}
	r.pip = sg.make_pipeline(desc)

	skinned := desc
	skinned.shader = sg.make_shader(skinned_shader_desc(sg.query_backend()))
	skinned.layout = {
		buffers = {0 = {stride = size_of(Skinned_Vertex)}},
		attrs = {
			ATTR_skinned_pos = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, pos))},
			ATTR_skinned_col = {format = .FLOAT4, offset = i32(offset_of(Skinned_Vertex, color))},
			ATTR_skinned_nrm = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, normal))},
			ATTR_skinned_uv = {format = .FLOAT2, offset = i32(offset_of(Skinned_Vertex, uv))},
			ATTR_skinned_joint_ids = {format = .UBYTE4, offset = i32(offset_of(Skinned_Vertex, joints))},
			ATTR_skinned_joint_weights = {format = .UBYTE4N, offset = i32(offset_of(Skinned_Vertex, weights))},
		},
	}
	skinned.label = "skinned"
	r.skinned_pip = sg.make_pipeline(skinned)

	// The sky draws the cube primitive from inside, so it reads only the
	// position and culls nothing. It writes no depth and passes at the
	// cleared depth, so it shows only where no mesh drew.
	r.sky_pip = sg.make_pipeline(
		{
			shader = sg.make_shader(sky_shader_desc(sg.query_backend())),
			sample_count = sample_count,
			colors = {0 = {pixel_format = TARGET_COLOR_FORMAT}},
			depth = {pixel_format = TARGET_DEPTH_FORMAT, compare = .GREATER_EQUAL},
			index_type = .UINT16,
			cull_mode = .NONE,
			layout = {buffers = {0 = {stride = size_of(Vertex)}}, attrs = {ATTR_sky_pos = {format = .FLOAT3, offset = i32(offset_of(Vertex, pos))}}},
			label = "sky",
		},
	)

	shadow := sg.Pipeline_Desc {
		shader = sg.make_shader(shadow_shader_desc(sg.query_backend())),
		sample_count = 1,
		// A NONE colour format is how sokol marks a depth-only pipeline.
		colors = {0 = {pixel_format = .NONE}},
		depth = {
			pixel_format = .DEPTH,
			compare = .GREATER_EQUAL,
			write_enabled = true,
			bias = SHADOW_DEPTH_BIAS,
			bias_slope_scale = SHADOW_SLOPE_BIAS,
		},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CCW,
		layout = {buffers = {0 = {stride = size_of(Vertex)}}, attrs = {ATTR_shadow_pos = {format = .FLOAT3, offset = i32(offset_of(Vertex, pos))}}},
		label = "shadow",
	}
	r.shadow_pip = sg.make_pipeline(shadow)

	skinned_shadow := shadow
	skinned_shadow.shader = sg.make_shader(skinned_shadow_shader_desc(sg.query_backend()))
	skinned_shadow.layout = {
		buffers = {0 = {stride = size_of(Skinned_Vertex)}},
		attrs = {
			ATTR_skinned_shadow_pos = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, pos))},
			ATTR_skinned_shadow_joint_ids = {format = .UBYTE4, offset = i32(offset_of(Skinned_Vertex, joints))},
			ATTR_skinned_shadow_joint_weights = {format = .UBYTE4N, offset = i32(offset_of(Skinned_Vertex, weights))},
		},
	}
	skinned_shadow.label = "skinned-shadow"
	r.skinned_shadow_pip = sg.make_pipeline(skinned_shadow)
}

// The sampler compares in hardware, and a fragment is lit where its depth is
// at least the stored depth. LINEAR filters each compare across 2 x 2 texels.
shadow_map_make :: proc(size: u32) -> Shadow_Map {
	m: Shadow_Map
	m.image = sg.make_image(
		{
			type = .ARRAY,
			usage = {depth_stencil_attachment = true},
			width = i32(size),
			height = i32(size),
			num_slices = MAX_CASCADES,
			pixel_format = .DEPTH,
			sample_count = 1,
			label = "shadow-map",
		},
	)
	m.texture = sg.make_view({texture = {image = m.image}})
	for &layer, i in m.layers {
		layer = sg.make_view({depth_stencil_attachment = {image = m.image, slice = i32(i)}})
	}
	m.sampler = sg.make_sampler(
		{
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u = .CLAMP_TO_EDGE,
			wrap_v = .CLAMP_TO_EDGE,
			compare = .GREATER_EQUAL,
			label = "shadow",
		},
	)
	return m
}

renderer_begin_pass :: proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb) {
	r := (^Renderer)(ctx)
	r.pass = pass
	switch pass {
	case .Shadow:
		// sokol discards depth at the end of a pass unless told to store it.
		sg.begin_pass({action = {depth = {load_action = .CLEAR, store_action = .STORE, clear_value = 0}}, attachments = {depth_stencil = r.shadow.layers[view]}, label = "shadow"})
		renderer_apply_pipeline(r, r.shadow_pip)
	case .Main:
		r.applied = {}
		r.swapchain = sglue.swapchain()
		render_target_fit(&r.target, {r.swapchain.width, r.swapchain.height})
		sg.begin_pass({action = main_pass_action(clear_colour), attachments = r.target.attachments, label = "main"})
	}
}

// A pass clear skips the shader, so the clear colour is encoded to sRGB here.
main_pass_action :: proc(clear_colour: Rgb) -> sg.Pass_Action {
	return {
		colors = {
			0 = {
				load_action = .CLEAR,
				clear_value = {
					r = linear_to_srgb(clamp(clear_colour.r, 0, 1)),
					g = linear_to_srgb(clamp(clear_colour.g, 0, 1)),
					b = linear_to_srgb(clamp(clear_colour.b, 0, 1)),
					a = 1,
				},
			},
		},
		depth = {load_action = .CLEAR, clear_value = 0},
	}
}

renderer_end_pass :: proc(ctx: rawptr) {
	r := (^Renderer)(ctx)
	sg.end_pass()
	if r.pass == .Main {
		render_target_copy(&r.target, r.swapchain)
	}
}

// A nil skin draws a rigid mesh.
renderer_shadow :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {
	r := (^Renderer)(ctx)
	renderer_apply_skin(r, r.shadow_pip, r.skinned_shadow_pip, skin)
	sg.apply_bindings({vertex_buffers = {0 = mesh.vertices}, index_buffer = mesh.indices})
	vs := vs_params
	sg.apply_uniforms(UB_shadow_vs_params, {ptr = &vs, size = size_of(Shadow_Vs_Params)})
	sg.draw(0, mesh.index_count, 1)
}

renderer_lights :: proc(ctx: rawptr, lights: Fs_Lights) {
	r := (^Renderer)(ctx)
	r.lights = lights
	renderer_apply_pipeline(r, r.pip)
}

// Every apply_pipeline of the Shadow and Main passes goes through here, so
// r.applied stays true.
// sokol drops the applied fs_lights at each apply_pipeline, so the Main
// pass applies them again after a change to a mesh pipeline.
renderer_apply_pipeline :: proc(r: ^Renderer, pip: sg.Pipeline) {
	sg.apply_pipeline(pip)
	r.applied = pip
	if pip == r.pip || pip == r.skinned_pip {
		sg.apply_uniforms(UB_fs_lights, {ptr = &r.lights, size = size_of(Fs_Lights)})
	}
}

// Changes to the rigid or the skinned pipeline of the pass when the Draw
// needs the other one, then applies the skin block of a skinned Draw.
@(private = "file")
renderer_apply_skin :: proc(r: ^Renderer, rigid, skinned: sg.Pipeline, skin: ^Skin_Params) {
	pip := skinned if skin != nil else rigid
	if r.applied != pip {
		renderer_apply_pipeline(r, pip)
	}
	if skin != nil {
		sg.apply_uniforms(UB_skin_params, {ptr = skin, size = size_of(Skin_Params)})
	}
}

// A nil skin draws a rigid mesh. Each change between the rigid and the
// skinned pipeline applies the lights again, so the uniform buffer has room
// for one change per Frame.
renderer_draw :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
	r := (^Renderer)(ctx)
	renderer_apply_skin(r, r.pip, r.skinned_pip, skin)
	base, metallic_roughness := mesh_textures(mesh, r.white)
	sg.apply_bindings(
		{
			vertex_buffers = {0 = mesh.vertices},
			index_buffer = mesh.indices,
			views = {VIEW_base_tex = base.view, VIEW_metallic_roughness_tex = metallic_roughness.view, VIEW_shadow_tex = r.shadow.texture},
			samplers = {SMP_base_smp = base.sampler, SMP_metallic_roughness_smp = metallic_roughness.sampler, SMP_shadow_smp = r.shadow.sampler},
		},
	)

	vs := vs_params
	fs := fs_params
	sg.apply_uniforms(UB_vs_params, {ptr = &vs, size = size_of(Vs_Params)})
	sg.apply_uniforms(UB_fs_params, {ptr = &fs, size = size_of(Fs_Params)})

	sg.draw(0, mesh.index_count, 1)
}

// Applies the sky pipeline, so it must follow every renderer_draw of the frame.
renderer_sky :: proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {
	r := (^Renderer)(ctx)
	cube := &r.meshes.meshes[Primitive.Cube]
	renderer_apply_pipeline(r, r.sky_pip)
	sg.apply_bindings(
		{
			vertex_buffers = {0 = cube.vertices},
			index_buffer = cube.indices,
			views = {VIEW_sky_tex = sky.texture.view},
			samplers = {SMP_sky_smp = sky.texture.sampler},
		},
	)
	vs := vs_params
	sg.apply_uniforms(UB_sky_vs_params, {ptr = &vs, size = size_of(Sky_Vs_Params)})
	sg.draw(0, cube.index_count, 1)
}

renderer_shutdown :: proc(r: ^Renderer) {
	// sg.shutdown destroys every pooled resource, later we would add a per mesh teardown.
	mesh_table_destroy(&r.meshes)
	sky_table_destroy(&r.skies)
}
