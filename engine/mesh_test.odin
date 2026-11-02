#+test
package engine

import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:testing"

// Two slots past the Fallback mesh and the Primitives, so two adds fill the table.
SMALL_MESHES :: len(Primitive) + 2

@(test)
test_mesh_table_holds_its_capacity_and_refuses_the_next_add :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	for name in ([]string{"a", "b"}) {
		_, ok := mesh_table_add(&table, strings.clone(name), {})
		testing.expectf(t, ok, "expected %v to fit", name)
	}
	testing.expect(t, mesh_table_full(&table))
	_, ok := mesh_table_add(&table, "c", {})
	testing.expect(t, !ok)
	testing.expect_value(t, table.count, SMALL_MESHES)

	mesh_table_remove(&table, SMALL_MESHES - 1)
	testing.expect(t, !mesh_table_full(&table))
	slot, refilled := mesh_table_add(&table, strings.clone("d"), {})
	testing.expect(t, refilled)
	testing.expect_value(t, slot, SMALL_MESHES - 1)
}

@(test)
test_mesh_table_resolves_a_known_id_to_its_slot :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	mesh, fallback := mesh_resolve(&table, u32(Primitive.Sphere), 4)
	testing.expect(t, !fallback)
	testing.expect_value(t, mesh, &table.meshes[Primitive.Sphere])
	testing.expect_value(t, len(table.logged), 0)
}

@(test)
test_mesh_table_resolves_id_0_and_unknown_ids_to_the_fallback :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	ids := []u32 {
		0,
		9,
		len(Primitive),
		SMALL_MESHES,
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
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
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
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
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
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
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
test_every_primitive_has_unit_tangents_at_right_angles_to_its_normals :: proc(t: ^testing.T) {
	for p in Primitive {
		data := primitive_build(p, context.temp_allocator)
		for v, i in data.vertices {
			testing.expectf(t, abs(v3_dot(v.tangent.xyz, v.tangent.xyz) - 1) < 1e-5, "%v vertex %v has tangent %v, want unit length", p, i, v.tangent)
			testing.expectf(t, abs(v3_dot(v.tangent.xyz, v.normal)) < 1e-5, "%v vertex %v has tangent %v and normal %v", p, i, v.tangent, v.normal)
			testing.expectf(t, v.tangent.w == 1 || v.tangent.w == -1, "%v vertex %v has handedness %v", p, i, v.tangent.w)
		}
	}
}

// Each triangle's uv gradients give the way u and v run across it. The
// tangent follows u, and its bitangent points up the image, towards less v.
@(test)
test_every_primitive_tangent_follows_its_uvs :: proc(t: ^testing.T) {
	for p in Primitive {
		data := primitive_build(p, context.temp_allocator)
		for i := 0; i < len(data.indices); i += 3 {
			a := data.vertices[data.indices[i]]
			b := data.vertices[data.indices[i + 1]]
			c := data.vertices[data.indices[i + 2]]
			e1, e2 := b.pos - a.pos, c.pos - a.pos
			d1, d2 := b.uv - a.uv, c.uv - a.uv
			area := d1.x * d2.y - d2.x * d1.y
			along_u := (e1 * d2.y - e2 * d1.y) / area
			along_v := (e2 * d1.x - e1 * d2.x) / area
			for v in ([]Vertex{a, b, c}) {
				bitangent := v3_cross(v.normal, v.tangent.xyz) * v.tangent.w
				testing.expectf(t, v3_dot(v.tangent.xyz, along_u) > 0, "%v triangle %v has a tangent against u", p, i / 3)
				testing.expectf(t, v3_dot(bitangent, along_v) < 0, "%v triangle %v has handedness %v", p, i / 3, v.tangent.w)
			}
		}
	}
}

@(test)
test_a_part_without_a_texture_binds_the_white_image :: proc(t: ^testing.T) {
	white := Mesh_Texture{image = {id = 1}, view = {id = 2}, sampler = {id = 3}}
	plain := Mesh_Part{}
	base, mr, emissive := mesh_part_textures(&plain, white)
	testing.expect_value(t, base, white)
	testing.expect_value(t, mr, white)
	testing.expect_value(t, emissive, white)
	textured := Mesh_Part {
		texture            = {image = {id = 7}, view = {id = 8}, sampler = {id = 9}},
		metallic_roughness = {image = {id = 4}, view = {id = 5}, sampler = {id = 6}},
		emissive           = {image = {id = 10}, view = {id = 11}, sampler = {id = 12}},
	}
	base, mr, emissive = mesh_part_textures(&textured, white)
	testing.expect_value(t, base, textured.texture)
	testing.expect_value(t, mr, textured.metallic_roughness)
	testing.expect_value(t, emissive, textured.emissive)
}

@(test)
test_each_primitive_has_one_matte_part_over_all_its_indices :: proc(t: ^testing.T) {
	meshes: Mesh_Table
	mesh_table_init(&meshes, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&meshes)
	for p in Primitive {
		indices := len(primitive_build(p, context.temp_allocator).indices)
		parts := meshes.meshes[p].parts
		testing.expect_value(t, len(parts), 1)
		testing.expect_value(t, parts[0], Mesh_Part{first = 0, count = indices, material = MATERIAL_MATTE})
		testing.expect_value(t, parts[0].material.emissive, [3]f32{0, 0, 0})
	}
}

@(test)
test_a_loaded_mesh_keeps_the_range_and_material_of_each_part :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	shiny := Material{roughness = 0.4, metallic = 1}
	lamp := Material{roughness = 1, emissive = {1, 0, 0}}
	data := Mesh_Data {
		vertices = make([]Vertex, 3),
		indices  = slice.clone([]u16{0, 1, 2, 0, 2, 1}),
		parts    = slice.clone([]Mesh_Data_Part{{first = 0, count = 3, material = shiny}, {first = 3, count = 3, material = lamp, texture = 0}}),
		textures = make([]Texture, 1),
	}
	slot, _ := mesh_table_add(&table, strings.clone("rock"), data)
	parts := table.meshes[slot].parts
	testing.expect_value(t, len(parts), 2)
	testing.expect_value(t, parts[0], Mesh_Part{first = 0, count = 3, material = shiny})
	testing.expect_value(t, parts[1], Mesh_Part{first = 3, count = 3, material = lamp})
}

