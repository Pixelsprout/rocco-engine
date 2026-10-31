#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import "core:testing"

EPS :: f32(1e-5)
IDENTITY :: Quat{w = 1}
// Above the Draw count of every fixture Scene except the capacity tests.
SMALL_DRAWS :: 8
// Above the Group count of every fixture Scene except the capacity tests.
SMALL_GROUPS :: 4

// joints holds the first skin matrices of a skinned Draw, as they were at the submit.
Submitted :: struct {
	mesh:         ^Mesh,
	model:        Mat4,
	normal_model: Mat4,
	tint:         [4]f32,
	material:     [4]f32,
	emissive:     [4]f32,
	glow:         [4]f32,
	light_pos:    [MAX_LIGHTS][4]f32,
	light_color:  [MAX_LIGHTS][4]f32,
	skinned:      bool,
	joints:       [2]Mat4,
}

// main_before is the number of main pass submits before this shadow submit.
Shadow_Submitted :: struct {
	mesh:        ^Mesh,
	light_mvp:   Mat4,
	view:        int,
	main_before: int,
	skinned:     bool,
	joints:      [2]Mat4,
}

Pass_Begun :: struct {
	pass: Pass,
	view: int,
}

// sky_after is the number of submits before the sky.
Recorder :: struct {
	passes:        [dynamic]Pass_Begun,
	pass_ends:     int,
	shadows:       [dynamic]Shadow_Submitted,
	submits:       [dynamic]Submitted,
	lights:        Fs_Lights,
	lights_calls:  int,
	sky:           ^Sky,
	sky_view_proj: Mat4,
	sky_calls:     int,
	sky_after:     int,
	ui_quads:      [dynamic]Ui_Quad,
	ui_screen:     [2]f32,
	ui_calls:      int,
	ui_after_sky:  int,
	main_clear:    Rgb,
}

// The table is never uploaded, so the tests need no sokol setup. ui is nil
// unless frame_fixture_init_ui ran.
Frame_Fixture :: struct {
	fr:     Frame_Render,
	meshes: Mesh_Table,
	skies:  Sky_Table,
	rec:    Recorder,
	ui:     ^Ui,
	window: Ui_Window,
}

@(test)
test_pairing_finds_the_previous_draw_by_id :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	nodes := draw_nodes({{id = 7}, {id = 3}})
	pairing_build(&p, nodes)
	found, _, ok := pairing_draw(&p, 3, {})
	testing.expect(t, ok && found == &nodes[1].payload.draw)
	_, _, missing := pairing_draw(&p, 9, {})
	testing.expect(t, !missing)

	pairing_build(&p, draw_nodes({{id = 9}}))
	_, _, stale := pairing_draw(&p, 7, {})
	testing.expect(t, !stale)
}

@(test)
test_pairing_keeps_the_first_of_a_duplicate_id_and_logs_it_once :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	nodes := draw_nodes({{id = 5}, {id = 5}, {id = 5}})
	pairing_build(&p, nodes)
	pairing_build(&p, draw_nodes({{id = 5}, {id = 5}}))
	pairing_build(&p, nodes)
	first, _, _ := pairing_draw(&p, 5, {})
	testing.expect(t, first == &nodes[0].payload.draw)
	testing.expect_value(t, len(p.logged), 1)
}

@(test)
test_pairing_builds_its_capacity_of_draws_and_groups_without_allocating :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, mem.tracking_allocator(&track))
	defer pairing_destroy(&p)

	draws := make([]Draw, SMALL_DRAWS)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	groups := make([]Node, SMALL_GROUPS + 1)
	defer delete(groups)
	groups[0] = node_group(100, {}, IDENTITY, draw_nodes(draws))
	for i in 1 ..< len(groups) {
		groups[i] = node_group(u64(100 + i), {}, IDENTITY, nil)
	}
	after_init := track.total_allocation_count
	pairing_build(&p, groups[:SMALL_GROUPS])
	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect(t, !p.over_capacity_logged)
	testing.expect_value(t, len(p.groups), SMALL_GROUPS)

	// Past group_capacity the first Groups pair, and the map does not grow.
	pairing_build(&p, groups)
	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect_value(t, len(p.groups), SMALL_GROUPS)
	testing.expect(t, pairing_group(&p, 100 + SMALL_GROUPS) == nil)
	testing.expect(t, p.groups_full_logged)
}

@(test)
test_pairing_logs_once_when_a_scene_has_more_draws_than_its_capacity :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	draws := make([]Draw, SMALL_DRAWS + 1)
	defer delete(draws)
	for &d, i in draws {
		d.id = u64(i)
	}
	pairing_build(&p, draw_nodes(draws[:SMALL_DRAWS]))
	testing.expect(t, !p.over_capacity_logged)
	nodes := draw_nodes(draws)
	pairing_build(&p, nodes)
	testing.expect(t, p.over_capacity_logged)
	found, _, ok := pairing_draw(&p, SMALL_DRAWS, {})
	testing.expect(t, ok && found == &nodes[SMALL_DRAWS].payload.draw)
}

@(test)
test_pairing_keeps_the_first_of_a_duplicate_group_id_and_logs_once :: proc(t: ^testing.T) {
	p: Pairing
	pairing_init(&p, SMALL_DRAWS, SMALL_GROUPS, context.allocator)
	defer pairing_destroy(&p)

	inner := []Node{node_group(5, {x = 2}, IDENTITY, nil)}
	nodes := []Node{node_group(5, {x = 1}, IDENTITY, inner), node_group(5, {x = 3}, IDENTITY, nil), node_group(6, {}, IDENTITY, nil), node_group(6, {}, IDENTITY, nil)}
	pairing_build(&p, nodes)
	testing.expect_value(t, pairing_group(&p, 5).local.pos, [3]f32{1, 0, 0})
	testing.expect(t, p.group_duplicate_logged)
}

