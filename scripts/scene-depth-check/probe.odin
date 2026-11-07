package main

import engine "../../engine"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

Probe_Mode :: enum { Baseline, Isolated, Gpu_Product, Pre_Depth, Zero_To_One, Depth_Fault }
Driver_Info :: struct {
	backend, vendor, renderer, version, language: string,
	clip_control: bool,
	subpixel_bits: int,
	clip_depth_mode: u32,
}
Probe_Metadata :: struct { mode: Probe_Mode, driver: Driver_Info, skipped: string }
Part_Input :: struct {
	first, count: int,
	fs: [24]u32,
	rigid_uniform_vertex, instanced_uniform_vertex: [64]u32,
	instance: [29]u32,
	vertex, fragment: [64]u32,
	draw_info: [4]u32,
	time: u32,
	imported: [4]int,
	game_views, game_samplers: [4]u32,
}
Draw_Input :: struct {
	fixture_index: int,
	view_projection, cpu_mvp, submitted_rigid_mvp, model, normal: [16]u32,
	vertices: [][16]u32,
	indices: []u16,
	parts: []Part_Input,
}

probe_mode: Probe_Mode
probe_samples: i32

probe_parse :: proc() {
	if len(os.args) == 3 { return }
	switch os.args[3] {
	case "isolated": probe_mode = .Isolated
	case "gpu_product": probe_mode = .Gpu_Product
	case "pre_depth": probe_mode = .Pre_Depth
	case "zero_to_one": probe_mode = .Zero_To_One
	case "depth_fault": probe_mode = .Depth_Fault
	case: panic("unknown fixture probe")
	}
}

write_json :: proc(path: string, value: any) {
	b: strings.Builder
	strings.builder_init(&b, context.temp_allocator)
	defer strings.builder_destroy(&b)
	assert(json.marshal_to_builder(&b, value, {}) == nil)
	assert(os.write_entire_file(path, transmute([]byte)strings.to_string(b)) == nil)
}

probe_inputs :: proc(draws: []engine.Draw_Params, pose: int) {
	for d, i in draws {
		if i != 3 { continue }
		p := d.p
		input := Draw_Input{fixture_index = i, view_projection = transmute([16]u32)camera().view_proj, cpu_mvp = transmute([16]u32)d.vs_params.mvp, submitted_rigid_mvp = transmute([16]u32)(camera().view_proj if probe_mode == .Gpu_Product else d.vs_params.mvp), model = transmute([16]u32)p.model, normal = transmute([16]u32)d.vs_params.normal_model, indices = p.mesh.data.indices}
		input.vertices = make([][16]u32, len(p.mesh.data.vertices), context.temp_allocator)
		for vertex, v in p.mesh.data.vertices {
			vertex := vertex
			if len(p.mesh.vertex_colors) > v { vertex.color = p.mesh.vertex_colors[v] }
			input.vertices[v] = transmute([16]u32)vertex
		}
		input.parts = make([]Part_Input, len(p.parts), context.temp_allocator)
		for &part, j in p.parts {
			fs := engine.frame_render_part_params(d.fs_params, &part)
			input.parts[j] = {first = part.first, count = part.count, fs = transmute([24]u32)fs, instance = transmute([29]u32)engine.surface_instance(d.vs_params, fs.tint)}
			if part.surface != nil {
				s := part.surface
				input.parts[j].vertex, input.parts[j].fragment = transmute([64]u32)s.vertex, transmute([64]u32)s.fragment
				input.parts[j].draw_info, input.parts[j].time, input.parts[j].imported = transmute([4]u32)s.draw_info, transmute(u32)s.time, s.imported
				rigid := engine.Surface_Vertex_Params{mvp = camera().view_proj if probe_mode == .Gpu_Product else d.vs_params.mvp, model = d.vs_params.model, normal_model = d.vs_params.normal_model, render_time = {s.time, 0, 0, 0}, draw_info = s.draw_info}
				instanced := engine.Surface_Vertex_Params{mvp = camera().view_proj, model = engine.mat4_identity(), normal_model = engine.mat4_identity(), render_time = {s.time, 0, 0, 0}, draw_info = s.draw_info}
				input.parts[j].rigid_uniform_vertex, input.parts[j].instanced_uniform_vertex = transmute([64]u32)rigid, transmute([64]u32)instanced
				for texture, k in s.textures { input.parts[j].game_views[k], input.parts[j].game_samplers[k] = texture.view.id, texture.sampler.id }
			}
		}
		write_json(fmt.tprintf("%v/inputs-%v-%v.json", os.args[2], probe_samples, pose), input)
	}
}

fixture_surface :: proc(ctx: rawptr, pass: engine.Surface_Pass, mesh: ^engine.Mesh, part: ^engine.Mesh_Part, pipeline: engine.Mesh_Pipeline, vs: engine.Vs_Params, fs: engine.Fs_Params, skin: ^engine.Skin_Params) {
	params := vs
	if probe_mode == .Gpu_Product { params.mvp = camera().view_proj }
	engine.renderer_surface(ctx, pass, mesh, part, pipeline, params, fs, skin)
}
