package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"

// Metal on macOS starts each uniform block on a 256 byte boundary.
UNIFORM_ALIGN :: 256
// The uniform buffer holds skin blocks for at most this many skinned Draws
// per Frame. The host drops the rest.
SKINNED_DRAW_LIMIT :: 256
// sokol on Metal starts each block on a UNIFORM_ALIGN boundary, so a block takes whole slots.
SHADOW_UNIFORM_SLOTS :: (size_of(Shadow_Vs_Params) + UNIFORM_ALIGN - 1) / UNIFORM_ALIGN
MAIN_UNIFORM_SLOTS :: (size_of(Vs_Params) + UNIFORM_ALIGN - 1) / UNIFORM_ALIGN + (size_of(Fs_Params) + UNIFORM_ALIGN - 1) / UNIFORM_ALIGN
LIGHTS_UNIFORM_SLOTS :: (size_of(Fs_Lights) + UNIFORM_ALIGN - 1) / UNIFORM_ALIGN
// The slots outside the Draws: the lights once per pipeline before the sky,
// the sky, the bloom, the tone map, the UI and two blocks per particle source.
UNIFORM_SPARE_SLOTS :: 21 + 2 * EMITTER_LIMIT + POST_UNIFORM_SLOTS
// The Prefilter and each Up apply a block. A Down applies none.
BLOOM_UNIFORM_SLOTS :: BLOOM_MIP_LIMIT
// sokol takes the uniform buffer size as a C int, so uniform_buffer_size must
// fit one. The limit takes MAX_CASCADES for every game.
DRAW_LIMIT ::
	((1 << 31 - 1) / UNIFORM_ALIGN - UNIFORM_SPARE_SLOTS - (3 + MAX_CASCADES) * SKINNED_DRAW_LIMIT * size_of(Skin_Params) / UNIFORM_ALIGN) /
	(14 + MAX_CASCADES * 4)

#assert(size_of(Vs_Params) <= UNIFORM_ALIGN && size_of(Shadow_Vs_Params) <= UNIFORM_ALIGN && size_of(Fs_Params) <= 128 && size_of(Fs_Lights) <= 512)
// The 3 is one block each for the sky, the tone map and the UI.
#assert(2 * len(SCENE_ORDER_PIPELINES) * LIGHTS_UNIFORM_SLOTS + 3 + BLOOM_UNIFORM_SLOTS <= UNIFORM_SPARE_SLOTS)
// The skin block is the one block above UNIFORM_ALIGN.
#assert(size_of(Skin_Params) % UNIFORM_ALIGN == 0)
#assert(sg.NUM_INFLIGHT_FRAMES == 2)

SHADOW_DEPTH_BIAS :: f32(0)
// Reversed-Z, so a negative bias pushes the stored depth away from the Sun.
SHADOW_SLOPE_BIAS :: f32(-2)

@(rodata)
WHITE_TEXEL := [4]byte{255, 255, 255, 255}
// A tangent-space normal of about (0, 0, 1). Material.normal_scale is 0 with it.
@(rodata)
FLAT_NORMAL_TEXEL := [4]byte{128, 128, 255, 255}

// The shaders of the Mesh_Pipelines other than Opaque, which takes the
// shader of its Pipeline_Desc.
Mesh_Shaders :: struct {
	mask:  sg.Shader,
	blend: sg.Shader,
}

