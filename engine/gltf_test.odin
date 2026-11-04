#+test
package engine

import "core:encoding/endian"
import "core:fmt"
import "core:math/linalg"
import "core:strings"
import "core:testing"

TRIANGLE_PRIMITIVES :: `[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]`
MATERIAL_PRIMITIVES :: `[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0}]`
TWO_MATERIAL_PRIMITIVES :: `[
	{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0},
	{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}]`

// One triangle in x-y facing +z, then its indices as u16, u32 and u8.
// Accessors: 0 POSITION, 1 NORMAL, 2 u16 indices, 3 u32 indices, 4 u8 indices.
TRIANGLE_BUFFERS :: `"buffers":[{"byteLength":96}],
"bufferViews":[
	{"buffer":0,"byteOffset":0,"byteLength":36},
	{"buffer":0,"byteOffset":36,"byteLength":36},
	{"buffer":0,"byteOffset":72,"byteLength":6},
	{"buffer":0,"byteOffset":80,"byteLength":12},
	{"buffer":0,"byteOffset":92,"byteLength":3}],
"accessors":[
	{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"},
	{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},
	{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"},
	{"bufferView":3,"componentType":5125,"count":3,"type":"SCALAR"},
	{"bufferView":4,"componentType":5121,"count":3,"type":"SCALAR"}]`

QUAD_PRIMITIVE :: `{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3,"material":0}`
NORMAL_MAPPED :: `[{"normalTexture":{"index":0}}]`
// u follows +x and v runs down the image, as glTF lays out a quad that is not mirrored.
QUAD_UVS :: [4][2]f32{{0, 1}, {1, 1}, {1, 0}, {0, 0}}

triangle_bin :: proc() -> []byte {
	bin := make([dynamic]byte, context.temp_allocator)
	for v in ([]f32{0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1}) {
		bin_put(&bin, v)
	}
	for i in ([]u16{0, 1, 2}) {
		bin_put(&bin, i)
	}
	append(&bin, 0, 0)
	for i in ([]u32{0, 1, 2}) {
		bin_put(&bin, i)
	}
	append(&bin, 0, 1, 2, 0)
	return bin[:]
}

// The material of a one-triangle file whose only material is this JSON.
glb_one_material :: proc(t: ^testing.T, material: string, loc := #caller_location) -> Material {
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = fmt.tprintf(`"materials":[%s],`, material)), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None, loc = loc)
	return data.parts[0].material if err == .None else {}
}

part_texture :: proc(data: Mesh_Data, slot: Maybe(int)) -> Maybe(Texture) {
	if i, ok := slot.?; ok {
		return data.textures[i]
	}
	return nil
}

bin_put :: proc(bin: ^[dynamic]byte, v: $T) {
	b: [size_of(T)]byte
	when T == f32 {
		endian.put_f32(b[:], .Little, v)
	} else when T == u32 {
		endian.put_u32(b[:], .Little, v)
	} else {
		endian.put_u16(b[:], .Little, v)
	}
	append(bin, ..b[:])
}

// Pads the JSON chunk with spaces and the BIN chunk with zeros, as the spec asks.
glb_make :: proc(json: string, bin: []byte) -> []byte {
	out := make([dynamic]byte, context.temp_allocator)
	put :: proc(out: ^[dynamic]byte, v: u32) {
		bin_put(out, v)
	}
	json_len := (len(json) + 3) &~ 3
	bin_len := (len(bin) + 3) &~ 3
	put(&out, GLB_MAGIC)
	put(&out, 2)
	put(&out, u32(12 + 8 + json_len + 8 + bin_len))
	put(&out, u32(json_len))
	put(&out, GLB_CHUNK_JSON)
	append(&out, json)
	for _ in len(json) ..< json_len {
		append(&out, ' ')
	}
	put(&out, u32(bin_len))
	put(&out, GLB_CHUNK_BIN)
	append(&out, ..bin)
	for _ in len(bin) ..< bin_len {
		append(&out, 0)
	}
	return out[:]
}

triangle_glb :: proc(primitives: string, nodes := `[{"mesh":0}]`, extra := "") -> []byte {
	json := fmt.tprintf(
		`{{"asset":{{"version":"2.0"}},"scene":0,"scenes":[{{"nodes":[0]}}],"nodes":%s,"meshes":[{{"primitives":%s}}],%s%s}}`,
		nodes,
		primitives,
		extra,
		TRIANGLE_BUFFERS,
	)
	return glb_make(json, triangle_bin())
}

@(test)
test_glb_loads_a_triangle_in_grey_without_a_material :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.vertices), 3)
	testing.expect_value(t, len(data.indices), 3)
	want_pos := [3][3]f32{{0, 0, 0}, {1, 0, 0}, {0, 1, 0}}
	for v, i in data.vertices {
		testing.expect_value(t, v.pos, want_pos[i])
		testing.expect_value(t, v.normal, [3]f32{0, 0, 1})
		testing.expect_value(t, v.color, GREY)
	}
	for index, i in data.indices {
		testing.expect_value(t, index, u16(i))
	}
}

@(test)
test_glb_rejects_a_bad_magic_number :: proc(t: ^testing.T) {
	bytes := triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]`)
	bytes[0] = 'x'
	_, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Magic)
}

@(test)
test_glb_rejects_a_primitive_without_normals :: proc(t: ^testing.T) {
	_, _, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0},"indices":2}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.No_Normals)
}

@(test)
test_glb_rejects_a_primitive_that_is_not_triangles :: proc(t: ^testing.T) {
	_, _, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"mode":1}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Not_Triangles)
}

// The parent's matrix is column-major, so its translation is the last four numbers.
@(test)
test_glb_bakes_each_node_world_transform_into_positions_and_normals :: proc(t: ^testing.T) {
	nodes := `[
		{"children":[1],"matrix":[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,2,0,1]},
		{"mesh":0,"rotation":[0,0.70710678,0,0.70710678],"scale":[2,2,2]}]`
	data, _, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":4}]`, nodes), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	want_pos := [3][3]f32{{0, 2, 0}, {0, 2, -2}, {0, 4, 0}}
	for v, i in data.vertices {
		testing.expectf(t, linalg.length(v.pos - want_pos[i]) < 1e-5, "vertex %v at %v, want %v", i, v.pos, want_pos[i])
		testing.expectf(t, linalg.length(v.normal - [3]f32{1, 0, 0}) < 1e-5, "normal %v is %v, want +x", i, v.normal)
	}
}

