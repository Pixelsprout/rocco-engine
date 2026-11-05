package engine

import sg "../sokol-odin/sokol/gfx"

surface_cull :: proc(material: Material, pass: Surface_Pass, pipeline: Mesh_Pipeline) -> sg.Cull_Mode {
	if pass == .Colour && material.alpha_mode == .Blend { return .FRONT if pipeline == .Blend_Back_Faces else .BACK }
	return .NONE if material.double_sided else .BACK
}

renderer_surface :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
	r := (^Renderer)(ctx)
	surface := part.surface
	layout := Shader_Layout.Skinned if skin != nil else .Rigid
	key := Shader_Pipeline_Key{pass, layout, part.material.alpha_mode, surface_cull(part.material, pass, pipeline)}
	pip, ready := shader_pipeline(r.shaders, surface.shader, key)
	if !ready { return }
	if r.applied != pip { renderer_apply_pipeline(r, pip) }
	program := surface.shader.programs[int(layout)*3+int(pass)]
	tex := mesh_part_textures(part, r.white, r.flat_normal)
	diffuse, specular := r.black_cube, r.black_cube
	if r.environment_sky != nil { diffuse, specular = r.environment_sky.diffuse, r.environment_sky.specular }
	views := [8]sg.View{tex.base.view, tex.metallic_roughness.view, r.shadow.texture, tex.emissive.view, tex.normal.view, tex.occlusion.view, diffuse.view, specular.view}
	samplers := [8]sg.Sampler{tex.base.sampler, tex.metallic_roughness.sampler, r.shadow.sampler, tex.emissive.sampler, tex.normal.sampler, tex.occlusion.sampler, diffuse.sampler, specular.sampler}
	bindings := sg.Bindings{vertex_buffers = {0 = mesh.surface_vertices}, index_buffer = mesh.indices}
	for view in shader_array(program.reflection["views"]) {
		o := shader_object(view)
		if t, has := o["texture"]; has {
			slot := shader_int(shader_object(t)["slot"])
			if slot < 8 { bindings.views[slot] = views[slot] } else {
				i := slot-8; game := surface.textures[i]
				switch surface.imported[i] {
				case 1:
					game = tex.base
				case 2:
					game = tex.metallic_roughness
				case 3:
					game = tex.emissive
				case 4:
					game = tex.normal
				case 5:
					game = tex.occlusion
				}
				bindings.views[slot] = game.view
			}
		}
		if b, has := o["storage_buffer"]; has { slot := shader_int(shader_object(b)["slot"]); bindings.views[slot] = r.cluster_views[slot-12] }
	}
	for sampler in shader_array(program.reflection["samplers"]) { slot := shader_int(shader_object(sampler)["slot"]); bindings.samplers[slot] = samplers[slot] if slot < 8 else surface.shader.samplers[slot-8] }
	sg.apply_bindings(bindings)
	vs := Surface_Vertex_Params{mvp = vs_params.mvp, model = vs_params.model, normal_model = vs_params.normal_model, render_time = {surface.time, 0, 0, 0}, draw_info = surface.draw_info}
	fs := fs_params; fs.environment_params = sky_lighting_params(r.environment_sky)
	for block in shader_array(program.reflection["uniform_blocks"]) {
		slot := shader_int(shader_object(block)["slot"])
		data: sg.Range
		switch slot {
		case 0: data = {ptr = &vs, size = size_of(vs)}
		case 1: data = {ptr = &fs, size = size_of(fs)}
		case 2: data = {ptr = &r.lights, size = size_of(r.lights)}
		case 3: data = {ptr = skin, size = size_of(Skin_Params)}
		case 4: data = {ptr = &surface.vertex, size = size_of(surface.vertex)}
		case 5: data = {ptr = &surface.fragment, size = size_of(surface.fragment)}
		}
		sg.apply_uniforms(slot, data)
	}
	sg.draw(part.first, part.count, 1)
	// Custom blocks invalidate the built-in material and binding caches.
	r.has_material, r.has_bindings = false, false
}
