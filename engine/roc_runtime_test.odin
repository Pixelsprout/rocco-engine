#+test
package engine

import "core:sync"
import "core:testing"

// The test runner uses several threads, and the Roc heap is a package
// global. Every test that allocates through roc_alloc holds this lock.
@(private = "file")
g_roc_heap_test_lock: sync.Mutex

roc_heap_test_begin :: proc() {
	sync.mutex_lock(&g_roc_heap_test_lock)
	roc_heap_init(context.allocator)
}

roc_heap_test_end :: proc() {
	roc_heap_shutdown()
	sync.mutex_unlock(&g_roc_heap_test_lock)
}

@(private = "file")
fill_bytes :: proc(ptr: rawptr, from, to: int) {
	bytes := ([^]u8)(ptr)
	for i in from ..< to {
		bytes[i] = u8(i * 7)
	}
}

@(private = "file")
expect_bytes :: proc(t: ^testing.T, ptr: rawptr, count: int) {
	bytes := ([^]u8)(ptr)
	for i in 0 ..< count {
		if bytes[i] != u8(i * 7) {
			testing.expectf(t, false, "byte %v is %v, expected %v", i, bytes[i], u8(i * 7))
			return
		}
	}
}

@(test)
test_roc_realloc_keeps_the_contents_when_a_block_grows_and_shrinks :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	ptr := roc_alloc(24, 8)
	fill_bytes(ptr, 0, 24)

	ptr = roc_realloc(ptr, 100_000, 8)
	expect_bytes(t, ptr, 24)
	fill_bytes(ptr, 24, 100_000)

	ptr = roc_realloc(ptr, 40, 8)
	expect_bytes(t, ptr, 40)

	ptr = roc_realloc(ptr, 64, 8)
	expect_bytes(t, ptr, 40)

	roc_dealloc(ptr, 8)
}

@(test)
test_roc_heap_blocks_keep_their_alignment :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	for alignment in ([]uint{1, 2, 4, 8, 16}) {
		for length in ([]uint{0, 1, 13, 64, 4097}) {
			ptr := roc_alloc(length, alignment)
			testing.expectf(t, uintptr(ptr) % uintptr(alignment) == 0, "roc_alloc(%v, %v) gave %p", length, alignment, ptr)
			ptr = roc_realloc(ptr, length * 3 + 5, alignment)
			testing.expectf(t, uintptr(ptr) % uintptr(alignment) == 0, "roc_realloc to %v at %v gave %p", length * 3 + 5, alignment, ptr)
			roc_dealloc(ptr, alignment)
		}
	}
}

@(test)
test_roc_heap_counters_agree_with_the_calls :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	a := roc_alloc(8, 8)
	b := roc_alloc(32, 8)
	c := roc_alloc(16, 16)
	b = roc_realloc(b, 256, 8)
	b = roc_realloc(b, 16, 8)
	roc_dealloc(a, 8)

	testing.expect_value(t, roc_heap_counters(), Roc_Heap_Counters{allocs = 3, deallocs = 1, reallocs = 2, live = 2})

	roc_dealloc(b, 8)
	roc_dealloc(c, 16)

	testing.expect_value(t, roc_heap_counters(), Roc_Heap_Counters{allocs = 3, deallocs = 3, reallocs = 2, live = 0})
}
