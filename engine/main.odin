package engine

import "core:fmt"
import "core:mem"

TRACK_ALLOC :: #config(ROCCO_TRACK_ALLOC, false)

// Only the TRACK_ALLOC code uses mem, so -vet needs this when it is off.
_ :: mem

when TRACK_ALLOC {
	g_track: mem.Tracking_Allocator
}

main :: proc() {
	run(ROC_GAME)
}

// An Odin twin calls run from its own main package with its own Game calls.
run :: proc(calls: Game_Calls) {
	when TRACK_ALLOC {
		mem.tracking_allocator_init(&g_track, context.allocator)
		context.allocator = mem.tracking_allocator(&g_track)
	}

	if err := app_run(calls); err != nil {
		fmt.eprintfln("engine failed to start: %v", err)
		return
	}
}
