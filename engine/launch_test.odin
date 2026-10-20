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
	testing.expect_value(t, f64(1) / f64(launch.step_hz), FIXED_DT)
	testing.expect_value(t, launch.shadow_map, SHADOW_MAP_SIZE)
	testing.expect_value(t, launch.capacity.meshes, MESH_CAPACITY)
	testing.expect_value(t, launch.capacity.skies, SKY_CAPACITY)
	testing.expect_value(t, launch.capacity.draws, DRAW_CAPACITY)
	testing.expect_value(t, launch.capacity.ui_quads, UI_QUAD_CAPACITY)
}
