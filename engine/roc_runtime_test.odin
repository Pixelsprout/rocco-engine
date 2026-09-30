package engine

import "core:sync"

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
