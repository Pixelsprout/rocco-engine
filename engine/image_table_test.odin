#+test
package engine

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// Slot 0 and two Images.
SMALL_IMAGES :: 3

@(test)
test_image_table_holds_its_capacity_and_refuses_the_next_image :: proc(t: ^testing.T) {
	table: Image_Table
	image_table_init(&table, SMALL_IMAGES, context.allocator, context.allocator)
	defer image_table_destroy(&table)

	for name in ([]string{"image/a", "image/b"}) {
		_, ok := image_table_add(&table, strings.clone(name), 1, 1, nil)
		testing.expectf(t, ok, "expected %v to fit", name)
	}
	testing.expect(t, image_table_full(&table))
	_, ok := image_table_add(&table, "image/c", 1, 1, nil)
	testing.expect(t, !ok)
	_, reason, loaded := image_load_file(&table, NO_ASSETS_DIR, "image/c")
	testing.expect(t, !loaded)
	testing.expect_value(t, reason, "the Image table is full at 2 Images")

	old := image_id(&table, SMALL_IMAGES - 1)
	image_table_remove(&table, SMALL_IMAGES - 1)
	_, found := image_lookup(&table, old)
	testing.expect(t, !found)
	slot, refilled := image_table_add(&table, strings.clone("image/d"), 1, 1, nil)
	testing.expect(t, refilled)
	testing.expect_value(t, slot, SMALL_IMAGES - 1)
	testing.expect(t, image_id(&table, slot) != old)
}

@(test)
test_image_lookup_finds_nothing_for_id_0_or_an_id_past_the_table :: proc(t: ^testing.T) {
	table: Image_Table
	image_table_init(&table, SMALL_IMAGES, context.allocator, context.allocator)
	defer image_table_destroy(&table)

	_, zero := image_lookup(&table, 0)
	testing.expect(t, !zero)
	_, past := image_lookup(&table, SMALL_IMAGES)
	testing.expect(t, !past)
}

@(test)
test_image_names_on_disk_are_each_png_stem_with_the_image_prefix_in_sorted_order :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["b.png"] = png_make(1, 1, PNG_RGBA, {0, 0, 0, 255})
	files["a.png"] = png_make(1, 1, PNG_RGBA, {0, 0, 0, 255})
	files["notes.txt"] = transmute([]byte)string("not an image")
	files["sub/c.png"] = png_make(1, 1, PNG_RGBA, {0, 0, 0, 255})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)

	names := image_names_on_disk(dir, context.temp_allocator)
	testing.expect(t, slice.equal(names, []string{"image/a", "image/b"}))
}

@(test)
test_image_load_file_keeps_the_size_and_bleeds_the_pixels :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["edge.png"] = png_make(2, 1, PNG_RGBA, {0, 0, 0, 0, 90, 60, 30, 255})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	table: Image_Table
	image_table_init(&table, SMALL_IMAGES, context.allocator, context.allocator)
	defer image_table_destroy(&table)

	id, reason, ok := image_load_file(&table, dir, "image/edge")
	testing.expectf(t, ok, "expected image/edge to load: %v", reason)
	image, found := image_lookup(&table, id)
	testing.expect(t, found)
	testing.expect_value(t, image.width, 2)
	testing.expect_value(t, image.height, 1)
	testing.expect(t, slice.equal(image.pixels, []byte{90, 60, 30, 0, 90, 60, 30, 255}))
}
