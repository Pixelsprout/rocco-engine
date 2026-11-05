#+test
package engine

import "core:fmt"
import "core:strings"
import "core:testing"

@(test)
test_glb_named_slots_survive_equal_values_and_part_sorting :: proc(t: ^testing.T) {
	materials := `"materials":[{"name":"leaves","alphaMode":"BLEND"},{"name":"bark"},{"name":"twigs"}],`
	primitives := `[{"attributes":{"POSITION":0,"NORMAL":1},"material":0},{"attributes":{"POSITION":0,"NORMAL":1},"material":2},{"attributes":{"POSITION":0,"NORMAL":1},"material":1}]`
	data, _, err := glb_parse(triangle_glb(primitives, extra = materials), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 3)
	testing.expect_value(t, len(data.material_slots), 3)
	for name, source in ([]string{"leaves", "bark", "twigs"}) {
		slot, slot_err := mesh_material_slot(data.material_slots, name)
		testing.expect_value(t, slot_err, Mesh_Material_Slot_Error.None)
		testing.expect_value(t, slot, source)
	}
	testing.expect_value(t, data.parts[0].slot, Maybe(int)(2))
	testing.expect_value(t, data.parts[1].slot, Maybe(int)(1))
	testing.expect_value(t, data.parts[2].slot, Maybe(int)(0))
	reversed := `[{"attributes":{"POSITION":0,"NORMAL":1},"material":1},{"attributes":{"POSITION":0,"NORMAL":1},"material":0},{"attributes":{"POSITION":0,"NORMAL":1},"material":2}]`
	other, _, other_err := glb_parse(triangle_glb(reversed, extra = materials), context.temp_allocator)
	testing.expect_value(t, other_err, Glb_Error.None)
	for slot, i in other.material_slots {
		testing.expect_value(t, slot, data.material_slots[i])
	}
	testing.expect_value(t, other.parts[0].slot, Maybe(int)(1))
	testing.expect_value(t, other.parts[1].slot, Maybe(int)(2))
	testing.expect_value(t, other.parts[2].slot, Maybe(int)(0))
}

@(test)
test_glb_duplicate_names_keep_identity_without_ambiguous_lookup :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = `"materials":[{"name":"leaves"},{"name":"leaves"}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 2)
	testing.expect_value(t, data.parts[0].slot, Maybe(int)(0))
	testing.expect_value(t, data.parts[1].slot, Maybe(int)(1))
	_, slot_err := mesh_material_slot(data.material_slots, "leaves")
	testing.expect_value(t, slot_err, Mesh_Material_Slot_Error.Duplicate_Name)
}

@(test)
test_glb_unnamed_slots_keep_legacy_merging :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(TWO_MATERIAL_PRIMITIVES, extra = `"materials":[{},{}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, len(data.parts), 1)
	testing.expect_value(t, len(data.material_slots), 2)
	testing.expect(t, data.parts[0].slot == nil)
	for source, i in data.vertex_materials {
		testing.expect_value(t, source, 0 if i < 3 else 1)
	}
	_, slot_err := mesh_material_slot(data.material_slots, "")
	testing.expect_value(t, slot_err, Mesh_Material_Slot_Error.Unnamed)
}

color_glb :: proc(accessor: string, colors: []byte, material := `{"name":"grass","alphaMode":"MASK","pbrMetallicRoughness":{"baseColorFactor":[0.5,0.25,1,0.5]}}`, stride := 0) -> []byte {
	bin := make([dynamic]byte, context.temp_allocator)
	append(&bin, ..triangle_bin())
	append(&bin, ..colors)
	json := fmt.tprintf(`{{"asset":{{"version":"2.0"}},"nodes":[{{"mesh":0}}],"meshes":[{{"primitives":[{{"attributes":{{"POSITION":0,"NORMAL":1,"COLOR_0":2}},"material":0}}]}}],"materials":[%s],"buffers":[{{"byteLength":%v}}],"bufferViews":[{{"buffer":0,"byteLength":36}},{{"buffer":0,"byteOffset":36,"byteLength":36}},{{"buffer":0,"byteOffset":96,"byteLength":%v,"byteStride":%v}}],"accessors":[{{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3"}},{{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"}},%s]}}`, material, len(bin), len(colors), stride, accessor)
	return glb_make(json, bin[:])
}