@(test)
test_draw_interpolates_pos_scale_and_rot :: proc(t: ^testing.T) {
	prev := Draw{pos = {0, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}
	curr := Draw{pos = {2, 4, 6}, scale = {3, 1, 1}, rot = quat_yaw(1)}
	x := draw_transform_at_root(&prev, &curr, 0.25)
	testing.expect_value(t, x.position, [3]f32{0.5, 1, 1.5})
	testing.expect_value(t, x.scale, [3]f32{1.5, 1, 1})
	expect_quat_near(t, x.rotation, quat_from_axis_angle(UP, 0.25))
}

// q and -q are one orientation, so the slerp does not turn the long way round.
@(test)
test_draw_rot_stays_put_between_a_quaternion_and_its_negation :: proc(t: ^testing.T) {
	prev := Draw{rot = IDENTITY}
	curr := Draw{rot = {w = -1}}
	x := draw_transform_at_root(&prev, &curr, 0.5)
	expect_quat_near(t, x.rotation, 1)
}

@(test)
test_draw_interpolates_scale_rot :: proc(t: ^testing.T) {
	prev := Draw{rot = IDENTITY, scale_rot = IDENTITY}
	curr := Draw{rot = IDENTITY, scale_rot = quat_yaw(1)}
	x := draw_transform_at_root(&prev, &curr, 0.25)
	expect_quat_near(t, x.scale_rotation, quat_from_axis_angle(UP, 0.25))
}

@(test)
test_draw_blends_the_pose_with_its_partner :: proc(t: ^testing.T) {
	prev := Draw{rot = IDENTITY, scale_rot = IDENTITY, pose = {clip = 1, time = 0.2, fade_clip = 2, fade_time = 0.1, fade = 0.25}}
	curr := Draw{rot = IDENTITY, scale_rot = IDENTITY, pose = {clip = 1, time = 0.4, fade_clip = 2, fade_time = 0.3, fade = 0.5}}
	x := draw_transform_at_root(&prev, &curr, 0.5)
	want := Draw_Pose{clip = 1, time = 0.3, fade_clip = 2, fade_time = 0.2, fade = 0.375}
	testing.expectf(t, draw_pose_near(x.pose, want), "got %v, want %v", x.pose, want)
}

// A root Draw paired with prev, as the Frame's walk places it.
draw_transform_at_root :: proc(prev, curr: ^Draw, alpha: f32) -> Draw_Transform {
	paired := Prev_Pose {
		local = pose_of(prev.pos, prev.rot),
		world = pose_of(prev.pos, prev.rot),
	}
	root := WALK_ROOT
	world := node_world(&paired, &root, pose_of(curr.pos, curr.rot), alpha)
	return draw_transform(prev, curr, world, alpha)
}

@(test)
test_draw_scale_acts_along_the_scale_rot_axes :: proc(t: ^testing.T) {
	m := draw_model_matrix({scale = {1, 1, 2}, rotation = 1, scale_rotation = quat_from_axis_angle(UP, math.PI / 2)})
	expect_v4_near(t, m * [4]f32{1, 0, 0, 0}, {2, 0, 0, 0})
	expect_v4_near(t, m * [4]f32{0, 0, 1, 0}, {0, 0, 1, 0})
}

@(test)
test_draw_scales_before_rot :: proc(t: ^testing.T) {
	m := draw_model_matrix({position = {1, 2, 3}, scale = {2, 1, 1}, rotation = quat_from_axis_angle(UP, math.PI / 2), scale_rotation = 1})
	expect_v4_near(t, m * [4]f32{1, 0, 0, 1}, {1, 2, 1, 1})
}

@(test)
test_draw_normal_matrix_is_the_inverse_transpose_of_the_model :: proc(t: ^testing.T) {
	x := Draw_Transform{
		position       = {3, 4, 5},
		scale          = {1, 2, 4},
		rotation       = quat_from_axis_angle(UP, 0.7),
		scale_rotation = quat_from_axis_angle({1, 0, 0}, 0.4),
	}
	linear := draw_model_matrix(x)
	linear[0, 3], linear[1, 3], linear[2, 3] = 0, 0, 0
	expect_mat4_near(t, linalg.transpose(draw_normal_matrix(x)) * linear, mat4_identity())
}

// A zero scale flattens the mesh. Its normals must stay finite.
@(test)
test_draw_normal_matrix_stays_finite_for_a_zero_scale :: proc(t: ^testing.T) {
	n := draw_normal_matrix({scale = {1, 0, 1}, rotation = 1, scale_rotation = 1})
	for c in 0 ..< 4 {
		for r in 0 ..< 4 {
			// x - x is 0 only for a finite x.
			testing.expect_value(t, n[r, c] - n[r, c], 0)
		}
	}
}

@(test)
test_frame_render_submits_the_normal_matrix :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	draws := []Draw{{id = 1, mesh = 1, scale = {1, 3, 1}, rot = quat_yaw(1), scale_rot = IDENTITY}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	want := draw_normal_matrix({scale = {1, 3, 1}, rotation = quat_from_axis_angle(UP, 1), scale_rotation = 1})
	expect_mat4_near(t, got[0].normal_model, want)
}

@(test)
test_camera_interpolates_eye_target_and_up_and_takes_the_new_fov :: proc(t: ^testing.T) {
	prev := Scene_Camera{eye = {0, 8, 8}, target = {0, 0, 0}, up = {0, 1, 0}, fov_y = 1}
	curr := Scene_Camera{eye = {2, 8, 8}, target = {2, 0, 0}, up = {1, 0, 0}, fov_y = 2}
	c := camera_lerp(prev, curr, 0.5)
	testing.expect_value(t, c.eye, [3]f32{1, 8, 8})
	testing.expect_value(t, c.target, [3]f32{1, 0, 0})
	testing.expect(t, v3_length(c.up - {math.SQRT_TWO / 2, math.SQRT_TWO / 2, 0}) < EPS)
	testing.expect_value(t, c.fov_y, 2)
}

record_submit :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {
	r := (^Recorder)(ctx)
	append(
		&r.submits,
		Submitted {
			mesh = mesh,
			model = vs_params.model,
			normal_model = vs_params.normal_model,
			tint = fs_params.tint,
			material = fs_params.material,
			emissive = fs_params.emissive,
			glow = fs_params.glow,
			light_pos = fs_params.light_pos,
			light_color = fs_params.light_color,
			skinned = skin != nil,
			joints = {skin.joints[0], skin.joints[1]} if skin != nil else {},
		},
	)
}

record_lights :: proc(ctx: rawptr, lights: Fs_Lights) {
	r := (^Recorder)(ctx)
	r.lights = lights
	r.lights_calls += 1
}

record_sky :: proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {
	r := (^Recorder)(ctx)
	r.sky = sky
	r.sky_view_proj = vs_params.view_proj
	r.sky_calls += 1
	r.sky_after = len(r.submits)
}

record_ui :: proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {
	r := (^Recorder)(ctx)
	append(&r.ui_quads, ..quads)
	r.ui_screen = screen
	r.ui_calls += 1
	r.ui_after_sky = r.sky_calls
}

record_begin_pass :: proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb) {
	r := (^Recorder)(ctx)
	append(&r.passes, Pass_Begun{pass, view})
	if pass == .Main {
		r.main_clear = clear_colour
	}
}

