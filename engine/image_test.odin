#+test
package engine

import "core:encoding/endian"
import "core:hash"
import "core:testing"

PNG_GRAY :: 0
PNG_RGB :: 2
PNG_RGBA :: 6

// A PNG whose one IDAT holds the rows uncompressed, in stored deflate blocks.
// A 16-bit pixel takes two big-endian bytes per channel.
png_make :: proc(width, height, color_type: int, pixels: []byte, depth := 8) -> []byte {
	channels := 1 if color_type == PNG_GRAY else (3 if color_type == PNG_RGB else 4)
	row := width * channels * depth / 8
	raw := make([dynamic]byte, context.temp_allocator)
	for y in 0 ..< height {
		append(&raw, 0)
		append(&raw, ..pixels[y * row:][:row])
	}

	zlib := make([dynamic]byte, context.temp_allocator)
	append(&zlib, 0x78, 0x01)
	rest := raw[:]
	for {
		n := min(len(rest), 65_535)
		final := byte(1) if n == len(rest) else 0
		append(&zlib, final, byte(n), byte(n >> 8), byte(~n), byte(~n >> 8))
		append(&zlib, ..rest[:n])
		rest = rest[n:]
		if final == 1 {
			break
		}
	}
	be_put(&zlib, hash.adler32(raw[:]))

	ihdr := make([dynamic]byte, context.temp_allocator)
	be_put(&ihdr, u32(width))
	be_put(&ihdr, u32(height))
	append(&ihdr, byte(depth), byte(color_type), 0, 0, 0)

	out := make([dynamic]byte, context.temp_allocator)
	append(&out, 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n')
	png_chunk(&out, "IHDR", ihdr[:])
	png_chunk(&out, "IDAT", zlib[:])
	png_chunk(&out, "IEND", nil)
	return out[:]
}

png_chunk :: proc(out: ^[dynamic]byte, kind: string, data: []byte) {
	be_put(out, u32(len(data)))
	start := len(out)
	append(out, kind)
	append(out, ..data)
	be_put(out, hash.crc32(out[start:]))
}

be_put :: proc(out: ^[dynamic]byte, v: u32) {
	b: [4]byte
	endian.put_u32(b[:], .Big, v)
	append(out, ..b[:])
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
