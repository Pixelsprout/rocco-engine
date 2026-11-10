#+test
package engine

import "core:fmt"
import "core:testing"

@(test)
test_game_log_writes_each_log_with_the_game_prefix_and_skips_other_commands :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	lines := game_log_lines({fake_log("ready"), {tag = .Quit}, fake_log("")})
	testing.expect_value(t, len(lines), 2)
	testing.expect_value(t, lines[0], "game: ready")
	testing.expect_value(t, lines[1], "game: ")
}

@(test)
test_game_log_writes_32_lines_per_step_then_counts_the_rest :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	commands := make([]Command, 40, context.temp_allocator)
	for &command, i in commands { command = fake_log(fmt.tprintf("line %v", i)) }
	lines := game_log_lines(commands)
	testing.expect_value(t, len(lines), 33)
	testing.expect_value(t, lines[31], "game: line 31")
	testing.expect_value(t, lines[32], "game: 8 lines dropped")
}

// A message over 23 bytes lives on the Roc heap, so the line must outlive the list.
@(test)
test_game_log_lines_outlive_the_commands_list :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	msg := "a message long enough for the Roc heap"
	list := roc_list_from_slice([]Command{fake_log(msg)})
	lines := game_log_lines(list.elements[:list.length])
	roc_list_decref(list)
	testing.expect_value(t, lines[0], fmt.tprintf("game: %v", msg))
}
