#+test
package engine

import sg "../sokol-odin/sokol/gfx"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

Texture_Fake_GPU :: struct {
	next: u32,
	live_images, live_samplers: map[u32]bool,
	sampler_settings: map[u32]Texture_Sampler,
	images_created, images_destroyed, samplers_destroyed: int,
	fail_image_at, image_attempts, fail_sampler_at, sampler_attempts: int,
}

texture_fake_image :: proc(ctx: rawptr, _: sg.Image_Desc) -> (sg.Image, sg.View, bool) {
	f := (^Texture_Fake_GPU)(ctx)
	f.image_attempts += 1
	if f.image_attempts == f.fail_image_at { return {}, {}, false }
	f.next += 1
	f.live_images[f.next] = true
	f.images_created += 1
	return {id = f.next}, {id = f.next}, true
}

texture_fake_image_destroy :: proc(ctx: rawptr, image: sg.Image, _: sg.View) {
	f := (^Texture_Fake_GPU)(ctx)
	assert(f.live_images[image.id])
	delete_key(&f.live_images, image.id)
	f.images_destroyed += 1
}

texture_fake_sampler :: proc(ctx: rawptr, s: Texture_Sampler) -> (sg.Sampler, bool) {
	f := (^Texture_Fake_GPU)(ctx)
	f.sampler_attempts += 1
	if f.sampler_attempts == f.fail_sampler_at { return {}, false }
	f.next += 1
	f.live_samplers[f.next] = true
	f.sampler_settings[f.next] = s
	return {id = f.next}, true
}

texture_fake_sampler_destroy :: proc(ctx: rawptr, sampler: sg.Sampler) {
	f := (^Texture_Fake_GPU)(ctx)
	assert(f.live_samplers[sampler.id])
	delete_key(&f.live_samplers, sampler.id)
	delete_key(&f.sampler_settings, sampler.id)
	f.samplers_destroyed += 1
}

texture_fake_init :: proc(c: ^Texture_Cache, f: ^Texture_Fake_GPU) {
	f.live_images = make(map[u32]bool)
	f.live_samplers = make(map[u32]bool)
	f.sampler_settings = make(map[u32]Texture_Sampler)
	c.gpu = {f, texture_fake_image, texture_fake_image_destroy, texture_fake_sampler, texture_fake_sampler_destroy}
}

texture_fake_destroy :: proc(f: ^Texture_Fake_GPU) {
	assert(len(f.live_images) == 0 && len(f.live_samplers) == 0)
	delete(f.live_images)
	delete(f.live_samplers)
	delete(f.sampler_settings)
}

texture_test_data :: proc(cutoff: f32 = 0, value: byte = 127) -> Texture {
	pixels: [16]byte
	for &p in pixels { p = value }
	return texture_build(2, 2, pixels[:], {min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_filter = .LINEAR, wrap_u = .REPEAT, wrap_v = .REPEAT, mipmaps = true}, true, context.allocator, cutoff)
}

@(test)
test_texture_cache_shares_images_and_keeps_samplers_per_use :: proc(t: ^testing.T) {
	c: Texture_Cache; texture_cache_init(&c, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&c, &f)
	defer texture_fake_destroy(&f)
	defer texture_cache_destroy(&c)
	tex := texture_test_data(); defer texture_delete(tex, context.allocator)
	a, ok := texture_cache_acquire(&c, tex); testing.expect(t, ok)
	tex.sampler.wrap_u = .CLAMP_TO_EDGE
	tex.sampler.mag_filter = .NEAREST
	b, second := texture_cache_acquire(&c, tex); testing.expect(t, second)
	testing.expect_value(t, a.image, b.image)
	testing.expect_value(t, a.view, b.view)
	testing.expect(t, a.sampler != b.sampler)
	testing.expect_value(t, f.sampler_settings[a.sampler.id].wrap_u, sg.Wrap.REPEAT)
	testing.expect_value(t, f.sampler_settings[b.sampler.id].wrap_u, sg.Wrap.CLAMP_TO_EDGE)
	testing.expect_value(t, f.sampler_settings[b.sampler.id].mag_filter, sg.Filter.NEAREST)
	testing.expect_value(t, c.unique_payload_bytes, u64(20))
	testing.expect_value(t, c.referenced_payload_bytes, u64(40))
	texture_cache_release(&c, a)
	testing.expect(t, f.live_images[b.image.id])
	texture_cache_release(&c, b)
	testing.expect_value(t, f.images_destroyed, 1)
	testing.expect_value(t, f.samplers_destroyed, 2)
	testing.expect_value(t, c.references, u64(0))
	testing.expect_value(t, c.unique_payload_bytes, u64(0))
	testing.expect_value(t, c.referenced_payload_bytes, u64(0))
}

