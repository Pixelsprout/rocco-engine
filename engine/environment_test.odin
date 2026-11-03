#+test
package engine

import "core:math"
import "core:testing"

// A zero Environment has the Fog and Bloom tags and an exposure of 0, so tests
// start from this copy of Environment.default.
ENVIRONMENT_DEFAULT :: Environment {
	tone_map = .Aces,
	exposure = 1,
	fog = {tag = .None},
	bloom = {tag = .None},
}

@(test)
test_environment_clamp_keeps_a_good_environment_and_logs_nothing :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.tone_map = .AgX
	env.exposure = 0.5
	env.fog = fog_of({r = 0.2}, 2, 10)
	env.bloom = bloom_of(0.5, 1, 0.5)

	got := environment_clamp(env, &logged)
	testing.expectf(t, environment_eq(got, env), "got %v, want %v", got, env)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{})
}

@(test)
test_environment_clamp_draws_an_exposure_at_or_below_0_with_1_and_logs_once :: proc(t: ^testing.T) {
	for exposure in ([]f32{0, -2, math.nan_f32()}) {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.exposure = exposure
		testing.expect_value(t, environment_clamp(env, &logged).exposure, 1)
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Exposure})
	}
}

@(test)
test_environment_clamp_moves_a_fog_end_at_or_below_its_start_past_the_start :: proc(t: ^testing.T) {
	for end in ([]f32{5, 3}) {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.fog = fog_of({g = 1}, 5, end)
		got := environment_clamp(env, &logged).fog
		want := fog_of({g = 1}, 5, 5 + FOG_MIN_SPAN)
		testing.expectf(t, fog_eq(got, want), "got %v, want %v", got, want)
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Range})
	}
}

@(test)
test_environment_clamp_moves_a_fog_end_above_a_large_start :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog = fog_of({}, 1e6, 1e6)
	fog := environment_clamp(env, &logged).fog.payload.fog
	testing.expectf(t, fog.end > fog.start, "got start %v, end %v", fog.start, fog.end)
}

@(test)
test_environment_clamp_draws_a_nan_fog_start_from_0 :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog = fog_of({}, math.nan_f32(), 10)
	got := environment_clamp(env, &logged).fog
	want := fog_of({}, 0, 10)
	testing.expectf(t, fog_eq(got, want), "got %v, want %v", got, want)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Range})
}

@(test)
test_environment_clamp_ignores_the_payload_of_no_fog_and_no_bloom :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog.payload.fog = {start = 4, end = 1}
	env.bloom.payload.bloom = {strength = -1, threshold = -1, knee = -1}
	environment_clamp(env, &logged)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{})
}

@(test)
test_environment_clamp_draws_each_negative_bloom_number_as_0 :: proc(t: ^testing.T) {
	cases := []struct {
		bloom: Bloom,
		want:  Bloom,
		log:   Environment_Clamp,
	} {
		{bloom_of(-1, 1, 0.5), bloom_of(0, 1, 0.5), .Bloom_Strength},
		{bloom_of(0.5, -1, 0.5), bloom_of(0.5, 0, 0.5), .Bloom_Threshold},
		{bloom_of(0.5, 1, -1), bloom_of(0.5, 1, 0), .Bloom_Knee},
		{bloom_of(math.nan_f32(), 1, 0.5), bloom_of(0, 1, 0.5), .Bloom_Strength},
	}
	for c in cases {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.bloom = c.bloom
		got := environment_clamp(env, &logged).bloom
		testing.expectf(t, bloom_eq(got, c.want), "got %v, want %v", got, c.want)
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{c.log})
	}
}

@(test)
test_environment_clamp_logs_each_bad_value_once_per_run :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.exposure = -1
	env.fog = fog_of({}, 3, 1)
	env.bloom = bloom_of(-1, -1, -1)
	every := bit_set[Environment_Clamp]{.Exposure, .Fog_Range, .Bloom_Strength, .Bloom_Threshold, .Bloom_Knee}

	first := environment_clamp(env, &logged)
	testing.expect_value(t, logged, every)
	second := environment_clamp(env, &logged)
	testing.expect_value(t, logged, every)
	testing.expectf(t, environment_eq(second, first), "got %v, want %v", second, first)
}

// A tag union with a payload is a raw union, which has no ==. Each compares
// the payload only under its tag.
environment_eq :: proc(a, b: Environment) -> bool {
	return a.sky == b.sky && a.clear == b.clear && a.tone_map == b.tone_map && a.exposure == b.exposure && fog_eq(a.fog, b.fog) && bloom_eq(a.bloom, b.bloom)
}

fog_eq :: proc(a, b: Fog) -> bool {
	return a.tag == b.tag && (a.tag == .None || a.payload.fog == b.payload.fog)
}

bloom_eq :: proc(a, b: Bloom) -> bool {
	return a.tag == b.tag && (a.tag == .None || a.payload.bloom == b.payload.bloom)
}

fog_of :: proc(color: Rgb, start, end: f32) -> Fog {
	return {tag = .Fog, payload = {fog = {color = color, start = start, end = end}}}
}

bloom_of :: proc(strength, threshold, knee: f32) -> Bloom {
	return {tag = .Bloom, payload = {bloom = {strength = strength, threshold = threshold, knee = knee}}}
}
