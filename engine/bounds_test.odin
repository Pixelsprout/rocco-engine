#+test
package engine

import "core:math"
import "core:testing"

UNIT_BOX :: Box{{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}}

@(test)
test_box_transform_turns_scales_and_moves_the_box :: proc(t: ^testing.T) {
	m := mat4_translate({10, 0, 0}) * mat4_from_quat(quat_from_axis_angle(UP, math.PI / 2)) * mat4_scale({2, 1, 1})
	got := box_transform(UNIT_BOX, m)
	want := Box{{9.5, -0.5, -1}, {10.5, 0.5, 1}}
	for i in 0 ..< 3 {
		testing.expectf(t, abs(got.min[i] - want.min[i]) < EPS && abs(got.max[i] - want.max[i]) < EPS, "got %v, want %v", got, want)
	}
}