record_end_pass :: proc(ctx: rawptr) {
	r := (^Recorder)(ctx)
	r.pass_ends += 1
}

record_shadow :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {
	r := (^Recorder)(ctx)
	append(
		&r.shadows,
		Shadow_Submitted {
			mesh = mesh,
			light_mvp = vs_params.light_mvp,
			view = r.passes[len(r.passes) - 1].view,
			main_before = len(r.submits),
			skinned = skin != nil,
			joints = {skin.joints[0], skin.joints[1]} if skin != nil else {},
		},
	)
}

frame_fixture_init :: proc(f: ^Frame_Fixture, draws := SMALL_DRAWS) {
	frame_render_init(&f.fr, draws, SMALL_GROUPS, context.allocator)
	mesh_table_init(&f.meshes, SMALL_MESHES, context.allocator, context.allocator)
	sky_table_init(&f.skies, SMALL_SKIES, context.allocator, context.allocator)
	f.rec.submits = make([dynamic]Submitted, context.allocator)
	f.rec.passes = make([dynamic]Pass_Begun, context.allocator)
	f.rec.shadows = make([dynamic]Shadow_Submitted, context.allocator)
	f.fr.begin_pass = record_begin_pass
	f.fr.end_pass = record_end_pass
	f.fr.submit_shadow = record_shadow
	f.fr.submit = record_submit
	f.fr.submit_lights = record_lights
	f.fr.submit_sky = record_sky
	f.fr.submit_ui = record_ui
	f.fr.submit_ctx = &f.rec
	f.window = {size = {960, 540}, dpi = 1}
}

frame_fixture_destroy :: proc(f: ^Frame_Fixture) {
	delete(f.rec.submits)
	delete(f.rec.passes)
	delete(f.rec.shadows)
	delete(f.rec.ui_quads)
	mesh_table_destroy(&f.meshes)
	sky_table_destroy(&f.skies)
	frame_render_destroy(&f.fr)
}

frame_fixture_draw :: proc(f: ^Frame_Fixture, prev, curr: Scene, alpha: f32, eye := [3]f32{}) -> []Submitted {
	clear(&f.rec.submits)
	clear(&f.rec.passes)
	clear(&f.rec.shadows)
	f.rec.pass_ends = 0
	f.rec.lights_calls = 0
	f.rec.sky_calls = 0
	clear(&f.rec.ui_quads)
	f.rec.ui_calls = 0
	frame_render_draw(&f.fr, prev, curr, alpha, 1, eye, &f.meshes, &f.skies, f.ui, f.window)
	return f.rec.submits[:]
}

// The Frame render only reads, so a Scene may point at a slice roc_alloc never saw.
scene_of :: proc(draws: []Draw) -> Scene {
	return {nodes = roc_list_view(draw_nodes(draws))}
}

// One unit Cube with id 1 at at, after the Lights. Returns its submit.
frame_fixture_light_list :: proc(f: ^Frame_Fixture, lights: []Light, at := [3]f32{}) -> Submitted {
	s := scene_lit({{id = 1, mesh = u32(Primitive.Cube), pos = to_vec3(at), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}, lights)
	frame_fixture_draw(f, s, s, 0)
	return f.rec.submits[0]
}

light_ambient :: proc(c: Rgb) -> Light {
	return {tag = .Ambient, payload = {ambient = c}}
}

light_directional :: proc(dir: Vec3, c: Rgb) -> Light {
	return {tag = .Directional, payload = {directional = {dir = dir, color = c}}}
}

light_sun :: proc(dir: Vec3, c: Rgb) -> Light {
	return {tag = .Directional, payload = {directional = {dir = dir, color = c, shadow = true}}}
}

// The Lights come first in the tree, as a game writes them.
scene_lit :: proc(draws: []Draw, lights: []Light) -> Scene {
	nodes := make([dynamic]Node, context.temp_allocator)
	append(&nodes, ..light_nodes(lights))
	append(&nodes, ..draw_nodes(draws))
	return {nodes = roc_list_view(nodes[:])}
}

light_point :: proc(pos: Vec3, c: Rgb, range: f32) -> Light {
	return {tag = .Point, payload = {point = {pos = pos, color = c, range = range}}}
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

	prev := []Draw{{id = 1, mesh = 1, pos = {0, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}}
	curr := []Draw{{id = 1, mesh = 1, pos = {4, 0, 0}, scale = {1, 1, 1}, rot = quat_yaw(1)}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.25)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}, rotation = quat_from_axis_angle(UP, 0.25)}))
}

@(test)
test_frame_render_draws_a_draw_with_no_partner_at_itself :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 2, mesh = 1, pos = {9, 9, 9}, scale = {1, 1, 1}, rot = IDENTITY}}
	curr := []Draw{{id = 1, mesh = 1, pos = {4, 0, 0}, scale = {1, 1, 1}, rot = quat_yaw(1)}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.25)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {4, 0, 0}, scale = {1, 1, 1}, rotation = quat_from_axis_angle(UP, 1)}))
}

@(test)
test_frame_render_blends_the_pose_of_each_root_and_grouped_draw :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = 3, time = 0.5}}, {id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = 4, time = 0}}}
	child := []Node{node_draw({id = 2, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = 4, time = 1}})}
	curr := []Node{node_draw({id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = 3, time = 0.75}}), node_group(9, {}, IDENTITY, child)}
	frame_fixture_draw(&f, scene_of(prev), {nodes = roc_list_view(curr)}, 0.5)

	testing.expect_value(t, len(f.fr.placed), 2)
	testing.expect_value(t, f.fr.placed[0].transform.pose, Draw_Pose{clip = 3, time = 0.625})
	testing.expect_value(t, f.fr.placed[1].transform.pose, Draw_Pose{clip = 4, time = 0.5})
}