@(test)
test_texture_cache_separates_all_mips_dimensions_formats_and_cutoffs :: proc(t: ^testing.T) {
	c: Texture_Cache; texture_cache_init(&c, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&c, &f)
	defer texture_fake_destroy(&f)
	defer texture_cache_destroy(&c)
	tex := texture_test_data(); defer texture_delete(tex, context.allocator)
	acquired := make([dynamic]Mesh_Texture); defer delete(acquired)
	base, ok := texture_cache_acquire(&c, tex); testing.expect(t, ok); append(&acquired, base)
	for variant in 0 ..< 6 {
		changed := tex
		changed.levels = slice.clone(tex.levels); defer delete(changed.levels)
		switch variant {
		case 0:
			changed.levels[1].pixels = slice.clone(tex.levels[1].pixels)
			changed.levels[1].pixels[0] += 1
			defer delete(changed.levels[1].pixels)
		case 1: changed.srgb = false
		case 2: changed.alpha_cutoff = 0.5
		case 3: changed.alpha_cutoff = 0.25
		case 4: changed.levels[0].width, changed.levels[0].height = 1, 4
		case 5: changed.levels = changed.levels[:1]
		}
		got, valid := texture_cache_acquire(&c, changed); testing.expect(t, valid)
		testing.expect(t, got.image != base.image)
		append(&acquired, got)
	}
	testing.expect_value(t, len(c.entries), 7)
	for texture in acquired { texture_cache_release(&c, texture) }
	testing.expect_value(t, len(c.entries), 0)
}

@(test)
test_texture_cache_failure_preserves_other_owners_and_allows_retry :: proc(t: ^testing.T) {
	c: Texture_Cache; texture_cache_init(&c, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&c, &f)
	defer texture_fake_destroy(&f)
	defer texture_cache_destroy(&c)
	tex := texture_test_data(); defer texture_delete(tex, context.allocator)
	owner, _ := texture_cache_acquire(&c, tex)
	f.fail_sampler_at = f.sampler_attempts + 1
	_, sampler_ok := texture_cache_acquire(&c, tex)
	testing.expect(t, !sampler_ok)
	changed := texture_test_data(value = 98); defer texture_delete(changed, context.allocator)
	f.fail_image_at = f.image_attempts + 1
	_, image_ok := texture_cache_acquire(&c, changed)
	testing.expect(t, !image_ok)
	testing.expect(t, f.live_images[owner.image.id])
	testing.expect_value(t, c.references, u64(1))
	testing.expect_value(t, len(f.live_samplers), 1)
	fresh, retry := texture_cache_acquire(&c, changed); testing.expect(t, retry)
	testing.expect(t, fresh.image != owner.image)
	texture_cache_release(&c, owner)
	texture_cache_release(&c, fresh)
}

@(test)
test_texture_references_stay_valid_when_cache_grows :: proc(t: ^testing.T) {
	c: Texture_Cache; texture_cache_init(&c, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&c, &f)
	defer texture_fake_destroy(&f)
	defer texture_cache_destroy(&c)
	owners: [100]Mesh_Texture
	for &owner, i in owners {
		tex := texture_test_data(value = byte(i)); defer texture_delete(tex, context.allocator)
		ok: bool; owner, ok = texture_cache_acquire(&c, tex); testing.expect(t, ok)
	}
	for owner in owners { texture_cache_release(&c, owner) }
	testing.expect_value(t, f.images_destroyed, len(owners))
}

@(test)
test_packs_preserve_shared_images_in_both_unload_orders_and_slot_reuse :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	bytes := textured_glb(png_make(2, 2, PNG_RGBA, {1,2,3,255,1,2,3,255,1,2,3,255,1,2,3,255}), second = `,{"attributes":{"POSITION":0,"NORMAL":1},"indices":3,"material":1}`, material = `{"name":"first","pbrMetallicRoughness":{"baseColorTexture":{"index":0}}},{"name":"second","pbrMetallicRoughness":{"baseColorTexture":{"index":0}}}`)
	files["meshes/a.glb"], files["meshes/b.glb"] = bytes, bytes
	dir := temp_assets_dir(t, files); defer os.remove_all(dir)
	for reverse in 0 ..< 2 {
		table: Mesh_Table; mesh_table_init(&table, 8, context.allocator, context.allocator)
		f: Texture_Fake_GPU; texture_fake_init(&table.texture_cache, &f)
		p: Packs; packs_init(&p, dir, context.allocator)
		skies: Sky_Table; images: Image_Table; audio: Audio
		packs_attach(&p, &table, &skies, &images, &audio, context.allocator)
		for cycle in 0 ..< 4 {
			a, _ := pack_load(&p, "A", {"a"}, context.temp_allocator)
			b, _ := pack_load(&p, "B", {"b"}, context.temp_allocator)
			shared, _ := pack_load(&p, "Shared", {"a"}, context.temp_allocator)
			testing.expect_value(t, a[0].id, shared[0].id)
			testing.expect(t, pack_unload(&p, "Shared"))
			testing.expect_value(t, table.texture_cache.references, u64(0))
			for id in ([]u32{a[0].id, b[0].id}) {
				m, _ := mesh_lookup(&table, id)
				testing.expect(t, mesh_textures_upload(&table, m))
				testing.expect_value(t, m.parts[0].texture.image, m.parts[1].texture.image)
			}
			testing.expect_value(t, table.texture_cache.references, u64(2))
			first := "A" if reverse == 0 else "B"
			last := "B" if reverse == 0 else "A"
			testing.expect(t, pack_unload(&p, first))
			testing.expect_value(t, len(f.live_images), 1)
			testing.expect_value(t, table.texture_cache.references, u64(1))
			testing.expect(t, pack_unload(&p, last))
			testing.expect_value(t, len(f.live_images), 0)
			testing.expect_value(t, table.texture_cache.references, u64(0))
			_, stale := mesh_lookup(&table, a[0].id); testing.expect(t, !stale)
			testing.expect_value(t, f.images_destroyed, cycle + 1)
		}
		packs_destroy(&p)
		mesh_table_destroy(&table)
		texture_fake_destroy(&f)
	}
}

