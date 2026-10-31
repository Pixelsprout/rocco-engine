#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:testing"

CASCADE_ASPECT :: f32(16.0 / 9)
CASCADE_CAMERA :: Camera_Pose {
	eye    = {0, 2, 0},
	target = {0, 2, -1},
	up     = UP,
	fov_y  = 1.047,
}

@(test)
test_cascade_splits_with_one_cascade_end_at_the_far_distance :: proc(t: ^testing.T) {
	testing.expect_value(t, cascade_splits(0.1, 150, 1, 0.5)[0], 150)
}

@(test)
test_cascade_splits_mix_log_and_linear_half_and_half :: proc(t: ^testing.T) {
	got := cascade_splits(0.1, 150, 4, 0.5)
	want := [4]f32{19.0987, 39.4615, 68.3139, 150}
	for i in 0 ..< 4 {
		testing.expectf(t, abs(got[i] - want[i]) < 1e-3, "split %v is %v, want %v", i, got[i], want[i])
	}
}

@(test)
test_cascade_splits_weight_0_is_linear_and_1_is_log :: proc(t: ^testing.T) {
	linear := cascade_splits(1, 100, 2, 0)
	testing.expectf(t, abs(linear[0] - 50.5) < 1e-3 && linear[1] == 100, "linear splits %v", linear)
	log := cascade_splits(1, 100, 2, 1)
	testing.expectf(t, abs(log[0] - 10) < 1e-3 && log[1] == 100, "log splits %v", log)
}

@(test)
test_cascade_splits_rise_and_end_exactly_at_far :: proc(t: ^testing.T) {
	for count in 1 ..= MAX_CASCADES {
		splits := cascade_splits(0.1, 150, count, 0.5)
		for i in 1 ..< count {
			testing.expectf(t, splits[i] > splits[i - 1], "%v cascades: split %v is %v after %v", count, i, splits[i], splits[i - 1])
		}
		for i in count - 1 ..< MAX_CASCADES {
			testing.expectf(t, splits[i] == 150, "%v cascades: split %v is %v", count, i, splits[i])
		}
	}
}

@(test)
test_cascade_slice_near_reaches_back_over_the_blend_band :: proc(t: ^testing.T) {
	splits := cascade_splits(0.1, 150, 4, 0.5)
	testing.expect_value(t, cascade_slice_near(splits, 0.1, 0), 0.1)
	testing.expect_value(t, cascade_slice_near(splits, 0.1, 1), splits[0] - CASCADE_BLEND * splits[0])
	testing.expect_value(t, cascade_slice_near(splits, 0.1, 2), splits[1] - CASCADE_BLEND * (splits[1] - splits[0]))
	testing.expect_value(t, cascade_slice_near(splits, 0.1, 3), splits[2] - CASCADE_BLEND * (splits[2] - splits[1]))
}

@(test)
test_cascade_sphere_holds_its_slice_and_the_blend_band :: proc(t: ^testing.T) {
	splits := cascade_splits(0.1, 150, 4, 0.5)
	spheres: [4]Cascade_Sphere
	for i in 0 ..< 4 {
		near := cascade_slice_near(splits, 0.1, i)
		spheres[i] = cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, near, splits[i])
		expect_slice_in_sphere(t, CASCADE_CAMERA, CASCADE_ASPECT, near, splits[i], spheres[i])
	}
	for i in 0 ..< 3 {
		band_far := splits[i]
		band_near := band_far - CASCADE_BLEND * (band_far - (splits[i - 1] if i > 0 else 0))
		expect_slice_in_sphere(t, CASCADE_CAMERA, CASCADE_ASPECT, band_near, band_far, spheres[i])
		expect_slice_in_sphere(t, CASCADE_CAMERA, CASCADE_ASPECT, band_near, band_far, spheres[i + 1])
	}
}

