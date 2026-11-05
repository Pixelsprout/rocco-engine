#+build windows
#+test
package engine

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_shader_reader_permits_replace_and_retains_previous_file :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	root := temp_assets_dir(t, files)
	defer os.remove_all(root)
	for long_path in ([]bool{false, true}) {
		dir := fmt.tprintf("%v/着色器", root)
		if long_path {
			for _ in 0..<5 { dir = strings.concatenate({dir, "/shader-directory-with-a-long-name-0123456789"}, context.temp_allocator) }
		}
		testing.expect_value(t, os.make_directory_all(dir), nil)
		for name in ([]string{"build.json", "Test.shaderpack"}) {
			path := fmt.tprintf("%v/%v", dir, name)
			replacement := fmt.tprintf("%v/replacement", dir)
			previous := transmute([]byte)string("previous")
			next := transmute([]byte)string("next generation")
			if name == "Test.shaderpack" {
				previous = shader_test_pack(shader_test_manifest(), "previous")
				next = shader_test_pack(shader_test_manifest(), "next generation")
			}
			testing.expect_value(t, os.write_entire_file(path, previous), nil)
			testing.expect_value(t, os.write_entire_file(replacement, next), nil)
			reader, err := shader_open_file(path)
			testing.expect_value(t, err, nil)
			if err != nil { continue }
			defer os.close(reader)
			testing.expect_value(t, os.rename(replacement, path), nil)
			size, size_error := os.file_size(reader)
			testing.expect_value(t, size_error, nil)
			testing.expect_value(t, size, i64(len(previous)))
			bytes := make([]byte, len(previous), context.temp_allocator)
			n, read_error := os.read(reader, bytes)
			testing.expect_value(t, read_error, nil)
			testing.expect_value(t, n, len(bytes))
			testing.expect_value(t, string(bytes), string(previous))
			current, read := shader_read_file(path, context.temp_allocator, len(next))
			testing.expect(t, read)
			testing.expect_value(t, string(current), string(next))
			if name == "Test.shaderpack" {
				table: Shader_Table
				shader_table_init(&table, context.allocator)
				id, reason, loaded := shader_load_file(&table, dir, "shader/Test")
				testing.expect(t, loaded, reason)
				asset, found := shader_lookup(&table, id)
				testing.expect(t, found)
				if found { testing.expect_value(t, string(asset.package_data.payload), "next generation") }
				shader_table_destroy(&table)
			}
		}
	}
}

@(test)
test_shader_reader_missing_path_returns_no_file :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	reader, err := shader_open_file(fmt.tprintf("%v/missing.shaderpack", dir))
	testing.expect(t, reader == nil && err != nil)
}
