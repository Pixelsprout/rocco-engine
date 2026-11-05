package engine

import vmem "core:mem/virtual"


Instance_Key :: struct {
	mesh: ^Mesh,
	mesh_generation, shader_generation: u16,
	first, count: int,
	raw_colour, double_sided: bool,
	fs_bits: [size_of(Fs_Params)/size_of(f32)]u32,
	textures: [5]Mesh_Texture,
	surface: int,
}

Surface_Instance_Key :: struct {
	shader: ^Shader,
	imported: [4]int,
	vertex, fragment: [64]u32,
	textures: [4]Mesh_Texture,
	draw_info: [4]u32,
	time: u32,
}

Instance_Member :: struct {
	instance: Surface_Instance,
	next: int,
}

Instance_Batch :: struct {
	key: Instance_Key,
	part: ^Mesh_Part,
	first, last: int,
}

instance_buffer_size :: proc(draws, cascades: int) -> uint {
	return uint(draws * (cascades + 3) * size_of(Surface_Instance))
}

// Homogeneous plane support keeps boxes that cross the eye plane.
box_in_frustum :: proc(box: Box, clip_from_local: Mat4) -> bool {
	return frustum_contains_box(frustum_from_matrix(clip_from_local), box)
}

frustum_from_matrix :: proc(clip_from_local: Mat4) -> (planes: [6][4]f32) {
	for plane in 0 ..< 6 {
		coefficients: [4]f32
		for column in 0 ..< 4 {
			switch plane {
			case 0: coefficients[column] = clip_from_local[3, column] + clip_from_local[0, column]
			case 1: coefficients[column] = clip_from_local[3, column] - clip_from_local[0, column]
			case 2: coefficients[column] = clip_from_local[3, column] + clip_from_local[1, column]
			case 3: coefficients[column] = clip_from_local[3, column] - clip_from_local[1, column]
			case 4: coefficients[column] = clip_from_local[2, column]
			case 5: coefficients[column] = clip_from_local[3, column] - clip_from_local[2, column]
			}
		}
		planes[plane] = coefficients
	}
	return
}

frustum_contains_box :: #force_inline proc(planes: [6][4]f32, box: Box) -> bool {
	for coefficients in planes {
		distance := coefficients.w
		for axis in 0 ..< 3 { distance += coefficients[axis] * (box.max[axis] if coefficients[axis] >= 0 else box.min[axis]) }
		if distance < 0 { return false }
	}
	return true
}

surface_instance :: proc(vs: Vs_Params, tint: [4]f32) -> (instance: Surface_Instance) {
	for column in 0 ..< 4 { for row in 0 ..< 4 { instance.model[column][row] = vs.model[row, column] } }
	for column in 0 ..< 3 { for row in 0 ..< 3 { instance.normal[column][row] = vs.normal_model[row, column] } }
	instance.tint = tint
	return
}

instance_texture :: proc(texture: Mesh_Texture) -> Mesh_Texture {
	return {image = texture.image, view = texture.view, sampler = texture.sampler}
}

instance_key :: proc(p: ^Placed, part: ^Mesh_Part, fs: Fs_Params, surface: int) -> (key: Instance_Key) {
	key = {mesh = p.mesh, mesh_generation = p.mesh.generation, first = part.first, count = part.count, raw_colour = part.raw_colour, double_sided = part.material.double_sided, surface = surface}
	if part.surface != nil { key.shader_generation = part.surface.shader.generation }
	params := fs
	params.tint = {}
	key.fs_bits = transmute([size_of(Fs_Params)/size_of(f32)]u32)params
	textures := [5]Mesh_Texture{part.texture, part.metallic_roughness, part.emissive, part.normal, part.occlusion}
	for texture, i in textures { key.textures[i] = instance_texture(texture) }
	return
}