@(test)
test_mesh_partial_texture_upload_releases_cutoff_and_ordinary_references :: proc(t: ^testing.T) {
	table: Mesh_Table; mesh_table_init(&table, 8, context.allocator, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&table.texture_cache, &f)
	defer texture_fake_destroy(&f)
	defer mesh_table_destroy(&table)
	for _ in 0 ..< 3 {
		data := Mesh_Data{textures = make([]Texture, 2)}
		data.textures[0], data.textures[1] = texture_test_data(0.5), texture_test_data(value = 99)
		slot, _ := mesh_table_add(&table, strings.clone("cutout"), data)
		m := &table.meshes[slot]
		f.fail_image_at = f.image_attempts + 3
		testing.expect(t, !mesh_textures_upload(&table, m))
		testing.expect_value(t, table.texture_cache.references, u64(0))
		testing.expect_value(t, len(f.live_samplers), 0)
		testing.expect(t, mesh_textures_upload(&table, m))
		testing.expect(t, m.textures[0].ordinary != nil)
		testing.expect(t, m.textures[0].image != m.textures[0].ordinary.image)
		mesh_table_remove(&table, slot)
	}
}

@(test)
test_mesh_reload_acquires_changed_content_while_previous_mesh_stays_live :: proc(t: ^testing.T) {
	table: Mesh_Table; mesh_table_init(&table, 8, context.allocator, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&table.texture_cache, &f)
	defer texture_fake_destroy(&f)
	defer mesh_table_destroy(&table)
	first_data := Mesh_Data{textures = make([]Texture, 1)}
	first_data.textures[0] = texture_test_data()
	first, _ := mesh_table_add(&table, strings.clone("old"), first_data)
	testing.expect(t, mesh_textures_upload(&table, &table.meshes[first]))
	old_id := mesh_id(&table, first)
	second_data := Mesh_Data{textures = make([]Texture, 1)}
	second_data.textures[0] = texture_test_data(value = 34)
	second, _ := mesh_table_add(&table, strings.clone("changed"), second_data)
	testing.expect(t, mesh_textures_upload(&table, &table.meshes[second]))
	testing.expect(t, table.meshes[first].textures[0].image != table.meshes[second].textures[0].image)
	mesh_table_remove(&table, first)
	testing.expect(t, f.live_images[table.meshes[second].textures[0].image.id])
	reload_data := Mesh_Data{textures = make([]Texture, 1)}
	reload_data.textures[0] = texture_test_data(value = 34)
	reused, _ := mesh_table_add(&table, strings.clone("reload"), reload_data)
	testing.expect_value(t, reused, first)
	testing.expect(t, mesh_textures_upload(&table, &table.meshes[reused]))
	testing.expect_value(t, table.meshes[reused].textures[0].image, table.meshes[second].textures[0].image)
	_, stale := mesh_lookup(&table, old_id); testing.expect(t, !stale)
	mesh_table_remove(&table, second)
	mesh_table_remove(&table, reused)
	testing.expect_value(t, len(table.texture_cache.entries), 0)
}

@(test)
test_headless_mesh_shutdown_needs_no_gpu_and_releases_prepared_data :: proc(t: ^testing.T) {
	table: Mesh_Table; mesh_table_init(&table, 8, context.allocator, context.allocator)
	f: Texture_Fake_GPU; texture_fake_init(&table.texture_cache, &f)
	defer texture_fake_destroy(&f)
	data := Mesh_Data{textures = make([]Texture, 1)}
	data.textures[0] = texture_test_data(0.5)
	_, added := mesh_table_add(&table, strings.clone("headless"), data)
	testing.expect(t, added)
	testing.expect_value(t, f.images_created, 0)
	mesh_table_destroy(&table)
	testing.expect_value(t, f.samplers_destroyed, 0)
}
