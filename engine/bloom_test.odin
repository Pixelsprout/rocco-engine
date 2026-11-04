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
		testing.expectf(t, bloom_mip_count(c.size, 1) == c.mips, "%v: got %v mips, want %v", c.size, bloom_mip_count(c.size, 1), c.mips)
	}
}

@(test)
test_bloom_mip_count_reads_the_logical_size :: proc(t: ^testing.T) {
	cases := []struct {
		size: [2]i32,
		dpi:  f32,
		mips: int,
	} {
		{{960, 540}, 1, 6},
		{{1920, 1080}, 2, 6},
		{{256, 64}, 1, 3},
		{{512, 128}, 2, 3},
		{{16, 16}, 1, 1},
		{{32, 32}, 2, 1},
		{{31, 2000}, 2, 0},
	}
	for c in cases {
		got := bloom_mip_count(c.size, c.dpi)
		testing.expectf(t, got == c.mips, "%v at dpi %v: got %v mips, want %v", c.size, c.dpi, got, c.mips)
	}
}

@(test)
test_bloom_mip_size_halves_the_size_once_per_mip :: proc(t: ^testing.T) {
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 1, 0), [2]i32{960, 540})
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 1, 1), [2]i32{480, 270})
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 1, 5), [2]i32{30, 16})
	// Each mip is its larger neighbour halved, rounded down, so a shader can
	// find its target size from its source size.
	for dpi in ([]f32{1, 1.5, 2}) {
		for mip in 1 ..< BLOOM_MIP_LIMIT {
			testing.expect_value(t, bloom_mip_size({1366, 767}, dpi, mip), bloom_mip_size({1366, 767}, dpi, mip - 1) / 2)
		}
	}
}

@(test)
test_bloom_mip_size_is_the_same_at_dpi_1_and_2_for_the_same_logical_window :: proc(t: ^testing.T) {
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 2, 0), [2]i32{480, 270})
	testing.expect_value(t, bloom_mip_size({1920, 1080}, 2, 5), [2]i32{15, 8})
	for mip in 0 ..< BLOOM_MIP_LIMIT {
		testing.expect_value(t, bloom_mip_size({1920, 1080}, 2, mip), bloom_mip_size({960, 540}, 1, mip))
	}
	testing.expect_value(t, bloom_mip_size({1440, 810}, 1.5, 0), [2]i32{480, 270})
}

@(test)
test_bloom_mip_size_reads_a_dpi_under_1_as_1 :: proc(t: ^testing.T) {
	for dpi in ([]f32{0, 0.5, -1}) {
		testing.expect_value(t, bloom_mip_size({960, 540}, dpi, 0), [2]i32{480, 270})
	}
}
