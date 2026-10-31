#+test
package engine

import "core:math"
import "core:testing"

UNIT_BOX :: Box{{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}}
WIDE_BOX :: Box{{-10, -1, -10}, {10, 1, 10}}

point_at :: proc(p: [3]f32, range: f32) -> Packed_Light {
	return {pos = {p.x, p.y, p.z, 1}, color = {1, 1, 1, range}}
}

dir_to :: proc(d: [3]f32) -> Packed_Light {
	return {pos = {d.x, d.y, d.z, 0}, color = {1, 1, 1, 0}}
}

@(test)
test_light_select_puts_the_directionals_first :: proc(t: ^testing.T) {
	directionals := []Packed_Light{dir_to({0, 1, 0}), dir_to({1, 0, 0})}
	points := []Packed_Light{point_at({1, 0, 0}, 4)}
	pos, color: [MAX_LIGHTS][4]f32
	dropped := light_select(directionals, points, UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, pos[1], [4]f32{1, 0, 0, 0})
	testing.expect_value(t, pos[2], [4]f32{1, 0, 0, 1})
	testing.expect_value(t, color[2], [4]f32{1, 1, 1, 4})
	testing.expect_value(t, color[3], [4]f32{})
	testing.expect(t, !dropped)
}

@(test)
test_light_select_orders_the_points_nearest_first :: proc(t: ^testing.T) {
	points := []Packed_Light{point_at({5, 0, 0}, 10), point_at({1.5, 0, 0}, 10), point_at({3, 0, 0}, 10)}
	pos, color: [MAX_LIGHTS][4]f32
	light_select(nil, points, UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos[0].x, 1.5)
	testing.expect_value(t, pos[1].x, 3)
	testing.expect_value(t, pos[2].x, 5)
	testing.expect_value(t, color[3], [4]f32{})
}

@(test)
test_light_select_skips_a_point_whose_range_does_not_reach_the_box :: proc(t: ^testing.T) {
	for range, i in ([3]f32{2, 3, 3.01}) {
		pos, color: [MAX_LIGHTS][4]f32
		light_select(nil, {point_at({3.5, 0, 0}, range)}, UNIT_BOX, &pos, &color)
		// The point is 3 units from the box, so a range of exactly 3 does not reach.
		testing.expectf(t, (color[0].w != 0) == (i == 2), "range %v gave slot 0 %v", range, color[0])
	}
}

@(test)
test_light_select_tests_the_range_against_the_box_not_the_centre :: proc(t: ^testing.T) {
	pos, color: [MAX_LIGHTS][4]f32
	light_select(nil, {point_at({11, 0, 0}, 2)}, WIDE_BOX, &pos, &color)
	testing.expect_value(t, pos[0], [4]f32{11, 0, 0, 1})
}

@(test)
test_light_select_keeps_the_nearest_8_and_reports_the_drop :: proc(t: ^testing.T) {
	points: [10]Packed_Light
	for &p, i in points {
		p = point_at({f32(10 - i), 0, 0}, 20)
	}
	pos, color: [MAX_LIGHTS][4]f32
	dropped := light_select(nil, points[:], UNIT_BOX, &pos, &color)
	for i in 0 ..< MAX_LIGHTS {
		testing.expect_value(t, pos[i].x, f32(i + 1))
	}
	testing.expect(t, dropped)
}

@(test)
test_light_select_gives_the_directionals_their_slots_before_the_points :: proc(t: ^testing.T) {
	directionals := []Packed_Light{dir_to({0, 1, 0}), dir_to({1, 0, 0}), dir_to({0, 0, 1})}
	points: [7]Packed_Light
	for &p, i in points {
		p = point_at({f32(7 - i), 0, 0}, 20)
	}
	pos, color: [MAX_LIGHTS][4]f32
	dropped := light_select(directionals, points[:], UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos[2], [4]f32{0, 0, 1, 0})
	for i in 3 ..< MAX_LIGHTS {
		testing.expect_value(t, pos[i], [4]f32{f32(i - 2), 0, 0, 1})
	}
	testing.expect(t, dropped)
}

@(test)
test_light_select_keeps_the_first_8_directionals :: proc(t: ^testing.T) {
	directionals: [9]Packed_Light
	for &d, i in directionals {
		d = dir_to({f32(i), 1, 0})
	}
	pos, color: [MAX_LIGHTS][4]f32
	dropped := light_select(directionals[:], {point_at({0, 0, 0}, 1)}, UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos[7], [4]f32{7, 1, 0, 0})
	testing.expect(t, dropped)
}

@(test)
test_light_select_orders_lights_inside_a_large_box_by_the_centre :: proc(t: ^testing.T) {
	points := []Packed_Light{point_at({8, 0, 0}, 1), point_at({2, 0, 0}, 1), point_at({5, 0, 0}, 1)}
	pos, color: [MAX_LIGHTS][4]f32
	light_select(nil, points, WIDE_BOX, &pos, &color)
	testing.expect_value(t, pos[0].x, 2)
	testing.expect_value(t, pos[1].x, 5)
	testing.expect_value(t, pos[2].x, 8)
}

@(test)
test_light_select_keeps_walk_order_on_a_tie :: proc(t: ^testing.T) {
	points := []Packed_Light{point_at({2, 0, 0}, 10), point_at({0, 0, 2}, 10)}
	pos, color: [MAX_LIGHTS][4]f32
	light_select(nil, points, UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos[0], [4]f32{2, 0, 0, 1})
	testing.expect_value(t, pos[1], [4]f32{0, 0, 2, 1})
}

@(test)
test_light_select_with_no_lights_writes_zeros :: proc(t: ^testing.T) {
	pos, color: [MAX_LIGHTS][4]f32
	dropped := light_select(nil, nil, UNIT_BOX, &pos, &color)
	testing.expect_value(t, pos, [MAX_LIGHTS][4]f32{})
	testing.expect_value(t, color, [MAX_LIGHTS][4]f32{})
	testing.expect(t, !dropped)
}

@(test)
test_box_transform_turns_scales_and_moves_the_box :: proc(t: ^testing.T) {
	m := mat4_translate({10, 0, 0}) * mat4_from_quat(quat_from_axis_angle(UP, math.PI / 2)) * mat4_scale({2, 1, 1})
	got := box_transform(UNIT_BOX, m)
	want := Box{{9.5, -0.5, -1}, {10.5, 0.5, 1}}
	for i in 0 ..< 3 {
		testing.expectf(t, abs(got.min[i] - want.min[i]) < EPS && abs(got.max[i] - want.max[i]) < EPS, "got %v, want %v", got, want)
	}
}

@(test)
test_box_distance_sq_is_zero_inside_and_squared_outside :: proc(t: ^testing.T) {
	testing.expect_value(t, box_distance_sq(UNIT_BOX, {0, 0, 0}), 0)
	testing.expect_value(t, box_distance_sq(UNIT_BOX, {2, 0, 0}), 2.25)
	testing.expect_value(t, box_distance_sq(UNIT_BOX, {1.5, 1.5, 0}), 2)
}
