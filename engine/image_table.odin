package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// The reserved slot and one Image.
IMAGE_CAPACITY_MIN :: 2
IMAGE_PREFIX :: "image/"

// The pixels are scratch until the upload: RGBA8 sRGB, top row first, with
// the edge colours bled into each fully transparent pixel. The size stays
// after the upload, for the Manifest.
Image :: struct {
	name:       string,
	width:      int,
	height:     int,
	pixels:     []byte,
	live:       bool,
	image:      sg.Image,
	view:       sg.View,
	generation: u16,
}

// Slot 0 is no Image and is never filled. After image_table_upload, a new
// Image uploads when it is added. Every Image shares the two samplers, so an
// Image takes one image and one view from the sokol pools. The table owns
// each Image's name and pixels. The slots never grow.
Image_Table :: struct {
	images:     []Image,
	count:      int,
	free:       []int,
	free_count: int,
	uploaded:   bool,
	linear:     sg.Sampler,
	nearest:    sg.Sampler,
	allocator:  mem.Allocator,
	perm:       mem.Allocator,
}

// The slots come from perm; the names and pixels from allocator, which must
// free.
image_table_init :: proc(t: ^Image_Table, capacity: int, perm, allocator: mem.Allocator) {
	fmt.assertf(capacity >= IMAGE_CAPACITY_MIN && capacity <= SLOT_LIMIT, "an Image table of %v slots cannot hold an Image or give each slot an id", capacity)
	t.allocator = allocator
	t.perm = perm
	t.images = make([]Image, capacity, perm)
	t.free = make([]int, capacity, perm)
	t.count = 1
}

// sg.shutdown destroys the images, views and samplers.
image_table_destroy :: proc(t: ^Image_Table) {
	for &image in t.images[1:t.count] {
		if image.live {
			delete(image.name, t.allocator)
			delete(image.pixels, t.allocator)
		}
	}
	delete(t.images, t.perm)
	delete(t.free, t.perm)
}

// An Image id packs the slot and generation as a mesh id does.
image_id :: proc(t: ^Image_Table, slot: int) -> u32 {
	return u32(t.images[slot].generation) << MESH_SLOT_BITS | u32(slot)
}

image_slot :: proc(id: u32) -> int {
	return mesh_slot(id)
}

image_table_full :: proc(t: ^Image_Table) -> bool {
	return t.free_count == 0 && t.count == len(t.images)
}

// Slot 0 holds no Image, so the table holds one Image fewer than its slots.
image_table_full_reason :: proc(t: ^Image_Table) -> string {
	return fmt.tprintf("the Image table is full at %v Images", len(t.images) - 1)
}

image_table_find :: proc(t: ^Image_Table, name: string) -> (id: u32, found: bool) {
	for image, slot in t.images[1:t.count] {
		if image.live && image.name == name {
			return image_id(t, slot + 1), true
		}
	}
	return 0, false
}

// Keeps the slot's generation, so an Image in a reused slot gets a new id.
// name and pixels must come from t.allocator.
image_table_add :: proc(t: ^Image_Table, name: string, width, height: int, pixels: []byte) -> (slot: int, ok: bool) {
	if image_table_full(t) {
		return 0, false
	}
	if t.free_count > 0 {
		t.free_count -= 1
		slot = t.free[t.free_count]
	} else {
		slot = t.count
		t.count += 1
	}
	t.images[slot] = {name = name, width = width, height = height, pixels = pixels, live = true, generation = t.images[slot].generation}
	if t.uploaded {
		image_upload(t, &t.images[slot])
	}
	return slot, true
}

// Empties the slot and adds 1 to its generation, so an id kept from it no
// longer finds an Image. The shared samplers stay.
image_table_remove :: proc(t: ^Image_Table, slot: int) {
	fmt.assertf(slot >= 1 && slot < t.count && t.images[slot].live, "Image slot %v holds no Image", slot)
	image := &t.images[slot]
	if image.image.id != 0 {
		sg.destroy_view(image.view)
		sg.destroy_image(image.image)
	}
	delete(image.name, t.allocator)
	delete(image.pixels, t.allocator)
	image^ = {generation = image.generation + 1}
	t.free[t.free_count] = slot
	t.free_count += 1
}

// Needs sokol set up. Makes the two samplers, then uploads each Image.
image_table_upload :: proc(t: ^Image_Table) {
	t.linear = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "image-linear"})
	t.nearest = sg.make_sampler({min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "image-nearest"})
	for &image in t.images[1:t.count] {
		if image.live {
			image_upload(t, &image)
		}
	}
	t.uploaded = true
}

// Id 0 and an id that is stale or past the table find nothing, and log
// nothing.
image_lookup :: proc(t: ^Image_Table, id: u32) -> (image: ^Image, ok: bool) {
	slot := image_slot(id)
	if id != 0 && slot < t.count && t.images[slot].live && image_id(t, slot) == id {
		return &t.images[slot], true
	}
	return nil, false
}

// image/<stem> for each .png file in dir, sorted.
image_names_on_disk :: proc(dir: string, allocator: mem.Allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		if err != .Not_Exist {
			fmt.eprintfln("cannot read %v: %v; no Image can load from it", dir, os.error_string(err))
		}
		return nil
	}

	names := make([dynamic]string, 0, len(entries), allocator)
	for e in entries {
		if e.type != .Directory && os.ext(e.name) == ".png" && os.stem(e.name) != "" {
			append(&names, strings.concatenate({IMAGE_PREFIX, os.stem(e.name)}, allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// Loads dir/<name without image/>.png into the next free slot. On failure
// the table does not change and reason says why.
image_load_file :: proc(t: ^Image_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
	if image_table_full(t) {
		return 0, image_table_full_reason(t), false
	}
	path := fmt.tprintf("%v/%v.png", dir, strings.trim_prefix(name, IMAGE_PREFIX))
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return 0, fmt.tprintf("%v: %v", path, os.error_string(read_err)), false
	}
	width, height, rgba, decoded := png_decode(bytes)
	if !decoded {
		return 0, fmt.tprintf("%v is not a PNG it can read", path), false
	}
	image_bleed(width, height, rgba)
	slot, _ := image_table_add(t, strings.clone(name, t.allocator), width, height, slice.clone(rgba, t.allocator))
	return image_id(t, slot), "", true
}

// The pixels are scratch once the GPU has them. An Image has one level.
@(private = "file")
image_upload :: proc(t: ^Image_Table, image: ^Image) {
	image.image = sg.make_image(
		{
			width = i32(image.width),
			height = i32(image.height),
			num_mipmaps = 1,
			pixel_format = .SRGB8A8,
			data = {mip_levels = {0 = {ptr = raw_data(image.pixels), size = uint(len(image.pixels))}}},
			label = "image",
		},
	)
	image.view = sg.make_view({texture = {image = image.image}})
	delete(image.pixels, t.allocator)
	image.pixels = nil
}
