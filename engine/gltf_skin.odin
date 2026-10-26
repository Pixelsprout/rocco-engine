package engine

import "core:encoding/endian"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"

// Reads JOINTS_0 and WEIGHTS_0 of a skinned primitive. glb_skin checks the
// joint indices once it knows the Joint count.
glb_add_influences :: proc(l: ^Glb_Loader, p: ^Gltf_Primitive, count: int) -> Glb_Error {
	joints_index, has_joints := p.attributes["JOINTS_0"]
	weights_index, has_weights := p.attributes["WEIGHTS_0"]
	if !has_joints || !has_weights {
		return .No_Influences
	}
	joints := glb_accessor(l, joints_index, "VEC4") or_return
	weights := glb_accessor(l, weights_index, "VEC4") or_return
	if joints.count != count || weights.count != count {
		return .Bad_Accessor
	}
	if joints.component_type != GLTF_U8 && joints.component_type != GLTF_U16 {
		return .Bad_Accessor
	}
	switch weights.component_type {
	case GLTF_U8, GLTF_U16, GLTF_F32:
	case:
		return .Bad_Accessor
	}
	for i in 0 ..< count {
		influence := Glb_Influence {
			weights = glb_weights_u8(glb_read_vec4(weights, i)),
		}
		for k in 0 ..< 4 {
			influence.joints[k] = glb_read_joint(joints, i, k)
		}
		append(&l.influences, influence)
	}
	return .None
}

// The rounding error goes to the largest weight, so the four sum to 255.
// Weights that sum to 0 give all the weight to the first joint.
glb_weights_u8 :: proc(weights: [4]f32) -> [4]u8 {
	w := linalg.max(weights, 0)
	sum := w[0] + w[1] + w[2] + w[3]
	if !(sum > 0) {
		return {255, 0, 0, 0}
	}
	q: [4]int
	total, largest := 0, 0
	for k in 0 ..< 4 {
		q[k] = int(math.round(w[k] / sum * 255))
		total += q[k]
		if w[k] > w[largest] {
			largest = k
		}
	}
	q[largest] += 255 - total
	return {u8(q[0]), u8(q[1]), u8(q[2]), u8(q[3])}
}

// Reads the one Skin and its Clips into frame memory. The Joints go parent
// first, and the influences and channels take the new Joint indices.
glb_skin :: proc(l: ^Glb_Loader) -> (skin: Skin, influences: []Influence, err: Glb_Error) {
	g := &l.gltf
	file_joints := g.skins[0].joints
	count := len(file_joints)
	if count > MAX_JOINTS {
		return {}, nil, .Too_Many_Joints
	}
	if count == 0 {
		return {}, nil, .Bad_Skin
	}
	node_joint := make([]int, len(g.nodes), context.temp_allocator)
	slice.fill(node_joint, -1)
	for node, j in file_joints {
		if node < 0 || node >= len(g.nodes) || node_joint[node] != -1 {
			return {}, nil, .Bad_Skin
		}
		node_joint[node] = j
	}
	node_parent := glb_node_parents(g) or_return

	joints := make([]Joint, count, context.temp_allocator)
	for node, j in file_joints {
		joints[j] = {
			parent       = -1,
			base         = mat4_identity(),
			rest         = glb_node_trs(&g.nodes[node]),
			inverse_bind = mat4_identity(),
		}
		above := node_parent[node]
		for steps := 0; above != -1 && node_joint[above] == -1; steps += 1 {
			if steps == len(g.nodes) {
				return {}, nil, .Bad_Node
			}
			joints[j].base = glb_node_local(&g.nodes[above]) * joints[j].base
			above = node_parent[above]
		}
		if above != -1 {
			joints[j].parent = node_joint[above]
		}
	}
	if index, ok := g.skins[0].inverse_bind_matrices.?; ok {
		matrices := glb_accessor(l, index, "MAT4") or_return
		if matrices.component_type != GLTF_F32 || matrices.count < count {
			return {}, nil, .Bad_Accessor
		}
		for &joint, j in joints {
			joint.inverse_bind = glb_read_mat4(matrices, j)
		}
	}

	rank := glb_joint_rank(joints) or_return
	skin.joints = make([]Joint, count, context.temp_allocator)
	for joint, j in joints {
		skin.joints[rank[j]] = joint
		if joint.parent != -1 {
			skin.joints[rank[j]].parent = rank[joint.parent]
		}
	}
	influences = make([]Influence, len(l.influences), context.temp_allocator)
	for raw, i in l.influences {
		for k in 0 ..< 4 {
			if raw.weights[k] == 0 {
				continue
			}
			if int(raw.joints[k]) >= count {
				return {}, nil, .Bad_Skin
			}
			influences[i].joints[k] = u8(rank[raw.joints[k]])
			influences[i].weights[k] = raw.weights[k]
		}
	}
	glb_clips(l, &skin, node_joint, rank) or_return
	return skin, influences, .None
}

