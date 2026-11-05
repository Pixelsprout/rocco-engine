#+test
package engine

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"

Post_Observed :: struct { location: Post_Location, count, blooms, ui: int, tone_mapped, outside_pass: bool }

post_test_manifest :: proc(t: ^testing.T) -> string {
	value, error := json.parse_string(shader_test_manifest(), spec = .JSON, parse_integers = true, allocator = context.temp_allocator)
	testing.expect_value(t, error, nil)
	root := shader_object(value)
	interface := shader_object(root["interface"])
	surface := shader_object(interface["surface"])
	delete_key(&surface, "skinning")
	delete_key(&surface, "instancing")
	surface["max_displacement"] = json.Integer(0)
	post := shader_object(interface["post"])
	inputs := make(json.Array, 2, context.temp_allocator)
	inputs[0], inputs[1] = json.String("scene_colour"), json.String("scene_depth")
	post["inputs"] = inputs
	locations := make(json.Array, 2, context.temp_allocator)
	locations[0], locations[1] = json.String("before_bloom"), json.String("after_tone_map")
	post["locations"] = locations
	for backend in shader_array(root["shaders"]) {
		b := shader_object(backend)
		programs := shader_array(b["programs"])
		first := shader_object(programs[0]); first["name"] = json.String("post_hdr")
		second := shader_object(programs[1]); second["name"] = json.String("post_ldr")
		selected := make(json.Array, 2, context.temp_allocator)
		selected[0], selected[1] = programs[0], programs[1]
		b["programs"] = selected
	}
	result, encoded := json.unparse(value, {spec = .JSON, sort_maps_by_key = true}, allocator = context.temp_allocator)
	testing.expect_value(t, encoded, nil)
	return result
}

post_test_fixture :: proc(t: ^testing.T, f: ^Surface_Fixture) {
	frame_fixture_init(&f.frame)
	image_table_init(&f.images, SMALL_IMAGES, context.allocator, context.allocator)
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(post_test_manifest(t))
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	packs_init(&f.packs, dir, context.allocator)
	packs_attach(&f.packs, &f.frame.meshes, &f.frame.skies, &f.images, &f.audio, context.allocator)
	_, loaded := pack_load(&f.packs, "trees", {"shader/Test"}, context.temp_allocator)
	testing.expect(t, loaded)
	f.frame.fr.packs = &f.packs
}

@(test)
test_post_resolution_preserves_duplicates_and_skips_only_invalid_or_disabled_effects :: proc(t: ^testing.T) {
	f: Surface_Fixture
	post_test_fixture(t, &f)
	defer surface_fixture_destroy(&f)
	values := surface_test_values(.Draw)
	bad := values
	bad.shader.asset = roc_str_from_slice("shader/Missing")
	effects := []Post_Effect{{values, true, .BeforeBloom}, {bad, true, .BeforeBloom}, {bad, false, .AfterToneMap}, {values, true, .AfterToneMap}, {values, true, .BeforeBloom}}
	resolved := post_resolve(&f.packs, effects, nil, 2.5)
	testing.expect_value(t, len(resolved), 3)
	testing.expect_value(t, resolved[0].location, Post_Location.BeforeBloom)
	testing.expect_value(t, resolved[1].location, Post_Location.AfterToneMap)
	testing.expect_value(t, resolved[2].location, Post_Location.BeforeBloom)
	for effect in resolved { testing.expect_value(t, effect.material.time, f32(2.5)); testing.expect_value(t, effect.inputs, Post_Inputs{.Scene_Colour, .Scene_Depth}) }
	testing.expect_value(t, len(post_resolve(&f.packs, effects[1:3], nil, 0)), 0)
	values.scope = .Material
	testing.expect_value(t, len(post_resolve(&f.packs, {{values, true, .BeforeBloom}}, nil, 0)), 0)
}

@(test)
test_post_capacity_counts_enabled_valid_instances :: proc(t: ^testing.T) {
	f: Surface_Fixture
	post_test_fixture(t, &f)
	defer surface_fixture_destroy(&f)
	effects: [POST_EFFECT_LIMIT + 2]Post_Effect
	for &effect in effects { effect = {surface_test_values(.Draw), true, .AfterToneMap} }
	effects[0].enabled = false
	effects[len(effects)-1].values.shader.asset = roc_str_from_slice("shader/Missing")
	testing.expect_value(t, len(post_resolve(&f.packs, effects[:], nil, 0)), POST_EFFECT_LIMIT)
	testing.expect_value(t, len(f.packs.logged_assets), 1)
	for key in f.packs.logged_assets { testing.expect(t, strings.contains(key, "enabled effect capacity exceeded")) }
}

