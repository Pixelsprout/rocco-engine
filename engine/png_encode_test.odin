#+test
package engine

import "core:testing"

// scripts/test_png_encode.py decodes this file with Python's zlib and checks
// the same pixels, so the Odin writer and an outside reader agree. If the
// writer's output changes on purpose, write the file again from png_encode.
PNG_FIXTURE :: #load("testdata/png_encode_4x3.png")
PNG_FIXTURE_WIDTH :: 4
PNG_FIXTURE_HEIGHT :: 3

// Keep in step with pixel() in scripts/test_png_encode.py.
png_fixture_pixels :: proc(width, height: int) -> []byte {
	rgba := make([]byte, width * height * 4, context.temp_allocator)
	for y in 0 ..< height {
		for x in 0 ..< width {
			px := rgba[(y * width + x) * 4:][:4]
			px[0] = byte(x * 64)
			px[1] = byte(y * 100)
			px[2] = byte(200 - x * 30 - y * 10)
			px[3] = byte(255 - x * 20 - y * 5)
		}
	}
	return rgba
}

@(test)
test_png_encode_writes_the_fixture :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	got := png_encode(PNG_FIXTURE_WIDTH, PNG_FIXTURE_HEIGHT, png_fixture_pixels(PNG_FIXTURE_WIDTH, PNG_FIXTURE_HEIGHT), allocator = context.temp_allocator)
	testing.expect_value(t, len(got), len(PNG_FIXTURE))
	testing.expect(t, string(got) == string(PNG_FIXTURE), "png_encode no longer writes testdata/png_encode_4x3.png")
}

// More than 65535 bytes of rows need a second stored block.
@(test)
test_png_encode_round_trips_rows_that_span_two_stored_blocks :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	width, height := 200, 82
	want := png_fixture_pixels(width, height)
	testing.expect(t, (width * 4 + 1) * height > PNG_STORED_BLOCK)

	got_width, got_height, got, ok := png_decode(png_encode(width, height, want, allocator = context.temp_allocator))

	testing.expect(t, ok)
	testing.expect_value(t, got_width, width)
	testing.expect_value(t, got_height, height)
	testing.expect(t, string(got) == string(want), "the decoded pixels differ")
}
