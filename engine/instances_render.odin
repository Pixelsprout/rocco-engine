package engine

import sg "../sokol-odin/sokol/gfx"

renderer_instances_init :: proc(r: ^Renderer, colour: sg.Pipeline_Desc) {
	colour := colour
	colour.shader = sg.make_shader(instanced_shader_desc(sg.query_backend()))
	colour.layout = instance_layout()
	mask := sg.make_shader(instanced_mask_shader_desc(sg.query_backend()))
	for pipeline in SCENE_ORDER_PIPELINES { r.instanced_pips[pipeline] = sg.make_pipeline(mesh_pipeline_desc(colour, {mask = mask}, pipeline)) }
	shadow := colour
	shadow.shader = sg.make_shader(instanced_shadow_shader_desc(sg.query_backend()))
	shadow.sample_count = 1
	shadow.colors[0].pixel_format = .NONE
	shadow.depth = {pixel_format = .DEPTH, compare = .GREATER_EQUAL, write_enabled = true, bias = SHADOW_DEPTH_BIAS, bias_slope_scale = SHADOW_SLOPE_BIAS}
	full := instance_layout()
	shadow.layout.attrs = {}
	shadow.layout.attrs[0] = full.attrs[0]
	for i in 0 ..< 4 { shadow.layout.attrs[1+i] = full.attrs[5+i] }
	r.instanced_shadow_pips[.Opaque] = sg.make_pipeline(shadow)
	shadow.shader = sg.make_shader(instanced_shadow_mask_shader_desc(sg.query_backend()))
	shadow.layout.attrs = {}
	shadow.layout.attrs[0], shadow.layout.attrs[1], shadow.layout.attrs[2] = full.attrs[0], full.attrs[1], full.attrs[3]
	for i in 0 ..< 4 { shadow.layout.attrs[3+i] = full.attrs[5+i] }
	shadow.layout.attrs[7] = full.attrs[12]
	for pipeline in SCENE_ORDER_PIPELINES { if pipeline != .Opaque { r.instanced_shadow_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(shadow, pipeline)) } }
	coverage := shadow
	coverage.shader = sg.make_shader(instanced_coverage_shader_desc(sg.query_backend()))
	coverage.depth = {pixel_format = .DEPTH, compare = .GREATER_EQUAL, write_enabled = true}
	coverage.color_count = 2
	coverage.colors[0].pixel_format = .R8
	coverage.colors[1].pixel_format = .R32F
	for pipeline in SCENE_ORDER_PIPELINES { r.instanced_depth_pips[pipeline] = sg.make_pipeline(shadow_mask_pipeline_desc(coverage, pipeline)) }
}

instance_layout :: proc() -> (layout: sg.Vertex_Layout_State) {
	layout.buffers[0].stride = size_of(Vertex)
	layout.buffers[1] = {stride = size_of(Surface_Instance), step_func = .PER_INSTANCE}
	formats := [5]sg.Vertex_Format{.FLOAT3, .FLOAT4, .FLOAT3, .FLOAT2, .FLOAT4}
	offsets := [5]uintptr{offset_of(Vertex, pos), offset_of(Vertex, color), offset_of(Vertex, normal), offset_of(Vertex, uv), offset_of(Vertex, tangent)}
	for format, i in formats { layout.attrs[i] = {format = format, offset = i32(offsets[i])} }
	for i in 0 ..< 4 { layout.attrs[5+i] = {format = .FLOAT4, buffer_index = 1, offset = i32(i*16)} }
	for i in 0 ..< 3 { layout.attrs[9+i] = {format = .FLOAT3, buffer_index = 1, offset = i32(64+i*12)} }
	layout.attrs[12] = {format = .FLOAT4, buffer_index = 1, offset = 100}
	return
}

renderer_instance_bindings :: proc(r: ^Renderer, bindings: ^sg.Bindings) {
	if r.instance_count > 0 {
		bindings.vertex_buffers[1] = r.instance_buffer
		bindings.vertex_buffer_offsets[1] = i32(r.instance_offset)
	}
}

// sokol keeps a destroyed buffer alive until the GPU completes the frames
// that use it.
renderer_upload_instances :: proc(ctx: rawptr, instances: []Surface_Instance) {
	r := (^Renderer)(ctx)
	assert(r.instance_slots_used < r.instance_slot_count)
	slot := &r.instance_slots[r.instance_slots_used]
	r.instance_slots_used += 1
	capacity := instance_slot_capacity(slot.capacity, len(instances))
	if capacity != slot.capacity {
		if slot.capacity > 0 { sg.destroy_buffer(slot.buffer) }
		slot^ = {buffer = sg.make_buffer({size = uint(capacity * size_of(Surface_Instance)), usage = {vertex_buffer = true, write_transient = true}, label = "instances"}), capacity = capacity}
	}
	buffer_write(slot.buffer, instances)
	r.instance_buffer = slot.buffer
	r.instance_offset = 0
}

renderer_instances :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, view_proj: Mat4, fs: Fs_Params, instances: []Surface_Instance) {
	if len(instances) == 0 { return }
	r := (^Renderer)(ctx)
	r.instance_count = len(instances)
	defer {
		r.instance_offset += len(instances) * size_of(Surface_Instance)
		r.instance_count = 0
	}
	vs := Vs_Params{mvp = view_proj, model = mat4_identity(), normal_model = mat4_identity()}
	if part.surface != nil {
		renderer_surface(ctx, pass, mesh, part, pipeline, vs, fs, nil)
	} else if pass == .Shadow {
		renderer_shadow(ctx, mesh, part, pipeline, {light_mvp = view_proj, shadow_material = {part.material.alpha_cutoff, 0, 0, 0}}, nil)
	} else if pass == .Selection { renderer_depth(ctx, mesh, part, pipeline, vs, fs, nil) }
	else { renderer_draw(ctx, mesh, part, pipeline, vs, fs, nil) }
}
