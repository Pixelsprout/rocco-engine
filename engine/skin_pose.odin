package engine

import "core:fmt"
import "core:math/linalg"

// Fills out with the skin matrices of the Draw's pose and returns the Joint
// count. A fade of 0 samples only pose.clip, and a fade of 1 only
// pose.fade_clip. Clip id 0 alone draws the bind pose; mixed with a Clip it
// gives the rest TRS. A Clip id of another mesh on either side, sampled or
// not, draws the bind pose and logs once, which is the only allocation.
skin_matrices :: proc(t: ^Mesh_Table, m: ^Mesh, pose: Draw_Pose, out: ^[MAX_JOINTS]Mat4) -> int {
	count := len(m.skin.joints)
	fade := clamp(pose.fade, 0, 1)
	first, first_ok := skin_clip(t, m, pose.clip)
	second, second_ok := skin_clip(t, m, pose.fade_clip)
	if fade == 1 {
		first = nil
	}
	if fade == 0 {
		second = nil
	}
	if !first_ok || !second_ok || (first == nil && second == nil) {
		for &mat in out[:count] {
			mat = mat4_identity()
		}
		return count
	}

	a, b: [MAX_JOINTS]Joint_Trs
	skin_sample(&m.skin, first, pose.time, a[:count])
	if fade > 0 {
		skin_sample(&m.skin, second, pose.fade_time, b[:count])
		for &trs, j in a[:count] {
			trs = joint_mix(trs, b[j], fade)
		}
	}
	skin_compose(&m.skin, a[:count], out[:count])
	return count
}

// Clip id 0 gives a nil Clip. An id of another mesh is not ok.
skin_clip :: proc(t: ^Mesh_Table, m: ^Mesh, id: u32) -> (clip: ^Clip, ok: bool) {
	if id == 0 {
		return nil, true
	}
	if clip, ok = mesh_clip(m, id); ok {
		return
	}
	if id not_in t.clips_logged {
		t.clips_logged[id] = {}
		fmt.eprintfln("clip id %v is not a Clip of mesh %q; drawing the bind pose", id, m.name)
	}
	return nil, false
}

// A nil Clip gives the rest TRS.
skin_sample :: proc(s: ^Skin, clip: ^Clip, time: f32, out: []Joint_Trs) {
	if clip == nil {
		for joint, j in s.joints {
			out[j] = joint.rest
		}
		return
	}
	clip_sample(s, clip, time, out)
}

// Fills out with each Joint's local TRS at time. A time before a channel's
// first key gives that key, and a time after its last key gives the last, so
// a time below 0 or past the duration is clamped.
clip_sample :: proc(s: ^Skin, clip: ^Clip, time: f32, out: []Joint_Trs) {
	for joint, j in s.joints {
		out[j] = joint.rest
	}
	for &channel in clip_channels(s, clip) {
		value := channel_sample(s, &channel, time)
		trs := &out[channel.joint]
		switch channel.path {
		case .Translation:
			trs.translation = value.xyz
		case .Rotation:
			trs.rotation = key_rotation(value)
		case .Scale:
			trs.scale = value.xyz
		}
	}
}

channel_sample :: proc(s: ^Skin, channel: ^Clip_Channel, time: f32) -> [4]f32 {
	times, values := channel_keys(s, channel)
	// at is the count of keys at or before time.
	at, above := 0, len(times)
	for at < above {
		mid := (at + above) / 2
		if times[mid] <= time {
			at = mid + 1
		} else {
			above = mid
		}
	}
	if at == 0 {
		return values[0]
	}
	i := at - 1
	if i == len(times) - 1 || channel.interpolation == .Step {
		return values[i]
	}
	weight := (time - times[i]) / (times[i + 1] - times[i])
	if channel.path == .Rotation {
		return rotation_key(quat_slerp(key_rotation(values[i]), key_rotation(values[i + 1]), weight))
	}
	return values[i] + (values[i + 1] - values[i]) * weight
}

// Rotations take the shortest arc.
joint_mix :: proc(a, b: Joint_Trs, weight: f32) -> Joint_Trs {
	return {
		translation = a.translation + (b.translation - a.translation) * weight,
		rotation = quat_slerp(a.rotation, b.rotation, weight),
		scale = a.scale + (b.scale - a.scale) * weight,
	}
}

// out holds each world matrix until the second pass, because a Joint's
// parent comes before it.
skin_compose :: proc(s: ^Skin, locals: []Joint_Trs, out: []Mat4) {
	for joint, j in s.joints {
		local := linalg.matrix4_from_trs_f32(locals[j].translation, locals[j].rotation, locals[j].scale)
		parent := out[joint.parent] if joint.parent != -1 else mat4_identity()
		out[j] = parent * joint.base * local
	}
	for joint, j in s.joints {
		out[j] = out[j] * joint.inverse_bind
	}
}

key_rotation :: proc(v: [4]f32) -> quaternion128 {
	return quaternion(w = v[3], x = v[0], y = v[1], z = v[2])
}

rotation_key :: proc(q: quaternion128) -> [4]f32 {
	return {q.x, q.y, q.z, q.w}
}