Renderer :: struct {
	depth_pips, skinned_depth_pips: [Mesh_Pipeline]sg.Pipeline,
	pips:               [Mesh_Pipeline]sg.Pipeline,
	instanced_pips, instanced_shadow_pips, instanced_depth_pips: [Mesh_Pipeline]sg.Pipeline,
	instance_buffer: sg.Buffer,
	instance_offset, instance_count: int,
	skinned_pips:       [Mesh_Pipeline]sg.Pipeline,
	sky_pip:            sg.Pipeline,
	shadow_pips:        [Mesh_Pipeline]sg.Pipeline,
	skinned_shadow_pips: [Mesh_Pipeline]sg.Pipeline,
	// The pipeline the pass applied last. sokol drops the applied
	// fs_lights at each apply_pipeline, so the Main pass keeps them to apply
	// again.
	applied:            sg.Pipeline,
	// The skin block applied since that pipeline. The parts of one Draw
	// share it, so the uniform buffer holds one skin block per Draw.
	applied_skin:       ^Skin_Params,
	lights:             Fs_Lights,
	cluster_buffers:    [3]sg.Buffer,
	cluster_views:      [3]sg.View,
	applied_bindings:   sg.Bindings,
	applied_material:   Fs_Params,
	has_bindings:       bool,
	has_material:       bool,
	meshes:             Mesh_Table,
	shaders: ^Shader_Table,
	skies:              Sky_Table,
	images:             Image_Table,
	white:              Mesh_Texture,
	flat_normal:        Mesh_Texture,
	black_cube:         Mesh_Texture,
	environment:        Environment_Light,
	sky_blend:          Sky_Blend_Target,
	shadow:             Shadow_Map,
	ui:                 Ui_Gpu,
	particles:          Particle_Gpu,
	target:             Render_Target,
	// Taken when the Main pass begins, where the wait for the drawable is
	// outside the render Span. The copy pass after the Post pass reuses it.
	swapchain:          sg.Swapchain,
	pass:               Pass,
}

// One layer per cascade. With no Sun the main pass still binds it, and
// the shader does not read it.
Shadow_Map :: struct {
	image:   sg.Image,
	texture: sg.View,
	layers:  [MAX_CASCADES]sg.View,
	sampler: sg.Sampler,
}

// Each loaded mesh can own MESH_TEXTURE_LIMIT textures, each with its own
// image, view and sampler. The white image, the flat normal image, each sky,
// each Image, the shadow map, the font atlas and the UI's checker need one
// more. Each Sky adds two lighting cubes. Missing skies share one black cube.
// The Images add their Linear and Nearest samplers.
// The render target adds its images.
texture_pool_size :: proc(capacity: Capacity) -> i32 {
	return i32(2 * MESH_TEXTURE_LIMIT * capacity.meshes + 2 + 4 * capacity.skies + 1 + 2 * capacity.images + 2 + 1 + 1 + 1 + TARGET_IMAGES + SHADER_ASSET_LIMIT * SHADER_TEXTURE_LIMIT)
}

// The shadow map adds one depth view per cascade to its texture view, and
// the render target adds its views.
view_pool_size :: proc(capacity: Capacity) -> i32 {
	return texture_pool_size(capacity) + MAX_CASCADES + TARGET_VIEWS - TARGET_IMAGES + 3
}

// Each part reserves Colour, scene depth, Selection, and shadow uniforms.
// Each skinned part also reserves a palette for each pass.
uniform_buffer_size :: proc(capacity: Capacity, cascades: int) -> i32 {
	skins := (3 + cascades) * skinned_draw_capacity(int(capacity.draws)) * size_of(Skin_Params)
	slots := 14 + cascades * 4
	return i32((slots * int(capacity.draws) + UNIFORM_SPARE_SLOTS) * UNIFORM_ALIGN + skins)
}

skinned_draw_capacity :: proc(draws: int) -> int {
	return min(draws, SKINNED_DRAW_LIMIT)
}

