package engine

import "core:mem"
import "core:slice"
import "core:strings"

// One skin uniform block holds this many Joint matrices.
MAX_JOINTS :: 64

#assert(size_of(Skinned_Vertex) == 56)
#assert(len(Skin_Params{}.joints) == MAX_JOINTS)

Skinned_Vertex :: struct {
	using vertex:    Vertex,
	using influence: Influence,
}

// joints index Skin.joints. weights are out of 255 and sum to 255.
Influence :: struct {
	joints:  [4]u8,
	weights: [4]u8,
}

Joint_Trs :: struct {
	translation: [3]f32,
	rotation:    quaternion128,
	scale:       [3]f32,
}

// A Joint's parent comes before it in Skin.joints, so one pass in order
// gives every world matrix: world = world(parent) * base * local, where a
// parent of -1 gives the identity. base is the fixed transform of the
// non-Joint nodes above the Joint, up to its parent Joint or the scene root,
// such as Blender's armature node. The inverse bind matrices include it.
Joint :: struct {
	parent:       int,
	base:         Mat4,
	rest:         Joint_Trs,
	inverse_bind: Mat4,
}

Clip_Path :: enum u8 {
	Translation,
	Rotation,
	Scale,
}

// A STEP key holds its value until the next key.
Clip_Interpolation :: enum u8 {
	Linear,
	Step,
}

// The keys are Skin.times and Skin.values from first_key, key_count long.
// Times are seconds and strictly rise. A value is x, y, z for a translation
// or scale, and a unit quaternion x, y, z, w for a rotation.
Clip_Channel :: struct {
	joint:         int,
	path:          Clip_Path,
	interpolation: Clip_Interpolation,
	first_key:     int,
	key_count:     int,
}

// The channels are Skin.channels from first_channel, channel_count long. A
// Joint with no channel keeps its rest TRS. duration is the last key time
// of any channel.
Clip :: struct {
	name:          string,
	duration:      f32,
	first_channel: int,
	channel_count: int,
}

// A rigid mesh has the zero Skin. Clip i of a mesh has the Clip id
// Mesh.first_clip + i.
Skin :: struct {
	joints:   []Joint,
	clips:    []Clip,
	channels: []Clip_Channel,
	times:    []f32,
	values:   [][4]f32,
}

mesh_skinned :: proc(m: ^Mesh) -> bool {
	return len(m.skin.joints) > 0
}

// Clip id 0 and the Clips of other meshes are not the mesh's.
mesh_clip :: proc(m: ^Mesh, id: u32) -> (clip: ^Clip, ok: bool) {
	if id == 0 || id < m.first_clip || id - m.first_clip >= u32(len(m.skin.clips)) {
		return nil, false
	}
	return &m.skin.clips[id - m.first_clip], true
}

clip_channels :: proc(s: ^Skin, clip: ^Clip) -> []Clip_Channel {
	return s.channels[clip.first_channel:][:clip.channel_count]
}

channel_keys :: proc(s: ^Skin, channel: ^Clip_Channel) -> (times: []f32, values: [][4]f32) {
	return s.times[channel.first_key:][:channel.key_count], s.values[channel.first_key:][:channel.key_count]
}

skinned_vertices :: proc(vertices: []Vertex, influences: []Influence, allocator: mem.Allocator) -> []Skinned_Vertex {
	out := make([]Skinned_Vertex, len(vertices), allocator)
	for v, i in vertices {
		out[i] = {vertex = v, influence = influences[i]}
	}
	return out
}

skin_clone :: proc(s: Skin, allocator: mem.Allocator) -> Skin {
	out := Skin {
		joints   = slice.clone(s.joints, allocator),
		clips    = slice.clone(s.clips, allocator),
		channels = slice.clone(s.channels, allocator),
		times    = slice.clone(s.times, allocator),
		values   = slice.clone(s.values, allocator),
	}
	for &clip in out.clips {
		clip.name = strings.clone(clip.name, allocator)
	}
	return out
}

skin_delete :: proc(s: Skin, allocator: mem.Allocator) {
	for clip in s.clips {
		delete(clip.name, allocator)
	}
	delete(s.joints, allocator)
	delete(s.clips, allocator)
	delete(s.channels, allocator)
	delete(s.times, allocator)
	delete(s.values, allocator)
}
