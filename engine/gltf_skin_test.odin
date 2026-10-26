#+test
package engine

import "core:encoding/endian"
import "core:fmt"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:testing"

// The hand-written Skin from examples/tutorial/source/make_meshes.py: Joints
// root, mid and tip up +y, and the Clip Bend.
SKINNED_GLB :: #load("testdata/skinned.glb")
PIP_GLB :: #load("../examples/tutorial/09-gamepad/assets/meshes/pip.glb")
SKIN_FIXTURE_NODE :: `{"name":"strip","mesh":0,"skin":0}`
SKIN_FIXTURE_JOINTS :: `"joints":[1,2,3]`
SKIN_FIXTURE_LAST_NODE :: `{"name":"tip","translation":[0.0,1.0,0.0]}`
// The byte of Bend's second rotation key time in the BIN chunk.
SKIN_FIXTURE_BEND_TIME_1 :: 484

// The fixture with each edit's first string replaced by its second in the JSON.
skinned_glb :: proc(t: ^testing.T, edits: ..[2]string, loc := #caller_location) -> []byte {
	bytes := SKINNED_GLB
	json_chunk, bin, err := glb_chunks(bytes)
	testing.expect_value(t, err, Glb_Error.None, loc = loc)
	json := string(json_chunk)
	for e in edits {
		testing.expectf(t, strings.count(json, e[0]) == 1, "the fixture JSON holds %q once", e[0], loc = loc)
		json, _ = strings.replace(json, e[0], e[1], 1, context.temp_allocator)
	}
	return glb_make(json, bin)
}

// world * inverse bind of each Joint in its rest TRS.
rest_skin_matrices :: proc(skin: Skin) -> []Mat4 {
	world := make([]Mat4, len(skin.joints), context.temp_allocator)
	out := make([]Mat4, len(skin.joints), context.temp_allocator)
	for joint, j in skin.joints {
		local := linalg.matrix4_from_trs_f32(joint.rest.translation, joint.rest.rotation, joint.rest.scale)
		parent := world[joint.parent] if joint.parent != -1 else mat4_identity()
		world[j] = parent * joint.base * local
		out[j] = world[j] * joint.inverse_bind
	}
	return out
}

expect_skin_matrices_near :: proc(t: ^testing.T, skin: Skin, want: Mat4, eps: f32, loc := #caller_location) {
	for got, j in rest_skin_matrices(skin) {
		for c in 0 ..< 4 {
			for r in 0 ..< 4 {
				if abs(got[r, c] - want[r, c]) > eps {
					testing.expectf(t, false, "Joint %v rest skin matrix is %v, want %v", j, got, want, loc = loc)
					return
				}
			}
		}
	}
}