// The render target and the pipelines that draw into it must agree on the
// sample count and the formats, or sokol rejects the pipelines. The sample
// count comes from the Launch.
renderer_init :: proc(r: ^Renderer, launch: Launch) {
	cluster_sizes := [3]uint{MAX_POINT_LIGHTS * size_of(Packed_Light), CLUSTER_COUNT * size_of(Cluster_Range), CLUSTER_INDEX_LIMIT * size_of(u32)}
	for size, i in cluster_sizes {
		r.cluster_buffers[i] = sg.make_buffer({size = size, usage = {storage_buffer = true, stream_update = true}})
		r.cluster_views[i] = sg.make_view({storage_buffer = {buffer = r.cluster_buffers[i]}})
	}
	sample_count := msaa_sample_count(launch.window.samples)
	render_target_init(&r.target, sample_count)
	particle_gpu_init(&r.particles, sample_count)
	r.instance_buffer = sg.make_buffer({size = instance_buffer_size(int(launch.capacity.draws), int(launch.shadow_cascades)), usage = {vertex_buffer = true, stream_update = true}})
	mesh_table_upload(&r.meshes)
	if r.shaders != nil { shader_table_upload(r.shaders, sample_count) }
	sky_table_upload(&r.skies)
	image_table_upload(&r.images)
	texel_sampler := Texture_Sampler {
		min_filter    = .NEAREST,
		mag_filter    = .NEAREST,
		mipmap_filter = .NEAREST,
		wrap_u        = .REPEAT,
		wrap_v        = .REPEAT,
	}
	r.white = texture_upload({levels = {{width = 1, height = 1, pixels = WHITE_TEXEL[:]}}, sampler = texel_sampler})
	r.flat_normal = texture_upload({levels = {{width = 1, height = 1, pixels = FLAT_NORMAL_TEXEL[:]}}, sampler = texel_sampler})

	black := sky_lighting_texture(1, false, context.allocator)
	r.black_cube = sky_lighting_upload(black, context.allocator)
	r.environment = {diffuse = r.black_cube, specular = r.black_cube}

	r.shadow = shadow_map_make(launch.shadow_map, int(launch.shadow_cascades))

	shader := sg.make_shader(basic_shader_desc(sg.query_backend()))

	// Reversed-Z: the depth buffer clears to 0 and nearer is greater.
	desc := sg.Pipeline_Desc {
		shader = shader,
		sample_count = sample_count,
		colors = {0 = {pixel_format = HDR_COLOR_FORMAT}},
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
				ATTR_basic_tng = {format = sg.Vertex_Format.FLOAT4},
			},
		},
	}
	desc.label = "mesh"
	renderer_instances_init(r, desc)
	r.pips = mesh_pipelines(desc, {mask = sg.make_shader(mask_shader_desc(sg.query_backend())), blend = sg.make_shader(blend_shader_desc(sg.query_backend()))})

	skinned := desc
	skinned.shader = sg.make_shader(skinned_shader_desc(sg.query_backend()))
	skinned.layout = {
		buffers = {0 = {stride = size_of(Skinned_Vertex)}},
		attrs = {
			ATTR_skinned_pos = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, pos))},
			ATTR_skinned_col = {format = .FLOAT4, offset = i32(offset_of(Skinned_Vertex, color))},
			ATTR_skinned_nrm = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, normal))},
			ATTR_skinned_uv = {format = .FLOAT2, offset = i32(offset_of(Skinned_Vertex, uv))},
			ATTR_skinned_tng = {format = .FLOAT4, offset = i32(offset_of(Skinned_Vertex, tangent))},
			ATTR_skinned_joint_ids = {format = .UBYTE4, offset = i32(offset_of(Skinned_Vertex, joints))},
			ATTR_skinned_joint_weights = {format = .UBYTE4N, offset = i32(offset_of(Skinned_Vertex, weights))},
		},
	}
	skinned.label = "skinned"
	r.skinned_pips = mesh_pipelines(skinned, {mask = sg.make_shader(skinned_mask_shader_desc(sg.query_backend())), blend = sg.make_shader(skinned_blend_shader_desc(sg.query_backend()))})

	// The sky draws the cube primitive from inside, so it reads only the
	// position and culls nothing. It writes no depth and passes at the
	// cleared depth, so it shows only where no mesh drew.
	r.sky_pip = sg.make_pipeline(
		{
			shader = sg.make_shader(sky_shader_desc(sg.query_backend())),
			sample_count = sample_count,
			colors = {0 = {pixel_format = HDR_COLOR_FORMAT}},
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
	r.shadow_pips[.Opaque] = sg.make_pipeline(shadow)

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
	r.skinned_shadow_pips[.Opaque] = sg.make_pipeline(skinned_shadow)

	mask_shadow := shadow
	mask_shadow.shader = sg.make_shader(shadow_mask_shader_desc(sg.query_backend()))
	mask_shadow.layout = {
		buffers = {0 = {stride = size_of(Vertex)}},
		attrs = {
			ATTR_shadow_mask_pos = {format = .FLOAT3, offset = i32(offset_of(Vertex, pos))},
			ATTR_shadow_mask_col = {format = .FLOAT4, offset = i32(offset_of(Vertex, color))},
			ATTR_shadow_mask_uv = {format = .FLOAT2, offset = i32(offset_of(Vertex, uv))},
		},
	}
	mask_shadow.label = "shadow-mask"
	skinned_mask_shadow := mask_shadow
	skinned_mask_shadow.shader = sg.make_shader(skinned_shadow_mask_shader_desc(sg.query_backend()))
	skinned_mask_shadow.layout = {
		buffers = {0 = {stride = size_of(Skinned_Vertex)}},
		attrs = {
			ATTR_skinned_shadow_mask_pos = {format = .FLOAT3, offset = i32(offset_of(Skinned_Vertex, pos))},
			ATTR_skinned_shadow_mask_col = {format = .FLOAT4, offset = i32(offset_of(Skinned_Vertex, color))},
			ATTR_skinned_shadow_mask_uv = {format = .FLOAT2, offset = i32(offset_of(Skinned_Vertex, uv))},
			ATTR_skinned_shadow_mask_joint_ids = {format = .UBYTE4, offset = i32(offset_of(Skinned_Vertex, joints))},
			ATTR_skinned_shadow_mask_joint_weights = {format = .UBYTE4N, offset = i32(offset_of(Skinned_Vertex, weights))},
		},
	}
	skinned_mask_shadow.label = "skinned-shadow-mask"
 coverage := mask_shadow
 coverage.shader = sg.make_shader(coverage_shader_desc(sg.query_backend()))
 coverage.depth = {pixel_format = .DEPTH, compare = .GREATER_EQUAL, write_enabled = true}
 coverage.color_count = 2
 coverage.colors[0].pixel_format = .R8
 coverage.colors[1].pixel_format = .R32F
 skinned_coverage := coverage
 skinned_coverage.shader = sg.make_shader(skinned_coverage_shader_desc(sg.query_backend()))
 skinned_coverage.layout = skinned_mask_shadow.layout
 for pipeline in SCENE_ORDER_PIPELINES {
  r.depth_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(coverage, pipeline))
  r.skinned_depth_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(skinned_coverage, pipeline))
 }
	for pipeline in SCENE_ORDER_PIPELINES {
		if pipeline == .Opaque { continue }
		r.shadow_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(mask_shadow, pipeline))
		r.skinned_shadow_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(skinned_mask_shadow, pipeline))
	}
}

