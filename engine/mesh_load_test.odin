package engine

import "core:os"
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
test_mesh_dir_loads_each_glb_by_stem_in_sorted_order_after_the_primitives :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["notes.txt"] = transmute([]byte)string("not a mesh")
	files["sub/c.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	mesh_table_load_dir(&table, dir, context.temp_allocator)

	testing.expect_value(t, table.count, len(Primitive) + 2)
	testing.expect_value(t, table.meshes[len(Primitive)].name, "a")
	testing.expect_value(t, table.meshes[len(Primitive) + 1].name, "b")
	testing.expect_value(t, len(table.meshes[len(Primitive)].data.vertices), 3)
	testing.expect_value(t, len(table.meshes[len(Primitive)].data.indices), 3)
}

@(test)
test_mesh_dir_skips_a_file_that_fails_and_loads_the_rest :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["bad.glb"] = transmute([]byte)string("not a glb")
	files["flat.glb"] = triangle_glb(`[{"attributes":{"POSITION":0},"indices":2}]`)
	files["good.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	mesh_table_load_dir(&table, dir, context.temp_allocator)

	testing.expect_value(t, table.count, len(Primitive) + 1)
	testing.expect_value(t, table.meshes[len(Primitive)].name, "good")
}

@(test)
test_mesh_dir_that_does_not_exist_loads_nothing :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	mesh_table_load_dir(&table, "no/such/rocco/dir", context.temp_allocator)

	testing.expect_value(t, table.count, len(Primitive))
}

@(test)
test_mesh_dir_stops_at_mesh_capacity :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	dir := temp_mesh_dir(t, files)
	defer os.remove_all(dir)

	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	table.count = MESH_CAPACITY - 1
	mesh_table_load_dir(&table, dir, context.temp_allocator)

	testing.expect_value(t, table.count, MESH_CAPACITY)
	testing.expect_value(t, table.meshes[MESH_CAPACITY - 1].name, "a")
}

@(test)
test_mesh_dir_is_meshes_under_rocco_assets_or_beside_the_program :: proc(t: ^testing.T) {
	Case :: struct {
		assets, program, want: string,
	}
	cases := []Case {
		{"/games/sprout", "./examples/entity-game/main.roc", "/games/sprout/meshes"},
		{"", "./examples/entity-game/main.roc", "./examples/entity-game/assets/meshes"},
		{"", "/opt/game/entity-game.bin", "/opt/game/assets/meshes"},
		{"", "./entity-game.bin", "./assets/meshes"},
		{"", "entity-game.bin", "assets/meshes"},
		{"", "", "assets/meshes"},
	}
	for c in cases {
		testing.expect_value(t, mesh_dir_from(c.assets, c.program, context.temp_allocator), c.want)
	}
}
