package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// The reserved slot and one sky.
SKY_CAPACITY_MIN :: 2
SKY_PREFIX :: "sky/"

// The file stems of a sky's faces, in the order sokol takes cubemap faces.
// Face px holds the directions nearest +x. Its image's top row is towards +y
// and its left column towards +z; each face follows the same cubemap layout.
SKY_FACES :: [6]string{"px", "nx", "py", "ny", "pz", "nz"}

// The pixels are scratch until the upload: six square faces of side texels,
// RGBA8 sRGB, in SKY_FACES order.
Sky :: struct {
	name:       string,
	side:       int,
	pixels:     []byte,
	live:       bool,
	texture:    Mesh_Texture,
	generation: u16,
}

// Slot 0 is no sky and is never filled. After sky_table_upload, a new sky
// uploads when it is added. The table owns each sky's name and pixels. The
// slots never grow.
Sky_Table :: struct {
	skies:      []Sky,
	count:      int,
	free:       []int,
	free_count: int,
	logged:     map[u32]struct {},
	uploaded:   bool,
	allocator:  mem.Allocator,
	perm:       mem.Allocator,
}

// The slots come from perm; the names, pixels and log from allocator, which
// must free.
sky_table_init :: proc(t: ^Sky_Table, capacity: int, perm, allocator: mem.Allocator) {
	fmt.assertf(capacity >= SKY_CAPACITY_MIN && capacity <= SLOT_LIMIT, "a sky table of %v slots cannot hold a sky or give each slot an id", capacity)
	t.allocator = allocator
	t.perm = perm
	t.skies = make([]Sky, capacity, perm)
	t.free = make([]int, capacity, perm)
	t.logged = make(map[u32]struct {}, allocator)
	t.count = 1
}

// sg.shutdown destroys the images.
sky_table_destroy :: proc(t: ^Sky_Table) {
	for &sky in t.skies[1:t.count] {
		if sky.live {
			delete(sky.name, t.allocator)
			delete(sky.pixels, t.allocator)
		}
	}
	delete(t.logged)
	delete(t.skies, t.perm)
	delete(t.free, t.perm)
}

// A sky id packs the slot and generation as a mesh id does.
sky_id :: proc(t: ^Sky_Table, slot: int) -> u32 {
	return u32(t.skies[slot].generation) << MESH_SLOT_BITS | u32(slot)
}

sky_slot :: proc(id: u32) -> int {
	return mesh_slot(id)
}

sky_table_full :: proc(t: ^Sky_Table) -> bool {
	return t.free_count == 0 && t.count == len(t.skies)
}

// Slot 0 holds no sky, so the table holds one sky fewer than its slots.
sky_table_full_reason :: proc(t: ^Sky_Table) -> string {
	return fmt.tprintf("the sky table is full at %v skies", len(t.skies) - 1)
}

sky_table_find :: proc(t: ^Sky_Table, name: string) -> (id: u32, found: bool) {
	for sky, slot in t.skies[1:t.count] {
		if sky.live && sky.name == name {
			return sky_id(t, slot + 1), true
		}
	}
	return 0, false
}

// Keeps the slot's generation, so a sky in a reused slot gets a new id.
// name and pixels must come from t.allocator.
sky_table_add :: proc(t: ^Sky_Table, name: string, side: int, pixels: []byte) -> (slot: int, ok: bool) {
	if sky_table_full(t) {
		return 0, false
	}
	if t.free_count > 0 {
		t.free_count -= 1
		slot = t.free[t.free_count]
	} else {
		slot = t.count
		t.count += 1
	}
	t.skies[slot] = {name = name, side = side, pixels = pixels, live = true, generation = t.skies[slot].generation}
	if t.uploaded {
		sky_upload(t, &t.skies[slot])
	}
	return slot, true
}

// Empties the slot and adds 1 to its generation, so an id kept from it draws no sky.
sky_table_remove :: proc(t: ^Sky_Table, slot: int) {
	fmt.assertf(slot >= 1 && slot < t.count && t.skies[slot].live, "sky slot %v holds no sky", slot)
	sky := &t.skies[slot]
	if sky.texture.image.id != 0 {
		sg.destroy_view(sky.texture.view)
		sg.destroy_image(sky.texture.image)
		sg.destroy_sampler(sky.texture.sampler)
	}
	delete(sky.name, t.allocator)
	delete(sky.pixels, t.allocator)
	sky^ = {generation = sky.generation + 1}
	t.free[t.free_count] = slot
	t.free_count += 1
}