shadow_mask_pipeline_desc :: proc(desc: sg.Pipeline_Desc, pipeline: Mesh_Pipeline) -> sg.Pipeline_Desc {
	d := desc
	d.cull_mode = .NONE if pipeline == .Mask_Double_Sided else .BACK
	return d
}

mesh_pipelines :: proc(opaque: sg.Pipeline_Desc, shaders: Mesh_Shaders) -> (pips: [Mesh_Pipeline]sg.Pipeline) {
	for pipeline in Mesh_Pipeline {
		pips[pipeline] = sg.make_pipeline(mesh_pipeline_desc(opaque, shaders, pipeline))
	}
	return pips
}

// A Blend part tests depth and writes none, so a Blend part behind it still
// draws. Its colour is premultiplied by alpha.
mesh_pipeline_desc :: proc(opaque: sg.Pipeline_Desc, shaders: Mesh_Shaders, pipeline: Mesh_Pipeline) -> sg.Pipeline_Desc {
	d := opaque
	switch pipeline {
	case .Opaque:
	case .Mask:
		d.shader = shaders.mask
	case .Mask_Double_Sided:
		d.shader = shaders.mask
		d.cull_mode = .NONE
	case .Blend, .Blend_Back_Faces:
		d.shader = shaders.blend
		d.depth.write_enabled = false
		d.colors[0].blend = {
			enabled          = true,
			src_factor_rgb   = .ONE,
			dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
			src_factor_alpha = .ONE,
			dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
		}
		d.cull_mode = .FRONT if pipeline == .Blend_Back_Faces else .BACK
	}
	return d
}

