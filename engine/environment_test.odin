#+test
package engine

import "core:math"
import "core:testing"

// A zero Environment has an exposure of 0, so tests start from this copy of
// Environment.default.
ENVIRONMENT_DEFAULT :: Environment {
	tone_map = .Aces,
	exposure = 1,
	fog = {color = {r = 0.5, g = 0.5, b = 0.5}, start = 10, end = 50, amount = 0},
	bloom = {strength = 0, threshold = 2, knee = 0.5},
}

@(test)
test_environment_clamp_keeps_a_good_environment_and_logs_nothing :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.tone_map = .AgX
	env.exposure = 0.5
	env.fog = {color = {r = 0.2}, start = 2, end = 10, amount = 1}
	env.bloom = {strength = 0.5, threshold = 1, knee = 0.5}

	testing.expect_value(t, environment_clamp(env, &logged), env)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{})
}

@(test)
test_environment_clamp_keeps_environment_default :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	testing.expect_value(t, environment_clamp(ENVIRONMENT_DEFAULT, &logged), ENVIRONMENT_DEFAULT)
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
		env.fog = {color = {g = 1}, start = 5, end = end, amount = 1}
		testing.expect_value(t, environment_clamp(env, &logged).fog, Fog{color = {g = 1}, start = 5, end = 5 + FOG_MIN_SPAN, amount = 1})
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Range})
	}
}

@(test)
test_environment_clamp_moves_a_fog_end_above_a_large_start :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog = {start = 1e6, end = 1e6, amount = 1}
	fog := environment_clamp(env, &logged).fog
	testing.expectf(t, fog.end > fog.start, "got start %v, end %v", fog.start, fog.end)
}

@(test)
test_environment_clamp_draws_a_nan_fog_start_from_0 :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog = {start = math.nan_f32(), end = 10, amount = 1}
	testing.expect_value(t, environment_clamp(env, &logged).fog, Fog{start = 0, end = 10, amount = 1})
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Range})
}

@(test)
test_environment_clamp_ignores_the_range_of_fog_with_amount_0 :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.fog = {start = 4, end = 1, amount = 0}
	testing.expect_value(t, environment_clamp(env, &logged).fog, env.fog)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{})
}

@(test)
test_environment_clamp_clamps_a_fog_amount_into_0_to_1 :: proc(t: ^testing.T) {
	cases := []struct {
		amount, want: f32,
	}{{-0.5, 0}, {1.5, 1}, {math.nan_f32(), 0}}
	for c in cases {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.fog.amount = c.amount
		testing.expect_value(t, environment_clamp(env, &logged).fog.amount, c.want)
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Amount})
	}
}

@(test)
test_environment_clamp_draws_each_negative_bloom_number_as_0 :: proc(t: ^testing.T) {
	cases := []struct {
		bloom, want: Bloom,
		log:         Environment_Clamp,
	} {
		{{strength = -1, threshold = 1, knee = 0.5}, {strength = 0, threshold = 1, knee = 0.5}, .Bloom_Strength},
		{{strength = 0.5, threshold = -1, knee = 0.5}, {strength = 0.5, threshold = 0, knee = 0.5}, .Bloom_Threshold},
		{{strength = 0.5, threshold = 1, knee = -1}, {strength = 0.5, threshold = 1, knee = 0}, .Bloom_Knee},
		{{strength = math.nan_f32(), threshold = 1, knee = 0.5}, {strength = 0, threshold = 1, knee = 0.5}, .Bloom_Strength},
	}
	for c in cases {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.bloom = c.bloom
		testing.expect_value(t, environment_clamp(env, &logged).bloom, c.want)
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{c.log})
	}
}

@(test)
test_environment_clamp_logs_each_bad_value_once_per_run :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.exposure = -1
	env.fog = {start = 3, end = 1, amount = 2}
	env.bloom = {strength = -1, threshold = -1, knee = -1}
	every := bit_set[Environment_Clamp]{.Exposure, .Fog_Amount, .Fog_Range, .Bloom_Strength, .Bloom_Threshold, .Bloom_Knee}

	first := environment_clamp(env, &logged)
	testing.expect_value(t, logged, every)
	second := environment_clamp(env, &logged)
	testing.expect_value(t, logged, every)
	testing.expect_value(t, second, first)
}

@(test)
test_environment_clamp_keeps_a_sky_blend_and_a_sky_fog_in_range :: proc(t: ^testing.T) {
	logged: bit_set[Environment_Clamp]
	env := ENVIRONMENT_DEFAULT
	env.sky_blend = {to = 3, amount = 0.25}
	env.fog.sky = 0.5

	testing.expect_value(t, environment_clamp(env, &logged), env)
	testing.expect_value(t, logged, bit_set[Environment_Clamp]{})
}

@(test)
test_environment_clamp_clamps_a_sky_blend_amount_into_0_to_1_and_logs_once :: proc(t: ^testing.T) {
	for c in ([][2]f32{{1.5, 1}, {-0.25, 0}, {math.nan_f32(), 0}}) {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.sky_blend = {to = 3, amount = c[0]}
		testing.expect_value(t, environment_clamp(env, &logged).sky_blend.amount, c[1])
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Sky_Blend_Amount})
	}
}

@(test)
test_environment_clamp_clamps_a_fog_sky_into_0_to_1_and_logs_once :: proc(t: ^testing.T) {
	for c in ([][2]f32{{2, 1}, {-1, 0}, {math.nan_f32(), 0}}) {
		logged: bit_set[Environment_Clamp]
		env := ENVIRONMENT_DEFAULT
		env.fog.sky = c[0]
		testing.expect_value(t, environment_clamp(env, &logged).fog.sky, c[1])
		testing.expect_value(t, logged, bit_set[Environment_Clamp]{.Fog_Sky})
	}
}