@(test)
test_glb_reads_the_skin_of_the_fixture :: proc(t: ^testing.T) {
	data, notes, err := glb_parse(skinned_glb(t), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	joints := data.skin.joints
	testing.expect_value(t, len(joints), 3)
	for joint, j in joints {
		testing.expect_value(t, joint.parent, j - 1)
		testing.expect_value(t, joint.base, mat4_identity())
		testing.expect_value(t, joint.inverse_bind, mat4_translate({0, -f32(j), 0}))
		testing.expect_value(t, joint.rest.translation, [3]f32{0, 0 if j == 0 else 1, 0})
		testing.expect_value(t, joint.rest.rotation, quaternion128(1))
		testing.expect_value(t, joint.rest.scale, [3]f32{1, 1, 1})
	}
	expect_skin_matrices_near(t, data.skin, mat4_identity(), EPS)
}

@(test)
test_glb_keeps_a_skinned_mesh_in_bind_pose_space :: proc(t: ^testing.T) {
	moved := `{"name":"strip","mesh":0,"skin":0,"translation":[5,0,0],"scale":[2,2,2]}`
	data, _, err := glb_parse(skinned_glb(t, {SKIN_FIXTURE_NODE, moved}), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	want := [6][3]f32{{-0.5, 0, 0}, {0.5, 0, 0}, {-0.5, 1, 0}, {0.5, 1, 0}, {-0.5, 2, 0}, {0.5, 2, 0}}
	testing.expect_value(t, len(data.vertices), 6)
	for v, i in data.vertices {
		testing.expect_value(t, v.pos, want[i])
		testing.expect_value(t, v.normal, [3]f32{0, 0, 1})
	}
}

@(test)
test_glb_gives_each_vertex_weights_that_sum_to_255 :: proc(t: ^testing.T) {
	data, _, err := glb_parse(skinned_glb(t), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	want := [6]Influence {
		{joints = {0, 0, 0, 0}, weights = {255, 0, 0, 0}},
		{joints = {0, 0, 0, 0}, weights = {255, 0, 0, 0}},
		{joints = {0, 1, 0, 0}, weights = {64, 191, 0, 0}},
		{joints = {0, 1, 0, 0}, weights = {64, 191, 0, 0}},
		{joints = {2, 0, 0, 0}, weights = {255, 0, 0, 0}},
		{joints = {2, 0, 0, 0}, weights = {255, 0, 0, 0}},
	}
	testing.expect(t, slice.equal(data.influences, want[:]))
}

@(test)
test_glb_weights_u8_moves_the_rounding_error_to_the_largest_weight :: proc(t: ^testing.T) {
	Case :: struct {
		weights: [4]f32,
		want:    [4]u8,
	}
	cases := []Case {
		{{0.25, 0.75, 0, 0}, {64, 191, 0, 0}},
		{{0.5, 0.5, 0, 0}, {127, 128, 0, 0}},
		{{1.0 / 3, 1.0 / 3, 1.0 / 3, 0}, {85, 85, 85, 0}},
		{{0.2, 0.2, 0.2, 0.2}, {63, 64, 64, 64}},
		{{2, 6, 0, 0}, {64, 191, 0, 0}},
		{{0, 0, 0, 0}, {255, 0, 0, 0}},
	}
	for c in cases {
		got := glb_weights_u8(c.weights)
		testing.expectf(t, got == c.want, "%v gave %v, want %v", c.weights, got, c.want)
		testing.expect_value(t, int(got[0]) + int(got[1]) + int(got[2]) + int(got[3]), 255)
	}
}

@(test)
test_glb_reads_the_bend_clip_with_its_keys :: proc(t: ^testing.T) {
	data, _, err := glb_parse(skinned_glb(t), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	skin := &data.skin
	testing.expect_value(t, len(skin.clips), 1)
	bend := &skin.clips[0]
	testing.expect_value(t, bend.name, "Bend")
	testing.expect_value(t, bend.duration, 1)
	channels := clip_channels(skin, bend)
	testing.expect_value(t, len(channels), 2)

	turn := &channels[0]
	testing.expect_value(t, turn.joint, 1)
	testing.expect_value(t, turn.path, Clip_Path.Rotation)
	testing.expect_value(t, turn.interpolation, Clip_Interpolation.Linear)
	times, values := channel_keys(skin, turn)
	testing.expect(t, slice.equal(times, []f32{0, 0.5, 1}))
	testing.expect_value(t, len(values), 3)
	testing.expect_value(t, values[0], [4]f32{0, 0, 0, 1})
	testing.expectf(t, linalg.length(values[1] - [4]f32{0, 0, 0.70710677, 0.70710677}) < EPS, "the 0.5 s key is %v", values[1])

	lift := &channels[1]
	testing.expect_value(t, lift.joint, 2)
	testing.expect_value(t, lift.path, Clip_Path.Translation)
	testing.expect_value(t, lift.interpolation, Clip_Interpolation.Step)
	times, values = channel_keys(skin, lift)
	testing.expect(t, slice.equal(times, []f32{0, 0.25, 0.75}))
	testing.expect(t, slice.equal(values, [][4]f32{{0, 1, 0, 0}, {0, 1.5, 0, 0}, {0, 1, 0, 0}}))
}

// The file lists tip, mid, root. The inverse bind matrices, the vertex
// joints and the channels follow each Joint to its new index.
@(test)
test_glb_puts_each_joint_after_its_parent :: proc(t: ^testing.T) {
	data, _, err := glb_parse(skinned_glb(t, {SKIN_FIXTURE_JOINTS, `"joints":[3,2,1]`}), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	joints := data.skin.joints
	testing.expect_value(t, len(joints), 3)
	want_inverse_bind := [3]Mat4{mat4_translate({0, -2, 0}), mat4_translate({0, -1, 0}), mat4_identity()}
	for joint, j in joints {
		testing.expect_value(t, joint.parent, j - 1)
		testing.expect_value(t, joint.inverse_bind, want_inverse_bind[j])
	}
	testing.expect_value(t, data.influences[0].joints, [4]u8{2, 0, 0, 0})
	testing.expect_value(t, data.influences[2], Influence{joints = {2, 1, 0, 0}, weights = {64, 191, 0, 0}})
	testing.expect_value(t, data.influences[4].joints, [4]u8{0, 0, 0, 0})
	channels := clip_channels(&data.skin, &data.skin.clips[0])
	testing.expect_value(t, channels[0].joint, 1)
	testing.expect_value(t, channels[1].joint, 2)
}

// Blender's inverse bind matrices include the armature node above the root bone.
@(test)
test_glb_folds_the_nodes_above_the_root_joint_into_its_base :: proc(t: ^testing.T) {
	rig := SKIN_FIXTURE_LAST_NODE + `,{"name":"rig","translation":[0,0,5],"children":[1]}`
	bytes := skinned_glb(t, {`"nodes":[0,1]}]`, `"nodes":[0,4]}]`}, {SKIN_FIXTURE_LAST_NODE, rig})
	data, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, data.skin.joints[0].base, mat4_translate({0, 0, 5}))
	testing.expect_value(t, data.skin.joints[1].base, mat4_identity())
	expect_skin_matrices_near(t, data.skin, mat4_translate({0, 0, 5}), EPS)
}

@(test)
test_glb_reads_pip_as_a_skinned_mesh_with_idle_and_walk :: proc(t: ^testing.T) {
	bytes := PIP_GLB
	data, notes, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.skin.joints), 12)
	testing.expect_value(t, len(data.influences), len(data.vertices))
	for joint, j in data.skin.joints {
		testing.expectf(t, joint.parent < j, "Joint %v has parent %v", j, joint.parent)
	}
	// Blender's float noise in the Joint scales stays far below a visible offset.
	expect_skin_matrices_near(t, data.skin, mat4_identity(), 1e-4)

	want_names := [2]string{"Idle", "Walk"}
	want_durations := [2]f32{2, 1}
	testing.expect_value(t, len(data.skin.clips), 2)
	for &clip, i in data.skin.clips {
		testing.expect_value(t, clip.name, want_names[i])
		testing.expect_value(t, clip.duration, want_durations[i])
		channels := clip_channels(&data.skin, &clip)
		testing.expect_value(t, len(channels), 24)
		for &channel in channels {
			testing.expect_value(t, channel.key_count, 13)
		}
	}
}

@(test)
test_glb_rejects_each_skin_and_clip_the_engine_cannot_draw :: proc(t: ^testing.T) {
	Case :: struct {
		edit: [2]string,
		want: Glb_Error,
	}
	extra_nodes := strings.builder_make(context.temp_allocator)
	joints := strings.builder_make(context.temp_allocator)
	strings.write_string(&extra_nodes, SKIN_FIXTURE_LAST_NODE)
	strings.write_string(&joints, `"joints":[1`)
	for node in 2 ..= MAX_JOINTS + 1 {
		if node > 3 {
			strings.write_string(&extra_nodes, `,{"name":"extra"}`)
		}
		fmt.sbprintf(&joints, ",%v", node)
	}
	strings.write_string(&joints, "]")

	skin :: `{"name":"strip","inverseBindMatrices":5,"joints":[1,2,3]}`
	cases := []Case {
		{{skin, skin + "," + skin}, .Two_Skins},
		{{`"nodes":[0,1]}]`, `"nodes":[0,1,4]}]`}, .None},
		{{`"interpolation":"STEP"`, `"interpolation":"CUBICSPLINE"`}, .Cubic_Spline},
		{{`"JOINTS_0":2,`, ""}, .No_Influences},
		{{SKIN_FIXTURE_JOINTS, `"joints":[1,2]`}, .Bad_Skin},
		{{SKIN_FIXTURE_JOINTS, `"joints":[1,2,2]`}, .Bad_Skin},
		{{SKIN_FIXTURE_JOINTS, `"joints":[1,2,9]`}, .Bad_Skin},
		{{`"skin":0`, `"skin":1`}, .Bad_Skin},
		{{`{"sampler":1,`, `{"sampler":2,`}, .Bad_Clip},
		{{`"interpolation":"STEP"`, `"interpolation":"SMOOTH"`}, .Bad_Clip},
	}
	for c in cases {
		edits := [][2]string{c.edit}
		want := c.want
		// A second mesh node with no skin.
		if c.want == .None {
			edits = {c.edit, {SKIN_FIXTURE_LAST_NODE, SKIN_FIXTURE_LAST_NODE + `,{"mesh":0}`}}
			want = .Mixed_Skinning
		}
		_, _, err := glb_parse(skinned_glb(t, ..edits), context.temp_allocator)
		testing.expectf(t, err == want, "%q gave %v, want %v", c.edit[1], err, want)
	}

	bytes := skinned_glb(t, {SKIN_FIXTURE_LAST_NODE, strings.to_string(extra_nodes)}, {SKIN_FIXTURE_JOINTS, strings.to_string(joints)})
	_, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Too_Many_Joints)
}

@(test)
test_glb_rejects_key_times_that_do_not_rise :: proc(t: ^testing.T) {
	bytes := slice.clone(skinned_glb(t), context.temp_allocator)
	_, bin, _ := glb_chunks(bytes)
	endian.put_f32(bin[SKIN_FIXTURE_BEND_TIME_1:], .Little, 0)
	_, _, err := glb_parse(bytes, context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.Bad_Clip)
}

@(test)
test_glb_skips_a_channel_that_moves_no_joint_and_notes_it :: proc(t: ^testing.T) {
	cases := [][2]string {
		{`"target":{"node":3,"path":"translation"}`, `"target":{"node":0,"path":"translation"}`},
		{`"target":{"node":3,"path":"translation"}`, `"target":{"node":3,"path":"weights"}`},
		{`"target":{"node":3,"path":"translation"}`, `"target":{"path":"translation"}`},
	}
	for c in cases {
		data, notes, err := glb_parse(skinned_glb(t, c), context.temp_allocator)
		testing.expect_value(t, err, Glb_Error.None)
		testing.expect_value(t, notes, Glb_Notes{.Channel_Skipped})
		testing.expect_value(t, data.skin.clips[0].channel_count, 1)
		testing.expect_value(t, data.skin.channels[0].joint, 1)
	}
}

@(test)
test_glb_loads_a_file_with_no_skin_as_a_rigid_mesh_and_ignores_its_clips :: proc(t: ^testing.T) {
	clips := `"animations":[{"name":"Spin","channels":[{"sampler":0,"target":{"node":0,"path":"rotation"}}],"samplers":[{"input":2,"output":0,"interpolation":"CUBICSPLINE"}]}],`
	data, notes, err := glb_parse(triangle_glb(TRIANGLE_PRIMITIVES, extra = clips), context.temp_allocator)
	testing.expect_value(t, err, Glb_Error.None)
	testing.expect_value(t, notes, Glb_Notes{})
	testing.expect_value(t, len(data.vertices), 3)
	testing.expect_value(t, len(data.influences), 0)
	testing.expect_value(t, len(data.skin.joints), 0)
	testing.expect_value(t, len(data.skin.clips), 0)
}
