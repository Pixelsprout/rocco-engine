#+test
package engine

import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:testing"

// The chain mesh's Clip ids: Lean turns the root 90 degrees about +z, and
// Lift raises the root from 0 to 2 up +y over 1 s.
LEAN :: 7
LIFT :: 8
// A Clip id of another mesh.
OTHER_CLIP :: 3
// Pip with the Clips Idle, Walk and Run.
ANIMATION_PIP_GLB :: #load("../examples/animation/assets/meshes/pip.glb")

// Two Joints bound at rest: root at the origin and tip 1 up +y.
chain_skin :: proc() -> Skin {
	joints := make([]Joint, 2, context.temp_allocator)
	joints[0] = {parent = -1, base = mat4_identity(), rest = {rotation = 1, scale = 1}, inverse_bind = mat4_identity()}
	joints[1] = {parent = 0, base = mat4_identity(), rest = {translation = {0, 1, 0}, rotation = 1, scale = 1}, inverse_bind = mat4_translate({0, -1, 0})}
	return {joints = joints}
}

// The chain with one Clip that keys one channel of the tip.
tip_clip_skin :: proc(path: Clip_Path, interpolation: Clip_Interpolation, times: []f32, values: [][4]f32) -> Skin {
	skin := chain_skin()
	skin.clips = slice.clone([]Clip{{name = "Test", duration = slice.last(times), channel_count = 1}}, context.temp_allocator)
	skin.channels = slice.clone([]Clip_Channel{{joint = 1, path = path, interpolation = interpolation, key_count = len(times)}}, context.temp_allocator)
	skin.times = slice.clone(times, context.temp_allocator)
	skin.values = slice.clone(values, context.temp_allocator)
	return skin
}

tip_at :: proc(skin: ^Skin, time: f32) -> Joint_Trs {
	out: [2]Joint_Trs
	clip_sample(skin, &skin.clips[0], time, out[:])
	return out[1]
}

// The chain with the Clips Lean and Lift, as the mesh table would add it.
chain_mesh :: proc() -> Mesh {
	skin := chain_skin()
	turn := rotation_key(quat_from_axis_angle({0, 0, 1}, math.PI / 2))
	skin.clips = slice.clone([]Clip{{name = "Lean", duration = 0, first_channel = 0, channel_count = 1}, {name = "Lift", duration = 1, first_channel = 1, channel_count = 1}}, context.temp_allocator)
	skin.channels = slice.clone([]Clip_Channel{{joint = 0, path = .Rotation, first_key = 0, key_count = 1}, {joint = 0, path = .Translation, first_key = 1, key_count = 2}}, context.temp_allocator)
	skin.times = slice.clone([]f32{0, 0, 1}, context.temp_allocator)
	skin.values = slice.clone([][4]f32{turn, {0, 0, 0, 0}, {0, 2, 0, 0}}, context.temp_allocator)
	return {name = "chain", skin = skin, first_clip = LEAN}
}

clip_table :: proc() -> Mesh_Table {
	return {clips_logged = make(map[u32]struct {})}
}

transform_point :: proc(m: Mat4, p: [3]f32) -> [3]f32 {
	return (m * [4]f32{p.x, p.y, p.z, 1}).xyz
}

@(test)
test_clip_sample_gives_each_linear_key_at_its_time_and_lerps_between_keys :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Translation, .Linear, {0, 1, 2}, {{0, 0, 0, 0}, {2, 0, 0, 0}, {2, 4, 0, 0}})
	testing.expect_value(t, tip_at(&skin, 0).translation, [3]f32{0, 0, 0})
	testing.expect_value(t, tip_at(&skin, 1).translation, [3]f32{2, 0, 0})
	testing.expect_value(t, tip_at(&skin, 2).translation, [3]f32{2, 4, 0})
	expect_v3_near(t, tip_at(&skin, 0.5).translation, {1, 0, 0})
	expect_v3_near(t, tip_at(&skin, 1.75).translation, {2, 3, 0})
}

@(test)
test_clip_sample_holds_each_step_key_until_the_next_key :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Scale, .Step, {0, 0.25, 0.75}, {{1, 1, 1, 0}, {2, 2, 2, 0}, {3, 3, 3, 0}})
	testing.expect_value(t, tip_at(&skin, 0).scale, [3]f32{1, 1, 1})
	testing.expect_value(t, tip_at(&skin, 0.2).scale, [3]f32{1, 1, 1})
	testing.expect_value(t, tip_at(&skin, 0.25).scale, [3]f32{2, 2, 2})
	testing.expect_value(t, tip_at(&skin, 0.7).scale, [3]f32{2, 2, 2})
	testing.expect_value(t, tip_at(&skin, 0.75).scale, [3]f32{3, 3, 3})
}

