package engine

import "core:fmt"
import sg "../sokol/gfx"

VS_SOURCE :: `
#include <metal_stdlib>
using namespace metal;
struct vs_in  { float3 pos [[attribute(0)]]; float4 col [[attribute(1)]]; float3 nrm [[attribute(2)]]; };
struct vs_out { float4 pos [[position]]; float4 col; float3 nrm; };
struct vs_params { float4x4 mvp; float4x4 model; };

vertex vs_out vs_main(vs_in in [[stage_in]],
                      constant vs_params& p [[buffer(0)]]) {
    vs_out out;
    out.pos = p.mvp * float4(in.pos, 1.0);
    out.col = in.col;
    out.nrm = (p.model * float4(in.nrm, 0.0)).xyz;
    return out;
}
`

FS_SOURCE :: `
#include <metal_stdlib>
using namespace metal;
struct fs_in { float4 pos [[position]]; float4 col; float3 nrm; };
struct fs_params { float3 light_dir; float4 light_color; float4 ambient; };

fragment float4 fs_main(fs_in in [[stage_in]],
						constant fs_params& p [[buffer(1)]]) {
	float3 nrm = normalize(in.nrm);
	float diffuse = max(dot(nrm, normalize(p.light_dir)), 0.0);
	float3 lighting = p.ambient.rgb + p.light_color.rgb * diffuse;
	return float4(in.col.rgb * lighting, in.col.a);
}
`

Vs_Params :: struct {
	mvp:   Mat4,
	model: Mat4,
}

Fs_Params :: struct {
	light_dir:   [4]f32,
	light_color: [4]f32,
	ambient:     [4]f32,
}

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

	// make the buffer, allocate enough to hold our fixed size
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

	fmt.printfln("Size of vertex: %v", size_of(ODIN_VENDOR))
	fmt.printfln("Offset of vertex: %v", offset_of(Vertex, normal))
	fmt.printfln("Offset of vertex: %v", offset_of(Vertex, color))

	// make the shader
	shader := sg.make_shader(
		{
			vertex_func = {source = VS_SOURCE, entry = "vs_main"},
			fragment_func = {source = FS_SOURCE, entry = "fs_main"},
			uniform_blocks = {
				0 = {stage = sg.Shader_Stage.VERTEX, size = size_of(Vs_Params), msl_buffer_n = 0},
				1 = {stage = sg.Shader_Stage.FRAGMENT, size = size_of(Fs_Params), msl_buffer_n = 1},
			},
		},
	)

	// make the pipeline
	pipeline := sg.make_pipeline(
		sg.Pipeline_Desc {
			shader = shader,
			depth = {compare = .GREATER_EQUAL, write_enabled = true}, // allow depth testing
			index_type = .UINT16,
			cull_mode = .BACK,
			face_winding = .CCW,
			layout = {
				attrs = {
					0 = {format = sg.Vertex_Format.FLOAT3},
					1 = {format = sg.Vertex_Format.FLOAT4},
					2 = {format = sg.Vertex_Format.FLOAT3},
				},
			},
		},
	)

	alt_pipeline := sg.make_pipeline(
		sg.Pipeline_Desc {
			shader = shader,
			depth = {compare = .GREATER_EQUAL, write_enabled = true}, // allow depth testing
			index_type = .UINT16,
			cull_mode = .NONE,
			face_winding = .CCW,
			layout = {
				attrs = {
					0 = {format = sg.Vertex_Format.FLOAT3},
					1 = {format = sg.Vertex_Format.FLOAT4},
					2 = {format = sg.Vertex_Format.FLOAT3},
				},
			},
		},
	)

	fmt.printfln("depth state: %v", sg.query_pipeline_desc(pipeline).depth)
	// store the buffer
	r.bind.vertex_buffers[0] = buf_vertices
	r.bind.index_buffer = buf_indices

	// store the pipeline
	r.pip = pipeline
	r.alt_pip = alt_pipeline

	fmt.printfln("CUBE_VERTICES size: %v", size_of(CUBE_VERTICES))
	fmt.printfln("CUBE_INDICIES size: %v", size_of(CUBE_INDICES))

	fmt.printfln("Cull mode: %v",
		sg.query_pipeline_desc(r.pip).cull_mode)

	fmt.printfln("ALT Cull mode: %v",
		sg.query_pipeline_desc(r.alt_pip).cull_mode)

	fmt.printfln("Face winding: %v",
		sg.query_pipeline_desc(r.pip).face_winding)

	fmt.printfln("ALT Face winding: %v",
		sg.query_pipeline_desc(r.alt_pip).face_winding)

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

	// setup uniform block
	sg.apply_uniforms(0, {ptr = &vs, size = size_of(Vs_Params)})
	sg.apply_uniforms(1, {ptr = &fs, size = size_of(Fs_Params)})

	// assume 1 instance for now
	sg.draw(0, len(CUBE_INDICES), 1)
}

renderer_shutdown :: proc(r: ^Renderer) {
	// sg.shutdown destroys every pooled resource, later we would add a per mesh teardown.
}
