package engine

BLOOM_MIP_LIMIT :: 6
// A mip with a side under this is too coarse to add to the halo.
BLOOM_MIP_MIN_SIDE :: 8
// A Prefilter, a Down into each mip after the first, and an Up into each mip
// but the last.
BLOOM_STEP_LIMIT :: 2 * BLOOM_MIP_LIMIT - 1

// Prefilter reads the HDR image, keeps the light above the threshold and
// draws mip 0. Down reads the mip above and draws mip. Up adds the mip below
// into mip.
Bloom_Step_Kind :: enum {
	Prefilter,
	Down,
	Up,
}

// threshold and knee are set only for the Prefilter.
Bloom_Step :: struct {
	kind:      Bloom_Step_Kind,
	mip:       int,
	threshold: f32,
	knee:      f32,
}

// Mip 0 has half the window's size. Each later mip halves the one before.
bloom_mip_count :: proc(window: [2]i32) -> int {
	count := 0
	for count < BLOOM_MIP_LIMIT {
		side := bloom_mip_size(window, count)
		if min(side.x, side.y) < BLOOM_MIP_MIN_SIDE {
			break
		}
		count += 1
	}
	return count
}

// Rounds down, so each mip is the one before it halved and rounded down.
bloom_mip_size :: proc(window: [2]i32, mip: int) -> [2]i32 {
	return {max(window.x, 0) >> uint(mip + 1), max(window.y, 0) >> uint(mip + 1)}
}

// The steps over a chain of mips mips, in the order they must run.
bloom_steps :: proc(bloom: Bloom, mips: int) -> (steps: [BLOOM_STEP_LIMIT]Bloom_Step, count: int) {
	if mips <= 0 {
		return
	}
	steps[0] = {kind = .Prefilter, threshold = bloom.threshold, knee = bloom.knee}
	count = 1
	for mip in 1 ..< mips {
		steps[count] = {kind = .Down, mip = mip}
		count += 1
	}
	for mip := mips - 2; mip >= 0; mip -= 1 {
		steps[count] = {kind = .Up, mip = mip}
		count += 1
	}
	return
}
