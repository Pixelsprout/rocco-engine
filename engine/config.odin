package engine

import "core:fmt"
import "core:os"
import "core:strconv"

SEED_ENV :: "ROCCO_SEED"
DEBUG_CAMERA_ENV :: "ROCCO_DEBUG_CAMERA"
ALLOC_REPORT_ENV :: "ROCCO_ALLOC_REPORT"
ASSETS_ENV :: "ROCCO_ASSETS"
DEFAULT_ASSETS :: "assets"

// Exits the process on a bad value, so a typo cannot change the run silently.
seed_from_env :: proc() -> u64 {
	value := os.get_env(SEED_ENV, context.temp_allocator)
	seed, ok := seed_parse(value)
	if !ok {
		fmt.eprintfln("%v must be an unsigned 64-bit integer, got %q", SEED_ENV, value)
		os.exit(1)
	}
	return seed
}

// Treat an empty value as unset. parse_u64_of_base wraps on overflow and
// accepts "+" and "_", so only a value that prints back unchanged passes.
seed_parse :: proc(value: string) -> (seed: u64, ok: bool) {
	if value == "" {
		return 0, true
	}
	n, parsed := strconv.parse_u64_of_base(value, 10)
	return n, parsed && value == fmt.tprint(n)
}

debug_camera_from_env :: proc() -> bool {
	return os.get_env(DEBUG_CAMERA_ENV, context.temp_allocator) == "1"
}

alloc_report_from_env :: proc() -> bool {
	return os.get_env(ALLOC_REPORT_ENV, context.temp_allocator) == "1"
}

mesh_dir_from_env :: proc() -> string {
	program := os.args[0] if len(os.args) > 0 else ""
	return mesh_dir_from(os.get_env(ASSETS_ENV, context.temp_allocator), program, context.temp_allocator)
}

// Every string and list is a fresh roc_alloc at refcount 1; roc_init consumes them.
config_make :: proc(seed: u64, table: ^Mesh_Table) -> Config {
	entries := make([]Mesh_Entry, table.count, context.temp_allocator)
	for mesh, id in table.meshes[:table.count] {
		entries[id] = {name = roc_str_from_slice(mesh.name), id = u32(id)}
	}
	return {seed = seed, meshes = roc_list_from_slice(entries)}
}