// The sampler compares in hardware, and a fragment is lit where its depth is
// at least the stored depth. LINEAR filters each compare across 2 x 2 texels.
// The layers past cascades stay zero.
shadow_map_make :: proc(size: u32, cascades: int) -> Shadow_Map {
	m: Shadow_Map
	m.image = sg.make_image(
		{
			type = .ARRAY,
			usage = {depth_stencil_attachment = true},
			width = i32(size),
			height = i32(size),
			num_slices = i32(cascades),
			pixel_format = .DEPTH,
			sample_count = 1,
			label = "shadow-map",
		},
	)
	m.texture = sg.make_view({texture = {image = m.image}})
	for &layer, i in m.layers[:cascades] {
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
	started: i64
	if g_state.capture.on { started = capture_tick() }
	defer if g_state.capture.on { g_state.capture.row.begin_pass += capture_tick() - started }
	r := (^Renderer)(ctx)
	r.pass = pass
	r.applied = {}
	switch pass {
	case .Shadow:
		// sokol discards depth at the end of a pass unless told to store it.
		gfx_begin_pass({action = {depth = {load_action = .CLEAR, store_action = .STORE, clear_value = 0}}, attachments = {depth_stencil = r.shadow.layers[view]}, label = "shadow"})
	case .Main:
		drawable_started: i64
		if g_state.capture.on { drawable_started = capture_tick() }
		r.swapchain = sglue.swapchain()
		if g_state.capture.on { g_state.capture.row.drawable += capture_tick() - drawable_started }
		render_target_fit(&r.target, {r.swapchain.width, r.swapchain.height}, sapp.dpi_scale())
		gfx_begin_pass({action = main_pass_action(clear_colour), attachments = r.target.hdr.attachments, label = "main"})
	case .Scene_Depth:
		gfx_begin_pass({action = coverage_pass_action(), attachments = r.target.post.scene.coverage.attachments, label = "scene-depth"})
	case .Selection:
		gfx_begin_pass({action = coverage_pass_action(), attachments = r.target.post.selection.coverage.attachments, label = "selection"})
	case .Post:
		render_target_begin_post(&r.target)
	}
}

// The clear colour is linear, like a surface, and the Post pass tone maps it.
main_pass_action :: proc(clear_colour: Rgb) -> sg.Pass_Action {
	return {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = max(clear_colour.r, 0), g = max(clear_colour.g, 0), b = max(clear_colour.b, 0), a = 1}}},
		depth = {load_action = .CLEAR, clear_value = 0},
	}
}

renderer_end_pass :: proc(ctx: rawptr) {
	r := (^Renderer)(ctx)
	gfx_end_pass()
	if r.pass == .Post {
		render_target_copy(&r.target, r.swapchain)
	}
}

// A nil skin draws a rigid mesh.
renderer_shadow :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {
	r := (^Renderer)(ctx)
	if r.instance_count > 0 {
		if r.applied != r.instanced_shadow_pips[pipeline] { renderer_apply_pipeline(r, r.instanced_shadow_pips[pipeline]) }
	} else { renderer_apply_skin(r, r.shadow_pips[pipeline], r.skinned_shadow_pips[pipeline], skin) }
	bindings := sg.Bindings{vertex_buffers = {0 = mesh.surface_vertices if part.raw_colour else mesh.vertices}, index_buffer = mesh.indices}
	if pipeline != .Opaque {
		tex := mesh_part_textures(part, r.white, r.flat_normal).base
		bindings.views[VIEW_base_tex] = tex.view
		bindings.samplers[SMP_base_smp] = tex.sampler
	}
	renderer_instance_bindings(r, &bindings)
	sg.apply_bindings(bindings)
	vs := vs_params
	sg.apply_uniforms(UB_shadow_vs_params, {ptr = &vs, size = size_of(Shadow_Vs_Params)})
	sg.draw(part.first, part.count, max(r.instance_count, 1))
}

renderer_lights :: proc(ctx: rawptr, lights: Fs_Lights, clusters: Cluster_Frame) {
	r := (^Renderer)(ctx)
	r.lights = lights
	empty_point: Packed_Light
	point_data := sg.Range{ptr = raw_data(clusters.points), size = uint(len(clusters.points) * size_of(Packed_Light))}
	if len(clusters.points) == 0 { point_data = {ptr = &empty_point, size = size_of(Packed_Light)} }
	sg.update_buffer(r.cluster_buffers[0], point_data)
	sg.update_buffer(r.cluster_buffers[1], {ptr = raw_data(clusters.ranges), size = uint(len(clusters.ranges) * size_of(Cluster_Range))})
	sg.update_buffer(r.cluster_buffers[2], {ptr = raw_data(clusters.indices), size = uint(len(clusters.indices) * size_of(u32))})
	renderer_apply_pipeline(r, r.pips[.Opaque])
}

