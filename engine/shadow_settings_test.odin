#+test
package engine

import "core:math"
import "core:testing"

@(test)
test_shadow_rejects_nonfinite_and_out_of_range_fields :: proc(t: ^testing.T) {
	for bad in ([]f32{math.nan_f32(), math.inf_f32(1), math.inf_f32(-1), -1, 1e7}) {
		requested := Shadow{distance = bad, normal_bias = bad, depth_bias = bad, distribution = bad, blend = bad, filter = .Pcf3}
		logged: bit_set[Shadow_Field]
		got := shadow_clamp(requested, &logged)
		testing.expect_value(t, got, shadow_default())
		testing.expect_value(t, card(logged), 5)
	}
}

@(test)
test_shadow_preserves_finite_boundaries :: proc(t: ^testing.T) {
	for requested in ([]Shadow{
		{distance = 0, normal_bias = 0, depth_bias = 0, distribution = 0, blend = 0, filter = .Hard},
		{distance = SHADOW_DISTANCE_MAX, normal_bias = 10, depth_bias = 0.1, distribution = 1, blend = 0.5, filter = .Pcf5},
	}) {
		logged: bit_set[Shadow_Field]
		testing.expect_value(t, shadow_clamp(requested, &logged), requested)
		testing.expect_value(t, card(logged), 0)
	}
	for distance in ([]f32{0.01, SCENE_NEAR}) {
		s := shadow_default()
		s.distance = distance
		logged: bit_set[Shadow_Field]
		testing.expect_value(t, shadow_clamp(s, &logged).distance, 0)
	}
}

@(test)
test_shadow_default_preserves_single_and_multiple_cascade_distances :: proc(t: ^testing.T) {
	s := shadow_default()
	testing.expect_value(t, shadow_distance(s, 1), 0)
	for count in 2 ..= MAX_CASCADES {
		testing.expect_value(t, shadow_distance(s, count), SHADOW_DISTANCE)
	}
	s.distance = 80
	for count in 1 ..= MAX_CASCADES {
		testing.expect_value(t, shadow_distance(s, count), 80)
	}
}

@(test)
test_shadow_filter_padding_and_blend_cover_valid_combinations :: proc(t: ^testing.T) {
	for count in 1 ..= MAX_CASCADES {
		for blend in ([]f32{0, 1e-12, 0.1, 0.5}) {
			for weight in ([]f32{0, 0.5, 1}) {
				splits := cascade_splits(SCENE_NEAR, 80, count, weight)
				for i in 0 ..< count {
					near := cascade_slice_near(splits, SCENE_NEAR, i, blend)
					sphere := cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, near, splits[i])
					for filter in ([]Shadow_Filter{.Hard, .Pcf3, .Pcf5}) {
						view := cascade_view(light_view_of({0, 1, 0}), sphere, SHADOW_MAP_MIN, nil, shadow_filter_radius(filter))
						testing.expect(t, view.hi.x > view.lo.x && view.hi.y > view.lo.y)
						testing.expect(t, !math.is_nan(view.view_proj[0, 0]) && !math.is_inf(view.view_proj[0, 0]))
					}
				}
			}
		}
	}
}

@(test)
test_launch_shadow_bounds_and_device_limits :: proc(t: ^testing.T) {
	launch := launch_default()
	for size in ([]u32{1, SHADOW_MAP_MIN - 1, SHADOW_MAP_MAX + 1, max(u32)}) {
		launch.shadow_map = size
		field, _, ok := launch_check(launch)
		testing.expect(t, !ok)
		testing.expect_value(t, field, "shadow_map")
	}
	for size in ([]u32{SHADOW_MAP_MIN, SHADOW_MAP_MAX}) {
		launch.shadow_map = size
		_, _, ok := launch_check(launch)
		testing.expect(t, ok)
	}
	launch = launch_default()
	_, _, ok := launch_device_check(launch, 2048, 1)
	testing.expect(t, ok)
	_, _, size_ok := launch_device_check(launch, 1024, 4)
	testing.expect(t, !size_ok)
	launch.shadow_cascades = 4
	_, _, layers_ok := launch_device_check(launch, 4096, 2)
	testing.expect(t, !layers_ok)
}

@(test)
test_shadow_live_controls_reach_current_frame_without_reallocation :: proc(t: ^testing.T) {
	for count in ([]int{1, 4}) {
		f: Frame_Fixture
		frame_fixture_init(&f, cascades = count)
		prev := scene_lit({{id = 1, mesh = u32(Primitive.Cube), pos = {0, 0, -5}, scale = {1, 1, 1}, rot = IDENTITY}}, {light_sun({0, -1, 0}, {1, 1, 1})})
		curr := prev
		curr.shadow = {distance = 80, normal_bias = 0.12, depth_bias = 0.002, distribution = 1, blend = 0, filter = .Pcf5}
		frame_fixture_draw(&f, prev, curr, 0)
		testing.expect_value(t, f.rec.lights.shadow, [4]f32{f32(count), 0, 0.12, 0})
		testing.expect_value(t, f.rec.lights.camera_pos.w, 0.002)
		testing.expect_value(t, f.rec.lights.fog_color.w, 2)
		testing.expect_value(t, f.rec.lights.view_dir.w, 80)
		testing.expect_value(t, f.rec.lights.cascade_far, cascade_splits(SCENE_NEAR, 80, count, 1))
		testing.expect_value(t, f.fr.cascades, count)
		testing.expect_value(t, f.fr.shadow_map, 2048)
		testing.expect_value(t, len(f.rec.passes), count + 2)
		curr.shadow.distance = 40
		curr.shadow.filter = .Hard
		frame_fixture_draw(&f, prev, curr, 0)
		testing.expect_value(t, f.rec.lights.cascade_far[count - 1], 40)
		testing.expect_value(t, f.rec.lights.fog_color.w, 0)
		testing.expect_value(t, f.fr.cascades, count)
		testing.expect_value(t, f.fr.shadow_map, 2048)
		frame_fixture_destroy(&f)
	}
}

@(test)
test_shadow_rejects_invalid_filter_and_keeps_valid_fields :: proc(t: ^testing.T) {
	requested := shadow_default()
	requested.distance = 75
	requested.filter = Shadow_Filter(255)
	logged: bit_set[Shadow_Field]
	got := shadow_clamp(requested, &logged)
	testing.expect_value(t, got.distance, 75)
	testing.expect_value(t, got.filter, Shadow_Filter.Pcf3)
	testing.expect_value(t, logged, bit_set[Shadow_Field]{.Filter})
}
