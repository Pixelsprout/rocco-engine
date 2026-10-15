package font_bake

import "core:testing"

@(test)
test_pack_starts_a_new_shelf_when_the_row_is_full :: proc(t: ^testing.T) {
	sizes := [][2]int{{6, 4}, {6, 7}, {5, 3}}
	rects := make([][4]int, len(sizes))
	defer delete(rects)
	height := pack_shelves(sizes, 14, rects)
	testing.expect_value(t, rects[0], [4]int{0, 0, 6, 4})
	testing.expect_value(t, rects[1], [4]int{7, 0, 6, 7})
	testing.expect_value(t, rects[2], [4]int{0, 8, 5, 3})
	testing.expect_value(t, height, 11)
}

@(test)
test_pack_gives_an_empty_glyph_an_empty_rect :: proc(t: ^testing.T) {
	sizes := [][2]int{{0, 0}, {3, 3}}
	rects := make([][4]int, len(sizes))
	defer delete(rects)
	height := pack_shelves(sizes, 8, rects)
	testing.expect_value(t, rects[0], [4]int{0, 0, 0, 0})
	testing.expect_value(t, rects[1], [4]int{0, 0, 3, 3})
	testing.expect_value(t, height, 3)
}
