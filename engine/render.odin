package engine

import sg "../sokol-odin/sokol/gfx"

Vertex :: struct {
	pos:   [3]f32,
	color: [4]f32,
	normal: [3]f32,
}

Renderer :: struct {
	pip:    sg.Pipeline,
	meshes: Mesh_Table,
}

renderer_init :: proc(r: ^Renderer) {
	mesh_table_upload(&r.meshes)

	shader := sg.make_shader(basic_shader_desc(sg.query_backend()))

	// Reversed-Z: the depth buffer clears to 0 and nearer is greater.
	desc := sg.Pipeline_Desc {
		shader = shader,
		depth = {compare = .GREATER_EQUAL, write_enabled = true},
		index_type = .UINT16,
		cull_mode = .BACK,
		face_winding = .CCW,
		layout = {
			attrs = {
				ATTR_basic_pos = {format = sg.Vertex_Format.FLOAT3},
				ATTR_basic_col = {format = sg.Vertex_Format.FLOAT4},
				ATTR_basic_nrm = {format = sg.Vertex_Format.FLOAT3},
			},
		},
	}
	r.pip = sg.make_pipeline(desc)
}

renderer_draw :: proc(r: ^Renderer, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params) {
	sg.apply_pipeline(r.pip)
	sg.apply_bindings({vertex_buffers = {0 = mesh.vertices}, index_buffer = mesh.indices})

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