// Every apply_pipeline of the Shadow and Main passes goes through here, so
// r.applied stays true.
// sokol drops the applied fs_lights at each apply_pipeline, so the Main
// pass applies them again after a change to a mesh pipeline.
renderer_apply_pipeline :: proc(r: ^Renderer, pip: sg.Pipeline) {
	sg.apply_pipeline(pip)
	r.applied = pip
	r.applied_skin = nil
	r.has_bindings = false
	r.has_material = false
	for pipeline in Mesh_Pipeline {
		if pip == r.pips[pipeline] || pip == r.skinned_pips[pipeline] || pip == r.instanced_pips[pipeline] {
			sg.apply_uniforms(UB_fs_lights, {ptr = &r.lights, size = size_of(Fs_Lights)})
			return
		}
	}
}

// Changes to the rigid or the skinned pipeline of the pass when the Draw
// needs the other one, then applies the skin block of a skinned Draw once.
@(private = "file")
renderer_apply_skin :: proc(r: ^Renderer, rigid, skinned: sg.Pipeline, skin: ^Skin_Params) {
	pip := skinned if skin != nil else rigid
	if r.applied != pip {
		renderer_apply_pipeline(r, pip)
	}
	if skin != nil && skin != r.applied_skin {
		sg.apply_uniforms(UB_skin_params, {ptr = skin, size = size_of(Skin_Params)})
		r.applied_skin = skin
	}
}

// A nil skin draws a rigid mesh. Each change of mesh pipeline applies the
// lights again and drops the applied skin block. Before the sky, the uniform
// buffer has room for one change to each mesh pipeline per Frame. After it,
// each Blend submit has room for one change.
renderer_draw :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
	r := (^Renderer)(ctx)
	if r.instance_count > 0 {
		if r.applied != r.instanced_pips[pipeline] { renderer_apply_pipeline(r, r.instanced_pips[pipeline]) }
	} else { renderer_apply_skin(r, r.pips[pipeline], r.skinned_pips[pipeline], skin) }
	tex := mesh_part_textures(part, r.white, r.flat_normal)
	diffuse, specular := r.environment.diffuse, r.environment.specular
	bindings := sg.Bindings {
		vertex_buffers = {0 = mesh.surface_vertices if part.raw_colour else mesh.vertices},
		index_buffer = mesh.indices,
		views = {
			VIEW_engine_points = r.cluster_views[0],
			VIEW_engine_clusters = r.cluster_views[1],
			VIEW_engine_indices = r.cluster_views[2],
			VIEW_base_tex = tex.base.view,
			VIEW_metallic_roughness_tex = tex.metallic_roughness.view,
			VIEW_shadow_tex = r.shadow.texture,
			VIEW_emissive_tex = tex.emissive.view,
			VIEW_normal_tex = tex.normal.view,
			VIEW_occlusion_tex = tex.occlusion.view,
			VIEW_env_diffuse_tex = diffuse.view,
			VIEW_env_specular_tex = specular.view,
		},
		samplers = {
			SMP_base_smp = tex.base.sampler,
			SMP_metallic_roughness_smp = tex.metallic_roughness.sampler,
			SMP_shadow_smp = r.shadow.sampler,
			SMP_emissive_smp = tex.emissive.sampler,
			SMP_normal_smp = tex.normal.sampler,
			SMP_occlusion_smp = tex.occlusion.sampler,
			SMP_env_diffuse_smp = diffuse.sampler,
			SMP_env_specular_smp = specular.sampler,
		},
	}
	renderer_instance_bindings(r, &bindings)
	if !r.has_bindings || bindings != r.applied_bindings {
		sg.apply_bindings(bindings)
		r.applied_bindings = bindings
		r.has_bindings = true
	}

	vs := vs_params
	fs := fs_params
	fs.environment_params = r.environment.params
	sg.apply_uniforms(UB_vs_params, {ptr = &vs, size = size_of(Vs_Params)})
	if !r.has_material || fs != r.applied_material {
		sg.apply_uniforms(UB_fs_params, {ptr = &fs, size = size_of(Fs_Params)})
		r.applied_material = fs
		r.has_material = true
	}

	sg.draw(part.first, part.count, max(r.instance_count, 1))
}

