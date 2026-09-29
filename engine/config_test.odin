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

// packages/meshes/Meshes.roc checks the same literal manifest.
@(test)
test_config_carries_the_seed_and_the_manifest_built_from_the_mesh_table :: proc(t: ^testing.T) {
	table: Mesh_Table
	mesh_table_init(&table, context.allocator)
	defer mesh_table_destroy(&table)
	table.meshes[table.count].name = "sprout"
	table.count += 1

	// roc_alloc reads g_state.seam.heap.
	g_state.seam.heap = context.allocator
	defer g_state.seam.heap = {}
	config := config_make(42, &table)
	defer roc_decref(config)

	Entry :: struct {
		name: string,
		id:   u32,
	}
	want := []Entry{{"primitive/fallback", 0}, {"primitive/cube", 1}, {"primitive/sphere", 2}, {"primitive/plane", 3}, {"sprout", 4}}
	testing.expect_value(t, config.seed, 42)
	testing.expect_value(t, int(config.meshes.length), len(want))
	for &e, i in config.meshes.elements[:config.meshes.length] {
		testing.expect_value(t, Entry{roc_str_inline(&e.name), e.id}, want[i])
	}
}

// Every name in the test is short enough to live inside the Roc_Str.
roc_str_inline :: proc(s: ^Roc_Str) -> string {
	raw := ([^]u8)(s)
	n := int(raw[size_of(Roc_Str) - 1] & 0x7f)
	return string(raw[:n])
}

@(test)
test_seed_rejects_bad_values :: proc(t: ^testing.T) {
	for value in ([]string{"-1", "+1", "1_0", "007", "abc", "12x", " 12", "1.5", "18446744073709551616", "36893488147419103231"}) {
		_, ok := seed_parse(value)
		testing.expectf(t, !ok, "expected %q to be rejected", value)
	}
}