// The first key need not be at 0 s, so a time from 0 up to the first key
// also holds the first key.
@(test)
test_clip_sample_clamps_a_time_before_the_first_key_and_after_the_last :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Translation, .Linear, {0.5, 1.5}, {{0, 1, 0, 0}, {0, 3, 0, 0}})
	testing.expect_value(t, tip_at(&skin, -1).translation, [3]f32{0, 1, 0})
	testing.expect_value(t, tip_at(&skin, 0).translation, [3]f32{0, 1, 0})
	testing.expect_value(t, tip_at(&skin, 0.25).translation, [3]f32{0, 1, 0})
	testing.expect_value(t, tip_at(&skin, 1.5).translation, [3]f32{0, 3, 0})
	testing.expect_value(t, tip_at(&skin, 9).translation, [3]f32{0, 3, 0})
}

@(test)
test_clip_sample_holds_a_channel_with_one_key_at_every_time :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Translation, .Step, {0}, {{0, 5, 0, 0}})
	for time in ([]f32{-1, 0, 0.5, 3}) {
		testing.expect_value(t, tip_at(&skin, time).translation, [3]f32{0, 5, 0})
	}
}

@(test)
test_clip_sample_slerps_a_rotation_between_keys :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Rotation, .Linear, {0, 1}, {rotation_key(1), rotation_key(quat_from_axis_angle({0, 0, 1}, math.PI / 2))})
	expect_quat_near(t, tip_at(&skin, 0.5).rotation, quat_from_axis_angle({0, 0, 1}, math.PI / 4))
	expect_quat_near(t, tip_at(&skin, 1).rotation, quat_from_axis_angle({0, 0, 1}, math.PI / 2))
}

// The second key is the negation of 60 degrees, the same rotation. The long
// arc would pass through 200 degrees.
@(test)
test_clip_sample_slerps_the_short_way_across_a_quaternion_sign_flip :: proc(t: ^testing.T) {
	from := quat_from_axis_angle({0, 0, 1}, math.to_radians(f32(20)))
	to := -quat_from_axis_angle({0, 0, 1}, math.to_radians(f32(60)))
	skin := tip_clip_skin(.Rotation, .Linear, {0, 1}, {rotation_key(from), rotation_key(to)})
	expect_quat_near(t, tip_at(&skin, 0.5).rotation, quat_from_axis_angle({0, 0, 1}, math.to_radians(f32(40))))
}

@(test)
test_clip_sample_keeps_the_rest_trs_of_a_joint_with_no_channel :: proc(t: ^testing.T) {
	skin := tip_clip_skin(.Translation, .Linear, {0, 1}, {{0, 2, 0, 0}, {0, 3, 0, 0}})
	out: [2]Joint_Trs
	clip_sample(&skin, &skin.clips[0], 0.5, out[:])
	testing.expect_value(t, out[0], skin.joints[0].rest)
	testing.expect_value(t, out[1].rotation, skin.joints[1].rest.rotation)
	testing.expect_value(t, out[1].scale, skin.joints[1].rest.scale)
}

// Lean turns only the root, so the tip, bound 1 up +y, swings to -x.
@(test)
test_skin_matrices_move_a_child_joint_with_its_parent :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	testing.expect_value(t, skin_matrices(&table, &m, {clip = LEAN}, &out), 2)
	expect_v3_near(t, transform_point(out[1], {0, 1, 0}), {-1, 0, 0})
	expect_v3_near(t, transform_point(out[1], {0, 2, 0}), {-2, 0, 0})
	expect_v3_near(t, transform_point(out[0], {0, 1, 0}), {-1, 0, 0})
}

// Lift is sampled at fade_time, not at time.
@(test)
test_skin_matrices_take_the_clip_at_fade_0_and_the_fade_clip_at_fade_1 :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	skin_matrices(&table, &m, {clip = LEAN, time = 0, fade_clip = LIFT, fade_time = 0.5, fade = 0}, &out)
	expect_mat4_near(t, out[0], mat4_from_quat(quat_from_axis_angle({0, 0, 1}, math.PI / 2)))
	skin_matrices(&table, &m, {clip = LEAN, time = 0, fade_clip = LIFT, fade_time = 0.5, fade = 1}, &out)
	expect_mat4_near(t, out[0], mat4_translate({0, 1, 0}))
}

@(test)
test_skin_matrices_mix_each_joint_of_the_two_clips_at_fade_half :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	skin_matrices(&table, &m, {clip = LEAN, time = 0, fade_clip = LIFT, fade_time = 1, fade = 0.5}, &out)
	expect_mat4_near(t, out[0], mat4_translate({0, 1, 0}) * mat4_from_quat(quat_from_axis_angle({0, 0, 1}, math.PI / 4)))
}

