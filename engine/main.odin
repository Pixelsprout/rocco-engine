package engine

import "core:fmt"
import "core:mem"

when ODIN_DEBUG {
	g_track: mem.Tracking_Allocator
}

main :: proc() {
	// Track memory allocations for leaks or bad frees
	when ODIN_DEBUG {
		mem.tracking_allocator_init(&g_track, context.allocator)
		context.allocator = mem.tracking_allocator(&g_track)
	}

	if err := app_run(); err != nil {
		fmt.eprintfln("engine failed to start: %v", err)
		return
	}
}
