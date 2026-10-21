#+test
package engine

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_screenshot_write_saves_an_opaque_png :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "rocco-screenshot-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	path := strings.concatenate({dir, "/out.png"}, context.temp_allocator)
	rgba := []byte{10, 20, 30, 0, 40, 50, 60, 128}

	testing.expect_value(t, screenshot_write(path, {2, 1}, rgba), "")

	data, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, read_err, nil)
	width, height, got, ok := png_decode(data)
	testing.expect(t, ok)
	testing.expect_value(t, width, 2)
	testing.expect_value(t, height, 1)
	want := [8]byte{10, 20, 30, 255, 40, 50, 60, 255}
	testing.expect(t, string(got) == string(want[:]), "the pixels differ")
}

@(test)
test_screenshot_write_to_a_missing_folder_returns_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	dir, err := os.make_directory_temp("", "rocco-screenshot-*", context.temp_allocator)
	testing.expect_value(t, err, nil)
	defer os.remove_all(dir)
	path := strings.concatenate({dir, "/missing/out.png"}, context.temp_allocator)

	error := screenshot_write(path, {1, 1}, []byte{1, 2, 3, 4})

	testing.expectf(t, strings.has_prefix(error, "the host cannot write "), "got %q", error)
	testing.expect(t, strings.contains(error, "missing/out.png"))
}

@(test)
test_screenshot_logical_size_divides_by_the_dpi :: proc(t: ^testing.T) {
	testing.expect_value(t, screenshot_logical_size({1920, 1080}, 2), [2]i32{960, 540})
	testing.expect_value(t, screenshot_logical_size({960, 540}, 1), [2]i32{960, 540})
	testing.expect_value(t, screenshot_logical_size({1441, 901}, 1.5), [2]i32{961, 601})
	testing.expect_value(t, screenshot_logical_size({800, 600}, 0), [2]i32{800, 600})
}

@(test)
test_rows_flip_reverses_the_rows :: proc(t: ^testing.T) {
	pixels := [6]byte{1, 2, 3, 4, 5, 6}
	rows_flip(pixels[:], 2)
	testing.expect_value(t, pixels, [6]byte{5, 6, 3, 4, 1, 2})
}
