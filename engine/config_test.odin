package engine

import "core:testing"

@(test)
test_seed_defaults_to_zero :: proc(t: ^testing.T) {
	seed, ok := seed_parse("")
	testing.expect(t, ok)
	testing.expect_value(t, seed, 0)
}

@(test)
test_seed_reads_any_u64 :: proc(t: ^testing.T) {
	Case :: struct {
		value: string,
		want:  u64,
	}
	for c in ([]Case{{"0", 0}, {"42", 42}, {"18446744073709551615", max(u64)}}) {
		seed, ok := seed_parse(c.value)
		testing.expectf(t, ok, "expected %q to parse", c.value)
		testing.expect_value(t, seed, c.want)
	}
}

@(test)
test_config_carries_the_seed_and_the_asset_names_with_no_ids :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	names := []string{"ball", "an asset name longer than twenty-three bytes"}
	config := config_make(42, names)
	defer roc_decref(config)

	testing.expect_value(t, config.seed, 42)
	testing.expect_value(t, int(config.assets.length), len(names))
	for &name, i in config.assets.elements[:config.assets.length] {
		testing.expect_value(t, roc_str_string(&name), names[i])
	}
}

@(test)
test_seed_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"-1", "+1", "1_0", "007", "abc", "12x", " 12", "1.5", "18446744073709551616", "36893488147419103231"}) {
		_, ok := seed_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}

@(test)
test_assets_dir_is_rocco_assets_or_beside_the_program :: proc(t: ^testing.T) {
	Case :: struct {
		assets, program, want: string,
	}
	cases := []Case {
		{"/games/sprout", "./examples/entity-game/main.roc", "/games/sprout"},
		{"", "./examples/entity-game/main.roc", "./examples/entity-game/assets"},
		{"", "/opt/game/entity-game.bin", "/opt/game/assets"},
		{"", "./entity-game.bin", "./assets"},
		{"", "entity-game.bin", "assets"},
		{"", "", "assets"},
	}
	for c in cases {
		testing.expect_value(t, assets_dir_from(c.assets, c.program, context.temp_allocator), c.want)
	}
}