@(test)
test_glb_color_factors_multiply_rgba_and_keep_raw_weights :: proc(t: ^testing.T) {
	for components in ([]int{3, 4}) {
		for component_type in ([]int{GLTF_F32, GLTF_U8, GLTF_U16}) {
			bin := make([dynamic]byte, context.temp_allocator)
			for _ in 0 ..< 3 {
				for i in 0 ..< components {
					switch component_type {
					case GLTF_F32: bin_put(&bin, f32(0.25) if i == 3 else f32(1))
					case GLTF_U8: append(&bin, u8(51) if i == 3 else u8(255))
					case GLTF_U16: bin_put(&bin, u16(13107) if i == 3 else u16(65535))
					}
				}
			}
			accessor := fmt.tprintf(`{{"bufferView":2,"componentType":%v,"count":3,"type":"VEC%v","normalized":%v}}`, component_type, components, component_type != GLTF_F32)
			data, _, err := glb_parse(color_glb(accessor, bin[:]), context.temp_allocator)
			testing.expect_value(t, err, Glb_Error.None)
			alpha: f32 = 1
			if components == 4 { alpha = 0.25 if component_type == GLTF_F32 else 0.2 }
			for vertex, i in data.vertices {
				testing.expect_value(t, vertex.color, [4]f32{0.5, 0.25, 1, alpha * 0.5})
				testing.expect_value(t, data.vertex_colors[i], [4]f32{1, 1, 1, alpha})
			}
			testing.expect_value(t, data.parts[0].material.alpha_mode, Alpha_Mode.Mask)
			testing.expect_value(t, data.material_slots[0].base_color_factor, [4]f32{0.5, 0.25, 1, 0.5})
		}
	}
}

@(test)
test_glb_reads_interleaved_vertex_colour_with_accessor_offset :: proc(t: ^testing.T) {
	bytes := []byte{0, 255, 128, 64, 32, 0, 0, 0, 0, 255, 128, 64, 32, 0, 0, 0, 0, 255, 128, 64, 32, 0, 0, 0}
	accessor := `{"bufferView":2,"byteOffset":1,"componentType":5121,"normalized":true,"count":3,"type":"VEC4"}`
	data, _, err := glb_parse(color_glb(accessor, bytes, stride = 8), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.vertex_colors[2], [4]f32{1, 128.0/255, 64.0/255, 32.0/255})
}

@(test)
test_glb_rejects_invalid_vertex_colour_accessors :: proc(t: ^testing.T) {
	accessors := []string{
		`{"bufferView":2,"componentType":5121,"count":3,"type":"VEC4"}`,
		`{"bufferView":2,"componentType":5123,"count":3,"type":"VEC4"}`,
		`{"bufferView":2,"componentType":5126,"normalized":true,"count":3,"type":"VEC4"}`,
		`{"bufferView":2,"componentType":5122,"normalized":true,"count":3,"type":"VEC4"}`,
		`{"bufferView":2,"componentType":5121,"normalized":true,"count":2,"type":"VEC4"}`,
		`{"bufferView":2,"componentType":5121,"normalized":true,"count":3,"type":"VEC2"}`,
		`{"bufferView":2,"componentType":5121,"normalized":true,"count":30,"type":"VEC4"}`,
	}
	for accessor in accessors {
		_, _, err := glb_parse(color_glb(accessor, make([]byte, 48, context.temp_allocator)), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.Bad_Accessor)
	}
}

@(test)
test_mesh_keeps_slot_names_and_raw_colours_until_unload :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, 8, context.temp_allocator, context.allocator)
	defer mesh_table_destroy(&table)
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES, extra = `"materials":[{"name":"bark"}],`), context.allocator)
	testing.expect_value(t, err, Glb_Error.None)
	slot, ok := mesh_table_add(&table, strings.clone("tree", context.allocator), data)
	testing.expect(t, ok)
	mesh := &table.meshes[slot]
	testing.expect_value(t, mesh.material_slots[0].name, "bark")
	testing.expect_value(t, mesh.parts[0].slot, Maybe(int)(0))
	testing.expect_value(t, len(mesh.vertex_colors), 3)
	testing.expect(t, mesh.data.vertex_colors == nil)
	testing.expect(t, mesh.data.vertex_materials == nil)
	testing.expect_value(t, mesh.vertex_materials[0], 0)
	testing.expect(t, mesh.data.material_slots == nil)
	testing.expect_value(t, mesh.material_slots[0].name, "bark")
	testing.expect_value(t, mesh.vertex_colors[0], [4]f32{1, 1, 1, 1})
	mesh_table_remove(&table, slot)
}

