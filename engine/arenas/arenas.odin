// Package arenas gives the engine one arena type for every target. Native
// targets reserve virtual memory. wasm has none, so its arenas take blocks
// from the context allocator.
package arenas

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"

// On wasm, core:mem/virtual reserve returns nil with no error.
HEAP :: #config(ROCCO_ARENAS_HEAP, ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32)

// Native builds do not use runtime, and -vet rejects an unused import.
_ :: runtime

when HEAP {
	Arena :: runtime.Arena
} else {
	Arena :: vmem.Arena
}

// A zero-value heap arena takes its blocks from the context allocator of the
// first call. That allocator must outlive the arena, so it cannot be a frame
// allocator.
allocator :: proc(a: ^Arena) -> mem.Allocator {
	when HEAP {
		if a.backing_allocator.procedure == nil {
			a.backing_allocator = context.allocator
		}
		// runtime.Arena starts at 4 MB. vmem starts growing arenas at 1 MB.
		if a.minimum_block_size == 0 {
			a.minimum_block_size = vmem.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE
		}
		return runtime.arena_allocator(a)
	} else {
		return vmem.arena_allocator(a)
	}
}

// A static arena holds one block of `reserved` bytes and never grows.
// The heap form takes the whole block from the context allocator at init.
init_static :: proc(a: ^Arena, reserved: uint) -> mem.Allocator_Error {
	when HEAP {
		runtime.arena_init(a, reserved, context.allocator) or_return
		// Each block keeps the allocator that made it, so destroy still frees
		// the first block.
		a.backing_allocator = {refuse_allocator_proc, nil}
		return nil
	} else {
		return vmem.arena_init_static(a, reserved)
	}
}

free_all :: proc(a: ^Arena) {
	when HEAP {
		runtime.arena_free_all(a)
	} else {
		vmem.arena_free_all(a)
	}
}

destroy :: proc(a: ^Arena) {
	when HEAP {
		runtime.arena_destroy(a)
		// A static arena keeps its refusing allocator past destroy otherwise.
		a^ = {}
	} else {
		vmem.arena_destroy(a)
	}
}

check_temp :: proc(a: ^Arena, loc := #caller_location) {
	when HEAP {
		runtime.arena_check_temp(a, loc)
	} else {
		vmem.arena_check_temp(a, loc)
	}
}

@(private)
refuse_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	return nil, .Out_Of_Memory
}