@(test)
test_cascade_sphere_radius_ignores_where_the_camera_looks :: proc(t: ^testing.T) {
	turned := Camera_Pose {
		eye    = {40, 7, -12},
		target = {41, 6, -14},
		up     = UP,
		fov_y  = CASCADE_CAMERA.fov_y,
	}
	splits := cascade_splits(0.1, 150, 4, 0.5)
	for i in 0 ..< 4 {
		near := cascade_slice_near(splits, 0.1, i)
		a := cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, near, splits[i])
		b := cascade_sphere(turned, CASCADE_ASPECT, near, splits[i])
		testing.expect_value(t, b.radius, a.radius)
		steps := a.radius / CASCADE_RADIUS_STEP
		testing.expectf(t, steps == math.floor(steps), "radius %v is not a whole number of steps", a.radius)
	}
}

@(test)
test_cascade_view_moves_in_whole_texels :: proc(t: ^testing.T) {
	light_view := light_view_of(v3_normalize({0.4, 0.8, 0.45}))
	splits := cascade_splits(0.1, 150, 4, 0.5)
	moved := CASCADE_CAMERA
	moved.eye += {0.137, 0, 0.071}
	moved.target += {0.137, 0, 0.071}
	a := cascade_view(light_view, cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, 0.1, splits[0]), 2048, nil)
	b := cascade_view(light_view, cascade_sphere(moved, CASCADE_ASPECT, 0.1, splits[0]), 2048, nil)

	texel := (a.hi.x - a.lo.x) / 2048
	testing.expect_value(t, b.hi.x - b.lo.x, a.hi.x - a.lo.x)
	testing.expect_value(t, b.hi.y - b.lo.y, a.hi.y - a.lo.y)
	for d in ([2]f32{(b.lo.x - a.lo.x) / texel, (b.lo.y - a.lo.y) / texel}) {
		testing.expectf(t, abs(d - math.round(d)) < 1e-3, "the view moved %v texels", d)
	}
	testing.expectf(t, b.lo != a.lo, "the view did not move")
}

// After the snap, the map is still at least one texel wider than the sphere
// on each side, so the 3 x 3 taps stay inside it.
@(test)
test_cascade_view_holds_its_sphere_with_a_texel_to_spare :: proc(t: ^testing.T) {
	light_view := light_view_of(v3_normalize({0.4, 0.8, 0.45}))
	sphere := cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, 0.1, 19)
	view := cascade_view(light_view, sphere, 2048, nil)
	texel := (view.hi.x - view.lo.x) / 2048
	c := (light_view * [4]f32{sphere.center.x, sphere.center.y, sphere.center.z, 1}).xyz
	testing.expect(t, view.lo.x <= c.x - sphere.radius - texel + 1e-3 && view.hi.x >= c.x + sphere.radius + texel - 1e-3)
	testing.expect(t, view.lo.y <= c.y - sphere.radius - texel + 1e-3 && view.hi.y >= c.y + sphere.radius + texel - 1e-3)
	testing.expect(t, view.lo.z <= c.z - sphere.radius && view.hi.z >= c.z + sphere.radius)
}

@(test)
test_cascade_view_reaches_a_caster_toward_the_sun :: proc(t: ^testing.T) {
	light_view := light_view_of({0, 1, 0})
	mesh := Mesh {
		box = {{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}},
	}
	model := mat4_translate({0, 60, -5})
	placed := []Placed{{mesh = &mesh, model = model, light_box = light_box(light_view, model, mesh.box)}}
	splits := cascade_splits(0.1, 150, 4, 0.5)
	view := cascade_view(light_view, cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, 0.1, splits[0]), 2048, placed)

	testing.expectf(t, placed[0].light_box.max.z <= view.hi.z && placed[0].light_box.min.z >= view.lo.z, "caster %v, view %v to %v", placed[0].light_box, view.lo.z, view.hi.z)
}