@(test)
test_glb_merges_primitives_and_colours_each_by_its_material :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1]}},
		{"pbrMetallicRoughness":{"baseColorFactor":[0,0,1,1]}}],`
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.vertices), 6)
	testing.expect_value(t, len(data.indices), 6)
	for v, i in data.vertices {
		want := [4]f32{1, 0, 0, 1} if i < 3 else [4]f32{0, 0, 1, 1}
		testing.expect_value(t, v.color, want)
	}
	for index, i in data.indices {
		testing.expect_value(t, index, u16(i))
	}
}

@(test)
test_glb_rejects_a_mesh_with_more_than_65535_vertices :: proc(t: ^testing.T) {
	COUNT :: 33_000
	json := fmt.tprintf(
		`{{"scenes":[{{"nodes":[0]}}],"nodes":[{{"mesh":0}}],
		"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":0}}}},{{"attributes":{{"POSITION":0,"NORMAL":0}}}}]}}],
		"buffers":[{{"byteLength":%v}}],
		"bufferViews":[{{"buffer":0,"byteLength":%v}}],
		"accessors":[{{"bufferView":0,"componentType":5126,"count":%v,"type":"VEC3"}}]}}`,
		COUNT * 12,
		COUNT * 12,
		COUNT,
	)
	_, _, err := glb_parse(glb_make(json, make([]byte, COUNT * 12, context.temp_allocator)), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Too_Many_Vertices)
}

@(test)
test_glb_rejects_a_header_length_shorter_than_the_header :: proc(t: ^testing.T) {
	bytes := triangle_glb(TRIANGLE_PRIMITIVES)
	endian.put_u32(bytes[8:], .Little, 4)
	_, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Chunks)
}

@(test)
test_glb_rejects_an_accessor_offset_past_its_buffer_view :: proc(t: ^testing.T) {
	Case :: struct {
		accessor: string,
		view:     string,
	}
	cases := []Case {
		{`{"bufferView":0,"byteOffset":1000,"componentType":5126,"count":0,"type":"VEC3"}`, `{"buffer":0,"byteLength":36}`},
		{`{"bufferView":0,"componentType":5126,"count":4611686018427387904,"type":"VEC3"}`, `{"buffer":0,"byteLength":36}`},
		{`{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}`, `{"buffer":0,"byteOffset":9223372036854775000,"byteLength":9223372036854775000}`},
	}
	for c in cases {
		json := fmt.tprintf(
			`{{"nodes":[{{"mesh":0}}],"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":0}}}}]}}],"bufferViews":[%s],"accessors":[%s]}}`,
			c.view,
			c.accessor,
		)
		_, _, err := glb_parse(glb_make(json, triangle_bin()), context.temp_allocator)
		testing.expectf(t, err == .Bad_Accessor, "%v gave %v, want Bad_Accessor", c.accessor, err)
	}
}

@(test)
test_glb_rejects_a_sparse_accessor :: proc(t: ^testing.T) {
	json := `{"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":0}}]}],
	"bufferViews":[{"buffer":0,"byteLength":36}],
	"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","sparse":{"count":1}}]}`
	_, _, err := glb_parse(glb_make(json, triangle_bin()), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Accessor)
}

// glTF reverses the winding of a node whose transform mirrors it.
@(test)
test_glb_keeps_a_mirrored_node_ccw_from_outside :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES, `[{"mesh":0,"scale":[-1,1,1]}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	a := data.vertices[data.indices[0]]
	b := data.vertices[data.indices[1]]
	c := data.vertices[data.indices[2]]
	face := v3_cross(b.pos - a.pos, c.pos - a.pos)
	testing.expectf(t, v3_dot(face, a.normal) > 0, "mirrored triangle winds clockwise from outside")
}

// The triangle with TEXCOORD_0 as accessor 5 and an image in buffer view 6.
// A second primitive, if given, joins the first.
textured_glb :: proc(
	image_bytes: []byte,
	image := `{"bufferView":6,"mimeType":"image/png"}`,
	texture := `{"source":0}`,
	samplers := "",
	second := "",
	material := `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}`,
) -> []byte {
	bin := make([dynamic]byte, context.temp_allocator)
	append(&bin, ..triangle_bin())
	for v in ([]f32{0, 0, 1, 0, 0, 1}) {
		bin_put(&bin, v)
	}
	image_offset := len(bin)
	append(&bin, ..image_bytes)
	json := fmt.tprintf(
		`{{"scenes":[{{"nodes":[0]}}],"nodes":[{{"mesh":0}}],
		"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5}},"indices":2,"material":0}}%s]}}],
		"materials":[%s],
		"textures":[%s],"images":[%s],%s
		"bufferViews":[
			{{"buffer":0,"byteOffset":0,"byteLength":36}},
			{{"buffer":0,"byteOffset":36,"byteLength":36}},
			{{"buffer":0,"byteOffset":72,"byteLength":6}},
			{{"buffer":0,"byteOffset":80,"byteLength":12}},
			{{"buffer":0,"byteOffset":92,"byteLength":3}},
			{{"buffer":0,"byteOffset":96,"byteLength":24}},
			{{"buffer":0,"byteOffset":%v,"byteLength":%v}}],
		"accessors":[
			{{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},
			{{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}},
			{{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"}},
			{{"bufferView":3,"componentType":5125,"count":3,"type":"SCALAR"}},
			{{"bufferView":4,"componentType":5121,"count":3,"type":"SCALAR"}},
			{{"bufferView":5,"componentType":5126,"count":3,"type":"VEC2"}}]}}`,
		second,
		material,
		texture,
		image,
		samplers,
		image_offset,
		len(image_bytes),
	)
	return glb_make(json, bin[:])
}

@(test)
test_glb_reads_texcoord_0_into_each_vertex_uv :: proc(t: ^testing.T) {
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3})), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	want := [3][2]f32{{0, 0}, {1, 0}, {0, 1}}
	for v, i in data.vertices {
		testing.expect_value(t, v.uv, want[i])
	}
}

