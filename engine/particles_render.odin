package engine

import "system"
import sg "../sokol-odin/sokol/gfx"

Particle_Gpu :: struct {
	instances: sg.Buffer,
	pip: [Particle_Blend]sg.Pipeline,
	view: Particle_Vs_Params,
}

particle_gpu_init :: proc(g: ^Particle_Gpu, samples: i32) {
	g.instances = sg.make_buffer({size = PARTICLE_LIMIT * size_of(Particle_Instance), usage = {vertex_buffer = true, stream_update = true}, label = "particle-instances"})
	shader := sg.make_shader(particle_shader_desc(sg.query_backend()))
	for blend in Particle_Blend {
		desc := particle_pipeline_desc(samples, blend)
		desc.shader = shader
		g.pip[blend] = sg.make_pipeline(desc)
	}
}

particle_pipeline_desc :: proc(samples: i32, blend: Particle_Blend) -> sg.Pipeline_Desc {
	return {
		sample_count = samples,
		depth = {pixel_format = TARGET_DEPTH_FORMAT, compare = .GREATER_EQUAL},
		colors = {0 = {pixel_format = HDR_COLOR_FORMAT, blend = {enabled = true, src_factor_rgb = .ONE, dst_factor_rgb = .ONE if blend == .Add else .ONE_MINUS_SRC_ALPHA, src_factor_alpha = .ONE, dst_factor_alpha = .ONE if blend == .Add else .ONE_MINUS_SRC_ALPHA}}},
		cull_mode = .NONE,
		layout = {buffers = {0 = {stride = size_of(Particle_Instance), step_func = .PER_INSTANCE}}, attrs = {ATTR_particle_position_size = {format = .FLOAT4}, ATTR_particle_colour = {format = .FLOAT4}}},
		label = "particles",
	}
}

renderer_upload_particles :: proc(ctx: rawptr, instances: []Particle_Instance, view: Frame_View) {
	r := (^Renderer)(ctx)
	if len(instances) == 0 { return }
	sg.update_buffer(r.particles.instances, {ptr = raw_data(instances), size = uint(len(instances) * size_of(Particle_Instance))})
	forward := v3_normalize(view.camera.target - view.camera.eye)
	right := v3_normalize(v3_cross(forward, view.camera.up))
	up := v3_cross(right, forward)
	r.particles.view = {view_proj = view.view_proj, camera_right = {right.x, right.y, right.z, 0}, camera_up = {up.x, up.y, up.z, 0}}
}

renderer_submit_particles :: proc(ctx: rawptr, batch: Particle_Batch) {
	r := (^Renderer)(ctx)
	g := &r.particles
	image, draw := particle_image_resolve(&r.images, batch.image)
	if !draw { return }
	renderer_apply_pipeline(r, g.pip[batch.blend])
	found := image != nil
	view, sampler := r.white.view, r.white.sampler
	if found { view = image.view; sampler = r.images.linear }
	sg.apply_bindings({vertex_buffers = {0 = g.instances}, vertex_buffer_offsets = {0 = i32(batch.start * size_of(Particle_Instance))}, views = {VIEW_particle_tex = view}, samplers = {SMP_particle_smp = sampler}})
	sg.apply_uniforms(UB_particle_vs_params, {ptr = &g.view, size = size_of(Particle_Vs_Params)})
	params := Particle_Fs_Params{sprite = {1 if found else 0, 0, 0, 0}}
	sg.apply_uniforms(UB_particle_fs_params, {ptr = &params, size = size_of(Particle_Fs_Params)})
	sg.draw(0, 6, i32(batch.count))
}

particle_image_resolve :: proc(images: ^Image_Table, id: u32) -> (image: ^Image, draw: bool) {
	if id == 0 { return nil, true }
	if resolved, found := image_lookup(images, id); found { return resolved, true }
	if id not_in images.logged {
		images.logged[id] = {}
		system.eprintfln("Particle Image id %v is missing or unloaded; omitting its particles", id)
	}
	return nil, false
}