@(test)
test_draw_pose_lerp_blends_a_time_on_its_clip_going_forward_and_the_fade_on_both_clips :: proc(t: ^testing.T) {
	Case :: struct {
		name:       string,
		prev, curr: Draw_Pose,
		want:       Draw_Pose,
	}
	cases := []Case {
		{"same clip, forward", {clip = 3, time = 1}, {clip = 3, time = 2}, {clip = 3, time = 1.25}},
		{"same clip, still", {clip = 3, time = 1}, {clip = 3, time = 1}, {clip = 3, time = 1}},
		{"same clip, wrapped back", {clip = 3, time = 0.9}, {clip = 3, time = 0.1}, {clip = 3, time = 0.1}},
		{"new clip", {clip = 3, time = 1}, {clip = 4, time = 2}, {clip = 4, time = 2}},
		{
			"same fade clip blends the fade and its time",
			{clip = 3, time = 1, fade_clip = 5, fade_time = 0, fade = 0},
			{clip = 3, time = 1, fade_clip = 5, fade_time = 0.4, fade = 0.8},
			{clip = 3, time = 1, fade_clip = 5, fade_time = 0.1, fade = 0.2},
		},
		{
			"same fade clip with its time wrapped back still blends the fade",
			{clip = 3, fade_clip = 5, fade_time = 0.9, fade = 1},
			{clip = 3, fade_clip = 5, fade_time = 0.1, fade = 0.6},
			{clip = 3, fade_clip = 5, fade_time = 0.1, fade = 0.9},
		},
		{
			"new fade clip takes the current fade",
			{clip = 3, time = 1, fade_clip = 5, fade_time = 0, fade = 0},
			{clip = 3, time = 2, fade_clip = 6, fade_time = 0.4, fade = 0.8},
			{clip = 3, time = 1.25, fade_clip = 6, fade_time = 0.4, fade = 0.8},
		},
		{
			"new clip with the same fade clip takes the current fade",
			{clip = 3, time = 1, fade_clip = 5, fade_time = 0, fade = 0},
			{clip = 4, time = 2, fade_clip = 5, fade_time = 0.4, fade = 0.8},
			{clip = 4, time = 2, fade_clip = 5, fade_time = 0.1, fade = 0.8},
		},
	}
	for c in cases {
		got := draw_pose_lerp(c.prev, c.curr, 0.25)
		testing.expectf(t, draw_pose_near(got, c.want), "%v: got %v, want %v", c.name, got, c.want)
	}
}

@(test)
test_frame_render_draws_every_draw_at_itself_when_the_scenes_are_one :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = 1, pos = {1, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}, {id = 2, mesh = 2, pos = {0, 2, 0}, scale = {2, 2, 2}, rot = quat_yaw(3)}}
	scene := scene_of(draws)
	got := frame_fixture_draw(&f, scene, scene, 0.5)

	testing.expect_value(t, len(got), 2)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}, rotation = 1}))
	expect_mat4_near(t, got[1].model, draw_model_matrix({position = {0, 2, 0}, scale = {2, 2, 2}, rotation = quat_from_axis_angle(UP, 3)}))
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
test_frame_render_submits_the_glow_of_each_draw :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = u32(Primitive.Sphere), glow = {r = 3.2, g = 1.9, b = 0.6}}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0].glow, [4]f32{3.2, 1.9, 0.6, 0})
	testing.expect_value(t, got[0].emissive, [4]f32{0, 0, 0, 0})
}

@(test)
test_frame_render_counts_a_negative_glow_channel_as_zero :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = u32(Primitive.Sphere), glow = {r = -1, g = 2, b = 0}}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0].glow, [4]f32{0, 2, 0, 0})
}

@(test)
test_frame_render_submits_the_fallback_with_no_glow :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = 0, glow = {r = 5}}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0].glow, [4]f32{0, 0, 0, 0})
}

@(test)
test_frame_render_takes_the_glow_of_the_current_scene :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 1, mesh = u32(Primitive.Sphere), glow = {r = 1}}}
	curr := []Draw{{id = 1, mesh = u32(Primitive.Sphere), glow = {g = 1}}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.5)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0].glow, [4]f32{0, 1, 0, 0})
}

@(test)
test_frame_render_pairs_a_shared_id_with_the_first_draw :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := []Draw{{id = 5, mesh = 1, pos = {0, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}, {id = 5, mesh = 1, pos = {10, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}}
	curr := []Draw{{id = 5, mesh = 1, pos = {2, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.5)

	testing.expect_value(t, len(got), 1)
	expect_mat4_near(t, got[0].model, draw_model_matrix({position = {1, 0, 0}, scale = {1, 1, 1}, rotation = 1}))
}

@(test)
test_frame_render_camera_builds_the_matrix_from_the_interpolated_pose :: proc(t: ^testing.T) {
	fr: Frame_Render
	prev := Scene{camera = {eye = {0, 8, 8}, target = {0, 0, 0}, up = {0, 1, 0}, fov_y = 1}}
	curr := Scene{camera = {eye = {2, 8, 8}, target = {2, 0, 0}, up = {0, 1, 0}, fov_y = 2}}
	got, eye := frame_render_camera(&fr, prev, curr, 0.5, 16.0 / 9.0)
	want := scene_view_proj({eye = {1, 8, 8}, target = {1, 0, 0}, up = {0, 1, 0}, fov_y = 2}, 16.0 / 9.0)
	expect_mat4_near(t, got, want)
	testing.expect_value(t, eye, [3]f32{1, 8, 8})
	testing.expect(t, !fr.up_fallback_logged)
}

@(test)
test_frame_render_camera_uses_the_scene_up :: proc(t: ^testing.T) {
	fr: Frame_Render
	s := Scene{camera = {eye = {0, 0, 5}, target = {0, 0, 0}, up = {1, 0, 0}, fov_y = 1}}
	got, _ := frame_render_camera(&fr, s, s, 0, 1)
	want := mat4_perspective_reversed_infinite(1, 1, SCENE_NEAR) * mat4_look_at({0, 0, 5}, {0, 0, 0}, {1, 0, 0})
	expect_mat4_near(t, got, want)
}

@(test)
test_frame_render_camera_falls_back_to_world_up_and_logs_once :: proc(t: ^testing.T) {
	fr: Frame_Render
	along := Scene{camera = {eye = {0, 0, 5}, target = {0, 0, 0}, up = {0, 0, 1}, fov_y = 1}}
	zero := Scene{camera = {eye = {0, 0, 5}, target = {0, 0, 0}, fov_y = 1}}
	want := mat4_perspective_reversed_infinite(1, 1, SCENE_NEAR) * mat4_look_at({0, 0, 5}, {0, 0, 0}, UP)
	got_along, _ := frame_render_camera(&fr, along, along, 0, 1)
	expect_mat4_near(t, got_along, want)
	testing.expect(t, fr.up_fallback_logged)
	got_zero, _ := frame_render_camera(&fr, zero, zero, 0, 1)
	expect_mat4_near(t, got_zero, want)
}

@(test)
test_frame_render_lights_an_empty_list_black :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := []Draw{{id = 1, mesh = 1}, {id = 2, mesh = 1}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 2)
	for s in got {
		testing.expect_value(t, s.light_pos, [MAX_LIGHTS][4]f32{})
		testing.expect_value(t, s.light_color, [MAX_LIGHTS][4]f32{})
	}
	testing.expect_value(t, f.rec.lights_calls, 1)
	testing.expect_value(t, f.rec.lights.ambient, [4]f32{})
	testing.expect_value(t, f.rec.lights.shadow, [4]f32{})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{})
}

@(test)
test_frame_render_packs_the_ambient_and_negates_a_directional_dir :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	got := frame_fixture_light_list(&f, {light_ambient({r = 0.1, g = 0.2, b = 0.3}), light_directional({x = 0, y = -4, z = 0}, {r = 2, g = 1, b = 1})})
	testing.expect_value(t, f.rec.lights.ambient, [4]f32{0.1, 0.2, 0.3, 1})
	testing.expect_value(t, got.light_pos[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, got.light_color[0], [4]f32{2, 1, 1, 0})
	testing.expect_value(t, got.light_color[1], [4]f32{})
}

@(test)
test_frame_render_packs_a_point_light_with_its_range :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	got := frame_fixture_light_list(&f, {light_point({x = 1, y = 2, z = 3}, {r = 1, g = 0.5, b = 0}, 6)})
	testing.expect_value(t, f.rec.lights.ambient, [4]f32{})
	testing.expect_value(t, got.light_pos[0], [4]f32{1, 2, 3, 1})
	testing.expect_value(t, got.light_color[0], [4]f32{1, 0.5, 0, 6})
}