// Needs sokol set up.
sky_table_upload :: proc(t: ^Sky_Table) {
	for &sky in t.skies[1:t.count] {
		if sky.live {
			sky_upload(t, &sky)
		}
	}
	t.uploaded = true
}

// Id 0 is no sky and is not logged. A stale or unknown id draws no sky and
// is logged once per run.
sky_resolve :: proc(t: ^Sky_Table, id: u32) -> (sky: ^Sky, ok: bool) {
	if id == 0 {
		return nil, false
	}
	slot := sky_slot(id)
	if slot < t.count && t.skies[slot].live && sky_id(t, slot) == id {
		return &t.skies[slot], true
	}
	if id not_in t.logged {
		t.logged[id] = {}
		stale := slot >= 1 && slot < len(t.skies) && id >> MESH_SLOT_BITS != u32(t.skies[slot].generation)
		if stale {
			fmt.eprintfln("sky id %v is from an unloaded pack; drawing no sky", id)
		} else {
			fmt.eprintfln("sky id %v is not in the table; drawing no sky", id)
		}
	}
	return nil, false
}

// sky/<dir> for each directory in dir, sorted. A directory with a missing
// face is listed, and fails when a Load asks for it.
sky_names_on_disk :: proc(dir: string, allocator: mem.Allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		if err != .Not_Exist {
			fmt.eprintfln("cannot read %v: %v; no sky can load from it", dir, os.error_string(err))
		}
		return nil
	}

	names := make([dynamic]string, 0, len(entries), allocator)
	for e in entries {
		if e.type == .Directory {
			append(&names, strings.concatenate({SKY_PREFIX, e.name}, allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// Loads the six faces of dir/<name without sky/> into the next free slot.
// On failure the table does not change and reason says why.
sky_load_dir :: proc(t: ^Sky_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
	if sky_table_full(t) {
		return 0, sky_table_full_reason(t), false
	}
	stem := strings.trim_prefix(name, SKY_PREFIX)
	side := 0
	faces: [len(SKY_FACES)][]byte
	for face, i in SKY_FACES {
		path := fmt.tprintf("%v/%v/%v.png", dir, stem, face)
		bytes, read_err := os.read_entire_file(path, context.temp_allocator)
		if read_err != nil {
			return 0, fmt.tprintf("%v: %v", path, os.error_string(read_err)), false
		}
		width, height, rgba, decoded := png_decode(bytes)
		if !decoded {
			return 0, fmt.tprintf("%v is not a PNG it can read", path), false
		}
		if width != height {
			return 0, fmt.tprintf("%v is %v x %v, not square", path, width, height), false
		}
		if i > 0 && width != side {
			return 0, fmt.tprintf("%v is %v texels wide, but %v.png is %v", path, width, SKY_FACES[0], side), false
		}
		side = width
		faces[i] = rgba
	}

	face_size := side * side * 4
	pixels := make([]byte, len(SKY_FACES) * face_size, t.allocator)
	for face, i in faces {
		copy(pixels[i * face_size:], face)
	}
	slot, _ := sky_table_add(t, strings.clone(name, t.allocator), side, pixels)
	return sky_id(t, slot), "", true
}

// The pixels are scratch once the GPU has them. A sky has no mipmaps.
@(private = "file")
sky_upload :: proc(t: ^Sky_Table, sky: ^Sky) {
	image := sg.make_image(
		{
			type = .CUBE,
			width = i32(sky.side),
			height = i32(sky.side),
			num_slices = len(SKY_FACES),
			num_mipmaps = 1,
			pixel_format = .SRGB8A8,
			data = {mip_levels = {0 = {ptr = raw_data(sky.pixels), size = uint(len(sky.pixels))}}},
			label = "sky",
		},
	)
	sky.texture = {
		image   = image,
		view    = sg.make_view({texture = {image = image}}),
		sampler = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, wrap_w = .CLAMP_TO_EDGE, label = "sky"}),
	}
	delete(sky.pixels, t.allocator)
	sky.pixels = nil
}
