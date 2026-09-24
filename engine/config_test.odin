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
test_seed_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"-1", "+1", "1_0", "007", "abc", "12x", " 12", "1.5", "18446744073709551616", "36893488147419103231"}) {
		_, ok := seed_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}
