package engine

import sg "../sokol-odin/sokol/gfx"
import "core:crypto/sha2"
import "core:mem"
import "system"

// Every cache image is immutable 2D, one slice, one sample, with no storage or attachment flags.
Texture_Image_Key :: struct {
	digest: [32]byte,
	dimensions: [16][2]int,
	mip_count: int,
	format: sg.Pixel_Format,
	image_type: sg.Image_Type,
	usage: sg.Image_Usage,
	num_slices, sample_count: i32,
	cutoff_bits: u32,
}

Texture_Image :: struct {
	key: Texture_Image_Key,
	image: sg.Image,
	view: sg.View,
	refs: int,
	payload_bytes: u64,
}

Texture_GPU :: struct {
	ctx: rawptr,
	create_image: proc(rawptr, sg.Image_Desc) -> (sg.Image, sg.View, bool),
	destroy_image: proc(rawptr, sg.Image, sg.View),
	create_sampler: proc(rawptr, Texture_Sampler) -> (sg.Sampler, bool),
	destroy_sampler: proc(rawptr, sg.Sampler),
}

Texture_Cache :: struct {
	entries: map[Texture_Image_Key]^Texture_Image,
	gpu: Texture_GPU,
	allocator: mem.Allocator,
	hits, references: u64,
	unique_payload_bytes, referenced_payload_bytes: u64,
}

texture_cache_init :: proc(c: ^Texture_Cache, allocator: mem.Allocator) {
	c.allocator = allocator
	c.gpu = {create_image = texture_gpu_create_image, destroy_image = texture_gpu_destroy_image, create_sampler = texture_gpu_create_sampler, destroy_sampler = texture_gpu_destroy_sampler}
}

// SHA-256 collisions are assumed infeasible. Map collisions still compare the complete key.
texture_image_key :: proc(tex: Texture) -> (key: Texture_Image_Key, payload: u64, ok: bool) {
	if len(tex.levels) == 0 || len(tex.levels) > len(key.dimensions) { return }
	key.mip_count = len(tex.levels)
	desc := texture_image_desc(tex)
	key.format = desc.pixel_format
	key.image_type = desc.type
	key.usage = desc.usage
	key.num_slices, key.sample_count = desc.num_slices, desc.sample_count
	key.cutoff_bits = transmute(u32)tex.alpha_cutoff
	hash: sha2.Context_256
	sha2.init_256(&hash)
	for level, i in tex.levels {
		if level.width <= 0 || level.height <= 0 || level.width > IMAGE_MAX_SIDE || level.height > IMAGE_MAX_SIDE || len(level.pixels) != level.width * level.height * 4 { return {}, 0, false }
		key.dimensions[i] = {level.width, level.height}
		sha2.update(&hash, level.pixels)
		payload += u64(len(level.pixels))
	}
	sha2.final(&hash, key.digest[:])
	return key, payload, true
}

texture_cache_acquire :: proc(c: ^Texture_Cache, tex: Texture) -> (result: Mesh_Texture, ok: bool) {
	key, payload, valid := texture_image_key(tex)
	if !valid { return }
	sampler, sampler_ok := c.gpu.create_sampler(c.gpu.ctx, tex.sampler)
	if !sampler_ok { return }
	entry, found := c.entries[key]
	if !found {
		image, view, image_ok := c.gpu.create_image(c.gpu.ctx, texture_image_desc(tex))
		if !image_ok { c.gpu.destroy_sampler(c.gpu.ctx, sampler); return }
		entry = new(Texture_Image, c.allocator)
		entry^ = {key = key, image = image, view = view, payload_bytes = payload}
		if c.entries == nil { c.entries = make(map[Texture_Image_Key]^Texture_Image, c.allocator) }
		c.entries[key] = entry
		c.unique_payload_bytes += payload
	} else { c.hits += 1 }
	entry.refs += 1
	c.references += 1
	c.referenced_payload_bytes += payload
	return {image = entry.image, view = entry.view, sampler = sampler, shared = entry}, true
}

// Parts borrow Mesh_Texture values. Only the owning mesh slot releases its reference.
texture_cache_release :: proc(c: ^Texture_Cache, tex: Mesh_Texture) {
	entry := tex.shared
	if entry == nil { return }
	c.gpu.destroy_sampler(c.gpu.ctx, tex.sampler)
	entry.refs -= 1
	c.references -= 1
	c.referenced_payload_bytes -= entry.payload_bytes
	if entry.refs == 0 {
		delete_key(&c.entries, entry.key)
		c.unique_payload_bytes -= entry.payload_bytes
		c.gpu.destroy_image(c.gpu.ctx, entry.image, entry.view)
		free(entry, c.allocator)
	}
}

texture_cache_destroy :: proc(c: ^Texture_Cache) {
	assert(len(c.entries) == 0 && c.references == 0)
	delete(c.entries)
	c.entries = nil
}

texture_gpu_create_image :: proc(_: rawptr, desc: sg.Image_Desc) -> (image: sg.Image, view: sg.View, ok: bool) {
	image = sg.make_image(desc)
	if sg.query_image_state(image) != .VALID {
		if image.id != 0 { sg.destroy_image(image) }
		return {}, {}, false
	}
	view = sg.make_view({texture = {image = image}})
	if sg.query_view_state(view) != .VALID {
		if view.id != 0 { sg.destroy_view(view) }
		sg.destroy_image(image)
		return {}, {}, false
	}
	return image, view, true
}

texture_gpu_destroy_image :: proc(_: rawptr, image: sg.Image, view: sg.View) {
	sg.destroy_view(view)
	sg.destroy_image(image)
}

texture_gpu_create_sampler :: proc(_: rawptr, s: Texture_Sampler) -> (sampler: sg.Sampler, ok: bool) {
	sampler = sg.make_sampler({min_filter = s.min_filter, mag_filter = s.mag_filter, mipmap_filter = s.mipmap_filter, wrap_u = s.wrap_u, wrap_v = s.wrap_v, label = "mesh-sampler"})
	if sg.query_sampler_state(sampler) != .VALID {
		if sampler.id != 0 { sg.destroy_sampler(sampler) }
		return {}, false
	}
	return sampler, true
}

texture_gpu_destroy_sampler :: proc(_: rawptr, sampler: sg.Sampler) { sg.destroy_sampler(sampler) }

texture_cache_report :: proc(c: ^Texture_Cache) {
	if value, _ := system.lookup_env("ROCCO_TEXTURE_CACHE_REPORT", context.temp_allocator); value != "1" { return }
	ordinary, cutoff: int
	for key in c.entries { if key.cutoff_bits == 0 { ordinary += 1 } else { cutoff += 1 } }
	system.eprintfln("texture_cache live_images=%v references=%v hits=%v unique_payload_bytes=%v referenced_payload_bytes=%v native_allocated_bytes=%v ordinary_images=%v cutoff_images=%v", len(c.entries), c.references, c.hits, c.unique_payload_bytes, c.referenced_payload_bytes, texture_cache_native_bytes(c), ordinary, cutoff)
}
