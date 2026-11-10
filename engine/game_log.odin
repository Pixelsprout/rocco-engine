package engine

import "core:fmt"

GAME_LOG_MAX_LINES :: 32

// The lines live in the Frame allocator. Each one borrows nothing from the
// commands, so the host can free the commands list first.
game_log_lines :: proc(commands: []Command, allocator := context.temp_allocator) -> []string {
	lines := make([dynamic]string, 0, 0, allocator)
	dropped := 0
	for &command in commands {
		if command.tag != .Log { continue }
		if len(lines) == GAME_LOG_MAX_LINES { dropped += 1; continue }
		append(&lines, fmt.aprintf("game: %v", roc_str_string(&command.payload.log), allocator = allocator))
	}
	if dropped > 0 { append(&lines, fmt.aprintf("game: %v lines dropped", dropped, allocator = allocator)) }
	return lines[:]
}