// A fade of 0 samples no fade Clip, and a fade of 1 samples no first Clip.
@(test)
test_skin_matrices_draw_the_bind_pose_for_a_clip_of_another_mesh_that_the_fade_leaves_out :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	skin_matrices(&table, &m, {clip = LEAN, fade_clip = OTHER_CLIP, fade = 0}, &out)
	testing.expect_value(t, out[0], mat4_identity())
	testing.expect_value(t, out[1], mat4_identity())
	skin_matrices(&table, &m, {clip = OTHER_CLIP, fade_clip = LEAN, fade = 1}, &out)
	testing.expect_value(t, out[0], mat4_identity())
	testing.expect_value(t, out[1], mat4_identity())
	testing.expect_value(t, len(table.clips_logged), 1)
}

@(test)
test_skin_matrices_give_the_bind_pose_for_clip_id_0 :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	testing.expect_value(t, skin_matrices(&table, &m, {}, &out), 2)
	testing.expect_value(t, out[0], mat4_identity())
	testing.expect_value(t, out[1], mat4_identity())
	testing.expect_value(t, len(table.clips_logged), 0)
}

// Clip id 0 as the fade Clip mixes toward the rest TRS.
@(test)
test_skin_matrices_mix_a_clip_with_the_rest_trs_of_clip_id_0 :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	skin_matrices(&table, &m, {clip = LEAN, fade = 0.5}, &out)
	expect_mat4_near(t, out[0], mat4_from_quat(quat_from_axis_angle({0, 0, 1}, math.PI / 4)))
	testing.expect_value(t, len(table.clips_logged), 0)
}

@(test)
test_skin_matrices_give_the_bind_pose_and_log_once_for_a_clip_of_another_mesh :: proc(t: ^testing.T) {
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4
	for pose in ([]Draw_Pose{{clip = OTHER_CLIP}, {clip = OTHER_CLIP}, {clip = LEAN, fade_clip = OTHER_CLIP, fade = 0.5}}) {
		testing.expect_value(t, skin_matrices(&table, &m, pose, &out), 2)
		testing.expect_value(t, out[0], mat4_identity())
		testing.expect_value(t, out[1], mat4_identity())
	}
	testing.expect_value(t, len(table.clips_logged), 1)
}

@(test)
test_skin_matrices_mix_two_clips_without_allocating :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	table := clip_table()
	defer delete(table.clips_logged)
	m := chain_mesh()
	out: [MAX_JOINTS]Mat4

	context.allocator = mem.tracking_allocator(&track)
	context.temp_allocator = mem.tracking_allocator(&track)
	skin_matrices(&table, &m, {clip = LEAN, time = 0.3, fade_clip = LIFT, fade_time = 0.6, fade = 0.4}, &out)
	testing.expect_value(t, track.total_allocation_count, 0)
}