// The triangle with TANGENT as accessor 5, which reads buffer view 5.
tangent_glb :: proc(nodes := `[{"mesh":0}]`, accessor := `{"bufferView":5,"componentType":5126,"count":3,"type":"VEC4"}`) -> []byte {
	bin := make([dynamic]byte, context.temp_allocator)
	append(&bin, ..triangle_bin())
	for v in ([]f32{1, 0, 0, 1, 0, 1, 0, -1, 0.6, 0.8, 0, 1}) {
		bin_put(&bin, v)
	}
	json := fmt.tprintf(
		`{{"scenes":[{{"nodes":[0]}}],"nodes":%s,
		"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":1,"TANGENT":5}},"indices":2}}]}}],
		"bufferViews":[
			{{"buffer":0,"byteOffset":0,"byteLength":36}},
			{{"buffer":0,"byteOffset":36,"byteLength":36}},
			{{"buffer":0,"byteOffset":72,"byteLength":6}},
			{{"buffer":0,"byteOffset":80,"byteLength":12}},
			{{"buffer":0,"byteOffset":92,"byteLength":3}},
			{{"buffer":0,"byteOffset":96,"byteLength":48}}],
		"accessors":[
			{{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},
			{{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}},
			{{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"}},
			{{"bufferView":3,"componentType":5125,"count":3,"type":"SCALAR"}},
			{{"bufferView":4,"componentType":5121,"count":3,"type":"SCALAR"}},
			%s]}}`,
		nodes,
		accessor,
	)
	return glb_make(json, bin[:])
}

expect_tangents :: proc(t: ^testing.T, data: Mesh_Data, want: [3][4]f32) {
	testing.expect_value(t, len(data.vertices), 3)
	for v, i in data.vertices {
		testing.expectf(t, linalg.length(v.tangent - want[i]) < 1e-5, "vertex %v has tangent %v, want %v", i, v.tangent, want[i])
	}
}

@(test)
test_glb_reads_tangent_into_each_vertex :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(tangent_glb(), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	expect_tangents(t, data, {{1, 0, 0, 1}, {0, 1, 0, -1}, {0.6, 0.8, 0, 1}})
}

@(test)
test_glb_gives_a_primitive_without_tangent_the_placeholder_and_no_note :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	for v in data.vertices {
		testing.expect_value(t, v.tangent, [4]f32{1, 0, 0, 1})
	}
}

@(test)
test_glb_rejects_a_tangent_that_is_not_three_float_vec4s :: proc(t: ^testing.T) {
	accessors := []string {
		`{"bufferView":5,"componentType":5126,"count":3,"type":"VEC3"}`,
		`{"bufferView":5,"componentType":5123,"count":3,"type":"VEC4"}`,
		`{"bufferView":5,"componentType":5126,"count":2,"type":"VEC4"}`,
	}
	for accessor in accessors {
		_, _, err := glb_parse(tangent_glb(accessor = accessor), context.temp_allocator)
		testing.expectf(t, err == .Bad_Accessor, "%v gave %v, want Bad_Accessor", accessor, err)
	}
}

