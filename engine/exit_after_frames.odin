package engine

import "core:fmt"
import "core:os"
import "core:strconv"

EXIT_AFTER_FRAMES_ENV :: "ROCCO_EXIT_AFTER_FRAMES"

// Exits the process on a bad value so a CI typo fails instead of running forever.
exit_after_frames_from_env :: proc() -> int {
	value := os.get_env(EXIT_AFTER_FRAMES_ENV, context.temp_allocator)
	limit, ok := exit_after_frames_parse(value)
	if !ok {
		fmt.eprintfln("%v must be a positive integer, got %q", EXIT_AFTER_FRAMES_ENV, value)
		os.exit(1)
	}
	return limit
}

// Treat an empty value as unset.
exit_after_frames_parse :: proc(value: string) -> (limit: int, ok: bool) {
	if value == "" {
		return 0, true
	}
	n := strconv.parse_int(value, 10) or_return
	if n <= 0 {
		return 0, false
	}
	return n, true
}
