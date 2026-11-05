#+build windows
#+test
package engine

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

@(test)
test_shader_reader_permits_source_rename_and_retains_previous_file :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	root := temp_assets_dir(t, files)
	defer os.remove_all(root)
	absolute, absolute_error := os.get_absolute_path(root, context.temp_allocator)
	testing.expect_value(t, absolute_error, nil)
	if absolute_error != nil { return }
	normal, path_error := os.replace_path_separators(absolute, '\\', context.temp_allocator)
	testing.expect_value(t, path_error, nil)
	if path_error != nil { return }
	directories := make([dynamic]string, context.temp_allocator)
	defer {
		for i := len(directories)-1; i >= 0; i -= 1 { testing.expect_value(t, os.remove(directories[i]), nil) }
	}
	for long_path in ([]bool{false, true}) {
		dir := fmt.tprintf("%v\\着色器-%v", normal, long_path)
		for {
			setup_dir := shader_test_extended_path(dir)
			create_error := os.make_directory(setup_dir)
			testing.expect_value(t, create_error, nil)
			if create_error != nil { return }
			append(&directories, setup_dir)
			if !long_path || len(dir) >= 300 { break }
			dir = strings.concatenate({dir, `\shader-directory-with-a-long-name-0123456789`}, context.temp_allocator)
		}
		shader_reader_publication_check(t, dir, shader_test_extended_path(dir))
	}
}

shader_test_extended_path :: proc(path: string) -> string {
	if strings.has_prefix(path, `\\?\`) { return path }
	if strings.has_prefix(path, `\\`) { return strings.concatenate({`\\?\UNC\`, path[2:]}, context.temp_allocator) }
	return strings.concatenate({`\\?\`, path}, context.temp_allocator)
}

shader_reader_publication_check :: proc(t: ^testing.T, dir, setup_dir: string) {
	for name in ([]string{"build.json", "Test.shaderpack"}) {
		path := fmt.tprintf("%v\\%v", dir, name)
		setup_path := fmt.tprintf("%v\\%v", setup_dir, name)
		replacement := fmt.tprintf("%v.replacement", setup_path)
		retained := fmt.tprintf("%v.retained", setup_path)
		defer os.remove(setup_path)
		defer os.remove(retained)
		defer os.remove(replacement)
		previous := transmute([]byte)string("previous")
		next := transmute([]byte)string("next generation")
		if name == "Test.shaderpack" {
			previous = shader_test_pack(shader_test_manifest(), "previous")
			next = shader_test_pack(shader_test_manifest(), "next generation")
		}
		testing.expect_value(t, os.write_entire_file(setup_path, previous), nil)
		testing.expect_value(t, os.write_entire_file(replacement, next), nil)
		reader, err := shader_open_file(path)
		testing.expect_value(t, err, nil)
		if err != nil { continue }
		defer os.close(reader)
		rename_error := os.rename(setup_path, retained)
		testing.expect_value(t, rename_error, nil)
		if rename_error != nil { continue }
		// MoveFileEx cannot replace an open destination without POSIX rename semantics.
		publish_error := os.rename(replacement, setup_path)
		testing.expect_value(t, publish_error, nil)
		if publish_error != nil { continue }
		size, size_error := os.file_size(reader)
		testing.expect_value(t, size_error, nil)
		testing.expect_value(t, size, i64(len(previous)))
		bytes := make([]byte, len(previous), context.temp_allocator)
		n, read_error := os.read(reader, bytes)
		testing.expect_value(t, read_error, nil)
		testing.expect_value(t, n, len(bytes))
		testing.expect(t, slice.equal(bytes, previous), "held Shader reader changed after source rename")
		current, read := shader_read_file(path, context.temp_allocator, len(next))
		testing.expect(t, read)
		testing.expect(t, slice.equal(current, next), "published Shader bytes differ")
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

@(test)
test_shader_reader_missing_path_returns_no_file :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	reader, err := shader_open_file(fmt.tprintf("%v/missing.shaderpack", dir))
	testing.expect(t, reader == nil && err != nil)
}
