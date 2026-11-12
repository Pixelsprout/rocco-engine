package engine

import "arenas"
import "base:runtime"
import "core:mem"

FRAME_ARENA_RESERVE :: 64 * mem.Megabyte

Memory :: struct {
	perm:            arenas.Arena,
	frame:           arenas.Arena,
	perm_allocator:  mem.Allocator,
	frame_allocator: mem.Allocator,
}


/**
	Initializes the memory allocators for the game engine.
*/
memory_init :: proc(m: ^Memory) -> (err: mem.Allocator_Error) {
	// Growing arena
	m.perm_allocator = arenas.allocator(&m.perm)

	// Static arena for frame
	arenas.init_static(&m.frame, FRAME_ARENA_RESERVE) or_return
	m.frame_allocator = arenas.allocator(&m.frame)

	return
}

/**
	Shuts down the memory allocators for the game engine.
*/
memory_shutdown :: proc(m: ^Memory) {
	arenas.destroy(&m.frame)
	arenas.destroy(&m.perm)
}

frame_end :: proc(m: ^Memory) {
	// check no watermark was left open
	arenas.check_temp(&m.frame)
	arenas.free_all(&m.frame)
}

// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
// So it takes n entries without growing.
map_reserve_unfilled :: proc(m: ^$M/map[$K]$V, n: int) {
	reserve(m, n * 100 / runtime.MAP_LOAD_FACTOR + 1)
}
