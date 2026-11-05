#+test
package engine

import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_glb_load_scratch_does_not_accumulate_in_frame_memory :: proc(t: ^testing.T) {
	pixels := make([]byte, 256 * 256 * 4, context.temp_allocator)
	for &p in pixels { p = 127 }
	bytes := textured_glb(png_make(256, 256, PNG_RGBA, pixels),
		texture = `{"source":0,"sampler":0},{"source":0,"sampler":1}`,
		samplers = `"samplers":[{"minFilter":9987},{"minFilter":9728}],`,
		second = `,{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}`,
		material = `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},{"pbrMetallicRoughness":{"baseColorTexture":{"index":1}}}`)
	files := make(map[string][]byte, context.temp_allocator)
	files["tree.glb"] = bytes
	files["bad.glb"] = textured_glb(png_make(1, 1, PNG_RGB, {19, 29, 39}),
		material = `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},"normalTexture":{"index":4}}`)
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	frame: vmem.Arena
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	assets: mem.Tracking_Allocator
	mem.tracking_allocator_init(&assets, context.allocator)
	defer mem.tracking_allocator_destroy(&assets)
	allocator := mem.tracking_allocator(&assets)
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, allocator, allocator)
	baseline := assets.current_memory_allocated
	for _ in 0 ..< 4 {
		before_error := frame.total_used
		_, reason, loaded_bad := mesh_load_file(&table, dir, "bad")
		after_error := frame.total_used
		testing.expect(t, !loaded_bad)
		testing.expect_value(t, reason, GLB_ERROR_REASONS[.Bad_Texture])
		testing.expect_value(t, assets.current_memory_allocated, baseline)
		testing.expect_value(t, after_error, before_error)
		ids: [2]u32
		for &id in ids {
			before := frame.total_used
			loaded, _, ok := mesh_load_file(&table, dir, "tree")
			after := frame.total_used
			testing.expect(t, ok)
			testing.expect_value(t, after, before)
			id = loaded
			data := table.meshes[mesh_slot(id)].data
			testing.expect_value(t, len(data.textures), 2)
			for tex in data.textures {
				testing.expect_value(t, tex.levels[0].width, 256)
				testing.expect_value(t, tex.levels[0].pixels[0], byte(127))
			}
		}
		for id in ids { mesh_table_remove(&table, mesh_slot(id)) }
		testing.expect_value(t, assets.current_memory_allocated, baseline)
	}
	mesh_table_destroy(&table)
	testing.expect_value(t, assets.current_memory_allocated, i64(0))
}

@(test)
test_glb_parse_scratch_preserves_a_caller_temp_allocator_result :: proc(t: ^testing.T) {
	bytes := textured_glb(png_make(1, 1, PNG_RGB, {19, 29, 39}))
	frame: vmem.Arena
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	data, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.vertices[1].pos, [3]f32{1, 0, 0})
	testing.expect_value(t, data.textures[0].pixels[0], byte(19))
	testing.expect_value(t, data.parts[0].texture, Maybe(int)(0))
}

@(test)
test_glb_parse_error_releases_textures_and_scratch :: proc(t: ^testing.T) {
	bytes := textured_glb(png_make(1, 1, PNG_RGB, {19, 29, 39}),
		material = `{"pbrMetallicRoughness":{"baseColorTexture":{"index":0}},"normalTexture":{"index":4}}`)
	frame: vmem.Arena
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	assets: mem.Tracking_Allocator
	mem.tracking_allocator_init(&assets, context.allocator)
	defer mem.tracking_allocator_destroy(&assets)
	for _ in 0 ..< 4 {
		_, _, err := glb_parse(bytes, mem.tracking_allocator(&assets))
		testing.expect_value(t, err, Glb_Error.Bad_Texture)
		testing.expect_value(t, assets.current_memory_allocated, i64(0))
		testing.expect_value(t, frame.total_used, uint(0))
	}
}

@(test)
test_glb_bad_png_releases_decode_scratch_and_keeps_the_mesh :: proc(t: ^testing.T) {
	pixels := make([]byte, 256 * 256 * 4, context.temp_allocator)
	image := png_make(256, 256, PNG_RGBA, pixels)
	bytes := textured_glb(image[:len(image) / 2])
	frame: vmem.Arena
	defer vmem.arena_destroy(&frame)
	context.temp_allocator = vmem.arena_allocator(&frame)
	assets: mem.Tracking_Allocator
	mem.tracking_allocator_init(&assets, context.allocator)
	defer mem.tracking_allocator_destroy(&assets)
	allocator := mem.tracking_allocator(&assets)
	table: Mesh_Table
	mesh_table_init(&table, SMALL_MESHES, allocator, allocator)
	baseline := assets.current_memory_allocated
	for _ in 0 ..< 4 {
		before := frame.total_used
		data, notes, err := glb_parse(bytes, allocator)
		after := frame.total_used
		testing.expect_value(t, err, Glb_Error.None)
		testing.expect_value(t, notes, Glb_Notes{.Bad_Png})
		testing.expect_value(t, len(data.vertices), 3)
		testing.expect_value(t, len(data.textures), 0)
		slot, _ := mesh_table_add(&table, strings.clone("partial", allocator), data)
		mesh_table_remove(&table, slot)
		testing.expect_value(t, assets.current_memory_allocated, baseline)
		testing.expect_value(t, after, before)
	}
	mesh_table_destroy(&table)
	testing.expect_value(t, assets.current_memory_allocated, i64(0))
}