@(test)
test_scene_depth_reuses_surface_coverage_and_omits_blend_and_casting_policy :: proc(t: ^testing.T) {
	f: Surface_Fixture
	surface_fixture_init(t, &f)
	defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f)
	d.casts_shadow = false
	d.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	parts := surface_resolve_parts(&f.packs, &d, mesh, nil, 3.5)
	parts[0].material.alpha_mode = .Blend
	p := Placed{mesh = mesh, parts = parts, camera_visible = true, model = mat4_identity(), tint = {1,1,1}}
	span := span_open()
	frame_render_depth(&f.frame.fr, {{p = &p, vs_params = {mvp = mat4_identity(), model = mat4_identity()}}}, mat4_identity(), &span)
	testing.expect_value(t, len(f.frame.rec.surfaces), 1)
	testing.expect_value(t, f.frame.rec.surfaces[0].first, parts[1].first)
	testing.expect_value(t, f.frame.rec.surfaces[0].pass, Surface_Pass.Selection)
	testing.expect_value(t, f.frame.rec.surfaces[0].time, f32(3.5))
	testing.expect_value(t, f.frame.rec.passes[0].pass, Pass.Scene_Depth)
	testing.expect_value(t, len(f.frame.rec.shadows), 0)
	p.camera_visible = false
	frame_render_depth(&f.frame.fr, {{p = &p}}, mat4_identity(), &span)
	testing.expect_value(t, len(f.frame.rec.surfaces), 1)
	testing.expect_value(t, len(p.parts), 2)
}

post_record :: proc(ctx: rawptr, effects: []Resolved_Post, location: Post_Location, time: f32) {
	r := (^Recorder)(ctx)
	count := 0
	for effect in effects { if effect.location == location { count += 1 } }
	r.post_events[r.post_count] = {location, count, len(r.blooms), r.ui_calls, r.tone_map_pass == .Post, r.pass_ends == len(r.passes)}
	r.post_count += 1
}

@(test)
test_post_locations_surround_bloom_and_tone_mapping_before_ui :: proc(t: ^testing.T) {
	f: Surface_Fixture
	post_test_fixture(t, &f)
	defer surface_fixture_destroy(&f)
	frame_fixture_init_ui(&f.frame)
	defer frame_fixture_destroy_ui(&f.frame)
	f.frame.fr.submits.submit_post = post_record
	scene := scene_ui({ui_text("UI", 16)})
	scene.environment.bloom = {strength = 0.2, threshold = 2, knee = 0.5}
	effects := []Post_Effect{{surface_test_values(.Draw), true, .AfterToneMap}, {surface_test_values(.Draw), true, .BeforeBloom}}
	scene.post = roc_list_view(effects)
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, f.frame.rec.post_count, 2)
	a, b := f.frame.rec.post_events[0], f.frame.rec.post_events[1]
	testing.expect_value(t, a.location, Post_Location.BeforeBloom)
	testing.expect_value(t, a.count, 1)
	testing.expect(t, a.outside_pass && !a.tone_mapped && a.blooms == 0 && a.ui == 0)
	testing.expect_value(t, b.location, Post_Location.AfterToneMap)
	testing.expect_value(t, b.count, 1)
	testing.expect(t, !b.outside_pass && b.tone_mapped && b.blooms > 0 && b.ui == 0)
	testing.expect_value(t, f.frame.rec.ui_calls, 1)
}

post_depth_palette_record :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs: Vs_Params, fs: Fs_Params, skin: ^Skin_Params) {
	r := (^Recorder)(ctx)
	if !r.depth_has_pipeline || r.depth_pipeline != pipeline { r.depth_skin = nil }
	r.depth_pipeline, r.depth_has_pipeline = pipeline, true
	if skin != nil && skin != r.depth_skin { r.depth_palette_count += 1; r.depth_skin = skin }
}

@(test)
test_scene_depth_groups_alternating_mask_parts_within_the_admitted_palette_budget :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f, draws = 12800)
	defer frame_fixture_destroy(&f)
	parts := make([]Mesh_Part, 100, context.temp_allocator)
	for &part, i in parts { part.material = MATERIAL_MATTE; part.material.alpha_mode = .Mask; part.material.double_sided = i % 2 == 0 }
	placed := make([]Placed, 128, context.temp_allocator)
	draws := make([]Draw_Params, 128, context.temp_allocator)
	for &p, i in placed {
		p.parts, p.skin = parts, &f.fr.skins[i]
		p.camera_visible = true
		draws[i].p = &p
	}
	f.fr.submits.submit_depth = post_depth_palette_record
	span := span_open()
	frame_render_depth(&f.fr, draws, mat4_identity(), &span)
	testing.expect_value(t, f.rec.depth_palette_count, 256)
	testing.expect_value(t, len(f.fr.skins), 256)
}

