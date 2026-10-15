package engine

import clay "../clay/bindings/odin/clay-odin"
import "base:runtime"
import "core:fmt"
import "core:mem"

Ui :: struct {
	memory:        []u8,
	ctx:           ^clay.Context,
	errors_logged: bit_set[clay.ErrorType],
}

// The arena lives as long as the allocator, so there is no ui_destroy.
ui_init :: proc(ui: ^Ui, size: [2]f32, allocator: mem.Allocator) -> mem.Allocator_Error {
	capacity := clay.MinMemorySize()
	ui.memory = make([]u8, capacity, allocator) or_return
	arena := clay.CreateArenaWithCapacityAndMemory(uint(capacity), raw_data(ui.memory))
	ui.ctx = clay.Initialize(arena, {size.x, size.y}, {handler = ui_error_cb, userData = ui})
	return nil
}

ui_error_mark_logged :: proc(ui: ^Ui, kind: clay.ErrorType) -> bool {
	if kind in ui.errors_logged {
		return false
	}
	ui.errors_logged += {kind}
	return true
}

ui_error_cb :: proc "c" (data: clay.ErrorData) {
	context = runtime.default_context()
	ui := (^Ui)(data.userData)
	if ui_error_mark_logged(ui, data.errorType) {
		fmt.eprintfln("clay %v: %s", data.errorType, string(data.errorText.chars[:data.errorText.length]))
	}
}