@(test)
test_glb_turns_each_tangent_with_its_node :: proc(t: ^testing.T) {
	data, _, err := glb_parse(tangent_glb(`[{"mesh":0,"rotation":[0,0.70710678,0,0.70710678],"scale":[2,2,2]}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	expect_tangents(t, data, {{0, 0, -1, 1}, {0, 1, 0, -1}, {0, 0.8, -0.6, 1}})
}

@(test)
test_glb_flips_the_tangent_handedness_of_a_mirrored_node :: proc(t: ^testing.T) {
	data, _, err := glb_parse(tangent_glb(`[{"mesh":0,"scale":[-1,1,1]}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	expect_tangents(t, data, {{-1, 0, 0, -1}, {0, 1, 0, 1}, {-0.6, 0.8, 0, -1}})
}

// The unit quad in x-y. Accessors: 0 POSITION, 1 NORMAL, 2 TEXCOORD_0, 3 u16
// indices, 4 TANGENT of (0, 1, 0, -1). Texture 0 is a flat normal PNG, so the
// normal map decodes.
quad_glb :: proc(
	uvs: [4][2]f32,
	materials := NORMAL_MAPPED,
	primitives := "[" + QUAD_PRIMITIVE + "]",
	nodes := `[{"mesh":0}]`,
	normal := [3]f32{0, 0, 1},
) -> []byte {
	bin := make([dynamic]byte, context.temp_allocator)
	for v in ([]f32{0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0}) {
		bin_put(&bin, v)
	}
	for _ in 0 ..< 4 {
		for v in normal {
			bin_put(&bin, v)
		}
	}
	for uv in uvs {
		bin_put(&bin, uv.x)
		bin_put(&bin, uv.y)
	}
	for i in ([]u16{0, 1, 2, 0, 2, 3}) {
		bin_put(&bin, i)
	}
	for _ in 0 ..< 4 {
		for v in ([]f32{0, 1, 0, -1}) {
			bin_put(&bin, v)
		}
	}
	png := png_make(1, 1, PNG_RGB, {128, 128, 255})
	append(&bin, ..png)
	json := fmt.tprintf(
		`{{"scenes":[{{"nodes":[0]}}],"nodes":%s,"meshes":[{{"primitives":%s}}],"materials":%s,
		"textures":[{{"source":0}}],"images":[{{"bufferView":5,"mimeType":"image/png"}}],
		"bufferViews":[
			{{"buffer":0,"byteOffset":0,"byteLength":48}},
			{{"buffer":0,"byteOffset":48,"byteLength":48}},
			{{"buffer":0,"byteOffset":96,"byteLength":32}},
			{{"buffer":0,"byteOffset":128,"byteLength":12}},
			{{"buffer":0,"byteOffset":140,"byteLength":64}},
			{{"buffer":0,"byteOffset":204,"byteLength":%v}}],
		"accessors":[
			{{"bufferView":0,"componentType":5126,"count":4,"type":"VEC3"}},
			{{"bufferView":1,"componentType":5126,"count":4,"type":"VEC3"}},
			{{"bufferView":2,"componentType":5126,"count":4,"type":"VEC2"}},
			{{"bufferView":3,"componentType":5123,"count":6,"type":"SCALAR"}},
			{{"bufferView":4,"componentType":5126,"count":4,"type":"VEC4"}}]}}`,
		nodes,
		primitives,
		materials,
		len(png),
	)
	return glb_make(json, bin[:])
}

expect_each_tangent :: proc(t: ^testing.T, vertices: []Vertex, want: [4]f32) {
	for v, i in vertices {
		testing.expectf(t, linalg.length(v.tangent - want) < 1e-5, "vertex %v has tangent %v, want %v", i, v.tangent, want)
	}
}

@(test)
test_glb_generates_the_tangent_of_a_normal_mapped_quad_from_its_uvs :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(quad_glb(QUAD_UVS), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Generated_Tangents})
	testing.expect_value(t, len(data.vertices), 4)
	expect_each_tangent(t, data.vertices, {1, 0, 0, 1})
}

@(test)
test_glb_generates_a_left_handed_tangent_for_uvs_mirrored_in_u :: proc(t: ^testing.T) {
	data, _, err := glb_parse(quad_glb({{1, 1}, {0, 1}, {0, 0}, {1, 0}}), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	expect_each_tangent(t, data.vertices, {-1, 0, 0, -1})
}

// u follows +y and v follows +x: the image turned a quarter, not mirrored.
@(test)
test_glb_generates_a_tangent_for_turned_uvs :: proc(t: ^testing.T) {
	data, _, err := glb_parse(quad_glb({{0, 0}, {0, 1}, {1, 1}, {1, 0}}), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	expect_each_tangent(t, data.vertices, {0, 1, 0, 1})
}

// The generated frame matches the one a TANGENT of (1, 0, 0, 1) gets under the same node.
@(test)
test_glb_generates_the_tangent_of_a_mirrored_node_from_its_placed_positions :: proc(t: ^testing.T) {
	data, _, err := glb_parse(quad_glb(QUAD_UVS, nodes = `[{"mesh":0,"scale":[-1,1,1]}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	expect_each_tangent(t, data.vertices, {-1, 0, 0, -1})
}

@(test)
test_glb_gives_uvs_with_zero_area_a_unit_tangent_at_right_angles_to_the_normal :: proc(t: ^testing.T) {
	line := [4][2]f32{{0, 0}, {1, 0}, {2, 0}, {3, 0}}
	for normal in ([][3]f32{{0, 0, 1}, {1, 0, 0}, {0.6, 0, 0.8}}) {
		data, notes, err := glb_parse(quad_glb(line, normal = normal), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.None)
		testing.expect_value(t, notes, Glb_Notes{.Generated_Tangents})
		for v, i in data.vertices {
			tangent := v.tangent.xyz
			testing.expectf(t, abs(linalg.length(tangent) - 1) < 1e-5, "normal %v, vertex %v: tangent %v is not unit", normal, i, v.tangent)
			testing.expectf(t, abs(linalg.dot(tangent, v.normal)) < 1e-5, "normal %v, vertex %v: tangent %v is not at right angles", normal, i, v.tangent)
			testing.expectf(t, v.tangent.w == 1, "normal %v, vertex %v: tangent %v has w other than 1", normal, i, v.tangent)
		}
	}
}

@(test)
test_glb_keeps_the_tangent_of_a_normal_mapped_primitive_that_has_one :: proc(t: ^testing.T) {
	primitives := `[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2,"TANGENT":4},"indices":3,"material":0}]`
	data, notes, err := glb_parse(quad_glb(QUAD_UVS, primitives = primitives), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	expect_each_tangent(t, data.vertices, {0, 1, 0, -1})
}

@(test)
test_glb_gives_a_primitive_without_a_normal_map_the_placeholder_and_no_note :: proc(t: ^testing.T) {
	materials := `[{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}]`
	data, notes, err := glb_parse(quad_glb({{0, 0}, {0, 1}, {1, 1}, {1, 0}}, materials = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	expect_each_tangent(t, data.vertices, GLB_PLACEHOLDER_TANGENT)
}

// The second primitive's vertices start past the first's, so its indices do too.
@(test)
test_glb_generates_tangents_only_for_the_normal_mapped_primitive :: proc(t: ^testing.T) {
	primitives := `[{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":2},"indices":3},` + QUAD_PRIMITIVE + "]"
	data, notes, err := glb_parse(quad_glb({{0, 0}, {0, 1}, {1, 1}, {1, 0}}, primitives = primitives), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Generated_Tangents})
	testing.expect_value(t, len(data.vertices), 8)
	expect_each_tangent(t, data.vertices[:4], GLB_PLACEHOLDER_TANGENT)
	expect_each_tangent(t, data.vertices[4:], {0, 1, 0, 1})
}

@(test)
test_glb_reads_an_embedded_png_as_the_base_colour_texture :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(textured_glb(png_make(2, 1, PNG_RGB, {10, 20, 30, 40, 50, 60})), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	tex, ok := part_texture(data, data.parts[0].texture).?
	testing.expect(t, ok)
	testing.expect_value(t, len(tex.levels), 1)
	testing.expect_value(t, [2]int{tex.levels[0].width, tex.levels[0].height}, [2]int{2, 1})
	want := [8]byte{10, 20, 30, 255, 40, 50, 60, 255}
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, want[i])
	}
	testing.expect_value(t, tex.sampler, Texture_Sampler{min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_filter = .NEAREST, wrap_u = .REPEAT, wrap_v = .REPEAT})
}

@(test)
test_glb_reads_the_sampler_and_builds_mipmaps_when_the_min_filter_asks :: proc(t: ^testing.T) {
	samplers := `"samplers":[{"magFilter":9728,"minFilter":9986,"wrapS":33071,"wrapT":33648}],`
	glb := textured_glb(png_make(2, 2, PNG_GRAY, {0, 0, 0, 0}), texture = `{"source":0,"sampler":0}`, samplers = samplers)
	data, _, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	tex, ok := part_texture(data, data.parts[0].texture).?
	testing.expect(t, ok)
	testing.expect_value(t, len(tex.levels), 2)
	testing.expect_value(
		t,
		tex.sampler,
		Texture_Sampler{min_filter = .NEAREST, mag_filter = .NEAREST, mipmap_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .MIRRORED_REPEAT, mipmaps = true},
	)
}

@(test)
test_glb_skips_a_jpeg_texture_with_a_note :: proc(t: ^testing.T) {
	jpeg := []byte{0xff, 0xd8, 0xff, 0xe0, 0, 0}
	data, notes, err := glb_parse(textured_glb(jpeg, image = `{"bufferView":6,"mimeType":"image/jpeg"}`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Jpeg_Skipped})
	testing.expect(t, data.parts[0].texture == nil)
	testing.expect_value(t, len(data.vertices), 3)
}

@(test)
test_glb_skips_a_png_that_does_not_decode_with_a_note :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(textured_glb(transmute([]byte)string("not a png")), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Bad_Png})
	testing.expect(t, data.parts[0].texture == nil)
}

