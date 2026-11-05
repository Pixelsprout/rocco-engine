#+test
package engine

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:testing"

Instance_Recorded :: struct {
	counts: [dynamic]int,
	tints: [dynamic][4]f32,
	passes: [dynamic]Surface_Pass,
}

Depth_Instance_Item :: struct {
	mesh: ^Mesh,
	first: int,
	pipeline: Mesh_Pipeline,
	model, normal: Mat4,
	fs: Fs_Params,
	skin: ^Skin_Params,
	surface: Surface_Material,
	has_surface: bool,
}

Depth_Instance_Record :: struct {
	items: [dynamic]Depth_Instance_Item,
	batches: int,
}

record_instances :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, view_proj: Mat4, fs: Fs_Params, instances: []Surface_Instance) {
	r := (^Instance_Recorded)(ctx)
	append(&r.counts, len(instances))
	append(&r.passes, pass)
	for instance in instances { append(&r.tints, instance.tint) }
}

@(test)
test_frustum_rejects_each_plane_and_keeps_crossing_boxes :: proc(t: ^testing.T) {
	view := scene_view_proj({eye = {}, target = {0, 0, -1}, up = UP, fov_y = 1.047}, 1)
	box := Box{min = {-0.5, -0.5, -0.5}, max = {0.5, 0.5, 0.5}}
	for position in ([5][3]f32{{-20, 0, -2}, {20, 0, -2}, {0, -20, -2}, {0, 20, -2}, {0, 0, 2}}) {
		testing.expect(t, !box_in_frustum(box, view * mat4_translate(position)))
	}
	testing.expect(t, box_in_frustum(box, view * mat4_translate({0, 0, -2})))
	testing.expect(t, box_in_frustum(box, view))
	testing.expect(t, box_in_frustum(box, view * mat4_translate({0, 0, -100000})))
	testing.expect(t, !box_in_frustum(Box{min = {-0.01, -0.01, -0.05}, max = {0.01, 0.01, -0.01}}, view))
}

@(test)
test_instance_columns_preserve_nonuniform_transform :: proc(t: ^testing.T) {
	x := Draw_Transform{position = {3, 4, -5}, scale = {2, 3, 4}, rotation = quat_from_axis_angle(UP, 0.7), scale_rotation = 1}
	vs := Vs_Params{model = draw_model_matrix(x), normal_model = draw_normal_matrix(x)}
	instance := surface_instance(vs, {0.2, 0.3, 0.4, 1})
	for column in 0 ..< 4 { for row in 0 ..< 4 { testing.expect_value(t, instance.model[column][row], vs.model[row, column]) } }
	for column in 0 ..< 3 { for row in 0 ..< 3 { testing.expect_value(t, instance.normal[column][row], vs.normal_model[row, column]) } }
	testing.expect_value(t, instance.tint, [4]f32{0.2, 0.3, 0.4, 1})
}

@(test)
test_instances_compare_surface_values_and_split_incompatible_values :: proc(t: ^testing.T) {
	shader: Shader
	shader.package_data.manifest, _ = json.parse_string(`{"interface":{"surface":{"instancing":true}}}`, allocator = context.temp_allocator)
	values := [4]Surface_Material{{shader = &shader}, {shader = &shader}, {shader = &shader}, {shader = &shader}}
	values[2].vertex[0] = 1
	values[3].draw_info[0] = 2
	parts: [4][1]Mesh_Part
	mesh: Mesh
	placed: [4]Placed
	for &p, i in placed {
		parts[i][0] = {surface = &values[i], count = 3, raw_colour = true, base_colour = {1, 1, 1, 1}}
		p = {draw_id = u64(10+i), mesh = &mesh, parts = parts[i][:], camera_visible = true, model = mat4_identity(), tint = {r = f32(i), g = 1, b = 1}, transform = {scale = {1, 1, 1}, rotation = 1, scale_rotation = 1}}
	}
	r := Instance_Recorded{counts = make([dynamic]int), tints = make([dynamic][4]f32), passes = make([dynamic]Surface_Pass)}
	defer { delete(r.counts); delete(r.tints); delete(r.passes) }
	fr := Frame_Render{placed = make([dynamic]Placed), submits = {ctx = &r, submit_instances = record_instances}}
	defer frame_render_destroy(&fr)
	append(&fr.placed, ..placed[:])
	frame_render_instances(&fr, .Colour, .Opaque, mat4_identity())
	testing.expect_value(t, len(r.counts), 3)
	testing.expect_value(t, r.counts[0], 2)
	testing.expect_value(t, r.tints[0], [4]f32{0, 1, 1, 1})
	testing.expect_value(t, r.tints[1], [4]f32{1, 1, 1, 1})
	for p, i in fr.placed { testing.expect_value(t, p.draw_id, u64(10+i)) }
}

