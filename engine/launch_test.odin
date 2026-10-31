#+test
package engine

import "core:testing"

// A game that returns the default must run as every game ran before Launch.
@(test)
test_launch_default_matches_the_host_constants :: proc(t: ^testing.T) {
	launch := launch_default()
	title := launch.window.title
	testing.expect_value(t, roc_str_string(&title), "rocco")
	testing.expect_value(t, launch.window.samples, Msaa.X4)
	testing.expect_value(t, launch.window.high_dpi, true)
	testing.expect_value(t, launch.step_hz, 120)
	testing.expect_value(t, launch.shadow_map, 2048)
	testing.expect_value(t, launch.shadow_cascades, 1)
	testing.expect_value(t, launch.capacity, Capacity{meshes = 64, skies = 16, draws = 16384, groups = 1024, ui_quads = 16384, sounds = 64, voices = 64})
}

@(test)
test_launch_check_passes_the_default :: proc(t: ^testing.T) {
	field, rule, ok := launch_check(launch_default())
	testing.expect(t, ok)
	testing.expect_value(t, field, "")
	testing.expect_value(t, rule, "")
}

@(test)
test_launch_check_passes_each_capacity_at_its_bound :: proc(t: ^testing.T) {
	launch := launch_default()
	launch.capacity = {meshes = 4, skies = 2, draws = 1, groups = 1, ui_quads = UI_QUAD_LIMIT, sounds = 2, voices = 1}
	_, _, low_ok := launch_check(launch)
	testing.expect(t, low_ok)
	launch.shadow_cascades = 4
	launch.capacity = {meshes = SLOT_LIMIT, skies = SLOT_LIMIT, draws = DRAW_LIMIT, groups = GROUP_LIMIT, ui_quads = 1, sounds = SLOT_LIMIT, voices = SLOT_LIMIT}
	_, _, high_ok := launch_check(launch)
	testing.expect(t, high_ok)
}

@(test)
test_launch_check_names_the_first_bad_field_and_its_rule :: proc(t: ^testing.T) {
	Case :: struct {
		bad:   proc(launch: ^Launch),
		field: string,
		rule:  string,
	}
	cases := []Case {
		{proc(l: ^Launch) {l.window.width = 0}, "window.width", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.window.height = 0}, "window.height", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.step_hz = 0}, "step_hz", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.shadow_map = 0}, "shadow_map", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.shadow_cascades = 0}, "shadow_cascades", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.meshes = 0}, "capacity.meshes", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.skies = 0}, "capacity.skies", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.draws = 0}, "capacity.draws", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.groups = 0}, "capacity.groups", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.ui_quads = 0}, "capacity.ui_quads", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.sounds = 0}, "capacity.sounds", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.voices = 0}, "capacity.voices", LAUNCH_RULE_ZERO},
		{proc(l: ^Launch) {l.capacity.ui_quads = UI_QUAD_LIMIT + 1}, "capacity.ui_quads", LAUNCH_RULE_UI_QUADS},
		{proc(l: ^Launch) {l.capacity.meshes = 3}, "capacity.meshes", LAUNCH_RULE_MESHES},
		{proc(l: ^Launch) {l.capacity.skies = 1}, "capacity.skies", LAUNCH_RULE_SKIES},
		{proc(l: ^Launch) {l.capacity.sounds = 1}, "capacity.sounds", LAUNCH_RULE_SOUNDS},
		{proc(l: ^Launch) {l.capacity.meshes = SLOT_LIMIT + 1}, "capacity.meshes", LAUNCH_RULE_SLOTS},
		{proc(l: ^Launch) {l.capacity.skies = SLOT_LIMIT + 1}, "capacity.skies", LAUNCH_RULE_SLOTS},
		{proc(l: ^Launch) {l.capacity.sounds = SLOT_LIMIT + 1}, "capacity.sounds", LAUNCH_RULE_SLOTS},
		{proc(l: ^Launch) {l.capacity.voices = SLOT_LIMIT + 1}, "capacity.voices", LAUNCH_RULE_SLOTS},
		{proc(l: ^Launch) {l.capacity.draws = DRAW_LIMIT + 1}, "capacity.draws", LAUNCH_RULE_DRAWS},
		{proc(l: ^Launch) {l.capacity.groups = GROUP_LIMIT + 1}, "capacity.groups", LAUNCH_RULE_GROUPS},
		{proc(l: ^Launch) {l.shadow_cascades = 5}, "shadow_cascades", LAUNCH_RULE_CASCADES},
	}
	for c in cases {
		launch := launch_default()
		c.bad(&launch)
		field, rule, ok := launch_check(launch)
		testing.expectf(t, !ok, "expected a bad %v to fail", c.field)
		testing.expect_value(t, field, c.field)
		testing.expect_value(t, rule, c.rule)
	}
}

@(test)
test_msaa_sample_count_maps_each_msaa_tag_to_its_sample_count :: proc(t: ^testing.T) {
	Case :: struct {
		samples: Msaa,
		want:    i32,
	}
	for c in ([]Case{{.Off, 1}, {.X2, 2}, {.X4, 4}, {.X8, 8}}) {
		got := msaa_sample_count(c.samples)
		testing.expectf(t, got == c.want, "%v gives %v samples, want %v", c.samples, got, c.want)
	}
}