@(test)
test_cascade_covers_only_the_boxes_over_its_square :: proc(t: ^testing.T) {
	light_view := light_view_of({0, 1, 0})
	splits := cascade_splits(0.1, 150, 4, 0.5)
	view := cascade_view(light_view, cascade_sphere(CASCADE_CAMERA, CASCADE_ASPECT, 0.1, splits[0]), 2048, nil)
	unit := Box{{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}}

	testing.expect(t, cascade_covers(view, light_box(light_view, mat4_translate({0, 0, -5}), unit)))
	testing.expect(t, !cascade_covers(view, light_box(light_view, mat4_translate({500, 0, 0}), unit)))
	touching := Box {
		min = {view.hi.x, view.lo.y, 0},
		max = {view.hi.x + 1, view.lo.y + 1, 1},
	}
	testing.expect(t, cascade_covers(view, touching))
}

@(test)
test_shadow_view_proj_is_unchanged_by_the_helpers :: proc(t: ^testing.T) {
	cube := Mesh {
		box = {{-0.5, -0.5, -0.5}, {0.5, 0.5, 0.5}},
	}
	sphere := Mesh {
		box = {{-0.3, -0.4, -0.2}, {0.6, 0.5, 0.7}},
	}
	placed := []Placed {
		{mesh = &cube, model = draw_model_matrix({position = {1.3, 0.2, -4}, scale = {2, 1, 1}, rotation = quat_from_axis_angle(UP, 0.7), scale_rotation = 1})},
		{mesh = &sphere, model = draw_model_matrix({position = {-6, 3, 2.5}, scale = {1, 3, 1}, rotation = quat_from_axis_angle({1, 0, 0}, 0.3), scale_rotation = 1})},
	}
	for to_light in ([][3]f32{v3_normalize({0.4, 0.8, 0.45}), {0, 1, 0}}) {
		testing.expect_value(t, shadow_view_proj(to_light, placed), shadow_view_proj_before_cascades(to_light, placed))
	}
}

// shadow_view_proj as it was before the cascade helpers, kept to check the
// refactor bit for bit.
shadow_view_proj_before_cascades :: proc(to_light: [3]f32, placed: []Placed) -> Mat4 {
	up := UP if abs(to_light.y) < 0.99 else [3]f32{0, 0, 1}
	light_view := mat4_look_at({}, -to_light, up)
	lo := [3]f32{max(f32), max(f32), max(f32)}
	hi := -lo
	for p in placed {
		to_view := light_view * p.model
		for corner in 0 ..< 8 {
			c := [3]f32 {
				p.mesh.box.max.x if corner & 1 != 0 else p.mesh.box.min.x,
				p.mesh.box.max.y if corner & 2 != 0 else p.mesh.box.min.y,
				p.mesh.box.max.z if corner & 4 != 0 else p.mesh.box.min.z,
			}
			v := (to_view * [4]f32{c.x, c.y, c.z, 1}).xyz
			lo = linalg.min(lo, v)
			hi = linalg.max(hi, v)
		}
	}
	lo = linalg.floor(lo / SHADOW_GRID) * SHADOW_GRID
	hi = linalg.max(linalg.ceil(hi / SHADOW_GRID) * SHADOW_GRID, lo + SHADOW_GRID)
	return mat4_ortho_reversed(lo.x, hi.x, lo.y, hi.y, -hi.z, -lo.z) * light_view
}

// The 8 corners of the camera's view between the depths near and far.
expect_slice_in_sphere :: proc(t: ^testing.T, camera: Camera_Pose, aspect, near, far: f32, s: Cascade_Sphere, loc := #caller_location) {
	forward := v3_normalize(camera.target - camera.eye)
	right := v3_normalize(v3_cross(forward, camera.up))
	up := v3_cross(right, forward)
	half_y := math.tan(camera.fov_y / 2)
	half_x := half_y * aspect
	for depth in ([2]f32{near, far}) {
		for corner in 0 ..< 4 {
			x := half_x if corner & 1 != 0 else -half_x
			y := half_y if corner & 2 != 0 else -half_y
			p := camera.eye + depth * (forward + x * right + y * up)
			d := v3_length(p - s.center)
			testing.expectf(t, d <= s.radius + 1e-3, "corner at depth %v is %v from the centre, radius %v", depth, d, s.radius, loc = loc)
		}
	}
}
