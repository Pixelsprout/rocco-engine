package engine

import "core:mem"
import vmem "core:mem/virtual"
FRAME_ARENA_RESERVE :: 64 * mem.Megabyte

Memory :: struct {
	perm:            vmem.Arena,
	level:           vmem.Arena,
	frame:           vmem.Arena,
	perm_allocator:  mem.Allocator,
	level_allocator: mem.Allocator,
	frame_allocator: mem.Allocator,
}


/**
	Initializes the memory allocators for the game engine.
*/
memory_init :: proc(m: ^Memory) -> (err: mem.Allocator_Error) {
	// Growing arenas
	m.perm_allocator = vmem.arena_allocator(&m.perm)
	m.level_allocator = vmem.arena_allocator(&m.level)

	// Static arena for frame
	vmem.arena_init_static(&m.frame, FRAME_ARENA_RESERVE) or_return
	m.frame_allocator = vmem.arena_allocator(&m.frame)

	return
}

/**
	Shuts down the memory allocators for the game engine.
*/
memory_shutdown :: proc(m: ^Memory) {
	vmem.arena_destroy(&m.level)
	vmem.arena_destroy(&m.frame)
	vmem.arena_destroy(&m.perm)
}

frame_end :: proc(m: ^Memory) {
	// check no watermark was left open
	vmem.arena_check_temp(&m.frame)
	vmem.arena_free_all(&m.frame)
}

level_unload :: proc(m: ^Memory) {
	vmem.arena_free_all(&m.level)
}