@(test)
test_frame_render_keeps_every_point_light_of_the_scene :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights: [20]Light
	for &l, i in lights {
		l = light_point({x = 10 * f32(i)}, {r = 1}, 2)
	}
	got := frame_fixture_light_list(&f, lights[:], at = {190, 0, 0})
	testing.expect_value(t, got.light_pos[0], [4]f32{190, 0, 0, 1})
	testing.expect_value(t, got.light_color[1], [4]f32{})
	testing.expect(t, .Draw_Over_Limit not_in f.fr.lights_logged)
}

@(test)
test_frame_render_gives_each_draw_its_own_point_lights :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := []Light{light_point({x = 0, y = 2, z = 0}, {r = 1}, 3), light_point({x = 20, y = 2, z = 0}, {g = 1}, 3)}
	draws := []Draw {
		{id = 1, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY},
		{id = 2, mesh = u32(Primitive.Cube), pos = {x = 20}, scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY},
	}
	scene := scene_lit(draws, lights)
	got := frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0].light_pos[0], [4]f32{0, 2, 0, 1})
	testing.expect_value(t, got[0].light_color[1], [4]f32{})
	testing.expect_value(t, got[1].light_pos[0], [4]f32{20, 2, 0, 1})
	testing.expect_value(t, got[1].light_color[1], [4]f32{})
}

@(test)
test_frame_render_draws_40_orbs_each_lit_by_its_own_light :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f, draws = 40)
	defer frame_fixture_destroy(&f)

	draws: [40]Draw
	lights: [40]Light
	for i in 0 ..< 8 {
		for j in 0 ..< 5 {
			at := Vec3{x = 4 * f32(i), z = 4 * f32(j)}
			draws[i * 5 + j] = {id = u64(i * 5 + j), mesh = u32(Primitive.Cube), pos = at, scale = {1, 0.1, 1}, rot = IDENTITY, scale_rot = IDENTITY}
			lights[i * 5 + j] = light_point({at.x, 1, at.z}, {r = 1}, 3)
		}
	}
	scene := scene_lit(draws[:], lights[:])
	got := frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, len(got), 40)
	for s, k in got {
		above := draws[k].pos
		testing.expect_value(t, s.light_pos[0], [4]f32{above.x, 1, above.z, 1})
		testing.expect(t, s.light_color[0] != {})
		testing.expect_value(t, s.light_color[1], [4]f32{})
	}
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{})
}

@(test)
test_frame_render_keeps_the_8_nearest_and_logs_a_draw_that_drops_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights: [MAX_LIGHTS + 2]Light
	for &l, i in lights {
		l = light_point({x = f32(len(lights) - i)}, {r = 1}, 20)
	}
	got := frame_fixture_light_list(&f, lights[:])
	for i in 0 ..< MAX_LIGHTS {
		testing.expect_value(t, got.light_pos[i].x, f32(i + 1))
	}
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Draw_Over_Limit})
	frame_fixture_light_list(&f, lights[:])
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Draw_Over_Limit})
}

@(test)
test_frame_render_puts_the_sun_in_slot_0 :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	got := frame_fixture_light_list(&f, {light_directional({z = -1}, {r = 1}), light_sun({y = -1}, {g = 1})})
	testing.expect_value(t, got.light_pos[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, got.light_pos[1], [4]f32{0, 0, 1, 0})
	testing.expect_value(t, f.rec.lights.shadow.x, 1)
	testing.expect_value(t, f.rec.lights.shadow.y, 0)
}

@(test)
test_frame_render_keeps_the_sun_past_8_directionals :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights: [MAX_LIGHTS + 1]Light
	for &l, i in lights {
		l = light_directional({x = f32(i + 1), y = -1}, {r = 1})
	}
	lights[MAX_LIGHTS] = light_sun({y = -1}, {g = 1})
	got := frame_fixture_light_list(&f, lights[:])
	testing.expect_value(t, got.light_pos[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, got.light_color[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Draw_Over_Limit})
	testing.expect_value(t, f.rec.lights.shadow.x, 1)
}

@(test)
test_frame_render_gives_an_unlit_draw_no_lights :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	sign, _ := mesh_table_add(&f.meshes, strings.clone("sign"), {material = {roughness = 1, unlit = true}})
	draws := []Draw{{id = 1, mesh = mesh_id(&f.meshes, sign), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}
	lights := []Light{light_point({x = 1}, {r = 1}, 4)}
	scene := scene_lit(draws, lights)
	got := frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0].light_pos, [MAX_LIGHTS][4]f32{})
	testing.expect_value(t, got[0].light_color, [MAX_LIGHTS][4]f32{})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{})
}