surface_instance_key :: proc(surface: Surface_Material) -> (key: Surface_Instance_Key) {
	key = {shader = surface.shader, imported = surface.imported, vertex = transmute([64]u32)surface.vertex, fragment = transmute([64]u32)surface.fragment, draw_info = transmute([4]u32)surface.draw_info, time = transmute(u32)surface.time}
	for texture, i in surface.textures { key.textures[i] = instance_texture(texture) }
	return
}

// Camera eligibility never removes a caster from the shared placement array.
frame_render_instances :: proc(fr: ^Frame_Render, pass: Surface_Pass, pipeline: Mesh_Pipeline, view_proj: Mat4, cascade: ^Cascade_View = nil, draw_params: []Draw_Params = nil) {
	context.temp_allocator = vmem.arena_allocator(&fr.instance_scratch)
	defer {
		fr.instance_scratch_peak = max(fr.instance_scratch_peak, fr.instance_scratch.total_used)
		vmem.arena_free_all(&fr.instance_scratch)
	}
	batches := make([dynamic]Instance_Batch, 0, min(len(fr.placed), 64), context.temp_allocator)
	members := make([dynamic]Instance_Member, 0, min(len(fr.placed), 64), context.temp_allocator)
	keys := make(map[Instance_Key]int, context.temp_allocator)
	surfaces := make(map[Surface_Instance_Key]int, context.temp_allocator)
	last_surface: Surface_Instance_Key
	last_surface_id := 0
	placed_count := len(draw_params) if len(draw_params) > 0 else len(fr.placed)
	for placed_index in 0 ..< placed_count {
		p := draw_params[placed_index].p if len(draw_params) > 0 else &fr.placed[placed_index]
		if p.skin != nil { continue }
		if pass == .Shadow {
			if p.shadow_count == 0 || cascade != nil && !cascade_covers(cascade^, p.light_box) { continue }
		} else if !p.camera_visible { continue }
		vs: Vs_Params
		base: Fs_Params
		prepared := false
		for &part in p.parts {
			pp, ok := part_pipeline(part.material)
			if !ok || pp != pipeline { continue }
			if !prepared {
				if len(draw_params) > 0 { vs, base = draw_params[placed_index].vs_params, draw_params[placed_index].fs_params } else { vs, base = placed_draw_params(p, view_proj) }
				prepared = true
			}
			fs := frame_render_part_params(base, &part)
			if part.surface != nil && !shader_bool(shader_interface(part.surface.shader)["instancing"]) {
				if fr.submits.submit_surface != nil { fr.submits.submit_surface(fr.submits.ctx, pass, p.mesh, &part, pipeline, vs, fs, nil) }
				continue
			}
			surface := 0
			if part.surface != nil {
				value := surface_instance_key(part.surface^)
				if last_surface_id > 0 && value == last_surface { surface = last_surface_id } else {
					if id, found := surfaces[value]; found { surface = id } else { surface = len(surfaces) + 1; surfaces[value] = surface }
					last_surface, last_surface_id = value, surface
				}
			}
			key := instance_key(p, &part, fs, surface)
			index := len(batches) - 1
			found := index >= 0 && batches[index].key == key
			if !found { index, found = keys[key] }
			if !found {
				index = len(batches)
				keys[key] = index
				append(&batches, Instance_Batch{key = key, part = &part, first = len(members), last = len(members)})
			} else { members[batches[index].last].next = len(members) }
			batches[index].last = len(members)
			append(&members, Instance_Member{surface_instance(vs, fs.tint), -1})
		}
	}
	instances := make([]Surface_Instance, len(members), context.temp_allocator)
	next := 0
	for batch in batches {
		start := next
		for member := batch.first; member >= 0; member = members[member].next { instances[next] = members[member].instance; next += 1 }
		fs := transmute(Fs_Params)batch.key.fs_bits; fs.tint = {1, 1, 1, 1}
		fr.submits.submit_instances(fr.submits.ctx, pass, batch.key.mesh, batch.part, pipeline, view_proj, fs, instances[start:next])
	}
}
