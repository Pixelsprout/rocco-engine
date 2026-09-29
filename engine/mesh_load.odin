package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// A forward slash works on all three targets.
mesh_dir_from_assets :: proc(assets: string, allocator: mem.Allocator) -> string {
	return fmt.aprintf("%v/meshes", assets if assets != "" else DEFAULT_ASSETS, allocator = allocator)
}

// Sorted, so mesh ids are stable across runs. A file that fails is skipped
// and logged, so its name resolves to the fallback.
mesh_table_load_dir :: proc(t: ^Mesh_Table, dir: string, level: mem.Allocator) {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		if err != .Not_Exist {
			fmt.eprintfln("cannot read %v: %v; loading no meshes from it", dir, os.error_string(err))
		}
		return
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})

	for e in entries {
		if e.type == .Directory || os.ext(e.name) != ".glb" || os.stem(e.name) == "" {
			continue
		}
		if t.count == MESH_CAPACITY {
			fmt.eprintfln("skipping %v: the mesh table is full at %v meshes", e.fullpath, MESH_CAPACITY)
			continue
		}
		bytes, read_err := os.read_entire_file(e.fullpath, context.temp_allocator)
		if read_err != nil {
			fmt.eprintfln("skipping %v: %v", e.fullpath, os.error_string(read_err))
			continue
		}
		data, glb_err := glb_parse(bytes, level)
		if glb_err != .None {
			fmt.eprintfln("skipping %v: %v", e.fullpath, GLB_ERROR_REASONS[glb_err])
			continue
		}
		t.meshes[t.count] = {name = strings.clone(os.stem(e.name), level), data = data}
		t.count += 1
	}
}
