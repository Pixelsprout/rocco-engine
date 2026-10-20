// The Roc heap micro benchmark. It calls the roc_alloc, roc_dealloc and
// roc_realloc hooks directly, with no game and no window.
// Run: odin run bench/roc-heap -o:speed -out:build/roc-heap
package roc_heap

import engine "../../engine"
import "core:fmt"
import "core:time"

ROUNDS :: 3
PAIRS :: 2_000_000
LIVE_BLOCKS :: 20
LISTS :: 20_000
ALIGN :: 8

main :: proc() {
	engine.g_state.ctx = context
	engine.roc_heap_init(context.allocator)
	defer engine.roc_heap_shutdown()

	for round in 1 ..= ROUNDS {
		fmt.printfln("== round %v", round)
		fmt.printfln("alloc and free pair: %.1f ns", pairs())

		// Live blocks, so a heap that tracks its blocks holds entries.
		live: [LIVE_BLOCKS]rawptr
		for &p in live {
			p = engine.roc_alloc(48, ALIGN)
		}
		fmt.printfln("alloc and free pair with %v live blocks: %.1f ns", LIVE_BLOCKS, pairs())
		for p in live {
			engine.roc_dealloc(p, ALIGN)
		}

		fmt.printfln("12 doubling reallocs, 16 B to 64 KiB: %.3f us per list", reallocs(64 * 1024, double))
		fmt.printfln("255 reallocs of +16 B, 16 B to 4 KiB: %.3f us per list", reallocs(4096, add_16))
	}
}

pairs :: proc() -> f64 {
	start := time.tick_now()
	for _ in 0 ..< PAIRS {
		p := engine.roc_alloc(64, ALIGN)
		engine.roc_dealloc(p, ALIGN)
	}
	return f64(time.tick_since(start)) / PAIRS
}

reallocs :: proc(limit: uint, grow: proc(n: uint) -> uint) -> f64 {
	start := time.tick_now()
	for _ in 0 ..< LISTS {
		n: uint = 16
		p := engine.roc_alloc(n, ALIGN)
		for n < limit {
			n = grow(n)
			p = engine.roc_realloc(p, n, ALIGN)
		}
		engine.roc_dealloc(p, ALIGN)
	}
	return time.duration_microseconds(time.tick_since(start)) / LISTS
}

double :: proc(n: uint) -> uint {
	return n * 2
}

add_16 :: proc(n: uint) -> uint {
	return n + 16
}
