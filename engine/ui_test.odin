package engine

import clay "../clay/bindings/odin/clay-odin"
import vmem "core:mem/virtual"
import "core:testing"

@(test)
test_ui_error_logs_once_per_kind :: proc(t: ^testing.T) {
	ui: Ui
	testing.expect(t, ui_error_mark_logged(&ui, .DuplicateId))
	testing.expect(t, !ui_error_mark_logged(&ui, .DuplicateId))
	testing.expect(t, ui_error_mark_logged(&ui, .ArenaCapacityExceeded))
	testing.expect_value(t, ui.errors_logged, bit_set[clay.ErrorType]{.DuplicateId, .ArenaCapacityExceeded})
}

@(test)
test_ui_init_sizes_the_arena_from_clay :: proc(t: ^testing.T) {
	arena: vmem.Arena
	defer vmem.arena_destroy(&arena)
	ui: Ui
	err := ui_init(&ui, {960, 540}, vmem.arena_allocator(&arena))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(ui.memory), int(clay.MinMemorySize()))
	testing.expect(t, ui.ctx != nil)
}
