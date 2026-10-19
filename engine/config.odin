package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

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

assets_dir_from_env :: proc() -> string {
	command_line := platform_command_line(context.temp_allocator)
	program := command_line[0] if len(command_line) > 0 else ""
	return assets_dir_from(os.get_env(ASSETS_ENV, context.temp_allocator), program, context.temp_allocator)
}

// ROCCO_ASSETS wins; otherwise the assets sit beside the program. roc run sets
// argv[0] to the game's main.roc, so a game finds its assets from any directory.
// A forward slash works on all three targets.
assets_dir_from :: proc(assets, program: string, allocator: mem.Allocator) -> string {
	if assets != "" {
		return strings.clone(assets, allocator)
	}
	dir, _ := os.split_path(program)
	if dir == "" {
		return strings.clone(DEFAULT_ASSETS, allocator)
	}
	return fmt.aprintf("%v/%v", dir, DEFAULT_ASSETS, allocator = allocator)
}

args_from_env :: proc() -> []string {
	return args_from(platform_command_line(context.temp_allocator))
}

// The Args are the words after the program name. The host does not parse them.
args_from :: proc(command_line: []string) -> []string {
	return command_line[1:] if len(command_line) > 1 else nil
}

// Every string and list is a fresh roc_alloc at refcount 1; the game init call consumes them.
config_make :: proc(seed: u64, assets: []string, args: []string = nil) -> Config {
	return {seed = seed, assets = roc_str_list_make(assets), args = roc_str_list_make(args)}
}

roc_str_list_make :: proc(words: []string) -> Roc_List(Roc_Str) {
	strs := make([]Roc_Str, len(words), context.temp_allocator)
	for word, i in words {
		strs[i] = roc_str_from_slice(word)
	}
	return roc_list_from_slice(strs)
}