// -1 for a node that is no node's child.
glb_node_parents :: proc(g: ^Gltf) -> (parents: []int, err: Glb_Error) {
	parents = make([]int, len(g.nodes), context.temp_allocator)
	slice.fill(parents, -1)
	for node, i in g.nodes {
		for child in node.children {
			if child < 0 || child >= len(g.nodes) || child == i || parents[child] != -1 {
				return nil, .Bad_Node
			}
			parents[child] = i
		}
	}
	return parents, .None
}

// Gives each Joint a place after its parent, in file order where the file
// already puts parents first.
glb_joint_rank :: proc(joints: []Joint) -> (rank: []int, err: Glb_Error) {
	rank = make([]int, len(joints), context.temp_allocator)
	slice.fill(rank, -1)
	next := 0
	chain: [MAX_JOINTS]int
	for j in 0 ..< len(joints) {
		n := 0
		for at := j; at != -1 && rank[at] == -1; at = joints[at].parent {
			if n == len(joints) {
				return nil, .Bad_Node
			}
			chain[n] = at
			n += 1
		}
		for k := n - 1; k >= 0; k -= 1 {
			rank[chain[k]] = next
			next += 1
		}
	}
	return rank, .None
}

// glTF lets no Clip move a node with a matrix, so its TRS only has to give
// the same matrix.
glb_node_trs :: proc(node: ^Gltf_Node) -> Joint_Trs {
	if m, ok := node.mat.?; ok {
		local := glb_mat4(m)
		basis: linalg.Matrix3f32
		scale: [3]f32
		for col in 0 ..< 3 {
			axis := [3]f32{local[0, col], local[1, col], local[2, col]}
			scale[col] = linalg.length(axis)
			axis = linalg.normalize0(axis)
			basis[0, col], basis[1, col], basis[2, col] = axis.x, axis.y, axis.z
		}
		return {
			translation = {local[0, 3], local[1, 3], local[2, 3]},
			rotation = linalg.quaternion_from_matrix3_f32(basis),
			scale = scale,
		}
	}
	r := node.rotation.? or_else {0, 0, 0, 1}
	return {
		translation = node.translation.? or_else {0, 0, 0},
		rotation = key_rotation(r),
		scale = node.scale.? or_else {1, 1, 1},
	}
}

