package engine

import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"

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
// change and reason says why. A skipped texture logs and still loads.
mesh_load_file :: proc(t: ^Mesh_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
	if mesh_table_full(t) {
		return 0, mesh_table_full_reason(t), false
	}
	caller_temp := context.temp_allocator
	scratch: vmem.Arena
	defer vmem.arena_destroy(&scratch)
	context.temp_allocator = vmem.arena_allocator(&scratch)
	path := fmt.tprintf("%v/%v.glb", dir, name)
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return 0, strings.clone(os.error_string(read_err), caller_temp), false
	}
	data, notes, glb_err := glb_parse(bytes, t.allocator)
	if glb_err != .None {
		return 0, GLB_ERROR_REASONS[glb_err], false
	}
	for note in notes {
		fmt.eprintfln("%v loaded, but %v", path, GLB_NOTE_REASONS[note])
	}
	slot, added := mesh_table_add(t, strings.clone(name, t.allocator), data)
	if !added { return 0, "GPU texture upload failed", false }
	return mesh_id(t, slot), "", true
}