@(test)
test_glb_without_a_texture_has_no_texture_and_zero_uvs :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect(t, data.parts[0].texture == nil)
	for v in data.vertices {
		testing.expect_value(t, v.uv, [2]f32{0, 0})
	}
}

@(test)
test_glb_rejects_a_texture_index_out_of_range :: proc(t: ^testing.T) {
	_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), texture = `{"source":4}`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Texture)
}

@(test)
test_glb_gives_a_primitive_with_no_material_its_own_matte_part :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1},"indices":3}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), second = second), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.parts), 2)
	testing.expect(t, data.parts[0].texture != nil)
	testing.expect_value(t, data.parts[1], Mesh_Data_Part{first = 3, count = 3, material = MATERIAL_MATTE})
}

@(test)
test_glb_without_a_material_is_matte_and_not_metal :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material, Material{roughness = 1, metallic = 0})
	testing.expect(t, data.parts[0].emissive == nil)
}

// glTF gives both factors 1 when a material leaves them out.
@(test)
test_glb_material_without_factors_takes_the_gltf_defaults :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = `"materials":[{}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material, Material{roughness = 1, metallic = 1})
}

@(test)
test_glb_reads_the_metallic_and_roughness_factors :: proc(t: ^testing.T) {
	materials := `"materials":[{"pbrMetallicRoughness":{"metallicFactor":0.25,"roughnessFactor":0.5}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material, Material{roughness = 0.5, metallic = 0.25})
}

@(test)
test_glb_reads_the_unlit_extension :: proc(t: ^testing.T) {
	materials := `"materials":[{"extensions":{"KHR_materials_unlit":{}}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, data.parts[0].material.unlit)
}

@(test)
test_glb_material_without_emissive_emits_nothing :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = `"materials":[{}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{0, 0, 0})
	testing.expect(t, data.parts[0].emissive == nil)
}

@(test)
test_glb_reads_the_emissive_factor :: proc(t: ^testing.T) {
	materials := `"materials":[{"emissiveFactor":[1,0.5,0.25]}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{1, 0.5, 0.25})
}

@(test)
test_glb_scales_the_emissive_factor_by_the_emissive_strength :: proc(t: ^testing.T) {
	materials := `"materials":[{"emissiveFactor":[1,0.5,0],
		"extensions":{"KHR_materials_emissive_strength":{"emissiveStrength":4}}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{4, 2, 0})
}

@(test)
test_glb_clamps_the_emissive_factor_and_the_strength :: proc(t: ^testing.T) {
	negative := `"materials":[{"emissiveFactor":[2,-1,0.5],
		"extensions":{"KHR_materials_emissive_strength":{"emissiveStrength":-3}}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = negative), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{0, 0, 0})

	data, _, err = glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = `"materials":[{"emissiveFactor":[2,-1,0.5]}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{1, 0, 0.5})
}

@(test)
test_glb_reads_an_emissive_texture_as_srgb :: proc(t: ^testing.T) {
	material := `{"emissiveTexture":{"index":0},"emissiveFactor":[1,1,1]}`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {200, 100, 50}), material = material)
	data, notes, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect(t, data.parts[0].texture == nil)
	testing.expect(t, data.parts[0].metallic_roughness == nil)
	tex, ok := part_texture(data, data.parts[0].emissive).?
	testing.expect(t, ok)
	testing.expect(t, tex.srgb)
	want := [4]byte{200, 100, 50, 255}
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, want[i])
	}
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{1, 1, 1})
}

// glTF's emissiveFactor defaults to black, so a texture alone emits nothing.
@(test)
test_glb_emissive_texture_without_a_factor_emits_nothing :: proc(t: ^testing.T) {
	material := `{"emissiveTexture":{"index":0}}`
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, data.parts[0].emissive != nil)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{0, 0, 0})
}

@(test)
test_glb_rejects_an_emissive_texture_index_out_of_range :: proc(t: ^testing.T) {
	material := `{"emissiveTexture":{"index":3}}`
	_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Texture)
}

@(test)
test_glb_keeps_the_emissive_of_each_material :: proc(t: ^testing.T) {
	materials := `"materials":[{"emissiveFactor":[1,0,0]}, {"emissiveFactor":[0,0,1]}],`
	data, notes, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{1, 0, 0})
	testing.expect_value(t, data.parts[1].material.emissive, [3]f32{0, 0, 1})
}

@(test)
test_glb_reads_the_metallic_roughness_texture_as_linear :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":0},"roughnessFactor":0.5}}`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {0, 200, 100}), material = material)
	data, notes, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect(t, data.parts[0].texture == nil)
	tex, ok := part_texture(data, data.parts[0].metallic_roughness).?
	testing.expect(t, ok)
	testing.expect(t, !tex.srgb)
	want := [4]byte{0, 200, 100, 255}
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, want[i])
	}
	testing.expect_value(t, data.parts[0].material, Material{roughness = 0.5, metallic = 1})
}

@(test)
test_glb_reads_a_base_colour_texture_as_srgb :: proc(t: ^testing.T) {
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3})), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	tex, ok := part_texture(data, data.parts[0].texture).?
	testing.expect(t, ok)
	testing.expect(t, tex.srgb)
}

@(test)
test_glb_rejects_a_metallic_roughness_texture_index_out_of_range :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":3}}}`
	_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Texture)
}

@(test)
test_glb_reads_the_normal_texture_as_linear_with_its_scale :: proc(t: ^testing.T) {
	material := `{"normalTexture":{"index":0,"scale":0.5}}`
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {128, 64, 255}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	part := data.parts[0]
	testing.expect(t, part.texture == nil)
	testing.expect(t, part.occlusion == nil)
	tex, ok := part_texture(data, part.normal).?
	testing.expect(t, ok)
	testing.expect(t, !tex.srgb)
	want := [4]byte{128, 64, 255, 255}
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, want[i])
	}
	testing.expect_value(t, part.material.normal_scale, f32(0.5))
	testing.expect_value(t, part.material.occlusion_strength, f32(0))
}

