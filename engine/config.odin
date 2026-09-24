package engine

import "core:fmt"
import "core:os"
import "core:strconv"

SEED_ENV :: "ROCCO_SEED"
DEBUG_CAMERA_ENV :: "ROCCO_DEBUG_CAMERA"

// The engine's own meshes. Id 0 stays free for the fallback mesh.
PRIMITIVE_MESHES :: [?]struct {
	name: string,
	id:   u32,
}{{"cube", 1}, {"sphere", 2}, {"slab", 3}}

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

// Every string and list is a fresh roc_alloc at refcount 1; roc_init consumes them.
config_make :: proc(seed: u64) -> Config {
	entries: [len(PRIMITIVE_MESHES)]Mesh_Entry
	for mesh, i in PRIMITIVE_MESHES {
		entries[i] = {name = roc_str_from_slice(mesh.name), id = mesh.id}
	}
	return {seed = seed, meshes = roc_list_from_slice(entries[:])}
}
