package engine

import "core:encoding/endian"
import "core:fmt"
import "core:math/linalg"
import "core:testing"

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
	data, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]`), context.temp_allocator)
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
	_, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Magic)
}

@(test)
test_glb_rejects_a_primitive_without_normals :: proc(t: ^testing.T) {
	_, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0},"indices":2}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.No_Normals)
}

@(test)
test_glb_rejects_a_primitive_that_is_not_triangles :: proc(t: ^testing.T) {
	_, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"mode":1}]`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Not_Triangles)
}

// The parent moves up 2 with a column-major matrix. The child scales by 2,
// then turns 90 degrees about +y, which takes +x to -z and +z to +x.
@(test)
test_glb_bakes_each_node_world_transform_into_positions_and_normals :: proc(t: ^testing.T) {
	nodes := `[
		{"children":[1],"matrix":[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,2,0,1]},
		{"mesh":0,"rotation":[0,0.70710678,0,0.70710678],"scale":[2,2,2]}]`
	data, err := glb_parse(triangle_glb(`[{"attributes":{"POSITION":0,"NORMAL":1},"indices":4}]`, nodes), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	want_pos := [3][3]f32{{0, 2, 0}, {0, 2, -2}, {0, 4, 0}}
	for v, i in data.vertices {
		testing.expectf(t, linalg.length(v.pos - want_pos[i]) < 1e-5, "vertex %v at %v, want %v", i, v.pos, want_pos[i])
		testing.expectf(t, linalg.length(v.normal - [3]f32{1, 0, 0}) < 1e-5, "normal %v is %v, want +x", i, v.normal)
	}
}

@(test)
test_glb_merges_primitives_and_colours_each_by_its_material :: proc(t: ^testing.T) {
	primitives := `[
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":2,"material":0},
		{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}]`
	materials := `"materials":[
		{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1]}},
		{"pbrMetallicRoughness":{"baseColorFactor":[0,0,1,1]}}],`
	data, err := glb_parse(triangle_glb(primitives, extra = materials), context.temp_allocator)
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
	_, err := glb_parse(glb_make(json, make([]byte, COUNT * 12, context.temp_allocator)), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Too_Many_Vertices)
}
