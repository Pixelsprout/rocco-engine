package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

// ROCCO_ASSETS wins; otherwise the assets sit beside the program. roc run sets
// argv[0] to the game's main.roc, so a game finds its assets from any directory.
// A forward slash works on all three targets.
mesh_dir_from :: proc(assets, program: string, allocator: mem.Allocator) -> string {
	if assets != "" {
		return fmt.aprintf("%v/meshes", assets, allocator = allocator)
	}
	dir, _ := os.split_path(program)
	if dir == "" {
		return fmt.aprintf("%v/meshes", DEFAULT_ASSETS, allocator = allocator)
	}
	return fmt.aprintf("%v/%v/meshes", dir, DEFAULT_ASSETS, allocator = allocator)
}

// The stem of each .glb file in dir, sorted. These are the mesh names a Load can ask for.
mesh_names_on_disk :: proc(dir: string, allocator: mem.Allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil {
		if err != .Not_Exist {
			fmt.eprintfln("cannot read %v: %v; no mesh can load from it", dir, os.error_string(err))
		}
		return nil
	}

	names := make([dynamic]string, 0, len(entries), allocator)
	for e in entries {
		if e.type != .Directory && os.ext(e.name) == ".glb" && os.stem(e.name) != "" {
			append(&names, strings.clone(os.stem(e.name), allocator))
		}
	}
	slice.sort(names[:])
	return names[:]
}

// Loads dir/name.glb into the next free slot. On failure the table does not
// change and reason says why.
mesh_load_file :: proc(t: ^Mesh_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
	path := fmt.tprintf("%v/%v.glb", dir, name)
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return 0, os.error_string(read_err), false
	}
	if mesh_table_full(t) {
		return 0, fmt.tprintf("the mesh table is full at %v meshes", MESH_CAPACITY), false
	}
	data, glb_err := glb_parse(bytes, t.allocator)
	if glb_err != .None {
		return 0, GLB_ERROR_REASONS[glb_err], false
	}
	slot, _ := mesh_table_add(t, strings.clone(name, t.allocator), data)
	return mesh_id(t, slot), "", true
}