@(test)
test_frame_render_headless_selects_no_lights :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights: [MAX_LIGHTS + 2]Light
	for &l, i in lights {
		l = light_point({x = f32(i)}, {r = 1}, 20)
	}
	draws := []Draw{{id = 1, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}
	scene := scene_lit(draws, lights[:])
	frame_render_draw(&f.fr, scene, scene, 0, 1, {}, &f.meshes, &f.skies, nil, f.window, submit = false)
	testing.expect_value(t, len(f.rec.submits), 0)
	testing.expect(t, .Draw_Over_Limit not_in f.fr.lights_logged)
}

@(test)
test_frame_render_keeps_the_first_ambient_and_logs_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	frame_fixture_light_list(&f, {light_ambient({r = 0.1}), light_ambient({g = 0.1}), light_ambient({b = 0.1})})
	testing.expect_value(t, f.rec.lights.ambient, [4]f32{0.1, 0, 0, 1})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Second_Ambient})
}

@(test)
test_frame_render_drops_a_zero_dir_without_taking_a_slot :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	got := frame_fixture_light_list(&f, {light_directional({}, {r = 1}), light_directional({z = -1}, {g = 1})})
	testing.expect_value(t, got.light_pos[0], [4]f32{0, 0, 1, 0})
	testing.expect_value(t, got.light_color[0], [4]f32{0, 1, 0, 0})
	testing.expect_value(t, got.light_color[1], [4]f32{})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Zero_Dir})
}

@(test)
test_frame_render_drops_a_point_light_with_a_range_of_zero_or_less :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	got := frame_fixture_light_list(&f, {light_point({}, {r = 1}, 0), light_point({}, {r = 1}, -1), light_point({}, {r = 1}, math.nan_f32())})
	testing.expect_value(t, got.light_pos, [MAX_LIGHTS][4]f32{})
	testing.expect_value(t, got.light_color, [MAX_LIGHTS][4]f32{})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Bad_Range})
}

@(test)
test_frame_render_logs_each_light_drop_reason_once_per_run :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	frame_fixture_light_list(&f, {light_ambient({}), light_ambient({}), light_directional({}, {})})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Second_Ambient, .Zero_Dir})
	frame_fixture_light_list(&f, {light_ambient({}), light_ambient({}), light_directional({}, {}), light_point({}, {}, 0)})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Second_Ambient, .Zero_Dir, .Bad_Range})
}

quat_yaw :: proc(rad: f32) -> Quat {
	return test_turn(UP, rad)
}

expect_v4_near :: proc(t: ^testing.T, got, want: [4]f32, loc := #caller_location) {
	d := got - want
	testing.expectf(t, math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z + d.w * d.w) < EPS, "got %v, want %v", got, want, loc = loc)
}

expect_quat_near :: proc(t: ^testing.T, got, want: quaternion128, loc := #caller_location) {
	testing.expectf(t, abs(abs(quat_dot(got, want)) - 1) < EPS, "got %v, want %v", got, want, loc = loc)
}

@(test)
test_frame_render_submits_the_material_of_each_mesh :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	shiny, _ := mesh_table_add(&f.meshes, strings.clone("shiny"), {material = {roughness = 0.3, metallic = 0.7}})
	sign, _ := mesh_table_add(&f.meshes, strings.clone("sign"), {material = {roughness = 1, unlit = true}})
	draws := []Draw {
		{id = 1, mesh = u32(Primitive.Sphere)},
		{id = 2, mesh = mesh_id(&f.meshes, shiny)},
		{id = 3, mesh = mesh_id(&f.meshes, sign)},
	}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[0].material, [4]f32{1, 0, 0, 0})
	testing.expect_value(t, got[1].material, [4]f32{0.3, 0.7, 0, 0})
	testing.expect_value(t, got[2].material, [4]f32{1, 0, 1, 0})
}

@(test)
test_frame_render_submits_the_emissive_of_each_mesh :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lamp, _ := mesh_table_add(&f.meshes, strings.clone("lamp"), {material = {roughness = 1, emissive = {4, 2, 0}}})
	draws := []Draw{{id = 1, mesh = u32(Primitive.Sphere)}, {id = 2, mesh = mesh_id(&f.meshes, lamp)}}
	got := frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0].emissive, [4]f32{0, 0, 0, 0})
	testing.expect_value(t, got[1].emissive, [4]f32{4, 2, 0, 0})
}

@(test)
test_frame_render_gives_the_lights_the_camera_eye :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	s := Scene{}
	frame_fixture_draw(&f, s, s, 0, eye = {1, 2, 3})
	testing.expect_value(t, f.rec.lights.camera_pos, [4]f32{1, 2, 3, 0})
}

// The table is never uploaded, so the sky needs no sokol.
frame_fixture_sky :: proc(f: ^Frame_Fixture) -> u32 {
	slot, _ := sky_table_add(&f.skies, strings.clone("sky/test"), 1, make([]byte, len(SKY_FACES) * 4))
	return sky_id(&f.skies, slot)
}

@(test)
test_frame_render_begins_the_main_pass_with_the_clear_of_the_current_scene :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	prev := Scene {
		clear = {r = 1},
	}
	curr := Scene {
		clear = {r = 0.2, g = 0.4, b = 0.6},
	}
	frame_fixture_draw(&f, prev, curr, 0.5)

	testing.expect_value(t, f.rec.main_clear, curr.clear)
}

@(test)
test_frame_render_submits_no_sky_for_sky_0 :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_sky(&f)

	draws := []Draw{{id = 1, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}
	frame_fixture_draw(&f, scene_of(draws), scene_of(draws), 0)
	testing.expect_value(t, f.rec.sky_calls, 0)
	testing.expect_value(t, len(f.skies.logged), 0)
}

@(test)
test_frame_render_submits_the_sky_after_every_draw :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	sky := frame_fixture_sky(&f)

	draws := []Draw{{id = 1, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}, {id = 2, mesh = u32(Primitive.Sphere), scale = {1, 1, 1}, rot = IDENTITY, scale_rot = IDENTITY}}
	prev := scene_of(draws)
	curr := scene_of(draws)
	curr.sky = sky
	frame_fixture_draw(&f, prev, curr, 0)

	testing.expect_value(t, f.rec.sky_calls, 1)
	testing.expect_value(t, f.rec.sky_after, 2)
	testing.expect_value(t, f.rec.sky, &f.skies.skies[sky_slot(sky)])
	expect_mat4_near(t, f.rec.sky_view_proj, 1)
}

