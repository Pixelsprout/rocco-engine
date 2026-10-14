package engine

import "core:math/linalg"
import "core:testing"

@(test)
test_mesh_table_resolves_a_known_id_to_its_slot :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	mesh, fallback := mesh_resolve(&table, u32(Primitive.Sphere), 4)
	testing.expect(t, !fallback)
	testing.expect_value(t, mesh, &table.meshes[Primitive.Sphere])
	testing.expect_value(t, len(table.logged), 0)
}

@(test)
test_mesh_table_resolves_id_0_and_unknown_ids_to_the_fallback :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	ids := []u32 {
		0,
		9,
		len(Primitive),
		MESH_CAPACITY,
		max(u32),
		1 << MESH_SLOT_BITS,
		1 << MESH_SLOT_BITS | u32(Primitive.Cube),
	}
	for id in ids {
		mesh, fallback := mesh_resolve(&table, id, 4)
		testing.expectf(t, fallback, "expected mesh id %v to be the fallback", id)
		testing.expect_value(t, mesh, &table.meshes[Primitive.Fallback])
	}
}

@(test)
test_mesh_table_logs_each_fallback_id_once :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	for id in ([]u32{9, 9, 0, 0, 9, 1}) {
		mesh_resolve(&table, id, 4)
	}
	testing.expect_value(t, len(table.logged), 2)
	testing.expect(t, 9 in table.logged)
	testing.expect(t, 0 in table.logged)
}

// packages/mesh/Mesh.roc pins the same ids, so a change to the slot order fails a test on each side.
@(test)
test_each_primitive_has_its_fixed_id_by_name :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	Case :: struct {
		name: string,
		id:   u32,
	}
	for c in ([]Case{{"primitive/fallback", 0}, {"primitive/cube", 1}, {"primitive/sphere", 2}, {"primitive/plane", 3}}) {
		id, found := mesh_table_find(&table, c.name)
		testing.expectf(t, found, "expected %v in the mesh table", c.name)
		testing.expect_value(t, id, c.id)
	}
	_, found := mesh_table_find(&table, "cube")
	testing.expect(t, !found)
}

@(test)
test_a_first_generation_id_is_the_slot_index :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)

	testing.expect_value(t, mesh_id(&table, int(Primitive.Sphere)), u32(Primitive.Sphere))
}

@(test)
test_sphere_has_16_rings_of_32_segments :: proc(t: ^testing.T) {
	data := primitive_build(.Sphere, context.temp_allocator)
	testing.expect_value(t, len(data.vertices), 561)
	testing.expect_value(t, len(data.indices), 3 * SPHERE_SEGMENTS * (2 * SPHERE_RINGS - 2))
}

@(test)
test_every_primitive_winds_ccw_from_outside :: proc(t: ^testing.T) {
	for p in Primitive {
		data := primitive_build(p, context.temp_allocator)
		testing.expectf(t, len(data.indices) % 3 == 0, "%v has a partial triangle", p)
		for i := 0; i < len(data.indices); i += 3 {
			a := data.vertices[data.indices[i]]
			b := data.vertices[data.indices[i + 1]]
			c := data.vertices[data.indices[i + 2]]
			face := v3_cross(b.pos - a.pos, c.pos - a.pos)
			// Every vertex normal points outside, so the face normal agrees with it.
			testing.expectf(t, v3_dot(face, a.normal + b.normal + c.normal) > 0, "%v triangle %v winds clockwise from outside", p, i / 3)
		}
	}
}

@(test)
test_sphere_normals_are_unit_and_point_out :: proc(t: ^testing.T) {
	data := primitive_build(.Sphere, context.temp_allocator)
	for v in data.vertices {
		testing.expect(t, abs(v3_dot(v.normal, v.normal) - 1) < 1e-4)
		testing.expect(t, abs(v3_dot(v.pos, v.pos) - 0.25) < 1e-4)
		testing.expect(t, v3_dot(v.pos, v.normal) > 0)
	}
}

@(test)
test_plane_is_one_quad_facing_up :: proc(t: ^testing.T) {
	data := primitive_build(.Plane, context.temp_allocator)
	testing.expect_value(t, len(data.vertices), 4)
	testing.expect_value(t, len(data.indices), 6)
	for v in data.vertices {
		testing.expect_value(t, v.pos.y, 0)
		testing.expect_value(t, v.normal, [3]f32{0, 1, 0})
	}
}

@(test)
test_fallback_is_a_magenta_cube :: proc(t: ^testing.T) {
	fallback := primitive_build(.Fallback, context.temp_allocator)
	cube := primitive_build(.Cube, context.temp_allocator)
	testing.expect_value(t, len(fallback.vertices), len(cube.vertices))
	for v, i in fallback.vertices {
		testing.expect_value(t, v.color, [4]f32{1, 0, 1, 1})
		testing.expect_value(t, v.pos, cube.vertices[i].pos)
	}
}

// A primitive with every uv at one point would draw a texture as one flat texel.
@(test)
test_every_primitive_has_uvs_from_0_to_1 :: proc(t: ^testing.T) {
	for p in Primitive {
		data := primitive_build(p, context.temp_allocator)
		lo, hi := [2]f32{1, 1}, [2]f32{0, 0}
		for v in data.vertices {
			lo = linalg.min(lo, v.uv)
			hi = linalg.max(hi, v.uv)
		}
		testing.expectf(t, lo == {0, 0} && hi == {1, 1}, "%v has uvs from %v to %v, want 0 to 1", p, lo, hi)
	}
}

@(test)
test_each_cube_face_spans_the_whole_texture :: proc(t: ^testing.T) {
	data := primitive_build(.Cube, context.temp_allocator)
	for face in 0 ..< 6 {
		corners := data.vertices[face * 4:][:4]
		for a, i in corners {
			for b in corners[i + 1:] {
				testing.expectf(t, a.uv != b.uv, "face %v repeats uv %v", face, a.uv)
			}
		}
	}
}

@(test)
test_a_mesh_without_a_texture_binds_the_white_image :: proc(t: ^testing.T) {
	white := Mesh_Texture{image = {id = 1}, view = {id = 2}, sampler = {id = 3}}
	plain := Mesh{}
	testing.expect_value(t, mesh_texture_or(&plain, white), white)
	textured := Mesh{texture = {image = {id = 7}, view = {id = 8}, sampler = {id = 9}}}
	testing.expect_value(t, mesh_texture_or(&textured, white), textured.texture)
}