@(test)
test_glb_reads_the_occlusion_texture_as_linear_with_its_strength :: proc(t: ^testing.T) {
	material := `{"occlusionTexture":{"index":0,"strength":0.25}}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {90, 0, 0}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	part := data.parts[0]
	testing.expect(t, part.normal == nil)
	tex, ok := part_texture(data, part.occlusion).?
	testing.expect(t, ok)
	testing.expect(t, !tex.srgb)
	testing.expect_value(t, tex.levels[0].pixels[0], 90)
	testing.expect_value(t, part.material.occlusion_strength, f32(0.25))
	testing.expect_value(t, part.material.normal_scale, f32(0))
}

@(test)
test_glb_gives_a_normal_scale_and_an_occlusion_strength_of_1_by_default :: proc(t: ^testing.T) {
	material := `{"normalTexture":{"index":0},"occlusionTexture":{"index":0}}`
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {128, 128, 255}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.parts[0].material.normal_scale, f32(1))
	testing.expect_value(t, data.parts[0].material.occlusion_strength, f32(1))
}

@(test)
test_glb_clamps_the_occlusion_strength :: proc(t: ^testing.T) {
	strengths := [2]f32{-1, 3}
	wants := [2]f32{0, 1}
	for strength, i in strengths {
		material := fmt.tprintf(`{{"occlusionTexture":{{"index":0,"strength":%v}}}}`, strength)
		data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.None)
		testing.expect_value(t, data.parts[0].material.occlusion_strength, wants[i])
	}
}

// The flat normal image gives the vertex normal exactly only with a scale of 0.
@(test)
test_glb_gives_a_normal_map_that_cannot_draw_a_scale_of_0 :: proc(t: ^testing.T) {
	material := `{"normalTexture":{"index":0,"scale":2},"occlusionTexture":{"index":0,"strength":0.5}}`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), image = `{"bufferView":6,"mimeType":"image/jpeg"}`, material = material)
	data, notes, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, .Jpeg_Skipped in notes)
	testing.expect(t, data.parts[0].normal == nil)
	testing.expect(t, data.parts[0].occlusion == nil)
	testing.expect_value(t, data.parts[0].material.normal_scale, f32(0))
	testing.expect_value(t, data.parts[0].material.occlusion_strength, f32(0))
}

@(test)
test_glb_rejects_a_normal_or_occlusion_texture_index_out_of_range :: proc(t: ^testing.T) {
	for material in ([]string{`{"normalTexture":{"index":3}}`, `{"occlusionTexture":{"index":3}}`}) {
		_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.Bad_Texture)
	}
}

// An ORM image holds occlusion in R and metallic-roughness in G and B. Both
// slots are linear, so they share one texture.
@(test)
test_glb_decodes_a_packed_orm_texture_once :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":0}},"occlusionTexture":{"index":0}}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {200, 120, 0}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.textures), 1)
	testing.expect_value(t, data.parts[0].occlusion, Maybe(int)(0))
	testing.expect_value(t, data.parts[0].metallic_roughness, Maybe(int)(0))
}

@(test)
test_glb_notes_a_second_uv_set_on_any_texture_and_still_loads :: proc(t: ^testing.T) {
	materials := []string {
		`{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,"texCoord":1}}}`,
		`{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":0,"texCoord":1}}}`,
		`{"normalTexture":{"index":0,"texCoord":1}}`,
		`{"occlusionTexture":{"index":0,"texCoord":1}}`,
		`{"emissiveTexture":{"index":0,"texCoord":1}}`,
	}
	for material in materials {
		data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
		testing.expectf(t, err == .None, "%v: %v", material, err)
		testing.expectf(t, .Second_Uv_Ignored in notes, "%v: %v", material, notes)
		testing.expect_value(t, len(data.textures), 1)
	}

	material := `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0,"texCoord":0}}}`
	_, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
}

@(test)
test_glb_gives_each_material_a_part_with_its_range_and_factors :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"pbrMetallicRoughness":{"roughnessFactor":0.2,"metallicFactor":0}},
		{"pbrMetallicRoughness":{"roughnessFactor":0.9,"metallicFactor":1}}],`
	data, notes, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.parts), 2)
	testing.expect_value(t, data.parts[0], Mesh_Data_Part{first = 0, count = 3, material = {roughness = 0.2}})
	testing.expect_value(t, data.parts[1], Mesh_Data_Part{first = 3, count = 3, material = {roughness = 0.9, metallic = 1}})
}

@(test)
test_glb_draws_primitives_that_share_a_material_as_one_part :: proc(t: ^testing.T) {
	primitives := `[
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0},
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1},
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":4,"material":0}]`
	materials := `"materials":[{"pbrMetallicRoughness":{"roughnessFactor":0.2}}, {"emissiveFactor":[1,0,0]}],`
	data, _, err := glb_parse(triangle_glb(primitives, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 2)
	testing.expect_value(t, data.parts[0].first, 0)
	testing.expect_value(t, data.parts[0].count, 6)
	testing.expect_value(t, data.parts[0].material.roughness, f32(0.2))
	testing.expect_value(t, data.parts[1].first, 6)
	testing.expect_value(t, data.parts[1].count, 3)
	// Each part is one range of the index buffer, in the order the walk met its material.
	want := [9]u16{0, 1, 2, 6, 7, 8, 3, 4, 5}
	for index, i in data.indices {
		testing.expect_value(t, index, want[i])
	}
}

