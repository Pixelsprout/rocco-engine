package engine

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
FRAME_ARENA_RESERVE :: 64 * mem.Megabyte

Memory :: struct {
	perm:            vmem.Arena,
	frame:           vmem.Arena,
	perm_allocator:  mem.Allocator,
	frame_allocator: mem.Allocator,
}


/**
	Initializes the memory allocators for the game engine.
*/
memory_init :: proc(m: ^Memory) -> (err: mem.Allocator_Error) {
	// Growing arena
	m.perm_allocator = vmem.arena_allocator(&m.perm)

	// Static arena for frame
	vmem.arena_init_static(&m.frame, FRAME_ARENA_RESERVE) or_return
	m.frame_allocator = vmem.arena_allocator(&m.frame)

	return
}

/**
	Shuts down the memory allocators for the game engine.
*/
memory_shutdown :: proc(m: ^Memory) {
	vmem.arena_destroy(&m.frame)
	vmem.arena_destroy(&m.perm)
}

frame_end :: proc(m: ^Memory) {
	// check no watermark was left open
	vmem.arena_check_temp(&m.frame)
	vmem.arena_free_all(&m.frame)
}

// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
// So it takes n entries without growing.
map_reserve_unfilled :: proc(m: ^$M/map[$K]$V, n: int) {
	reserve(m, n * 100 / runtime.MAP_LOAD_FACTOR + 1)
}