@(test)
test_frame_render_submits_no_sky_for_a_stale_sky_id_and_logs_it_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	sky := frame_fixture_sky(&f)
	sky_table_remove(&f.skies, sky_slot(sky))

	scene := Scene{sky = sky}
	frame_fixture_draw(&f, scene, scene, 0)
	frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, f.rec.sky_calls, 0)
	testing.expect_value(t, len(f.skies.logged), 1)
}

@(test)
test_frame_render_draws_every_draw_from_the_sun_before_the_main_pass :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := []Light{light_sun({x = 0, y = -1, z = 0}, {r = 1})}
	prev := []Draw{{id = 1, mesh = 1, pos = {0, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}, {id = 2, mesh = 2, scale = {1, 1, 1}, rot = IDENTITY}}
	curr := []Draw{{id = 1, mesh = 1, pos = {4, 0, 0}, scale = {1, 1, 1}, rot = IDENTITY}, {id = 2, mesh = 2, scale = {1, 1, 1}, rot = IDENTITY}}
	frame_fixture_draw(&f, scene_lit(prev, lights), scene_lit(curr, lights), 0.25)

	testing.expect_value(t, len(f.rec.passes), 2)
	testing.expect_value(t, f.rec.passes[0], Pass_Begun{.Shadow, 0})
	testing.expect_value(t, f.rec.passes[1], Pass_Begun{.Main, 0})
	testing.expect_value(t, f.rec.pass_ends, 2)
	testing.expect_value(t, len(f.rec.shadows), 2)
	testing.expect_value(t, f.rec.shadows[0].mesh, &f.meshes.meshes[Primitive.Cube])
	testing.expect_value(t, f.rec.shadows[1].mesh, &f.meshes.meshes[Primitive.Sphere])
	testing.expect_value(t, f.rec.shadows[1].main_before, 0)
	light_view_proj := f.rec.lights.light_view_proj[0]
	expect_mat4_near(t, f.rec.shadows[0].light_mvp, light_view_proj * mat4_translate({1, 0, 0}))
	testing.expect_value(t, f.rec.lights.shadow.x, 1)
	testing.expect_value(t, f.rec.lights.shadow.y, 0)
}

@(test)
test_frame_render_draws_at_most_its_draw_capacity_and_logs_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	draws := make([]Draw, SMALL_DRAWS + 1)
	defer delete(draws)
	for &d, i in draws {
		d = {id = u64(i), mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}
	}
	lights := []Light{light_sun({x = 0, y = -1, z = 0}, {r = 1})}
	scene := scene_lit(draws, lights)
	got := frame_fixture_draw(&f, scene, scene, 0.5)

	testing.expect_value(t, len(got), SMALL_DRAWS)
	testing.expect_value(t, len(f.rec.shadows), SMALL_DRAWS)
	testing.expect(t, f.fr.draws_logged)
	got = frame_fixture_draw(&f, scene_lit(draws[:SMALL_DRAWS], lights), scene, 0.5)
	testing.expect_value(t, len(got), SMALL_DRAWS)
}

// The pairing map and the placed list come from init, so a full Frame allocates nothing.
@(test)
test_frame_render_places_its_draw_capacity_without_allocating :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	fr: Frame_Render
	frame_render_init(&fr, SMALL_DRAWS, SMALL_GROUPS, mem.tracking_allocator(&track))
	defer frame_render_destroy(&fr)
	meshes: Mesh_Table
	mesh_table_init(&meshes, SMALL_MESHES, context.allocator, context.allocator)
	defer mesh_table_destroy(&meshes)
	skies: Sky_Table
	sky_table_init(&skies, SMALL_SKIES, context.allocator, context.allocator)
	defer sky_table_destroy(&skies)

	draws := make([]Draw, SMALL_DRAWS)
	defer delete(draws)
	for &d, i in draws {
		d = {id = u64(i), mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}
	}
	after_init := track.total_allocation_count
	frame_render_draw(&fr, scene_of(draws), scene_of(draws), 0.5, 1, {}, &meshes, &skies, nil, {size = {960, 540}, dpi = 1}, submit = false)

	testing.expect_value(t, track.total_allocation_count, after_init)
	testing.expect_value(t, len(fr.placed), SMALL_DRAWS)
	testing.expect(t, !fr.pairing.over_capacity_logged)
	testing.expect(t, !fr.draws_logged)
}

@(test)
test_frame_render_skips_the_shadow_pass_with_no_sun :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := []Light{light_directional({x = 0, y = -1, z = 0}, {r = 1})}
	draws := []Draw{{id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}}
	frame_fixture_draw(&f, scene_lit(draws, lights), scene_lit(draws, lights), 0)

	testing.expect_value(t, len(f.rec.passes), 1)
	testing.expect_value(t, f.rec.passes[0], Pass_Begun{.Main, 0})
	testing.expect_value(t, f.rec.pass_ends, 1)
	testing.expect_value(t, len(f.rec.shadows), 0)
	testing.expect_value(t, f.rec.lights.shadow, [4]f32{})
}

@(test)
test_frame_render_takes_the_first_sun_and_logs_a_second_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := []Light {
		light_ambient({r = 0.1}),
		light_directional({x = 1, y = 0, z = 0}, {r = 1}),
		light_sun({x = 0, y = -1, z = 0}, {r = 2}),
		light_sun({x = 0, y = 0, z = -1}, {r = 3}),
	}
	draws := []Draw{{id = 1, mesh = 1, scale = {1, 1, 1}, rot = IDENTITY}}
	frame_fixture_draw(&f, scene_lit(draws, lights), scene_lit(draws, lights), 0)

	testing.expect_value(t, f.rec.lights.shadow.x, 1)
	testing.expect_value(t, f.rec.lights.shadow.y, 0)
	testing.expect_value(t, f.rec.submits[0].light_color[0], [4]f32{2, 0, 0, 0})
	testing.expect_value(t, f.rec.submits[0].light_color[2], [4]f32{3, 0, 0, 0})
	testing.expect_value(t, f.fr.lights_logged, bit_set[Light_Drop]{.Second_Sun})
}