// The base colour factor goes in the vertex colour, so materials that differ
// only in it draw with one part.
@(test)
test_glb_draws_materials_that_differ_only_in_colour_as_one_part :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1],"metallicFactor":0}},
		{"pbrMetallicRoughness":{"baseColorFactor":[0,0,1,1],"metallicFactor":0}}],`
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 1)
	testing.expect_value(t, data.parts[0], Mesh_Data_Part{first = 0, count = 6, material = {roughness = 1}})
	testing.expect_value(t, data.vertices[0].color, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, data.vertices[3].color, [4]f32{0, 0, 1, 1})
}

@(test)
test_glb_reads_each_alpha_mode :: proc(t: ^testing.T) {
	cases := []struct {
		material: string,
		want:     Alpha_Mode,
	} {
		{`{}`, .Opaque},
		{`{"alphaMode":"OPAQUE"}`, .Opaque},
		{`{"alphaMode":"MASK"}`, .Mask},
		{`{"alphaMode":"BLEND"}`, .Blend},
		{`{"alphaMode":"SHINY"}`, .Opaque},
	}
	for c in cases {
		got := glb_one_material(t, c.material).alpha_mode
		testing.expectf(t, got == c.want, "%s has alpha mode %v, want %v", c.material, got, c.want)
	}
}

// glTF ignores alphaCutoff outside MASK, so only a MASK part keeps one.
@(test)
test_glb_reads_the_alpha_cutoff_of_a_mask_material_with_a_default_of_half :: proc(t: ^testing.T) {
	cases := []struct {
		material: string,
		want:     f32,
	} {
		{`{"alphaMode":"MASK"}`, 0.5},
		{`{"alphaMode":"MASK","alphaCutoff":0.25}`, 0.25},
		{`{"alphaMode":"BLEND","alphaCutoff":0.25}`, 0},
		{`{"alphaCutoff":0.25}`, 0},
	}
	for c in cases {
		got := glb_one_material(t, c.material).alpha_cutoff
		testing.expectf(t, got == c.want, "%s has cutoff %v, want %v", c.material, got, c.want)
	}
}

@(test)
test_glb_reads_double_sided_for_mask_and_blend_materials_only :: proc(t: ^testing.T) {
	cases := []struct {
		material: string,
		want:     bool,
	} {
		{`{"doubleSided":true}`, false},
		{`{"alphaMode":"MASK","doubleSided":true}`, true},
		{`{"alphaMode":"MASK"}`, false},
		{`{"alphaMode":"BLEND","doubleSided":true}`, true},
		{`{"alphaMode":"BLEND","doubleSided":false}`, false},
	}
	for c in cases {
		got := glb_one_material(t, c.material).double_sided
		testing.expectf(t, got == c.want, "%s has double_sided %v, want %v", c.material, got, c.want)
	}
}

@(test)
test_glb_draws_opaque_materials_that_differ_only_in_double_sided_as_one_part :: proc(t: ^testing.T) {
	materials := `"materials":[{"doubleSided":true}, {}],`
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 1)
}

@(test)
test_glb_orders_the_parts_opaque_then_mask_then_blend :: proc(t: ^testing.T) {
	primitives := `[
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0},
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1},
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":4,"material":2}]`
	materials := `"materials":[{"alphaMode":"BLEND"}, {"alphaMode":"MASK"}, {}],`
	data, _, err := glb_parse(triangle_glb(primitives, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 3)
	want_modes := [3]Alpha_Mode{.Opaque, .Mask, .Blend}
	for part, i in data.parts {
		testing.expect_value(t, part.material.alpha_mode, want_modes[i])
		testing.expect_value(t, part.first, 3 * i)
		testing.expect_value(t, part.count, 3)
	}
	want := [9]u16{6, 7, 8, 3, 4, 5, 0, 1, 2}
	for index, i in data.indices {
		testing.expect_value(t, index, want[i])
	}
}

// The alpha goes in the vertex colour with the base colour factor.
@(test)
test_glb_draws_blend_materials_that_differ_only_in_alpha_as_one_part :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"alphaMode":"BLEND","pbrMetallicRoughness":{"baseColorFactor":[1,1,1,0.5]}},
		{"alphaMode":"BLEND","pbrMetallicRoughness":{"baseColorFactor":[1,1,1,0.25]}}],`
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 1)
	testing.expect_value(t, data.parts[0].material.alpha_mode, Alpha_Mode.Blend)
	testing.expect_value(t, data.vertices[0].color, [4]f32{1, 1, 1, 0.5})
	testing.expect_value(t, data.vertices[3].color, [4]f32{1, 1, 1, 0.25})
}

@(test)
test_glb_reads_unlit_and_emissive_strength_for_each_material :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"extensions":{"KHR_materials_unlit":{}}},
		{"emissiveFactor":[1,0.5,0],"extensions":{"KHR_materials_emissive_strength":{"emissiveStrength":4}}}],`
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, data.parts[0].material.unlit)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{0, 0, 0})
	testing.expect(t, !data.parts[1].material.unlit)
	testing.expect_value(t, data.parts[1].material.emissive, [3]f32{4, 2, 0})
}

@(test)
test_glb_draws_an_untextured_emissive_part_beside_a_textured_part :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}`
	materials := `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}, {"emissiveFactor":[0,1,1]}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), second = second, material = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.parts), 2)
	testing.expect(t, data.parts[0].texture != nil)
	testing.expect_value(t, data.parts[0].material.emissive, [3]f32{0, 0, 0})
	testing.expect(t, data.parts[1].texture == nil)
	testing.expect(t, data.parts[1].emissive == nil)
	testing.expect_value(t, data.parts[1].material.emissive, [3]f32{0, 1, 1})
}

@(test)
test_glb_decodes_a_texture_that_two_materials_share_once :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5},"indices":3,"material":1}`
	materials := `
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0}},
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":1}}`
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), second = second, material = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.textures), 1)
	testing.expect_value(t, data.parts[0].texture, Maybe(int)(0))
	testing.expect_value(t, data.parts[1].texture, Maybe(int)(0))
}

@(test)
test_glb_decodes_textures_that_name_the_same_image_and_sampler_once :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5},"indices":3,"material":1}`
	materials := `
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicFactor":0}},
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":1},"metallicFactor":1}}`
	textures := `{"source":0,"sampler":0},{"source":0,"sampler":0}`
	samplers := `"samplers":[{"magFilter":9729}],`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), texture = textures, samplers = samplers, second = second, material = materials)
	data, _, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.textures), 1)
	testing.expect_value(t, len(data.parts), 2)
	testing.expect_value(t, data.parts[0].texture, Maybe(int)(0))
	testing.expect_value(t, data.parts[1].texture, Maybe(int)(0))
}