// A Clip with no name takes its index as its name.
glb_clips :: proc(l: ^Glb_Loader, skin: ^Skin, node_joint, rank: []int) -> Glb_Error {
	g := &l.gltf
	clips := make([]Clip, len(g.animations), context.temp_allocator)
	channels := make([dynamic]Clip_Channel, context.temp_allocator)
	times := make([dynamic]f32, context.temp_allocator)
	values := make([dynamic][4]f32, context.temp_allocator)
	for &a, i in g.animations {
		clip := Clip {
			name          = a.name if a.name != "" else fmt.tprint(i),
			first_channel = len(channels),
		}
		for &c in a.channels {
			if c.sampler < 0 || c.sampler >= len(a.samplers) {
				return .Bad_Clip
			}
			s := &a.samplers[c.sampler]
			interpolation: Clip_Interpolation
			switch s.interpolation {
			case "", "LINEAR":
				interpolation = .Linear
			case "STEP":
				interpolation = .Step
			case "CUBICSPLINE":
				return .Cubic_Spline
			case:
				return .Bad_Clip
			}
			path: Clip_Path
			switch c.target.path {
			case "translation":
				path = .Translation
			case "rotation":
				path = .Rotation
			case "scale":
				path = .Scale
			case:
				l.notes += {.Channel_Skipped}
				continue
			}
			node, targeted := c.target.node.?
			if !targeted {
				l.notes += {.Channel_Skipped}
				continue
			}
			if node < 0 || node >= len(g.nodes) {
				return .Bad_Clip
			}
			if node_joint[node] == -1 {
				l.notes += {.Channel_Skipped}
				continue
			}

			input := glb_accessor(l, s.input, "SCALAR") or_return
			output := glb_accessor(l, s.output, "VEC4" if path == .Rotation else "VEC3") or_return
			if input.component_type != GLTF_F32 {
				return .Bad_Accessor
			}
			switch output.component_type {
			case GLTF_F32:
			case GLTF_I8, GLTF_U8, GLTF_I16, GLTF_U16:
				if path != .Rotation {
					return .Bad_Accessor
				}
			case:
				return .Bad_Accessor
			}
			if input.count == 0 || output.count != input.count {
				return .Bad_Clip
			}
			first_key := len(times)
			for k in 0 ..< input.count {
				time, _ := endian.get_f32(input.data[k * input.stride:], .Little)
				if math.is_nan(time) || (k > 0 && time <= times[len(times) - 1]) {
					return .Bad_Clip
				}
				append(&times, time)
				if path == .Rotation {
					append(&values, linalg.normalize0(glb_read_vec4(output, k)))
				} else {
					v := glb_read_vec3(output, k)
					append(&values, [4]f32{v.x, v.y, v.z, 0})
				}
			}
			clip.duration = max(clip.duration, times[len(times) - 1])
			append(
				&channels,
				Clip_Channel {
					joint = rank[node_joint[node]],
					path = path,
					interpolation = interpolation,
					first_key = first_key,
					key_count = input.count,
				},
			)
		}
		clip.channel_count = len(channels) - clip.first_channel
		clips[i] = clip
	}
	skin.clips = clips
	skin.channels = channels[:]
	skin.times = times[:]
	skin.values = values[:]
	return .None
}

glb_read_mat4 :: proc(v: Glb_View, i: int) -> Mat4 {
	b := v.data[i * v.stride:]
	m: [16]f32
	for k in 0 ..< 16 {
		m[k], _ = endian.get_f32(b[4 * k:], .Little)
	}
	return glb_mat4(m)
}

// Integer components are normalised: unsigned to 0..1, signed to -1..1.
glb_read_vec4 :: proc(v: Glb_View, i: int) -> [4]f32 {
	b := v.data[i * v.stride:]
	out: [4]f32
	for k in 0 ..< 4 {
		switch v.component_type {
		case GLTF_I8:
			out[k] = max(f32(i8(b[k])) / 127, -1)
		case GLTF_U8:
			out[k] = f32(b[k]) / 255
		case GLTF_I16:
			n, _ := endian.get_i16(b[2 * k:], .Little)
			out[k] = max(f32(n) / 32767, -1)
		case GLTF_U16:
			n, _ := endian.get_u16(b[2 * k:], .Little)
			out[k] = f32(n) / 65535
		case:
			out[k], _ = endian.get_f32(b[4 * k:], .Little)
		}
	}
	return out
}

glb_read_joint :: proc(v: Glb_View, i, k: int) -> u16 {
	b := v.data[i * v.stride:]
	if v.component_type == GLTF_U8 {
		return u16(b[k])
	}
	n, _ := endian.get_u16(b[2 * k:], .Little)
	return n
}
