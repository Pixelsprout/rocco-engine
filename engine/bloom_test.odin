#+test
package engine

import "core:testing"

@(test)
test_bloom_mip_count_starts_at_half_size_and_stops_under_8_px_or_at_the_limit :: proc(t: ^testing.T) {
	cases := []struct {
		size: [2]i32,
		mips: int,
	} {
		{{1920, 1080}, 6},
		{{960, 540}, 6},
		{{256, 64}, 3},
		{{16, 16}, 1},
		{{15, 1000}, 0},
		{{0, 0}, 0},
		{{-4, 100}, 0},
	}
	for c in cases {
		testing.expectf(t, bloom_mip_count(c.size) == c.mips, "%v: got %v mips, want %v", c.size, bloom_mip_count(c.size), c.mips)
	}
}

@(test)
test_bloom_mip_size_halves_the_size_once_per_mip :: proc(t: ^testing.T) {
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 0), [2]i32{960, 540})
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 1), [2]i32{480, 270})
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 5), [2]i32{30, 16})
	// Each mip is its larger neighbour halved, rounded down, so a shader can
	// find its target size from its source size.
	for mip in 1 ..< BLOOM_MIP_LIMIT {
		testing.expect_value(t, bloom_mip_size({1366, 767}, mip), bloom_mip_size({1366, 767}, mip - 1) / 2)
	}
}