@(test)
test_glb_named_slots_preserve_maps_and_uvs :: proc(t: ^testing.T) {
	material := `{"name":"bark","pbrMetallicRoughness":{"baseColorTexture":{"index":0},"metallicRoughnessTexture":{"index":0}},"normalTexture":{"index":0},"occlusionTexture":{"index":0},"emissiveTexture":{"index":0}}`
	data, notes, err := glb_parse(textured_glb(png_make(1, 1, PNG_RGB, {128, 128, 255}), material = material), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{.Generated_Tangents})
	part := data.parts[0]
	testing.expect_value(t, part.slot, Maybe(int)(0))
	testing.expect_value(t, part.texture, part.emissive)
	testing.expect_value(t, part.normal, part.occlusion)
	testing.expect_value(t, part.normal, part.metallic_roughness)
	testing.expect(t, part.normal != part.texture)
	testing.expect_value(t, data.vertices[1].uv, [2]f32{1, 0})
	testing.expect_value(t, data.vertices[1].tangent, [4]f32{1, 0, 0, -1})
}

@(test)
test_glb_slots_do_not_change_authored_root_transforms :: proc(t: ^testing.T) {
	data, _, err := glb_parse(triangle_glb(MATERIAL_PRIMITIVES,
		nodes = `[{"translation":[0,2,0],"children":[1]},{"mesh":0,"translation":[3,0,0]}]`,
		extra = `"materials":[{"name":"bark"}],`), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.vertices[0].pos, [3]f32{3, 2, 0})
	testing.expect_value(t, data.vertices[0].normal, [3]f32{0, 0, 1})
	testing.expect_value(t, data.parts[0].slot, Maybe(int)(0))
}

@(test)
test_mask_mip_threshold_uses_combined_imported_alpha_once :: proc(t: ^testing.T) {
	bytes := []byte{255,255,255,128, 255,255,255,128, 255,255,255,128}
	accessor := `{"bufferView":2,"componentType":5121,"normalized":true,"count":3,"type":"VEC4"}`
	data, _, err := glb_parse(color_glb(accessor, bytes), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	loader := Glb_Loader{vertices = make([dynamic]Vertex, context.temp_allocator)}
	append(&loader.vertices, ..data.vertices)
	run := Glb_Material_Run{material = {values = {alpha_mode = .Mask, alpha_cutoff = 0.2}}, indices = make([dynamic]u16, context.temp_allocator)}
	append(&run.indices, 0, 1, 2)
	testing.expect_value(t, glb_mask_texture_cutoff(&loader, &run), f32(0.2) / (f32(128) / 255 * 0.5))
	loader.vertices[1].color.w = 1
	testing.expect_value(t, glb_mask_texture_cutoff(&loader, &run), 0)
}

@(test)
test_mask_mip_variants_share_only_equal_effective_cutoffs_and_keep_named_slots :: proc(t: ^testing.T) {
	materials := `{"name":"leaf","alphaMode":"MASK","alphaCutoff":0.3,"pbrMetallicRoughness":{"baseColorFactor":[1,1,1,0.5],"baseColorTexture":{"index":0}}},
	{"name":"bark","pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},
	{"name":"twig","alphaMode":"MASK","alphaCutoff":0.6,"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}`
	second := `,{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5},"indices":2,"material":1},{"attributes":{"POSITION":0,"NORMAL":1,"TEXCOORD_0":5},"indices":2,"material":2}`
	rgba := []byte{80,120,160,255, 80,120,160,0, 80,120,160,0, 80,120,160,0}
	bytes := textured_glb(png_make(2, 2, PNG_RGBA, rgba), material = materials, second = second, texture = `{"source":0,"sampler":0}`, samplers = `"samplers":[{"minFilter":9987}],`)
	data, notes, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.textures), 2)
	testing.expect_value(t, data.parts[0].slot, Maybe(int)(1))
	testing.expect_value(t, data.parts[1].slot, Maybe(int)(0))
	testing.expect_value(t, data.parts[2].slot, Maybe(int)(2))
	testing.expect_value(t, data.parts[1].texture, data.parts[2].texture)
	testing.expect(t, data.parts[0].texture != data.parts[1].texture)
	opaque := data.textures[data.parts[0].texture.? or_else -1]
	mask := data.textures[data.parts[1].texture.? or_else -1]
	testing.expect_value(t, opaque.levels[1].pixels[3], 64)
	testing.expect(t, f32(mask.levels[1].pixels[3]) / 255 >= 0.6)
}