@(test)
test_glb_decodes_textures_with_different_samplers_apart :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5},"indices":3,"material":1}`
	materials := `
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},
		{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}`
	textures := `{"source":0,"sampler":0},{"source":0,"sampler":1}`
	samplers := `"samplers":[{"magFilter":9729},{"magFilter":9728}],`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), texture = textures, samplers = samplers, second = second, material = materials)
	data, _, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.textures), 2)
	testing.expect_value(t, len(data.parts), 2)
}

// Base colour and emissive are sRGB and metallic-roughness is linear, so one
// glTF texture in all three slots decodes twice.
@(test)
test_glb_decodes_a_texture_once_per_colour_space :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":0}},"emissiveTexture":{"index":0}}`
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.textures), 2)
	part := data.parts[0]
	testing.expect_value(t, part.emissive, part.texture)
	testing.expect(t, part.metallic_roughness != part.texture)
	base, _ := part_texture(data, part.texture).?
	metallic_roughness, _ := part_texture(data, part.metallic_roughness).?
	testing.expect(t, base.srgb)
	testing.expect(t, !metallic_roughness.srgb)
}

// Each material names its own glTF texture and image, so the file has one more texture than the limit.
@(test)
test_glb_keeps_the_first_textures_up_to_the_limit_and_notes_the_rest :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(over_texture_limit_glb(), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Too_Many_Textures})
	testing.expect_value(t, len(data.textures), MESH_TEXTURE_LIMIT)
	testing.expect_value(t, len(data.parts), MESH_TEXTURE_LIMIT + 1)
	testing.expect_value(t, data.parts[MESH_TEXTURE_LIMIT - 1].texture, Maybe(int)(MESH_TEXTURE_LIMIT - 1))
	testing.expect(t, data.parts[MESH_TEXTURE_LIMIT].texture == nil)
}

// Each material names its own normal and occlusion images, so the ninth
// material's two textures are past the limit.
// The first material is the first the walk meets, so its texture keeps a slot
// though its Blend part goes last.
@(test)
test_glb_gives_the_textures_slots_in_walk_order_before_it_orders_the_parts :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(over_texture_limit_glb(`"alphaMode":"BLEND",`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Too_Many_Textures})
	last := data.parts[MESH_TEXTURE_LIMIT]
	testing.expect_value(t, last.material.alpha_mode, Alpha_Mode.Blend)
	testing.expect_value(t, last.texture, Maybe(int)(0))
	testing.expect(t, data.parts[MESH_TEXTURE_LIMIT - 1].texture == nil)
}

// One primitive per material, and one more material than MESH_TEXTURE_LIMIT,
// each with its own base colour texture. first goes at the start of the first
// material's JSON.
over_texture_limit_glb :: proc(first := "") -> []byte {
	primitives := strings.builder_make(context.temp_allocator)
	materials := strings.builder_make(context.temp_allocator)
	textures := strings.builder_make(context.temp_allocator)
	images := strings.builder_make(context.temp_allocator)
	for i in 0 ..= MESH_TEXTURE_LIMIT {
		if i > 0 {
			fmt.sbprintf(&primitives, `,{{"attributes":{{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5}},"indices":2,"material":%v}}`, i)
			strings.write_string(&materials, ",")
			strings.write_string(&textures, ",")
			strings.write_string(&images, ",")
		}
		fmt.sbprintf(&materials, `{{%s"pbrMetallicRoughness":{{"baseColorTexture":{{"index":%v}}}}}}`, first if i == 0 else "", i)
		fmt.sbprintf(&textures, `{{"source":%v}}`, i)
		strings.write_string(&images, `{"bufferView":6,"mimeType":"image/png"}`)
	}
	return textured_glb(
		png_make(1, 1, PNG_RGB, {1, 2, 3}),
		image = strings.to_string(images),
		texture = strings.to_string(textures),
		second = strings.to_string(primitives),
		material = strings.to_string(materials),
	)
}

@(test)
test_glb_counts_normal_and_occlusion_textures_against_the_limit :: proc(t: ^testing.T) {
	MATERIALS :: MESH_TEXTURE_LIMIT / 2 + 1
	primitives := strings.builder_make(context.temp_allocator)
	materials := strings.builder_make(context.temp_allocator)
	textures := strings.builder_make(context.temp_allocator)
	images := strings.builder_make(context.temp_allocator)
	for i in 0 ..< MATERIALS {
		if i > 0 {
			fmt.sbprintf(&primitives, `,{{"attributes":{{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5}},"indices":2,"material":%v}}`, i)
			strings.write_string(&materials, ",")
			strings.write_string(&textures, ",")
			strings.write_string(&images, ",")
		}
		fmt.sbprintf(&materials, `{{"normalTexture":{{"index":%v}},"occlusionTexture":{{"index":%v}}}}`, 2 * i, 2 * i + 1)
		fmt.sbprintf(&textures, `{{"source":%v}},{{"source":%v}}`, 2 * i, 2 * i + 1)
		strings.write_string(&images, `{"bufferView":6,"mimeType":"image/png"},{"bufferView":6,"mimeType":"image/png"}`)
	}
	glb := textured_glb(
		png_make(1, 1, PNG_RGB, {128, 128, 255}),
		image = strings.to_string(images),
		texture = strings.to_string(textures),
		second = strings.to_string(primitives),
		material = strings.to_string(materials),
	)
	data, notes, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, .Too_Many_Textures in notes)
	testing.expect_value(t, len(data.textures), MESH_TEXTURE_LIMIT)
	testing.expect_value(t, len(data.parts), MATERIALS)
	last := data.parts[MATERIALS - 2]
	testing.expect_value(t, last.normal, Maybe(int)(MESH_TEXTURE_LIMIT - 2))
	testing.expect_value(t, last.occlusion, Maybe(int)(MESH_TEXTURE_LIMIT - 1))
	past := data.parts[MATERIALS - 1]
	testing.expect(t, past.normal == nil)
	testing.expect(t, past.occlusion == nil)
	testing.expect_value(t, past.material.normal_scale, f32(0))
}

@(test)
test_glb_notes_transmission_and_uses_the_material_alpha_mode :: proc(t: ^testing.T) {
	Case :: struct {
		json: string,
		want: Alpha_Mode,
	}
	cases := []Case {
		{`{"extensions":{"KHR_materials_transmission":{"transmissionFactor":0.7}}}`, .Opaque},
		{`{"alphaMode":"BLEND","extensions":{"KHR_materials_transmission":{"transmissionFactor":0.7}}}`, .Blend},
	}
	for mode in cases {
		materials := fmt.tprintf(`"materials":[%s],`, mode.json)
		data, notes, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.None)
		testing.expect_value(t, notes, Glb_Notes{.Transmission_Ignored})
		testing.expect_value(t, data.parts[0].material.alpha_mode, mode.want)
	}
}
