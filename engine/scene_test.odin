package engine

import "core:math"
import "core:testing"

EPS :: f32(1e-5)

@(test)
test_yaw_takes_the_short_way_across_pi :: proc(t: ^testing.T) {
	testing.expect(t, abs(yaw_lerp(3.0, -3.0, 0.5) - math.PI) < EPS)
	testing.expect(t, abs(yaw_lerp(-3.0, 3.0, 0.5) + math.PI) < EPS)
}

@(test)
test_yaw_lerps_a_small_turn :: proc(t: ^testing.T) {
	testing.expect(t, abs(yaw_lerp(0, math.PI / 2, 0.5) - math.PI / 4) < EPS)
	testing.expect(t, abs(yaw_lerp(1, 2, 0) - 1) < EPS)
	testing.expect(t, abs(yaw_lerp(1, 2, 1) - 2) < EPS)
}

@(test)
test_yaw_ignores_whole_turns :: proc(t: ^testing.T) {
	testing.expect(t, abs(yaw_lerp(0.1, 0.1 + 4 * math.PI, 0.5) - 0.1) < 1e-4)
}

@(test)
test_pairing_finds_the_previous_draw_by_id :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, context.allocator)
	defer pairing_destroy(&p)

	pairing_build(&p, []Draw{{id = 7}, {id = 3}})
	i, ok := pairing_find(&p, 3)
	testing.expect(t, ok)
	testing.expect_value(t, i, 1)
	_, missing := pairing_find(&p, 9)
	testing.expect(t, !missing)

	pairing_build(&p, []Draw{{id = 9}})
	_, stale := pairing_find(&p, 7)
	testing.expect(t, !stale)
}

@(test)
test_pairing_keeps_the_first_of_a_duplicate_id_and_logs_it_once :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, context.allocator)
	defer pairing_destroy(&p)

	pairing_build(&p, []Draw{{id = 5}, {id = 5}, {id = 5}})
	pairing_build(&p, []Draw{{id = 5}, {id = 5}})
	i, _ := pairing_find(&p, 5)
	testing.expect_value(t, i, 0)
	testing.expect_value(t, len(p.logged), 1)
}

@(test)
test_draw_interpolates_pos_scale_yaw_and_takes_the_new_tint :: proc(t: ^testing.T) {
	prev := Draw{pos = {0, 0, 0}, scale = {1, 1, 1}, yaw = 0, tint = {1, 0, 0}}
	curr := Draw{pos = {2, 4, 6}, scale = {3, 1, 1}, yaw = 1, tint = {0, 1, 0}}
	x := draw_transform(prev, curr, 0.25)
	testing.expect_value(t, x.position, [3]f32{0.5, 1, 1.5})
	testing.expect_value(t, x.scale, [3]f32{1.5, 1, 1})
	testing.expect(t, abs(x.yaw - 0.25) < EPS)
}

@(test)
test_camera_interpolates_eye_and_target_and_takes_the_new_fov :: proc(t: ^testing.T) {
	prev := Scene_Camera{eye = {0, 8, 8}, target = {0, 0, 0}, fov_y = 1}
	curr := Scene_Camera{eye = {2, 8, 8}, target = {2, 0, 0}, fov_y = 2}
	c := camera_lerp(prev, curr, 0.5)
	testing.expect_value(t, c.eye, Vec3{1, 8, 8})
	testing.expect_value(t, c.target, Vec3{1, 0, 0})
	testing.expect_value(t, c.fov_y, 2)
}
