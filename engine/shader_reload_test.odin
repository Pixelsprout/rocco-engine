#+test
package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

shader_reload_record :: proc(t: ^testing.T, dir, name: string, bytes: []byte, revision := "test") {
	path := fmt.tprintf("%v/%v.shaderpack", dir, name)
	testing.expect(t, os.write_entire_file(path, bytes) == nil)
	record := strings.concatenate({`{"contract":1,"revision":"`, revision, `","assets":[{"asset":"shader/`, name, `","file":"`, name, `.shaderpack","sha256":"`, shader_hash_text(bytes), `"}]}`}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/build.json", dir), transmute([]byte)record) == nil)
}

@(test)
test_shader_reload_preserves_shared_ids_and_pack_request_membership :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest(), "first")
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	a, _ := pack_load(&p, "a", {"shader/Test"}, context.temp_allocator)
	b, _ := pack_load(&p, "b", {"shader/Test"}, context.temp_allocator)
	testing.expect_value(t, a[0].id, b[0].id)
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest(), "second"))
	packs_shader_reload(&p)
	for pack in ([]string{"a", "b"}) { asset, ok := pack_asset_lookup(&p, pack, "shader/Test"); testing.expect(t, ok); testing.expect_value(t, asset.id, a[0].id) }
	testing.expect_value(t, p.shaders.refs[mesh_slot(a[0].id)], 2)
	testing.expect(t, pack_unload(&p, "a"))
	_, ok := pack_asset_lookup(&p, "a", "shader/Test"); testing.expect(t, !ok)
	_, ok = pack_asset_lookup(&p, "b", "shader/Test"); testing.expect(t, ok)
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest(), "third"))
	packs_shader_reload(&p)
	testing.expect_value(t, p.shaders.refs[mesh_slot(a[0].id)], 1)
	testing.expect(t, pack_unload(&p, "b"))
	_, ok = shader_lookup(&p.shaders, a[0].id); testing.expect(t, !ok)
}

@(test)
test_shader_reload_recovers_missing_and_invalid_first_loads :: proc(t: ^testing.T) {
	for invalid in ([]bool{false, true}) {
		files := make(map[string][]byte, context.temp_allocator)
		files["shaders/placeholder"] = {'x'}
		if invalid { files["shaders/Test.shaderpack"] = {'x'} }
		dir := temp_assets_dir(t, files)
		p: Packs; packs_init(&p, dir, context.allocator)
		for pack in ([]string{"a", "b", "unloaded"}) { lines, _ := pack_load(&p, pack, {"shader/Test"}, context.temp_allocator); testing.expect_value(t, lines[0].id, u32(0)) }
		pack_unload(&p, "unloaded")
		shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest()))
		packs_shader_reload(&p)
		for pack in ([]string{"a", "b"}) { asset, ok := pack_asset_lookup(&p, pack, "shader/Test"); testing.expect(t, ok && asset.id != 0); testing.expect_value(t, p.shaders.refs[mesh_slot(asset.id)], 2) }
		_, ok := pack_asset_lookup(&p, "unloaded", "shader/Test"); testing.expect(t, !ok)
		packs_destroy(&p); os.remove_all(dir)
	}
}

@(test)
test_shader_reload_rejects_incomplete_publication_and_incompatible_interface :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	first := shader_test_pack(shader_test_manifest(), "first")
	files["shaders/Test.shaderpack"] = first
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	lines, _ := pack_load(&p, "a", {"shader/Test"}, context.temp_allocator)
	active, _ := shader_lookup(&p.shaders, lines[0].id)
	second := shader_test_pack(shader_test_manifest(), "second")
	shader_reload_record(t, p.shader_dir, "Test", second)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/Test.shaderpack", p.shader_dir), first) == nil)
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "first")
	testing.expect(t, !p.shader_revision_set)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/Test.shaderpack", p.shader_dir), second) == nil)
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "second")
	metadata, _ := strings.replace_all(shader_test_manifest(), `"max_displacement":0.25`, `"max_displacement":0.5`, context.temp_allocator)
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(metadata, "incompatible"))
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "second")
	testing.expect_value(t, active.package_data.max_displacement, f32(0.25))
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest(), "fixed"))
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "fixed")
}

@(test)
test_shader_reload_staging_capacity_preserves_active_id_and_retries :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest(), "first")
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	lines, _ := pack_load(&p, "a", {"shader/Test"}, context.temp_allocator)
	for &s, slot in p.shaders.assets { if slot > 1 { s.staged = true } }
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest(), "second"))
	packs_shader_reload(&p)
	active, ok := shader_lookup(&p.shaders, lines[0].id); testing.expect(t, ok)
	testing.expect_value(t, string(active.package_data.payload), "first")
	testing.expect_value(t, p.shaders.refs[mesh_slot(lines[0].id)], 1)
	testing.expect(t, !p.shader_revision_set)
	p.shaders.assets[2].staged = false
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "second")
}