@(test)
test_camera_culling_keeps_offscreen_shadow_casters_and_capacity_order :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f, 1)
	defer frame_fixture_destroy(&f)
	draws := []Draw{{id = 1, mesh = 1, pos = {100, 0, -2}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}, {id = 2, mesh = 1, pos = {0, 0, -2}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}
	scene := scene_lit(draws, {light_sun({1, -1, 1}, {1, 1, 1})})
	view := Frame_View{camera = {target = {0, 0, -1}, up = UP, fov_y = 1.047}, aspect = 1}
	view.view_proj = scene_view_proj(view.camera, view.aspect)
	frame_render_draw(&f.fr, scene, scene, 0, view, &f.meshes, &f.skies, nil, nil, f.window)
	testing.expect_value(t, len(f.rec.submits), 0)
	testing.expect_value(t, len(f.rec.shadows), 1)
	testing.expect_value(t, len(f.fr.placed), 1)
	testing.expect_value(t, f.fr.placed[0].draw_id, 1)
	testing.expect(t, !f.fr.placed[0].camera_visible)
}

@(test)
test_displaced_bounds_keep_surface_at_frustum_edge :: proc(t: ^testing.T) {
	view := scene_view_proj({target = {0, 0, -1}, up = UP, fov_y = 1.047}, 1)
	mesh := Mesh{box = {min = {-0.1, -0.1, -0.1}, max = {0.1, 0.1, 0.1}}}
	p := Placed{mesh = &mesh, box = {min = {-2, -2, -2}, max = {2, 2, 2}}, bounds_resolved = true, model = mat4_translate({2, 0, -2})}
	testing.expect(t, !box_in_frustum(mesh.box, view * p.model))
	testing.expect(t, box_in_frustum(placed_box(&p), view * p.model))
}

@(test)
test_instance_keys_split_textures_materials_and_streams :: proc(t: ^testing.T) {
	mesh: Mesh
	p := Placed{mesh = &mesh}
	part := Mesh_Part{count = 3}
	base := instance_key(&p, &part, {}, 0)
	part.texture.view.id = 9
	testing.expect(t, instance_key(&p, &part, {}, 0) != base)
	part.texture = {}
	part.raw_colour = true
	testing.expect(t, instance_key(&p, &part, {}, 0) != base)
	part.raw_colour = false
	part.material.double_sided = true
	testing.expect(t, instance_key(&p, &part, {}, 0) != base)
	part.material.double_sided = false
	fs := Fs_Params{material = {0.3, 0, 0, 0}}
	testing.expect(t, instance_key(&p, &part, fs, 0) != base)
	part.first = 3
	testing.expect(t, instance_key(&p, &part, {}, 0) != base)
	part.first = 0
	other: Mesh_Texture
	part.texture.ordinary = &other
	testing.expect_value(t, instance_key(&p, &part, {}, 0), base)
}

@(test)
test_skinned_draw_bypasses_camera_culling :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	id := frame_fixture_skinned_mesh(&f, "animated", {{count = 3}})
	scene := scene_of({{id = 1, mesh = id, pos = {100, 0, -2}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}})
	view := Frame_View{camera = {target = {0, 0, -1}, up = UP, fov_y = 1.047}, aspect = 1}
	view.view_proj = scene_view_proj(view.camera, view.aspect)
	frame_render_draw(&f.fr, scene, scene, 0, view, &f.meshes, &f.skies, nil, nil, f.window)
	testing.expect_value(t, len(f.rec.submits), 1)
	testing.expect(t, f.rec.submits[0].skinned)
	testing.expect(t, f.fr.placed[0].camera_visible)
}

record_instance_calls :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, view_proj: Mat4, fs: Fs_Params, instances: []Surface_Instance) {
	r := (^Recorder)(ctx)
	r.instance_calls += 1
	r.instance_records += len(instances)
}

@(test)
test_rigid_only_surface_uses_declared_colour_and_shadow_variants :: proc(t: ^testing.T) {
	f: Surface_Fixture
	surface_fixture_init(t, &f)
	defer surface_fixture_destroy(&f)
	f.frame.fr.submits.submit_instances = record_instance_calls
	d := surface_test_draw(&f)
	d.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	other := d; other.id = 11
	scene := scene_lit({d, other}, {light_sun({x = 0, y = -1, z = 0}, {r = 1, g = 1, b = 1})})
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, f.frame.rec.instance_calls, 0)
	testing.expect_value(t, len(f.frame.rec.submits), 4)
	testing.expect_value(t, len(f.frame.rec.shadows), 4)
	testing.expect_value(t, len(f.frame.rec.surfaces), 8)
}

