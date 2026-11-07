#+test
package engine

import "core:testing"

@(test)
test_surface_reuse_compares_values_and_preserves_each_draw :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	a, b := surface_test_draw(&f), surface_test_draw(&f)
	a.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	b.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	ap := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.25}}}
	bp := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.25}}}
	a.material.properties, b.material.properties = roc_list_view(ap), roc_list_view(bp)
	b.id = 11; b.pos = {2, 0, 0}; b.tint = {0.2, 0.4, 0.6}; b.glow = {0.1, 0.2, 0.3}; b.casts_shadow = false
	scene := scene_lit({a, b}, {light_sun({x = 0, y = -1, z = 0}, {r = 1, g = 1, b = 1})}, default_casting = false)
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, len(f.frame.fr.placed), 2)
	first, second := &f.frame.fr.placed[0], &f.frame.fr.placed[1]
	testing.expect(t, first.parts[0].surface == second.parts[0].surface)
	testing.expect(t, first.model != second.model)
	testing.expect_value(t, second.tint, b.tint)
	testing.expect_value(t, second.glow, b.glow)
	testing.expect_value(t, second.shadow_count, 0)
	testing.expect_value(t, len(f.frame.rec.submits), 4)
	testing.expect_value(t, len(f.frame.rec.shadows), 2)
}

@(test)
test_surface_reuse_rejects_colliding_values_and_excluded_overrides :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	a := surface_test_draw(&f); a.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	b := a; b.id = 11
	ap := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.25}}}
	bp := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.75}}}
	a.material.properties, b.material.properties = roc_list_view(ap), roc_list_view(bp)
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	surface_reuse_init(&cache)
	parts := surface_reuse_parts(&cache, &f.packs, &a, mesh, nil, 0)
	hash, eligible := surface_reuse_hash(&b); testing.expect(t, eligible)
	cache.buckets[hash] = {count = 1}
	found, hit := surface_reuse_find(&cache, hash, &b, mesh)
	testing.expect(t, !hit && len(found) == 0)
	resolved := surface_reuse_parts(&cache, &f.packs, &b, mesh, nil, 0)
	testing.expect_value(t, parts[0].material.roughness, f32(0.25))
	testing.expect_value(t, resolved[0].material.roughness, f32(0.75))
	values := []Shader_Values{surface_test_values(.Draw)}
	b.shader_values = roc_list_view(values)
	_, eligible = surface_reuse_hash(&b); testing.expect(t, !eligible)
	slots := []Roc_VocabularyNode_Draw_SlotMaterials{{slot = surface_test_slot(1)}}
	b.shader_values = {}; b.slot_materials = roc_list_view(slots)
	_, eligible = surface_reuse_hash(&b); testing.expect(t, !eligible)
}

@(test)
test_surface_reuse_ends_before_scene_time_and_pack_changes :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	a := surface_test_draw(&f); a.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	b := a; b.id = 11
	scene := scene_of({a, b})
	scene_values := []Shader_Values{surface_test_values(.Scene)}
	wind := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name = roc_str_from_slice("wind"), value = {tag = .Scalar, payload = {scalar = 0.2}}}}
	scene_values[0].parameters = roc_list_view(wind); scene.shader_values = roc_list_view(scene_values)
	f.frame.fr.render_time = 1.25
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, f.frame.fr.placed[1].parts[0].surface.vertex[0], f32(0.2))
	testing.expect_value(t, f.frame.fr.placed[1].parts[0].surface.time, f32(1.25))
	wind[0].value.payload.scalar = 0.8; f.frame.fr.render_time = 2.5
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, f.frame.fr.placed[1].parts[0].surface.vertex[0], f32(0.8))
	testing.expect_value(t, f.frame.fr.placed[1].parts[0].surface.time, f32(2.5))
	testing.expect(t, pack_unload(&f.packs, "trees"))
	frame_fixture_draw(&f.frame, scene, scene, 0)
	testing.expect_value(t, len(f.frame.fr.placed), 0)
	testing.expect(t, len(f.packs.logged_assets) >= 2)
}

@(test)
test_surface_partial_resolution_reports_incomplete :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f); values := surface_test_values(); values.shader.asset = roc_str_from_slice("shader/Missing")
	assignments := []Roc_VocabularyNode_Draw_Materials{{slot = surface_test_slot(1), values = values}}
	d.materials = roc_list_view(assignments)
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	complete := true
	parts := surface_resolve_parts(&f.packs, &d, mesh, nil, 0, &complete)
	testing.expect_value(t, len(parts), 1)
	testing.expect(t, !complete)
}

@(test)
test_surface_reuse_distinguishes_defaults_parameters_and_draw_scope :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f); d.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	omitted := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	parameters := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name = roc_str_from_slice("tint"), value = {tag = .LinearColour, payload = {linear_colour = {r = 1, g = 1, b = 1, a = 1}}}}}
	d.material.surface.payload.surface.parameters = roc_list_view(parameters)
	explicit := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	testing.expect_value(t, len(cache.entries), 2)
	testing.expect(t, omitted[0].surface != explicit[0].surface)
	equal_parameters := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{parameters[0]}
	d.material.surface.payload.surface.parameters = roc_list_view(equal_parameters)
	equal := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	testing.expect(t, equal[0].surface == explicit[0].surface)
	changed_parameters := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{parameters[0]}
	changed_parameters[0].value.payload.linear_colour.r = 0.2
	d.material.surface.payload.surface.parameters = roc_list_view(changed_parameters)
	changed := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	testing.expect_value(t, changed[0].surface.fragment[0], f32(0.2))
	testing.expect_value(t, explicit[0].surface.fragment[0], f32(1))
	phase := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name = roc_str_from_slice("phase"), value = {tag = .Scalar, payload = {scalar = 0.75}}}}
	values := []Shader_Values{surface_test_values(.Draw)}; values[0].parameters = roc_list_view(phase)
	d.shader_values = roc_list_view(values)
	per_draw := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	testing.expect_value(t, per_draw[0].surface.vertex[4], f32(0.75))
	testing.expect_value(t, len(cache.entries), 3)
}

