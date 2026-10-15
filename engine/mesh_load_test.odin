#+test
package engine

import "core:os"
import "core:slice"
import "core:testing"

// Each file path is relative to the new directory. Remove it with os.remove_all.
temp_mesh_dir :: proc(t: ^testing.T, files: map[string][]byte) -> string {
	dir, err := os.make_directory_temp("", "rocco-meshes-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	for path, bytes in files {
		full, _ := os.join_path({dir, path}, context.temp_allocator)
		parent, _ := os.split_path(full)
		_ = os.make_directory_all(parent)
		testing.expect_value(t, os.write_entire_file(full, bytes), nil)
	}
	return dir
}

@(test)
test_mesh_names_on_disk_are_each_glb_stem_in_sorted_order :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["notes.txt"] = transmute([]byte)string("not a mesh")
	files["sub/c.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	names := mesh_names_on_disk(dir, context.temp_allocator)
	testing.expect(t, slice.equal(names, []string{"a", "b"}))
}

@(test)
test_mesh_names_on_disk_of_a_missing_dir_are_empty :: proc(t: ^testing.T) {
	testing.expect_value(t, len(mesh_names_on_disk("no/such/rocco/dir", context.temp_allocator)), 0)
}

@(test)
test_mesh_load_file_adds_the_mesh_after_the_primitives :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	id, _, ok := mesh_load_file(&table, dir, "a")

	testing.expect(t, ok)
	testing.expect_value(t, id, len(Primitive))
	testing.expect_value(t, table.meshes[len(Primitive)].name, "a")
	testing.expect_value(t, len(table.meshes[len(Primitive)].data.vertices), 3)
	testing.expect_value(t, len(table.meshes[len(Primitive)].data.indices), 3)
}

@(test)
test_mesh_load_file_that_fails_adds_nothing_and_gives_the_reason :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["bad.glb"] = transmute([]byte)string("not a glb")
	files["flat.glb"] = triangle_glb(`[{"attributes":{"POSITION":0},"indices":2}]`)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	for name in ([]string{"bad", "flat", "gone"}) {
		_, reason, ok := mesh_load_file(&table, dir, name)
		testing.expectf(t, !ok, "expected %v to fail", name)
		testing.expect(t, reason != "")
	}
	testing.expect_value(t, table.count, len(Primitive))
}

@(test)
test_mesh_load_file_stops_at_mesh_capacity :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	table.count = MESH_CAPACITY - 1
	_, _, a_ok := mesh_load_file(&table, dir, "a")
	_, _, b_ok := mesh_load_file(&table, dir, "b")

	testing.expect(t, a_ok)
	testing.expect(t, !b_ok)
	testing.expect_value(t, table.count, MESH_CAPACITY)
	testing.expect_value(t, table.meshes[MESH_CAPACITY - 1].name, "a")
}

@(test)
test_a_reloaded_mesh_gets_a_new_id_and_the_old_id_draws_the_fallback :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	old, _, _ := mesh_load_file(&table, dir, "a")
	mesh_table_remove(&table, mesh_slot(old))
	fresh, _, _ := mesh_load_file(&table, dir, "a")

	testing.expect(t, fresh != old)
	_, fallback := mesh_resolve(&table, old, 4)
	testing.expect(t, fallback)
}