@(test)
test_instance_scratch_reuses_storage_across_four_shadow_cascades :: proc(t: ^testing.T) {
	mesh: Mesh
	part := [1]Mesh_Part{{count = 3}}
	r: Recorder
	fr := Frame_Render{placed = make([dynamic]Placed, 0, 32768), submits = {ctx = &r, submit_instances = record_instance_calls}}
	defer frame_render_destroy(&fr)
	for _ in 0 ..< 32768 {
		append(&fr.placed, Placed{mesh = &mesh, parts = part[:], model = mat4_identity(), camera_visible = true, shadow_count = 3, tint = {r = 1, g = 1, b = 1}, transform = {scale = {1, 1, 1}, rotation = 1, scale_rotation = 1}})
	}
	for pass in ([6]Surface_Pass{.Colour, .Shadow, .Shadow, .Shadow, .Shadow, .Selection}) {
		for pipeline in SCENE_ORDER_PIPELINES {
			frame_render_instances(&fr, pass, pipeline, mat4_identity())
			testing.expect_value(t, fr.instance_scratch.total_used, 0)
		}
	}
	testing.expect_value(t, r.instance_calls, 6)
	testing.expect_value(t, r.instance_records, 32768 * (MAX_CASCADES + 2))
	testing.expect(t, uint(r.instance_records * size_of(Surface_Instance)) < instance_buffer_size(32768, MAX_CASCADES))
	testing.expect(t, fr.instance_scratch_peak < 16 * mem.Megabyte)
	fmt.eprintfln("instance scratch peak for 32768 rigid Draws and four cascades: %v bytes", fr.instance_scratch_peak)
}

@(test)
test_selection_does_not_reuse_a_colour_batch_containing_unselected_draws :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.fr.submits.submit_instances = record_instance_calls
	f.fr.submits.submit_selection = record_submit
	f.fr.submits.prepare_post = post_selection_inputs
	d := Draw{id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
	other := d
	other.id, other.pos.x = 2, 3
	nodes := []Node{node_group(1, {}, IDENTITY, draw_nodes({d}), selected = true), node_draw(other)}
	scene := scene_nodes(nodes)
	frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, f.rec.instance_calls, 2)
	testing.expect_value(t, len(f.rec.submits), 1)
	testing.expect_value(t, f.rec.submits[0].model, f.fr.placed[0].model)
	testing.expect(t, f.fr.placed[0].selected && !f.fr.placed[1].selected)
}

record_depth_item :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs: Vs_Params, fs: Fs_Params, skin: ^Skin_Params) {
	r := (^Depth_Instance_Record)(ctx)
	item := Depth_Instance_Item{mesh = mesh, first = part.first, pipeline = pipeline, model = vs.model, normal = vs.normal_model, fs = fs, skin = skin, has_surface = part.surface != nil}
	if part.surface != nil { item.surface = part.surface^ }
	append(&r.items, item)
}

record_depth_surface :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs: Vs_Params, fs: Fs_Params, skin: ^Skin_Params) {
	assert(pass == .Selection)
	record_depth_item(ctx, mesh, part, pipeline, vs, fs, skin)
}

record_depth_instances :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, view_proj: Mat4, fs: Fs_Params, instances: []Surface_Instance) {
	assert(pass == .Selection)
	r := (^Depth_Instance_Record)(ctx)
	r.batches += 1
	for instance in instances {
		vs: Vs_Params
		for column in 0 ..< 4 { for row in 0 ..< 4 { vs.model[row, column] = instance.model[column][row] } }
		for column in 0 ..< 3 { for row in 0 ..< 3 { vs.normal_model[row, column] = instance.normal[column][row] } }
		vs.normal_model[3, 3] = 1
		params := fs
		params.tint = instance.tint
		record_depth_item(ctx, mesh, part, pipeline, vs, params, nil)
	}
}