@(test)
test_a_mesh_whose_data_has_no_parts_gets_one_matte_part_over_all_its_indices :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	slot, _ := mesh_table_add(&table, strings.clone("rock"), {indices = slice.clone([]u16{0, 1, 2})})
	parts := table.meshes[slot].parts
	testing.expect_value(t, len(parts), 1)
	testing.expect_value(t, parts[0], Mesh_Part{first = 0, count = 3, material = MATERIAL_MATTE})
}

// One part over no indices, as a one-material file gives. The parts come
// from context.allocator, which the test tables use.
mesh_data_of :: proc(material: Material) -> Mesh_Data {
	return {parts = slice.clone([]Mesh_Data_Part{{material = material}})}
}

@(test)
test_a_loaded_mesh_keeps_the_box_around_its_vertices :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	vertices := make([]Vertex, 3)
	vertices[0].pos = {-1, 0, 2}
	vertices[1].pos = {3, -4, 1}
	vertices[2].pos = {0, 5, 1.5}
	slot, _ := mesh_table_add(&table, strings.clone("rock"), {vertices = vertices})
	testing.expect_value(t, table.meshes[slot].box, Box{min = {-1, -4, 1}, max = {3, 5, 2}})
}

@(test)
test_each_primitive_keeps_the_box_around_its_vertices :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&table)

	testing.expect_value(t, table.meshes[Primitive.Fallback].box, Box{min = -0.5, max = 0.5})
	testing.expect_value(t, table.meshes[Primitive.Cube].box, Box{min = -0.5, max = 0.5})
	testing.expect_value(t, table.meshes[Primitive.Plane].box, Box{min = {-0.5, 0, -0.5}, max = {0.5, 0, 0.5}})
	sphere := table.meshes[Primitive.Sphere].box
	for i in 0 ..< 3 {
		testing.expect(t, abs(sphere.min[i] + 0.5) < EPS && abs(sphere.max[i] - 0.5) < EPS)
	}
}
