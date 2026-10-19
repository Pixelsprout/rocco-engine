package engine

import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"

// The window swapchain and the pipeline must agree, or sokol rejects the pipeline.
SAMPLE_COUNT :: 4

// Each loaded mesh can own a base colour and a metallic-roughness texture,
// each with its own image, view and sampler. The white image, each sky, the
// shadow map and the font atlas need one more.
TEXTURE_POOL_SIZE :: 2 * MESH_CAPACITY + 1 + SKY_CAPACITY + 1 + 1

// Metal on macOS starts each uniform block on a 256 byte boundary. A Draw
// applies three blocks: shadow, vertex and fragment. The spare blocks cover
// the lights, the sky and the UI.
UNIFORM_ALIGN :: 256
UNIFORM_BUFFER_SIZE :: (3 * DRAW_CAPACITY + 16) * UNIFORM_ALIGN

#assert(size_of(Vs_Params) <= UNIFORM_ALIGN && size_of(Fs_Params) <= UNIFORM_ALIGN && size_of(Shadow_Vs_Params) <= UNIFORM_ALIGN)

SHADOW_MAP_SIZE :: 2048
SHADOW_DEPTH_BIAS :: f32(0)
// Reversed-Z, so a negative bias pushes the stored depth away from the Sun.
SHADOW_SLOPE_BIAS :: f32(-2)

@(rodata)
WHITE_TEXEL := [4]byte{255, 255, 255, 255}

Renderer :: struct {
	pip:         sg.Pipeline,
	sky_pip:     sg.Pipeline,
	shadow_pip:  sg.Pipeline,
	meshes:      Mesh_Table,
	skies:       Sky_Table,
	white:       Mesh_Texture,
	shadow:      Shadow_Map,
	ui:          Ui_Gpu,
	pass_action: sg.Pass_Action,
}

// One layer per shadow view. With no Sun the main pass still binds it, and
// the shader does not read it.
Shadow_Map :: struct {
	image:   sg.Image,
	texture: sg.View,
	layers:  [MAX_CASCADES]sg.View,
	sampler: sg.Sampler,
}

renderer_init :: proc(r: ^Renderer) {
	mesh_table_upload(&r.meshes)
	sky_table_upload(&r.skies)
	r.white = texture_upload(
		{
			levels = {{width = 1, height = 1, pixels = WHITE_TEXEL[:]}},
			sampler = {min_filter = .NEAREST, mag_filter = .NEAREST, mipmap_filter = .NEAREST, wrap_u = .REPEAT, wrap_v = .REPEAT},
		},
	)

	r.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.0, g = 0.0, b = 0.0, a = 1.0}}},
		depth = {load_action = .CLEAR, clear_value = 0.0},
	}
	r.shadow = shadow_map_make()

	shader := sg.make_shader(basic_shader_desc(sg.query_backend()))

	// Reversed-Z: the depth buffer clears to 0 and nearer is greater.
	desc := sg.Pipeline_Desc {
		shader = shader,
		sample_count = SAMPLE_COUNT,
		depth = {compare = .GREATER_EQUAL, write_enabled = true},
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

	// The sky draws the cube primitive from inside, so it reads only the
	// position and culls nothing. It writes no depth and passes at the
	// cleared depth, so it shows only where no mesh drew.
	r.sky_pip = sg.make_pipeline(
		{
			shader = sg.make_shader(sky_shader_desc(sg.query_backend())),
			sample_count = SAMPLE_COUNT,
			depth = {compare = .GREATER_EQUAL},
			index_type = .UINT16,
			cull_mode = .NONE,
			layout = {buffers = {0 = {stride = size_of(Vertex)}}, attrs = {ATTR_sky_pos = {format = .FLOAT3, offset = i32(offset_of(Vertex, pos))}}},
			label = "sky",
		},
	)

	r.shadow_pip = sg.make_pipeline(
		{
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
		},
	)
}

// The sampler compares in hardware, and a fragment is lit where its depth is
// at least the stored depth. LINEAR filters each compare across 2 x 2 texels.
shadow_map_make :: proc() -> Shadow_Map {
	m: Shadow_Map
	m.image = sg.make_image(
		{
			type = .ARRAY,
			usage = {depth_stencil_attachment = true},
			width = SHADOW_MAP_SIZE,
			height = SHADOW_MAP_SIZE,
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

renderer_begin_pass :: proc(ctx: rawptr, pass: Pass, view: int) {
	r := (^Renderer)(ctx)
	switch pass {
	case .Shadow:
		// sokol discards depth at the end of a pass unless told to store it.
		sg.begin_pass({action = {depth = {load_action = .CLEAR, store_action = .STORE, clear_value = 0}}, attachments = {depth_stencil = r.shadow.layers[view]}, label = "shadow"})
		sg.apply_pipeline(r.shadow_pip)
	case .Main:
		sg.begin_pass({action = r.pass_action, swapchain = sglue.swapchain()})
	}
}

renderer_end_pass :: proc(ctx: rawptr) {
	sg.end_pass()
}

renderer_shadow :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params) {
	sg.apply_bindings({vertex_buffers = {0 = mesh.vertices}, index_buffer = mesh.indices})
	vs := vs_params
	sg.apply_uniforms(UB_shadow_vs_params, {ptr = &vs, size = size_of(Shadow_Vs_Params)})
	sg.draw(0, mesh.index_count, 1)
}

// sokol keeps the applied fs_lights until the next apply_pipeline, so renderer_draw must not apply the pipeline.
renderer_lights :: proc(ctx: rawptr, lights: Fs_Lights) {
	r := (^Renderer)(ctx)
	sg.apply_pipeline(r.pip)
	l := lights
	sg.apply_uniforms(UB_fs_lights, {ptr = &l, size = size_of(Fs_Lights)})
}

renderer_draw :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params) {
	r := (^Renderer)(ctx)
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
	sg.apply_pipeline(r.sky_pip)
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
