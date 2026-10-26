#+test
package engine

import "core:strings"
import "core:testing"

skinned_fixture_data :: proc(t: ^testing.T) -> Mesh_Data {
	data, _, err := glb_parse(skinned_glb(t), context.allocator)
	testing.expect_value(t, err, Glb_Error.None)
	return data
}

@(test)
test_mesh_table_pads_the_box_of_a_skinned_mesh_by_a_quarter_of_its_largest_side :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	slot, _ := mesh_table_add(&table, strings.clone("strip"), skinned_fixture_data(t))
	testing.expect_value(t, table.meshes[slot].box, Box{{-1, -0.5, -0.5}, {1, 2.5, 0.5}})
}

@(test)
test_mesh_table_keeps_the_skin_apart_from_the_upload_data :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	slot, _ := mesh_table_add(&table, strings.clone("strip"), skinned_fixture_data(t))
	m := &table.meshes[slot]
	testing.expect_value(t, len(m.skin.joints), 3)
	testing.expect_value(t, m.skin.clips[0].name, "Bend")
	testing.expect_value(t, len(m.data.skin.joints), 0)
	testing.expect_value(t, len(m.data.influences), 6)
}

@(test)
test_mesh_table_gives_clip_ids_from_1_that_a_new_mesh_never_reuses :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	a, _ := mesh_table_add(&table, strings.clone("a"), skinned_fixture_data(t))
	b, _ := mesh_table_add(&table, strings.clone("b"), skinned_fixture_data(t))
	testing.expect_value(t, table.meshes[a].first_clip, 1)
	testing.expect_value(t, table.meshes[b].first_clip, 2)

	bend, ok := mesh_clip(&table.meshes[a], 1)
	testing.expect(t, ok)
	testing.expect_value(t, bend.name, "Bend")
	for id in ([]u32{0, 2, 3}) {
		_, found := mesh_clip(&table.meshes[a], id)
		testing.expectf(t, !found, "Clip id %v is not a Clip of mesh a", id)
	}
	_, ok = mesh_clip(&table.meshes[b], 2)
	testing.expect(t, ok)
	_, ok = mesh_clip(&table.meshes[Primitive.Cube], 1)
	testing.expect(t, !ok)

	mesh_table_remove(&table, a)
	c, _ := mesh_table_add(&table, strings.clone("c"), skinned_fixture_data(t))
	testing.expect_value(t, c, a)
	testing.expect_value(t, table.meshes[c].first_clip, 3)
	_, ok = mesh_clip(&table.meshes[c], 1)
	testing.expect(t, !ok)
}

@(test)
test_skinned_vertices_pair_each_vertex_with_its_influence :: proc(t: ^testing.T) {
	vertices := []Vertex{{pos = {1, 2, 3}, color = GREY}, {pos = {4, 5, 6}, uv = {1, 0}}}
	influences := []Influence{{joints = {1, 0, 0, 0}, weights = {255, 0, 0, 0}}, {joints = {2, 3, 0, 0}, weights = {64, 191, 0, 0}}}
	out := skinned_vertices(vertices, influences, context.temp_allocator)
	testing.expect_value(t, len(out), 2)
	for v, i in out {
		testing.expect_value(t, v.vertex, vertices[i])
		testing.expect_value(t, v.influence, influences[i])
	}
}
