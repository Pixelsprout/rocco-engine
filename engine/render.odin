package engine

import sg "../sokol/gfx"

Vertex :: struct {
	pos:   [3]f32,
	color: [4]f32,
	normal: [3]f32,
}

Renderer :: struct {
	pip:  sg.Pipeline,
	alt_pip: sg.Pipeline,
	bind: sg.Bindings,
}

renderer_init :: proc(r: ^Renderer) {

	buf_vertices := sg.make_buffer(
		{
			label = "cube-vertices",
			data = {ptr = raw_data(CUBE_VERTICES[:]), size = len(CUBE_VERTICES) * size_of(Vertex)},
		},
	)

	buf_indices := sg.make_buffer(
		{
			label = "cube-indices",
			data = {ptr = raw_data(CUBE_INDICES[:]), size = len(CUBE_INDICES) * size_of(u16)},
			usage = {index_buffer = true},
		},
	)

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

	desc.cull_mode = .NONE
	r.alt_pip = sg.make_pipeline(desc)

	r.bind.vertex_buffers[0] = buf_vertices
	r.bind.index_buffer = buf_indices
}

renderer_draw :: proc(r: ^Renderer, vs_params: Vs_Params, fs_params: Fs_Params) {

	// if Cn is pressed toggle between the two pipelines
	chosen_pip := r.pip
	if g_state.toggled_pipeline {
		chosen_pip = r.alt_pip
	}

	sg.apply_pipeline(chosen_pip)


	sg.apply_bindings(r.bind)


	vs := vs_params
	fs := fs_params
	sg.apply_uniforms(UB_vs_params, {ptr = &vs, size = size_of(Vs_Params)})
	sg.apply_uniforms(UB_fs_params, {ptr = &fs, size = size_of(Fs_Params)})

	sg.draw(0, len(CUBE_INDICES), 1)
}

renderer_shutdown :: proc(r: ^Renderer) {
	// sg.shutdown destroys every pooled resource, later we would add a per mesh teardown.
}