@(test)
test_frame_render_fits_the_sun_view_to_the_draws_snapped_to_whole_units :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)

	lights := []Light{light_sun({x = 0, y = -1, z = 0}, {r = 1})}
	draws := []Draw{{id = 1, mesh = 1, pos = {0.2, 0, 0.3}, scale = {1, 1, 1}, rot = IDENTITY}}
	frame_fixture_draw(&f, scene_lit(draws, lights), scene_lit(draws, lights), 0)

	light_view_proj := f.rec.lights.light_view_proj[0]
	for corner in 0 ..< 8 {
		w := [4]f32{-1 if corner & 1 == 0 else 1, -1 if corner & 2 == 0 else 1, -1 if corner & 4 == 0 else 1, 1}
		clip := light_view_proj * w
		testing.expectf(t, abs(abs(clip.x) - 1) < EPS && abs(abs(clip.y) - 1) < EPS, "corner %v maps to %v", w, clip)
		testing.expectf(t, abs(clip.z) < EPS || abs(clip.z - 1) < EPS, "corner %v has depth %v", w, clip.z)
	}
	top := light_view_proj * [4]f32{0, 1, 0, 1}
	bottom := light_view_proj * [4]f32{0, -1, 0, 1}
	testing.expectf(t, top.z > bottom.z, "the side nearer the Sun is nearer in reversed-Z: %v, %v", top.z, bottom.z)
}

draw_pose_near :: proc(a, b: Draw_Pose) -> bool {
	return a.clip == b.clip && a.fade_clip == b.fade_clip && abs(a.time - b.time) < EPS && abs(a.fade_time - b.fade_time) < EPS && abs(a.fade - b.fade) < EPS
}

// Gives the Sphere slot the chain Skin, so its id draws as a skinned mesh.
frame_fixture_skinned :: proc(f: ^Frame_Fixture) -> u32 {
	chain := chain_mesh()
	m := &f.meshes.meshes[Primitive.Sphere]
	m.skin = chain.skin
	m.first_clip = chain.first_clip
	return u32(Primitive.Sphere)
}

expect_skin_of_pose :: proc(t: ^testing.T, f: ^Frame_Fixture, got: [2]Mat4, pose: Draw_Pose, loc := #caller_location) {
	want: [MAX_JOINTS]Mat4
	skin_matrices(&f.meshes, &f.meshes.meshes[Primitive.Sphere], pose, &want)
	expect_mat4_near(t, got[0], want[0], loc)
	expect_mat4_near(t, got[1], want[1], loc)
}

@(test)
test_frame_render_submits_the_skin_of_the_blended_pose_in_both_passes :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)

	lights := []Light{light_sun({x = 0, y = -1, z = 0}, {r = 1})}
	prev := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LIFT, time = 0.25}}}
	curr := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LIFT, time = 0.75}}}
	got := frame_fixture_draw(&f, scene_lit(prev, lights), scene_lit(curr, lights), 0.5)

	testing.expect_value(t, len(got), 1)
	testing.expect(t, got[0].skinned)
	expect_mat4_near(t, got[0].joints[0], mat4_translate({0, 1, 0}))
	expect_mat4_near(t, got[0].joints[1], mat4_translate({0, 1, 0}))
	testing.expect_value(t, len(f.rec.shadows), 1)
	testing.expect(t, f.rec.shadows[0].skinned)
	expect_mat4_near(t, f.rec.shadows[0].joints[0], mat4_translate({0, 1, 0}))
}

@(test)
test_frame_render_takes_the_current_time_when_a_looped_time_wraps :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)

	prev := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LIFT, time = 0.9}}}
	curr := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LIFT, time = 0.1}}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.5)

	expect_mat4_near(t, got[0].joints[0], mat4_translate({0, 0.2, 0}))
}

@(test)
test_frame_render_submits_the_skin_of_the_blended_fade :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)

	prev := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LEAN, fade_clip = LIFT, fade_time = 1, fade = 0}}}
	curr := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LEAN, fade_clip = LIFT, fade_time = 1, fade = 1}}}
	got := frame_fixture_draw(&f, scene_of(prev), scene_of(curr), 0.5)

	expect_skin_of_pose(t, &f, got[0].joints, {clip = LEAN, fade_clip = LIFT, fade_time = 1, fade = 0.5})
	half_turn := linalg.matrix4_from_trs_f32({0, 1, 0}, quat_from_axis_angle({0, 0, 1}, math.PI / 4), 1)
	expect_mat4_near(t, got[0].joints[0], half_turn)
}

@(test)
test_frame_render_submits_skinned_draws_after_rigid_draws_in_each_pass :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)

	lights := []Light{light_sun({x = 0, y = -1, z = 0}, {r = 1})}
	draws := []Draw {
		{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY},
		{id = 2, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY},
		{id = 3, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY},
		{id = 4, mesh = u32(Primitive.Plane), scale = {1, 1, 1}, rot = IDENTITY},
	}
	scene := scene_lit(draws, lights)
	got := frame_fixture_draw(&f, scene, scene, 0)

	want := []bool{false, false, true, true}
	testing.expect_value(t, len(got), len(want))
	testing.expect_value(t, len(f.rec.shadows), len(want))
	for skinned, i in want {
		testing.expectf(t, got[i].skinned == skinned, "submit %v: skinned is %v", i, got[i].skinned)
		testing.expectf(t, f.rec.shadows[i].skinned == skinned, "shadow %v: skinned is %v", i, f.rec.shadows[i].skinned)
	}
	testing.expect_value(t, got[0].mesh, &f.meshes.meshes[Primitive.Cube])
	testing.expect_value(t, got[1].mesh, &f.meshes.meshes[Primitive.Plane])
}

@(test)
test_frame_render_draws_its_skinned_capacity_and_logs_the_rest_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)
	delete(f.fr.skins)
	f.fr.skins = make([]Skin_Params, 2)

	draws := []Draw {
		{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY},
		{id = 2, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY},
		{id = 3, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY},
		{id = 4, mesh = u32(Primitive.Cube), scale = {1, 1, 1}, rot = IDENTITY},
	}
	scene := scene_of(draws)
	got := frame_fixture_draw(&f, scene, scene, 0)

	testing.expect_value(t, len(got), 3)
	testing.expect(t, f.fr.skinned_logged)
	testing.expect(t, !f.fr.draws_logged)
}

// The skins start at zero, and a posed skin is not zero.
@(test)
test_frame_render_skips_the_skin_with_submit_off :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	chain := frame_fixture_skinned(&f)

	draws := []Draw{{id = 1, mesh = chain, scale = {1, 1, 1}, rot = IDENTITY, pose = {clip = LEAN}}}
	frame_render_draw(&f.fr, scene_of(draws), scene_of(draws), 0, 1, {}, &f.meshes, &f.skies, nil, f.window, submit = false)

	testing.expect_value(t, len(f.fr.placed), 1)
	testing.expect(t, f.fr.placed[0].skin != nil)
	expect_mat4_near(t, f.fr.placed[0].skin.joints[0], 0)
}
