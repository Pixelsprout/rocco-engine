package engine

import "core:fmt"
import "core:math"

// A Fog end at or below its start moves at least this far past the start,
// so the fog ramp never divides by zero.
FOG_MIN_SPAN :: f32(0.001)

Environment_Clamp :: enum {
	Exposure,
	Fog_Amount,
	Fog_Range,
	Bloom_Strength,
	Bloom_Threshold,
	Bloom_Knee,
}

// Returns env with each bad value replaced by one the renderer can draw. The
// checks are written so a NaN fails them too. logged holds the values already
// logged this run.
environment_clamp :: proc(env: Environment, logged: ^bit_set[Environment_Clamp]) -> Environment {
	e := env
	if !(e.exposure > 0) {
		environment_log(logged, .Exposure, "an Environment exposure of %v is at or below 0; the host draws with 1", e.exposure)
		e.exposure = 1
	}
	fog := &e.fog
	if !(fog.amount >= 0 && fog.amount <= 1) {
		environment_log(logged, .Fog_Amount, "a Fog amount of %v is outside 0 to 1; the host clamps it", fog.amount)
		fog.amount = 0 if math.is_nan(fog.amount) else clamp(fog.amount, 0, 1)
	}
	// Fog with amount 0 draws nothing, so its range is not read.
	if fog.amount > 0 {
		if math.is_nan(fog.start) {
			environment_log(logged, .Fog_Range, "a Fog start is NaN; the host draws with 0")
			fog.start = 0
		}
		if !(fog.end > fog.start) {
			environment_log(logged, .Fog_Range, "a Fog end of %v is at or below its start of %v; the host draws with the start plus %v", fog.end, fog.start, FOG_MIN_SPAN)
			// Past 32768 the f32 sum rounds back to the start.
			fog.end = max(fog.start + FOG_MIN_SPAN, math.nextafter(fog.start, math.inf_f32(1)))
		}
	}
	e.bloom.strength = bloom_number(logged, .Bloom_Strength, "strength", e.bloom.strength)
	e.bloom.threshold = bloom_number(logged, .Bloom_Threshold, "threshold", e.bloom.threshold)
	e.bloom.knee = bloom_number(logged, .Bloom_Knee, "knee", e.bloom.knee)
	return e
}

@(private = "file")
bloom_number :: proc(logged: ^bit_set[Environment_Clamp], which: Environment_Clamp, name: string, n: f32) -> f32 {
	if n >= 0 {
		return n
	}
	environment_log(logged, which, "a Bloom %v of %v is negative; the host draws with 0", name, n)
	return 0
}

@(private = "file")
environment_log :: proc(logged: ^bit_set[Environment_Clamp], which: Environment_Clamp, format: string, args: ..any) {
	if which in logged {
		return
	}
	logged^ += {which}
	fmt.eprintfln(format, ..args)
}
