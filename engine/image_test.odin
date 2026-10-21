#+test
package engine

import "core:testing"

// Writes the test image in frame memory.
png_make :: proc(width, height, color_type: int, pixels: []byte, depth := 8) -> []byte {
	return png_encode(width, height, pixels, color_type, depth, context.temp_allocator)
}

@(test)
test_png_decode_gives_rgba8_with_opaque_alpha_for_rgb :: proc(t: ^testing.T) {
	width, height, rgba, ok := png_decode(png_make(2, 1, PNG_RGB, {10, 20, 30, 40, 50, 60}))
	testing.expect(t, ok)
	testing.expect_value(t, width, 2)
	testing.expect_value(t, height, 1)
	testing.expect_value(t, len(rgba), 8)
	want := [8]byte{10, 20, 30, 255, 40, 50, 60, 255}
	for b, i in rgba {
		testing.expect_value(t, b, want[i])
	}
}

@(test)
test_png_decode_spreads_gray_over_rgb :: proc(t: ^testing.T) {
	_, _, rgba, ok := png_decode(png_make(1, 1, PNG_GRAY, {77}))
	testing.expect(t, ok)
	testing.expect_value(t, len(rgba), 4)
	want := [4]byte{77, 77, 77, 255}
	for b, i in rgba {
		testing.expect_value(t, b, want[i])
	}
}

@(test)
test_png_decode_keeps_the_high_byte_of_a_16_bit_channel :: proc(t: ^testing.T) {
	_, _, rgba, ok := png_decode(png_make(1, 1, PNG_RGB, {0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc}, depth = 16))
	testing.expect(t, ok)
	want := [4]byte{0x12, 0x56, 0x9a, 255}
	for b, i in rgba {
		testing.expect_value(t, b, want[i])
	}
}

@(test)
test_png_decode_rejects_bytes_that_are_not_a_png :: proc(t: ^testing.T) {
	_, _, _, ok := png_decode(transmute([]byte)string("not a png"))
	testing.expect(t, !ok)
}

@(test)
test_texture_build_without_mipmaps_keeps_one_level :: proc(t: ^testing.T) {
	rgba := make([]byte, 4 * 4 * 4, context.temp_allocator)
	tex := texture_build(4, 4, rgba, {mipmaps = false}, srgb = true, allocator = context.temp_allocator)
	testing.expect_value(t, len(tex.levels), 1)
	testing.expect_value(t, tex.levels[0].width, 4)
	testing.expect_value(t, tex.levels[0].height, 4)
}

@(test)
test_texture_build_halves_each_mipmap_down_to_1_by_1 :: proc(t: ^testing.T) {
	rgba := make([]byte, 5 * 3 * 4, context.temp_allocator)
	tex := texture_build(5, 3, rgba, {mipmaps = true}, srgb = true, allocator = context.temp_allocator)
	want := [][2]int{{5, 3}, {2, 1}, {1, 1}}
	testing.expect_value(t, len(tex.levels), len(want))
	for level, i in tex.levels {
		testing.expect_value(t, [2]int{level.width, level.height}, want[i])
		testing.expect_value(t, len(level.pixels), level.width * level.height * 4)
	}
}

// Half black and half white averages to linear 0.5, which is sRGB 188, not 128.
// Alpha is linear already, so it averages as it is.
@(test)
test_texture_build_averages_mipmaps_in_linear_light :: proc(t: ^testing.T) {
	rgba := []byte{0, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0}
	tex := texture_build(2, 2, rgba, {mipmaps = true}, srgb = true, allocator = context.temp_allocator)
	testing.expect_value(t, len(tex.levels), 2)
	top := tex.levels[1].pixels
	want := [4]byte{188, 188, 188, 128}
	for b, i in top {
		testing.expect_value(t, b, want[i])
	}
}

@(test)
test_texture_build_keeps_level_0_as_given :: proc(t: ^testing.T) {
	rgba := []byte{1, 2, 3, 4, 5, 6, 7, 8}
	tex := texture_build(2, 1, rgba, {mipmaps = true}, srgb = true, allocator = context.temp_allocator)
	for b, i in tex.levels[0].pixels {
		testing.expect_value(t, b, rgba[i])
	}
}

@(test)
test_texture_build_averages_a_linear_texture_as_stored :: proc(t: ^testing.T) {
	rgba := []byte{0, 0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0}
	tex := texture_build(2, 2, rgba, {mipmaps = true}, srgb = false, allocator = context.temp_allocator)
	testing.expect(t, !tex.srgb)
	top := tex.levels[1].pixels
	want := [4]byte{128, 128, 128, 128}
	for b, i in top {
		testing.expect_value(t, b, want[i])
	}
}