post_selection_inputs :: proc(ctx: rawptr, effects: []Resolved_Post) -> Post_Inputs {
	return {.Scene_Depth, .Selection_Coverage, .Selection_Depth}
}

@(test)
test_selection_draws_one_independent_union_including_blend_and_noncasters :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	parts := []Mesh_Part{
		{first = 0, material = {alpha_mode = .Opaque}},
		{first = 3, material = {alpha_mode = .Mask, alpha_cutoff = 0.4}},
		{first = 6, material = {alpha_mode = .Blend, double_sided = true}},
	}
	placed := []Placed{
		{selected = true, camera_visible = true, parts = parts},
		{selected = false, camera_visible = true, parts = parts},
		{selected = true, camera_visible = false, parts = parts},
	}
	draws := make([]Draw_Params, len(placed), context.temp_allocator)
	for &p, i in placed { draws[i] = {p = &p, vs_params = {model = mat4_translate({f32(i), 2, 3})}} }
	f.fr.submits.submit_selection = record_submit
	span := span_open()
	frame_render_selection(&f.fr, draws, &span)
	testing.expect_value(t, len(f.rec.passes), 1)
	testing.expect_value(t, f.rec.passes[0].pass, Pass.Selection)
	testing.expect_value(t, f.rec.pass_ends, 1)
	testing.expect_value(t, len(f.rec.submits), 3)
	for got, i in f.rec.submits {
		testing.expect_value(t, got.part.first, i*3)
		testing.expect_value(t, got.model, draws[0].vs_params.model)
	}
	testing.expect_value(t, f.rec.submits[2].pipeline, Mesh_Pipeline.Mask_Double_Sided)
	testing.expect_value(t, len(f.rec.shadows), 0)
}

@(test)
test_selection_preserves_surface_values_time_transform_and_palette :: proc(t: ^testing.T) {
	f: Surface_Fixture
	surface_fixture_init(t, &f)
	defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f)
	d.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	mesh, _ := mesh_lookup(&f.frame.meshes, d.mesh)
	parts := surface_resolve_parts(&f.packs, &d, mesh, nil, 3.5)
	parts[0].material.alpha_mode = .Blend
	p := Placed{mesh = mesh, parts = parts, selected = true, camera_visible = true, skin = &f.frame.fr.skins[0]}
	vs := Vs_Params{model = mat4_translate({1, 2, 3})}
	span := span_open()
	frame_render_selection(&f.frame.fr, {{p = &p, vs_params = vs}}, &span)
	testing.expect_value(t, len(f.frame.rec.surfaces), 2)
	for got in f.frame.rec.surfaces {
		testing.expect_value(t, got.pass, Surface_Pass.Selection)
		testing.expect_value(t, got.time, f32(3.5))
		testing.expect_value(t, got.model, vs.model)
		testing.expect_value(t, got.skin, p.skin)
	}
}

@(test)
test_selection_follows_scene_depth_before_post_and_keeps_one_clear_without_selected_groups :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.fr.submits.prepare_post = post_selection_inputs
	f.fr.submits.submit_post = post_record
	scene := scene_of(nil)
	frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, len(f.rec.passes), 4)
	testing.expect_value(t, f.rec.passes[1].pass, Pass.Scene_Depth)
	testing.expect_value(t, f.rec.passes[2].pass, Pass.Selection)
	testing.expect(t, f.rec.post_events[0].outside_pass)
	testing.expect_value(t, len(f.rec.submits), 0)
}

@(test)
test_selection_groups_alternating_parts_within_the_admitted_palette_budget :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f, draws = 12800)
	defer frame_fixture_destroy(&f)
	parts := make([]Mesh_Part, 100, context.temp_allocator)
	for &part, i in parts { part.material = MATERIAL_MATTE; part.material.alpha_mode = .Mask; part.material.double_sided = i % 2 == 0 }
	placed := make([]Placed, 128, context.temp_allocator)
	draws := make([]Draw_Params, 128, context.temp_allocator)
	for &p, i in placed {
		p.parts, p.skin = parts, &f.fr.skins[i]
		p.selected, p.camera_visible = true, true
		draws[i].p = &p
	}
	f.fr.submits.submit_selection = post_depth_palette_record
	span := span_open()
	frame_render_selection(&f.fr, draws, &span)
	testing.expect_value(t, f.rec.depth_palette_count, 256)
}