@(test)
test_shader_reload_staged_names_stay_private_and_old_generation_retires :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["Test.shaderpack"] = shader_test_pack(shader_test_manifest(), "first")
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	table: Shader_Table; shader_table_init(&table, context.allocator); defer shader_table_destroy(&table)
	id, _, _ := shader_load_file(&table, dir, "shader/Test")
	active, _ := shader_lookup(&table, id)
	bytes := shader_test_pack(shader_test_manifest(), "second", context.allocator)
	slot, reason := shader_candidate_stage(&table, "shader/Test", bytes, active)
	testing.expect_value(t, reason, "")
	found, _ := shader_table_find(&table, "shader/Test"); testing.expect_value(t, found, id)
	_, ok := shader_lookup(&table, shader_id(&table, slot)); testing.expect(t, !ok)
	active.ready = true; table.uploaded = true
	testing.expect_value(t, shader_candidate_publish(&table, slot, mesh_slot(id)), id)
	testing.expect(t, table.assets[slot].retiring)
	for _ in 0 ..< 2 { shader_table_frame(&table); testing.expect(t, table.assets[slot].retiring) }
	shader_table_frame(&table); testing.expect(t, !table.assets[slot].retiring)
	testing.expect_value(t, string(active.package_data.payload), "second")
}

@(test)
test_shader_reload_repeated_rejection_and_replacement_free_all_owned_memory :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator; mem.tracking_allocator_init(&tracker, context.allocator); defer mem.tracking_allocator_destroy(&tracker)
	allocator := mem.tracking_allocator(&tracker)
	files := make(map[string][]byte, context.temp_allocator); files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest())
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, allocator)
	pack_load(&p, "a", {"shader/Test"}, context.temp_allocator)
	for i in 0 ..< 20 {
		shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest(), fmt.tprintf("code-%v", i)))
		packs_shader_reload(&p)
		shader_reload_record(t, p.shader_dir, "Test", {'b', 'a', 'd'}, fmt.tprintf("bad-%v", i))
		packs_shader_reload(&p)
	}
	pack_unload(&p, "a"); packs_destroy(&p)
	testing.expect_value(t, tracker.current_memory_allocated, i64(0))
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
test_shader_reload_recovers_a_request_after_an_earlier_completion_observation :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/placeholder"] = {'x'}
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	pack_load(&p, "unrelated", {"shader/Other"}, context.temp_allocator)
	shader_reload_record(t, p.shader_dir, "Test", shader_test_pack(shader_test_manifest()))
	packs_shader_reload(&p)
	testing.expect(t, p.shader_revision_set)
	lines, _ := pack_load(&p, "late", {"shader/Test"}, context.temp_allocator)
	testing.expect_value(t, lines[0].id, u32(0))
	testing.expect(t, !p.shader_revision_set)
	packs_shader_reload(&p)
	asset, ok := pack_asset_lookup(&p, "late", "shader/Test")
	testing.expect(t, ok && asset.id != 0)
}

@(test)
test_shader_reload_without_requests_preserves_the_no_io_path :: proc(t: ^testing.T) {
	p: Packs
	packs_shader_reload_poll(&p)
	testing.expect(t, !p.shader_polled && !p.shader_revision_set)
}

@(test)
test_shader_reload_distinguishes_declared_assets_from_standalone_packages :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest())
	files["shaders/Standalone.shaderpack"] = shader_test_pack(shader_test_manifest())
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	lines, _ := pack_load(&p, "a", {"shader/Test", "shader/Standalone"}, context.temp_allocator)
	shader_reload_record(t, p.shader_dir, "Test", files["shaders/Test.shaderpack"])
	packs_shader_reload(&p)
	active, _ := shader_lookup(&p.shaders, lines[0].id)
	standalone, _ := shader_lookup(&p.shaders, lines[1].id)
	testing.expect(t, active.declared && !standalone.declared)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/build.json", p.shader_dir), `{"contract":1,"assets":[]}`) == nil)
	packs_shader_reload(&p)
	testing.expect(t, active.live && active.declared && standalone.live && !standalone.declared)
	testing.expect_value(t, shader_id(&p.shaders, mesh_slot(lines[0].id)), lines[0].id)
}

@(test)
test_shader_reload_waits_for_unrequested_packages_in_the_completion_record :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest(), "first")
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	p: Packs; packs_init(&p, dir, context.allocator); defer packs_destroy(&p)
	lines, _ := pack_load(&p, "a", {"shader/Test"}, context.temp_allocator)
	active, _ := shader_lookup(&p.shaders, lines[0].id)
	second := shader_test_pack(shader_test_manifest(), "second")
	other := shader_test_pack(shader_test_manifest(), "other")
	shader_reload_record(t, p.shader_dir, "Test", second)
	first_record, _ := shader_read_file(fmt.tprintf("%v/build.json", p.shader_dir), context.temp_allocator, SHADER_METADATA_LIMIT)
	record := strings.concatenate({string(first_record[:len(first_record)-2]), `,{"asset":"shader/Other","file":"Other.shaderpack","sha256":"`, shader_hash_text(other), `"}]}`}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/build.json", p.shader_dir), record) == nil)
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "first")
	testing.expect(t, !p.shader_revision_set)
	testing.expect(t, os.write_entire_file(fmt.tprintf("%v/Other.shaderpack", p.shader_dir), other) == nil)
	packs_shader_reload(&p)
	testing.expect_value(t, string(active.package_data.payload), "second")
}
