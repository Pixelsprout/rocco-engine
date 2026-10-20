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
	testing.expect_value(t, launch.capacity.meshes, MESH_CAPACITY)
	testing.expect_value(t, launch.capacity.skies, SKY_CAPACITY)
	testing.expect_value(t, launch.capacity.draws, DRAW_CAPACITY)
	testing.expect_value(t, launch.capacity.ui_quads, UI_QUAD_CAPACITY)
}

@(test)
test_launch_check_passes_the_default :: proc(t: ^testing.T) {
	field, ok := launch_check(launch_default())
	testing.expect(t, ok)
	testing.expect_value(t, field, "")
}

@(test)
test_launch_check_names_the_first_zero_field :: proc(t: ^testing.T) {
	Case :: struct {
		zero:  proc(launch: ^Launch),
		field: string,
	}
	cases := []Case {
		{proc(l: ^Launch) {l.window.width = 0}, "window.width"},
		{proc(l: ^Launch) {l.window.height = 0}, "window.height"},
		{proc(l: ^Launch) {l.step_hz = 0}, "step_hz"},
		{proc(l: ^Launch) {l.shadow_map = 0}, "shadow_map"},
	}
	for c in cases {
		launch := launch_default()
		c.zero(&launch)
		field, ok := launch_check(launch)
		testing.expectf(t, !ok, "expected a zero %v to fail", c.field)
		testing.expect_value(t, field, c.field)
	}
}