renderer_environment :: proc(ctx: rawptr, sky: Sky_View) {
	r := (^Renderer)(ctx)
	r.environment = environment_light(r, sky)
}

// The sky must follow every Draw that writes depth.
// With no blend, the to texture is the from texture. A blend from no sky
// binds the to texture twice and the shader reads the clear colour instead.
renderer_sky :: proc(ctx: rawptr, sky: Sky_View, vs_params: Sky_Vs_Params, fs_params: Sky_Fs_Params) {
	r := (^Renderer)(ctx)
	cube := &r.meshes.meshes[Primitive.Cube]
	renderer_apply_pipeline(r, r.sky_pip)
	to := sky.to.texture if sky.to != nil else sky.from.texture
	from := sky.from.texture if sky.from != nil else to
	sg.apply_bindings(
		{
			vertex_buffers = {0 = cube.vertices},
			index_buffer = cube.indices,
			views = {VIEW_sky_tex = from.view, VIEW_sky_to_tex = to.view},
			samplers = {SMP_sky_smp = from.sampler, SMP_sky_to_smp = to.sampler},
		},
	)
	vs, fs := vs_params, fs_params
	sg.apply_uniforms(UB_sky_vs_params, {ptr = &vs, size = size_of(Sky_Vs_Params)})
	sg.apply_uniforms(UB_sky_fs_params, {ptr = &fs, size = size_of(Sky_Fs_Params)})
	sg.draw(0, cube.index_count, 1)
}

renderer_bloom :: proc(ctx: rawptr, step: Bloom_Step) {
	r := (^Renderer)(ctx)
	render_target_bloom(&r.target, step)
}

renderer_tone_map :: proc(ctx: rawptr, params: Tone_Map_Params) {
	r := (^Renderer)(ctx)
	render_target_tone_map(&r.target, params)
}

renderer_submits :: proc(r: ^Renderer) -> Frame_Render_Submits {
	return {
		begin_pass = renderer_begin_pass,
		end_pass = renderer_end_pass,
		submit_shadow = renderer_shadow,
		submit = renderer_draw,
		submit_lights = renderer_lights,
		submit_surface = renderer_surface,
		submit_depth = renderer_depth,
		submit_selection = renderer_selection,
		prepare_post = renderer_prepare_post,
		submit_post = renderer_post,
		submit_instances = renderer_instances,
		submit_sky = renderer_sky,
		submit_environment = renderer_environment,
		submit_bloom = renderer_bloom,
		submit_tone_map = renderer_tone_map,
		submit_ui = renderer_ui,
		upload_particles = renderer_upload_particles,
		submit_particles = renderer_submit_particles,
		ctx = r,
	}
}

renderer_depth :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
 r := (^Renderer)(ctx)
 rigid := r.instanced_depth_pips[pipeline] if r.instance_count > 0 else r.depth_pips[pipeline]
 renderer_apply_skin(r, rigid, r.skinned_depth_pips[pipeline], skin)
 tex := mesh_part_textures(part, r.white, r.flat_normal).base
 bindings := sg.Bindings{vertex_buffers = {0 = mesh.surface_vertices if part.raw_colour else mesh.vertices}, index_buffer = mesh.indices, views = {VIEW_base_tex = tex.view}, samplers = {SMP_base_smp = tex.sampler}}
 renderer_instance_bindings(r, &bindings)
 sg.apply_bindings(bindings)
 params := Shadow_Vs_Params{light_mvp = vs_params.mvp, shadow_material = {fs_params.material.w if part.material.alpha_mode == .Mask else -1, fs_params.tint.a, 0, 0}}
 sg.apply_uniforms(UB_shadow_vs_params, {ptr = &params, size = size_of(params)})
 sg.draw(part.first, part.count, max(r.instance_count, 1))
}

renderer_selection :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
	renderer_depth(ctx, mesh, part, pipeline, vs_params, fs_params, skin)
}
