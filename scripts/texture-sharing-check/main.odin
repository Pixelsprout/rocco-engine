#+build darwin
package main

import engine "../../engine"
import sg "../../sokol-odin/sokol/gfx"
import slog "../../sokol-odin/sokol/log"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import MTL "vendor:darwin/Metal"

@(rodata)
MESH_NAMES := [2]string{"Grass_Common_Short", "Grass_Common_Tall"}

main :: proc() {
	assert(len(os.args) == 2)
	data: [2]engine.Mesh_Data
	indices: [2]int
	for name, i in MESH_NAMES {
		bytes, read_err := os.read_entire_file(fmt.tprintf("%s/%s.glb", os.args[1], name), context.allocator)
		assert(read_err == nil)
		loaded, notes, err := engine.glb_parse(bytes, context.allocator)
		delete(bytes)
		assert(err == .None)
		data[i] = loaded
		index, has_texture := loaded.parts[0].texture.?
		assert(has_texture)
		indices[i] = index
		fmt.printf("mesh=%s loader_notes=%v textures=%v base_slot=%v\n", name, notes, len(loaded.textures), index)
	}
	a, b := data[0].textures[indices[0]], data[1].textures[indices[1]]
	assert(a.srgb == b.srgb && a.alpha_cutoff == b.alpha_cutoff && a.sampler == b.sampler)
	assert(len(a.levels) == len(b.levels))
	payload_bytes := 0
	for level, i in a.levels {
		other := b.levels[i]
		assert(level.width == other.width && level.height == other.height)
		assert(slice.equal(level.pixels, other.pixels))
		payload_bytes += len(level.pixels)
	}
	fmt.printf("decoded_mips_equal=true width=%v height=%v mip_count=%v payload_bytes=%v srgb=%v cutoff=%v sampler=%v\n", a.levels[0].width, a.levels[0].height, len(a.levels), payload_bytes, a.srgb, a.alpha_cutoff, a.sampler)

	device := MTL.CreateSystemDefaultDevice()
	assert(device != nil)
	defer device->release()
	sg.setup({environment = {metal = {device = device}, defaults = {color_format = .RGBA8, depth_format = .DEPTH_STENCIL, sample_count = 1}}, uniform_buffer_size = 1024 * 1024, logger = {func = slog.func}})
	assert(sg.isvalid())
	defer sg.shutdown()
	table: engine.Mesh_Table
	engine.mesh_table_init(&table, 6, context.allocator, context.allocator)
	defer engine.mesh_table_destroy(&table)
	slots: [2]int
	for name, i in MESH_NAMES {
		slot, ok := engine.mesh_table_add(&table, strings.clone(name), data[i])
		assert(ok)
		slots[i] = slot
	}
	engine.mesh_table_upload(&table)
	textures: [2]rawptr
	for slot, i in slots {
		m := &table.meshes[slot]
		textures[i] = report_texture(MESH_NAMES[i], "base", m.textures[indices[i]])
		ordinary := m.textures[indices[i]].ordinary
		if ordinary != nil { report_texture(MESH_NAMES[i], "ordinary", ordinary^) }
	}
	assert(textures[0] == textures[1])
 resource := (^MTL.Resource)(textures[0])
 assert(resource->allocatedSize() == 1_425_408)
 fmt.printf("shared_base_image=true unique_native_bytes=%v avoided_native_bytes=1425408 cache_hits=%v references=%v live_images=%v\n", resource->allocatedSize(), table.texture_cache.hits, table.texture_cache.references, len(table.texture_cache.entries))
 engine.mesh_table_remove(&table, slots[0])
 report_texture(MESH_NAMES[1], "after-first-unload", table.meshes[slots[1]].textures[indices[1]])
 assert(table.texture_cache.references == 1)
 engine.mesh_table_remove(&table, slots[1])
 assert(table.texture_cache.references == 0 && len(table.texture_cache.entries) == 0)
 for name, i in MESH_NAMES {
  id, reason, ok := engine.mesh_load_file(&table, os.args[1], name)
  assert(ok && reason == "")
  slots[i] = engine.mesh_slot(id)
 }
 assert(table.meshes[slots[0]].textures[indices[0]].image == table.meshes[slots[1]].textures[indices[1]].image)
 engine.mesh_table_remove(&table, slots[1])
 report_texture(MESH_NAMES[0], "after-reverse-unload", table.meshes[slots[0]].textures[indices[0]])
 engine.mesh_table_remove(&table, slots[0])
 assert(table.texture_cache.references == 0 && len(table.texture_cache.entries) == 0)
 fmt.println("both_unload_orders=true final_live_images=0 final_references=0")
}

report_texture :: proc(mesh, kind: string, texture: engine.Mesh_Texture) -> rawptr {
	assert(sg.query_image_state(texture.image) == .VALID)
	info := sg.mtl_query_image_info(texture.image)
	native := info.tex[info.active_slot]
	assert(native != nil)
	resource := (^MTL.Resource)(native)
	fmt.printf("mesh=%s kind=%s image_id=%v native=%v allocated_bytes=%v\n", mesh, kind, texture.image.id, native, resource->allocatedSize())
	return native
}