// The expected positions are Blender's skinned vertices of the fixture,
// rounded to 3 places. The u8 weights 64 and 191 move them less than 0.001.
@(test)
test_skin_matrices_pose_the_fixture_where_blender_does :: proc(t: ^testing.T) {
	data, _, err := glb_parse(skinned_glb(t), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	table := clip_table()
	defer delete(table.clips_logged)
	m := Mesh{name = "strip", skin = data.skin, first_clip = 1}
	Case :: struct {
		time: f32,
		want: [4][3]f32,
	}
	cases := []Case {
		{0, {{-0.5, 1, 0}, {0.5, 1, 0}, {-0.5, 2, 0}, {0.5, 2, 0}}},
		{0.25, {{-0.39, 0.735, 0}, {0.39, 1.265, 0}, {-1.414, 1.707, 0}, {-0.707, 2.414, 0}}},
		{0.5, {{-0.125, 0.625, 0}, {0.125, 1.375, 0}, {-1.5, 0.5, 0}, {-1.5, 1.5, 0}}},
		{0.75, {{-0.39, 0.735, 0}, {0.39, 1.265, 0}, {-1.061, 1.354, 0}, {-0.354, 2.061, 0}}},
		{1, {{-0.5, 1, 0}, {0.5, 1, 0}, {-0.5, 2, 0}, {0.5, 2, 0}}},
	}
	out: [MAX_JOINTS]Mat4
	for c in cases {
		testing.expect_value(t, skin_matrices(&table, &m, {clip = 1, time = c.time}, &out), 3)
		for want, k in c.want {
			v := k + 2
			got: [3]f32
			influence := data.influences[v]
			for joint, i in influence.joints {
				got += f32(influence.weights[i]) / 255 * transform_point(out[joint], data.vertices[v].pos)
			}
			testing.expectf(t, v3_length(got - want) < 0.002, "vertex %v at %v s is %v, want %v", v, c.time, got, want)
		}
	}
	for v in 0 ..< 2 {
		testing.expect_value(t, transform_point(out[0], data.vertices[v].pos), data.vertices[v].pos)
	}
}

PIP_FEET :: []string{"lower_leg.L", "lower_leg.R"}

// Pip with the Clip ids of Walk and Run, found by name.
pip_mesh :: proc(t: ^testing.T) -> (m: Mesh, walk, run: u32) {
	data, _, err := glb_parse(ANIMATION_PIP_GLB, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	m = Mesh{name = "pip", skin = data.skin, first_clip = 1}
	for clip, i in m.skin.clips {
		switch clip.name {
		case "Walk":
			walk = m.first_clip + u32(i)
		case "Run":
			run = m.first_clip + u32(i)
		}
	}
	testing.expect(t, walk != 0 && run != 0, "Pip has a Walk and a Run Clip")
	return
}

// A ground with the feet as the Roc strings of a Draw.
pip_ground :: proc(feet: []string) -> Skin_Ground {
	strs := make([]Roc_Str, len(feet), context.temp_allocator)
	for name, i in feet {
		strs[i] = roc_str_from_slice(name)
	}
	return {draw = 1, feet = strs}
}

// The lowest foot Joint's height in model space minus its bind height.
pip_foot_drop :: proc(t: ^testing.T, m: ^Mesh, pose: Draw_Pose, ground := Skin_Ground{}) -> f32 {
	table := clip_table()
	defer delete(table.clips_logged)
	defer delete(table.feet_logged)
	out: [MAX_JOINTS]Mat4
	skin_matrices(&table, m, pose, &out, ground)
	drop := f32(math.F32_MAX)
	for name in PIP_FEET {
		j, found := skin_joint(&m.skin, name)
		testing.expectf(t, found, "Pip has the Joint %v", name)
		bind := linalg.inverse(m.skin.joints[j].inverse_bind)
		drop = min(drop, (out[j] * bind)[1, 3] - bind[1, 3])
	}
	return drop
}

// A per-Joint mix of two leg poses shortens the leg. At phase 0 Walk passes
// with its legs straight down, and Run lands with its hips low, so the fade
// sinks a foot that neither Clip sinks alone.
@(test)
test_pip_walk_to_run_fade_sinks_a_foot_below_its_bind_height :: proc(t: ^testing.T) {
	m, walk, run := pip_mesh(t)
	walk_clip, _ := mesh_clip(&m, walk)
	run_clip, _ := mesh_clip(&m, run)
	for phase in ([]f32{0, 0.125, 0.25, 0.375, 0.5}) {
		walk_time := phase * walk_clip.duration
		run_time := phase * run_clip.duration
		testing.expectf(t, pip_foot_drop(t, &m, {clip = walk, time = walk_time}) > -0.001, "Walk alone sinks at phase %v", phase)
		testing.expectf(t, pip_foot_drop(t, &m, {clip = run, time = run_time}) > -0.001, "Run alone sinks at phase %v", phase)
	}
	drop := pip_foot_drop(t, &m, {clip = walk, time = 0, fade_clip = run, fade_time = 0, fade = 0.5})
	testing.expectf(t, drop < -0.01, "the half fade at phase 0 drops the lowest foot %v, want below -0.01", drop)
}

@(test)
test_grounding_lifts_the_sinking_fade_to_the_bind_height :: proc(t: ^testing.T) {
	m, walk, run := pip_mesh(t)
	drop := pip_foot_drop(t, &m, {clip = walk, time = 0, fade_clip = run, fade_time = 0, fade = 0.5}, pip_ground(PIP_FEET))
	testing.expectf(t, abs(drop) < 0.0001, "the grounded half fade drops the lowest foot %v, want 0", drop)
}

// Run at phase 0.25 has both feet 1.34 cm above their bind height.
@(test)
test_grounding_does_not_lower_an_airborne_pose :: proc(t: ^testing.T) {
	m, _, run := pip_mesh(t)
	run_clip, _ := mesh_clip(&m, run)
	pose := Draw_Pose{clip = run, time = 0.25 * run_clip.duration}
	drop := pip_foot_drop(t, &m, pose, pip_ground(PIP_FEET))
	testing.expectf(t, abs(drop - 0.01336) < 0.0001, "the grounded airborne Run has its lowest foot %v above its bind height, want 0.01336", drop)
}

@(test)
test_grounding_skips_an_unknown_foot :: proc(t: ^testing.T) {
	m, walk, run := pip_mesh(t)
	drop := pip_foot_drop(t, &m, {clip = walk, time = 0, fade_clip = run, fade_time = 0, fade = 0.5}, pip_ground({"no_such_foot", "lower_leg.L", "lower_leg.R"}))
	testing.expectf(t, abs(drop) < 0.0001, "the grounded half fade drops the lowest foot %v, want 0", drop)
}