@(test)
test_surface_reuse_shared_lists_reuse_only_matching_draws :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	a := surface_test_draw(&f); a.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	shared := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.25}}}
	a.material.properties = roc_list_view(shared)
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	first := surface_reuse_parts(&cache, &f.packs, &a, mesh, nil, 0)
	b := a; b.id = 11
	testing.expect(t, raw_data(surface_reuse_parts(&cache, &f.packs, &b, mesh, nil, 0)) == raw_data(first))

	other := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.75}}}
	c := a; c.material.properties = roc_list_view(other)
	testing.expect_value(t, surface_reuse_parts(&cache, &f.packs, &c, mesh, nil, 0)[0].material.roughness, f32(0.75))

	slots := []Roc_VocabularyNode_Draw_SlotMaterials{{slot = surface_test_slot(1)}}
	s := a; s.slot_materials = roc_list_view(slots)
	testing.expect(t, raw_data(surface_reuse_parts(&cache, &f.packs, &s, mesh, nil, 0)) != raw_data(first))

	missing := a; missing.material.surface.payload.surface.shader.asset = roc_str_from_slice("shader/Missing")
	unresolved := surface_reuse_parts(&cache, &f.packs, &missing, mesh, nil, 0)
	testing.expect(t, raw_data(unresolved) != raw_data(first))
	testing.expect(t, raw_data(surface_reuse_parts(&cache, &f.packs, &missing, mesh, nil, 0)) != raw_data(first))
	testing.expect(t, raw_data(surface_reuse_parts(&cache, &f.packs, &a, mesh, nil, 0)) == raw_data(first))
}

@(test)
test_surface_reuse_capacity_and_collision_overflow_resolve_normally :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f); d.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	for i in 0 ..= SURFACE_REUSE_LIMIT {
		properties := make([]Roc_VocabularyNode_Draw_Material_Properties, 1, context.temp_allocator)
		properties[0] = {tag = .Roughness, payload = {roughness = f32(i) / f32(SURFACE_REUSE_LIMIT)}}
		d.material.properties = roc_list_view(properties)
		parts := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
		testing.expect_value(t, parts[0].material.roughness, properties[0].payload.roughness)
	}
	testing.expect_value(t, len(cache.entries), SURFACE_REUSE_LIMIT)
	properties := []Roc_VocabularyNode_Draw_Material_Properties{{tag = .Roughness, payload = {roughness = 0.99}}}
	d.material.properties = roc_list_view(properties)
	hash, _ := surface_reuse_hash(&d)
	bucket: Surface_Reuse_Bucket
	for i in 0 ..< SURFACE_REUSE_BUCKET_LIMIT { bucket.entries[i] = i }
	bucket.count = SURFACE_REUSE_BUCKET_LIMIT
	cache.buckets[hash] = bucket
	parts := surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)
	testing.expect_value(t, parts[0].material.roughness, f32(0.99))
	testing.expect_value(t, len(cache.entries), SURFACE_REUSE_LIMIT)
	testing.expect_value(t, cache.buckets[hash].count, SURFACE_REUSE_BUCKET_LIMIT)
}

@(test)
test_surface_reuse_keeps_invalid_draw_diagnostics_separate :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	d := surface_test_draw(&f); values := surface_test_values(); values.shader.asset = roc_str_from_slice("shader/Missing")
	d.material.surface = {tag = .Surface, payload = {surface = values}}
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	for id in ([2]u64{10, 11}) {
		d.id = id
		testing.expect_value(t, len(surface_reuse_parts(&cache, &f.packs, &d, mesh, nil, 0)), 0)
	}
	testing.expect_value(t, len(cache.entries), 0)
	testing.expect_value(t, len(f.packs.logged_assets), 2)
}

@(test)
test_surface_reuse_preserves_signed_zero_under_hash_collision :: proc(t: ^testing.T) {
	f: Surface_Fixture; surface_fixture_init(t, &f); defer surface_fixture_destroy(&f)
	a := surface_test_draw(&f); a.material.surface = {tag = .Surface, payload = {surface = surface_test_values()}}
	b := a; b.id = 11
	positive := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name = roc_str_from_slice("tint"), value = {tag = .LinearColour, payload = {linear_colour = {r = 0, g = 1, b = 1, a = 1}}}}}
	negative := []Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{positive[0]}
	negative[0].value.payload.linear_colour.r = transmute(f32)u32(0x80000000)
	a.material.surface.payload.surface.parameters = roc_list_view(positive)
	b.material.surface.payload.surface.parameters = roc_list_view(negative)
	mesh, _ := mesh_lookup(&f.frame.meshes, f.mesh)
	cache: Surface_Reuse
	surface_reuse_parts(&cache, &f.packs, &a, mesh, nil, 0)
	hash, _ := surface_reuse_hash(&b)
	cache.buckets[hash] = {count = 1}
	_, hit := surface_reuse_find(&cache, hash, &b, mesh)
	testing.expect(t, !hit)
	parts := surface_reuse_parts(&cache, &f.packs, &b, mesh, nil, 0)
	testing.expect_value(t, transmute(u32)parts[0].surface.fragment[0], u32(0x80000000))
	testing.expect_value(t, len(cache.entries), 2)
}
