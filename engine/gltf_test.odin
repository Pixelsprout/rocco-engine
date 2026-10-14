package engine

import "core:encoding/endian"
import "core:fmt"
import "core:math/linalg"
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

@(test)
test_glb_reads_an_embedded_png_as_the_base_colour_texture :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(textured_glb(png_make(2, 1, PNG_RGB, {10, 20, 30, 40, 50, 60})), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	tex, ok := data.texture.?
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
	tex, ok := data.texture.?
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
	testing.expect(t, data.texture == nil)
	testing.expect_value(t, len(data.vertices), 3)
}

@(test)
test_glb_skips_a_png_that_does_not_decode_with_a_note :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(textured_glb(transmute([]byte)string("not a png")), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Bad_Png})
	testing.expect(t, data.texture == nil)
}

@(test)
test_glb_without_a_texture_has_no_texture_and_zero_uvs :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect(t, data.texture == nil)
	for v in data.vertices {
		testing.expect_value(t, v.uv, [2]f32{0, 0})
	}
}

@(test)
test_glb_rejects_a_texture_index_out_of_range :: proc(t: ^testing.T) {
	_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), texture = `{"source":4}`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Texture)
}

// The mesh has one texture, so an untextured primitive beside a textured one draws it too.
@(test)
test_glb_notes_a_textured_primitive_merged_with_an_untextured_one :: proc(t: ^testing.T) {
	second := `,{"attributes":{"POSITION":0,"NORMAL":1},"indices":3}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), second = second), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Mixed_Textures, .Mixed_Materials})
	testing.expect(t, data.texture != nil)
}

@(test)
test_glb_without_a_material_is_matte_and_not_metal :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.material, Material{roughness = 1, metallic = 0})
}

// glTF gives both factors 1 when a material leaves them out.
@(test)
test_glb_material_without_factors_takes_the_gltf_defaults :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = `"materials":[{}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.material, Material{roughness = 1, metallic = 1})
}

@(test)
test_glb_reads_the_metallic_and_roughness_factors :: proc(t: ^testing.T) {
	materials := `"materials":[{"pbrMetallicRoughness":{"metallicFactor":0.25,"roughnessFactor":0.5}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.material, Material{roughness = 0.5, metallic = 0.25})
}

@(test)
test_glb_reads_the_unlit_extension :: proc(t: ^testing.T) {
	materials := `"materials":[{"extensions":{"KHR_materials_unlit":{}}}],`
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect(t, data.material.unlit)
}

@(test)
test_glb_reads_the_metallic_roughness_texture_as_linear :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":0},"roughnessFactor":0.5}}`
	glb := textured_glb(png_make(1, 1, PNG_RGB, {0, 200, 100}), material = material)
	data, notes, err := glb_parse(glb, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect(t, data.texture == nil)
	tex, ok := data.metallic_roughness.?
	testing.expect(t, ok)
	testing.expect(t, !tex.srgb)
	want := [4]byte{0, 200, 100, 255}
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, want[i])
	}
	testing.expect_value(t, data.material, Material{roughness = 0.5, metallic = 1})
}

@(test)
test_glb_reads_a_base_colour_texture_as_srgb :: proc(t: ^testing.T) {
	data, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3})), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	tex, ok := data.texture.?
	testing.expect(t, ok)
	testing.expect(t, tex.srgb)
}

@(test)
test_glb_rejects_a_metallic_roughness_texture_index_out_of_range :: proc(t: ^testing.T) {
	material := `{"pbrMetallicRoughness":{"metallicRoughnessTexture":{"index":3}}}`
	_, _, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {1, 2, 3}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Texture)
}

// The mesh has one material, so every primitive draws with the first one's.
@(test)
test_glb_notes_primitives_with_different_materials :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"pbrMetallicRoughness":{"roughnessFactor":0.2}},
		{"pbrMetallicRoughness":{"roughnessFactor":0.9}}],`
	data, notes, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Mixed_Materials})
	testing.expect_value(t, data.material.roughness, f32(0.2))
}

@(test)
test_glb_does_not_note_materials_that_differ_only_in_colour :: proc(t: ^testing.T) {
	materials := `"materials":[
		{"pbrMetallicRoughness":{"baseColorFactor":[1,0,0,1],"metallicFactor":0}},
		{"pbrMetallicRoughness":{"baseColorFactor":[0,0,1,1],"metallicFactor":0}}],`
	_, notes, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
}
