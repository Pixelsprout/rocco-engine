#+test
package engine

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:testing"

Instance_Recorded :: struct {
	counts: [dynamic]int,
	tints: [dynamic][4]f32,
	passes: [dynamic]Surface_Pass,
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
	for pass in ([5]Surface_Pass{.Colour, .Shadow, .Shadow, .Shadow, .Shadow}) {
		for pipeline in SCENE_ORDER_PIPELINES {
			frame_render_instances(&fr, pass, pipeline, mat4_identity())
			testing.expect_value(t, fr.instance_scratch.total_used, 0)
		}
	}
	testing.expect_value(t, r.instance_calls, 5)
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
	testing.expect_value(t, f.rec.instance_calls, 1)
	testing.expect_value(t, len(f.rec.submits), 1)
	testing.expect_value(t, f.rec.submits[0].model, f.fr.placed[0].model)
	testing.expect(t, f.fr.placed[0].selected && !f.fr.placed[1].selected)
}
