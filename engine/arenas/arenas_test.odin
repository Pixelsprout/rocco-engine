#+test
package arenas

import "core:mem"
import "core:testing"

@(test)
test_zero_value_arena_grows_past_one_block :: proc(t: ^testing.T) {
	a: Arena
	defer destroy(&a)
	alloc := allocator(&a)
	first, first_err := mem.alloc_bytes(64, 16, alloc)
	testing.expect_value(t, first_err, nil)
	testing.expect_value(t, len(first), 64)
	big, big_err := mem.alloc_bytes(32 * mem.Megabyte, 16, alloc)
	testing.expect_value(t, big_err, nil)
	testing.expect_value(t, len(big), 32 * mem.Megabyte)
	big[len(big) - 1] = 7
	testing.expect(t, a.total_used >= 32 * mem.Megabyte + 64)
}

@(test)
test_free_all_empties_a_growing_arena :: proc(t: ^testing.T) {
	a: Arena
	defer destroy(&a)
	_, err := mem.alloc_bytes(1024, 16, allocator(&a))
	testing.expect_value(t, err, nil)
	free_all(&a)
	testing.expect_value(t, a.total_used, uint(0))
}

@(test)
test_static_arena_takes_its_full_reserve_and_no_more :: proc(t: ^testing.T) {
	a: Arena
	testing.expect_value(t, init_static(&a, 4 * mem.Megabyte), nil)
	defer destroy(&a)
	alloc := allocator(&a)
	data, err := mem.alloc_bytes(3 * mem.Megabyte, 16, alloc)
	testing.expect_value(t, err, nil)
	data[len(data) - 1] = 1
	_, over_err := mem.alloc_bytes(2 * mem.Megabyte, 16, alloc)
	testing.expect_value(t, over_err, mem.Allocator_Error.Out_Of_Memory)
}

@(test)
test_static_arena_reuses_its_memory_after_free_all :: proc(t: ^testing.T) {
	a: Arena
	testing.expect_value(t, init_static(&a, 4 * mem.Megabyte), nil)
	defer destroy(&a)
	alloc := allocator(&a)
	first, _ := mem.alloc_bytes(1024, 16, alloc)
	first[0] = 9
	check_temp(&a)
	free_all(&a)
	testing.expect_value(t, a.total_used, uint(0))
	second, err := mem.alloc_bytes(1024, 16, alloc)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, raw_data(second), raw_data(first))
	testing.expect_value(t, second[0], u8(0))
}

@(test)
test_destroyed_static_arena_works_again_as_a_growing_arena :: proc(t: ^testing.T) {
	a: Arena
	testing.expect_value(t, init_static(&a, 1 * mem.Megabyte), nil)
	destroy(&a)
	defer destroy(&a)
	_, err := mem.alloc_bytes(2 * mem.Megabyte, 16, allocator(&a))
	testing.expect_value(t, err, nil)
}

@(test)
test_zero_value_arena_takes_small_blocks_first :: proc(t: ^testing.T) {
	a: Arena
	defer destroy(&a)
	_, err := mem.alloc_bytes(64, 16, allocator(&a))
	testing.expect_value(t, err, nil)
	when HEAP {
		testing.expect(t, a.total_capacity <= 2 * mem.Megabyte)
	} else {
		testing.expect(t, a.total_reserved <= 2 * mem.Megabyte)
	}
}

// Only the -define:ROCCO_ARENAS_HEAP=true run tests this.
@(test)
test_heap_arenas_take_blocks_from_the_context_allocator :: proc(t: ^testing.T) {
	when !HEAP {
		return
	}
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)

	growing, static: Arena
	_, err := mem.alloc_bytes(64, 16, allocator(&growing))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, init_static(&static, 2 * mem.Megabyte), nil)
	testing.expect_value(t, len(tracking.allocation_map), 2)
	destroy(&growing)
	destroy(&static)
	testing.expect_value(t, len(tracking.allocation_map), 0)
}