@(test)
test_scene_depth_batches_preserve_individual_materials_transforms_visibility_and_fallbacks :: proc(t: ^testing.T) {
	shader, rigid_shader: Shader
	shader.package_data.manifest, _ = json.parse_string(`{"interface":{"surface":{"instancing":true}}}`, allocator = context.temp_allocator)
	rigid_shader.package_data.manifest, _ = json.parse_string(`{"interface":{"surface":{"instancing":false}}}`, allocator = context.temp_allocator)
	values := [3]Surface_Material{{shader = &shader, time = 2.5}, {shader = &shader, time = 2.5}, {shader = &rigid_shader, time = 2.5}}
	values[1].vertex[0], values[1].fragment[4], values[1].draw_info[0] = 0.4, 0.7, 3
	values[1].textures[0].view.id = 9
	mesh := Mesh{generation = 4}
	parts := [5]Mesh_Part{
		{first = 0, count = 3},
		{first = 3, count = 3, raw_colour = true, base_colour = {0.2, 0.5, 0.7, 0.4}, material = {alpha_mode = .Mask, alpha_cutoff = 0.35}},
		{first = 6, count = 3, surface = &values[0], material = {alpha_mode = .Mask, double_sided = true, alpha_cutoff = 0.6}},
		{first = 9, count = 3, surface = &values[2]},
		{first = 12, count = 3, material = {alpha_mode = .Blend, double_sided = true}},
	}
	other_parts := parts
	other_parts[2].surface = &values[1]
	placed: [5]Placed
	draws: [5]Draw_Params
	skin: Skin_Params
	for &p, i in placed {
		x := Draw_Transform{position = {f32(i), 2, -3}, scale = {2, 3, 4}, rotation = quat_from_axis_angle(UP, 0.4), scale_rotation = 1}
		p = {mesh = &mesh, parts = parts[:], camera_visible = i != 2, transform = x, model = draw_model_matrix(x), tint = {r = 0.2 + f32(i), g = 0.5, b = 0.7}, shadow_count = 0}
		if i == 3 { p.parts = other_parts[:] }
		if i == 4 { p.skin = &skin }
		vs, fs := placed_draw_params(&p, mat4_identity())
		draws[i] = {p = &p, vs_params = vs, fs_params = fs}
	}
	r := Depth_Instance_Record{items = make([dynamic]Depth_Instance_Item)}
	defer delete(r.items)
	fr := Frame_Render{submits = {ctx = &r, begin_pass = proc(ctx: rawptr, pass: Pass, view: int, clear: Rgb) {}, end_pass = proc(ctx: rawptr) {}, submit_depth = record_depth_item, submit_surface = record_depth_surface}}
	defer frame_render_destroy(&fr)
	span := span_open()
	frame_render_depth(&fr, draws[:], mat4_identity(), &span)
	expected := slice.clone(r.items[:], context.temp_allocator)
	clear(&r.items)
	fr.submits.submit_instances = record_depth_instances
	frame_render_depth(&fr, draws[:], mat4_identity(), &span)
	testing.expect_value(t, len(expected), 16)
	testing.expect_value(t, len(r.items), len(expected))
	testing.expect_value(t, r.batches, 4)
	for want in expected {
		found := 0
		for got in r.items { if got == want { found += 1 } }
		testing.expect_value(t, found, 1)
	}
	testing.expect_value(t, fr.instance_scratch.total_used, 0)
}

@(test)
test_instance_keys_preserve_mesh_and_shader_generations :: proc(t: ^testing.T) {
	shader: Shader
	surface := Surface_Material{shader = &shader}
	mesh: Mesh
	p := Placed{mesh = &mesh}
	part := Mesh_Part{surface = &surface, count = 3}
	base := instance_key(&p, &part, {}, 1)
	mesh.generation += 1
	testing.expect(t, instance_key(&p, &part, {}, 1) != base)
	mesh.generation -= 1
	shader.generation += 1
	testing.expect(t, instance_key(&p, &part, {}, 1) != base)
}

@(test)
test_adjacent_surface_batches_preserve_signed_zero_payload_bits :: proc(t: ^testing.T) {
	shader: Shader
	shader.package_data.manifest, _ = json.parse_string(`{"interface":{"surface":{"instancing":true}}}`, allocator = context.temp_allocator)
	negative_zero := transmute(f32)u32(0x80000000)
	values := [5]Surface_Material{{shader = &shader}, {shader = &shader}, {shader = &shader}, {shader = &shader}, {shader = &shader}}
	values[1].vertex[0] = negative_zero
	values[2].fragment[0] = negative_zero
	values[3].draw_info[0] = negative_zero
	values[4].time = negative_zero
	mesh: Mesh
	parts: [5][1]Mesh_Part
	placed: [5]Placed
	for &p, i in placed {
		parts[i][0] = {surface = &values[i], count = 3}
		p = {mesh = &mesh, parts = parts[i][:], camera_visible = true, model = mat4_identity()}
	}
	r := Instance_Recorded{counts = make([dynamic]int), tints = make([dynamic][4]f32), passes = make([dynamic]Surface_Pass)}
	defer { delete(r.counts); delete(r.tints); delete(r.passes) }
	fr := Frame_Render{placed = make([dynamic]Placed), submits = {ctx = &r, submit_instances = record_instances}}
	defer frame_render_destroy(&fr)
	append(&fr.placed, ..placed[:])
	frame_render_instances(&fr, .Selection, .Opaque, mat4_identity())
	testing.expect_value(t, len(r.counts), len(values))
	for count in r.counts { testing.expect_value(t, count, 1) }
	part := Mesh_Part{count = 3}
	fs := Fs_Params{}
	base := instance_key(&placed[0], &part, fs, 0)
	fs.material[0] = negative_zero
	testing.expect(t, instance_key(&placed[0], &part, fs, 0) != base)
}
