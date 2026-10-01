package engine

import "core:math"
import "core:mem"
import "core:testing"

EPS :: f32(1e-5)

Submitted :: struct {
	mesh:  ^Mesh,
	model: Mat4,
	tint:  [4]f32,
}

Recorder :: struct {
	submits: [dynamic]Submitted,
}

// The table is never uploaded, so the tests need no sokol setup.
Frame_Fixture :: struct {
	fr:     Frame_Render,
	meshes: Mesh_Table,
	rec:    Recorder,
}

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
test_pairing_builds_its_capacity_of_draws_without_allocating :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	p: Pairing
	pairing_init(&p, mem.tracking_allocator(&track))
	defer pairing_destroy(&p)

	draws := make([]Draw, PAIRING_CAPACITY)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	after_init := track.total_allocation_count
	pairing_build(&p, draws)
	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect(t, !p.over_capacity_logged)
}

@(test)
test_pairing_logs_once_when_a_scene_has_more_draws_than_its_capacity :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, context.allocator)
	defer pairing_destroy(&p)

	draws := make([]Draw, PAIRING_CAPACITY + 1)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	pairing_build(&p, draws[:PAIRING_CAPACITY])
	testing.expect(t, !p.over_capacity_logged)
	pairing_build(&p, draws)
	testing.expect(t, p.over_capacity_logged)
	i, ok := pairing_find(&p, PAIRING_CAPACITY)
	testing.expect(t, ok)
	testing.expect_value(t, i, PAIRING_CAPACITY)
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
	testing.expect_value(t, c.eye, [3]f32{1, 8, 8})
	testing.expect_value(t, c.target, [3]f32{1, 0, 0})
	testing.expect_value(t, c.fov_y, 2)
}

record_submit :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params) {
	r := (^Recorder)(ctx)
	append(&r.submits, Submitted{mesh = mesh, model = vs_params.model, tint = fs_params.tint})
}

frame_fixture_init :: proc(f: ^Frame_Fixture) {
	frame_render_init(&f.fr, context.allocator)
	mesh_table_init(&f.meshes, context.allocator)
	f.rec.submits = make([dynamic]Submitted, context.allocator)
	f.fr.submit = record_submit
	f.fr.submit_ctx = &f.rec
}

frame_fixture_destroy :: proc(f: ^Frame_Fixture) {
	delete(f.rec.submits)
	mesh_table_destroy(&f.meshes)
	frame_render_destroy(&f.fr)
}

frame_fixture_draw :: proc(f: ^Frame_Fixture, prev, curr: Scene, alpha: f32) -> []Submitted {
	clear(&f.rec.submits)
	frame_render_draw(&f.fr, prev, curr, alpha, 1, &f.meshes)
	return f.rec.submits[:]
}

// The Frame render only reads, so a Scene may point at a slice roc_alloc never saw.
scene_of :: proc(draws: []Draw) -> Scene {
	return {draws = {elements = raw_data(draws), length = uint(len(draws))}}
}

expect_mat4_near :: proc(t: ^testing.T, got, want: Mat4, loc := #caller_location) {
	for c in 0 ..< 4 {
		for r in 0 ..< 4 {
			if abs(got[r, c] - want[r, c]) > EPS {
				testing.expectf(t, false, "got %v, want %v", got, want, loc = loc)
				return
			}
		}
	}
}

@(test)
test_frame_render_interpolates_a_draw_with_a_partner :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 1, mesh = 1, pos = {0, 0, 0}, scale = {1, 1, 1}, yaw = 0}}
	curr := []Draw{{id = 1, mesh = 1, pos = {4, 0, 0}, scale = {1, 1, 1}, yaw = 1}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.25)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}, yaw = 0.25}))
}

@(test)
test_frame_render_draws_a_draw_with_no_partner_at_itself :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 2, mesh = 1, pos = {9, 9, 9}, scale = {1, 1, 1}}}
	curr := []Draw{{id = 1, mesh = 1, pos = {4, 0, 0}, scale = {1, 1, 1}, yaw = 1}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.25)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {4, 0, 0}, scale = {1, 1, 1}, yaw = 1}))
}

@(test)
test_frame_render_draws_every_draw_at_itself_when_the_scenes_are_one :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = 1, pos = {1, 0, 0}, scale = {1, 1, 1}}, {id = 2, mesh = 2, pos = {0, 2, 0}, scale = {2, 2, 2}, yaw = 3}}
	scene := scene_of(draws)
	got := frame_fixture_draw(&f, scene, scene, 0.5)

	testing.expect_value(t, len(got), 2)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}}))
	expect_mat4_near(t, got[1].model, draw_model_matrix({position = {0, 2, 0}, scale = {2, 2, 2}, yaw = 3}))
}

@(test)
test_frame_render_submits_the_fallback_with_a_white_tint :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = 0, tint = {r = 1}}, {id = 2, mesh = u32(f.meshes.count), tint = {g = 1}}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)

	testing.expect_value(t, len(got), 2)
	for s in got {
		testing.expect(t, s.mesh == &f.meshes.meshes[Primitive.Fallback])
		testing.expect_value(t, s.tint, [4]f32{1, 1, 1, 1})
	}
}

@(test)
test_frame_render_submits_a_known_mesh_with_its_tint :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = u32(Primitive.Sphere), tint = {r = 0.2, g = 0.4, b = 0.6}}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)

	testing.expect_value(t, len(got), 1)
	testing.expect(t, got[0].mesh == &f.meshes.meshes[Primitive.Sphere])
	testing.expect_value(t, got[0].tint, [4]f32{0.2, 0.4, 0.6, 1})
}

@(test)
test_frame_render_pairs_a_shared_id_with_the_first_draw :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 5, mesh = 1, pos = {0, 0, 0}, scale = {1, 1, 1}}, {id = 5, mesh = 1, pos = {10, 0, 0}, scale = {1, 1, 1}}}
	curr := []Draw{{id = 5, mesh = 1, pos = {2, 0, 0}, scale = {1, 1, 1}}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.5)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}}))
}

@(test)
test_frame_render_camera_builds_the_matrix_from_the_interpolated_pose :: proc(t: ^testing.T) {
	prev := Scene{camera = {eye = {0, 8, 8}, target = {0, 0, 0}, fov_y = 1}}
	curr := Scene{camera = {eye = {2, 8, 8}, target = {2, 0, 0}, fov_y = 2}}
	got := frame_render_camera(prev, curr, 0.5, 16.0 / 9.0)
	want := scene_view_proj({eye = {1, 8, 8}, target = {1, 0, 0}, fov_y = 2}, 16.0 / 9.0)
	expect_mat4_near(t, got, want)
}
