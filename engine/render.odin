package engine

import sg "../sokol-odin/sokol/gfx"

// The window swapchain and the pipeline must agree, or sokol rejects the pipeline.
SAMPLE_COUNT :: 4

// Each loaded mesh can own a base colour and a metallic-roughness texture,
// each with its own image, view and sampler. The white image needs one more.
TEXTURE_POOL_SIZE :: 2 * MESH_CAPACITY + 1

@(rodata)
WHITE_TEXEL := [4]byte{255, 255, 255, 255}

Renderer :: struct {
	pip:    sg.Pipeline,
	meshes: Mesh_Table,
	white:  Mesh_Texture,
}

renderer_init :: proc(r: ^Renderer) {
	mesh_table_upload(&r.meshes)
	r.white = texture_upload(
		{
			levels = {{width = 1, height = 1, pixels = WHITE_TEXEL[:]}},
			sampler = {min_filter = .NEAREST, mag_filter = .NEAREST, mipmap_filter = .NEAREST, wrap_u = .REPEAT, wrap_v = .REPEAT},
		},
	)

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
			views = {VIEW_base_tex = base.view, VIEW_metallic_roughness_tex = metallic_roughness.view},
			samplers = {SMP_base_smp = base.sampler, SMP_metallic_roughness_smp = metallic_roughness.sampler},
		},
	)

	vs := vs_params
	fs := fs_params
	sg.apply_uniforms(UB_vs_params, {ptr = &vs, size = size_of(Vs_Params)})
	sg.apply_uniforms(UB_fs_params, {ptr = &fs, size = size_of(Fs_Params)})

	sg.draw(0, mesh.index_count, 1)
}

renderer_shutdown :: proc(r: ^Renderer) {
	// sg.shutdown destroys every pooled resource, later we would add a per mesh teardown.
	mesh_table_destroy(&r.meshes)
}
