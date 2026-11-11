package engine

import "core:fmt"
import "core:hash"
import "core:math/linalg"
import "core:strings"

// Why an Attach has no Joint to place its children at.
Attach_Miss :: enum u8 {
	None,
	No_Draw,
	No_Skin,
	No_Joint,
}

// An Attach logs once per draw id and joint name.
Attach_Key :: struct {
	draw:  u64,
	joint: u64,
}

// An Attach the walk met. tree_walk_attached walks its children after the
// rest of the tree, so the Draw it names is already placed.
Attach_Pending :: struct {
	attach:   ^Attach,
	selected: bool,
}

// What scene_attach_joint searches: the Scene as the game wrote it, with no
// interpolation.
Scene_Joints :: struct {
	meshes: ^Mesh_Table,
	nodes:  []Node,
}

attach_children :: #force_inline proc(a: ^Attach) -> []Node {
	return a._1.elements[:a._1.length]
}

// The joint hash is never 0, so an Attach never has the id of a Group.
attach_parent_id :: proc(config: ^Attach_Config) -> Parent_Id {
	return {id = config.draw, grouped = true, joint_hash = attach_joint_hash(roc_str_string(&config.joint))}
}

attach_joint_hash :: proc(name: string) -> u64 {
	return hash.fnv64a(transmute([]u8)name) | 1
}

// With no joint_pose, as in the pairing of the previous Scene, the children
// have no known world Pose.
tree_walk_attached :: proc(walk: ^Tree_Walk) {
	for i := 0; i < len(walk.attaches); i += 1 {
		pending := walk.attaches[i]
		config := &pending.attach._0
		parent := Walk_Parent {
			id       = attach_parent_id(config),
			selected = pending.selected,
			world    = POSE_IDENTITY,
		}
		if walk.joint_pose == nil {
			parent.unpaired = true
			parent.no_world = true
		} else {
			world, ok := walk.joint_pose(walk, config)
			if !ok {
				continue
			}
			parent.world = world
		}
		parent.scene_world = parent.world
		tree_walk(walk, attach_children(pending.attach), &parent)
	}
	clear(&walk.attaches)
}

skin_joint :: proc(s: ^Skin, name: string) -> (index: int, found: bool) {
	for joint, j in s.joints {
		if joint.name == name {
			return j, true
		}
	}
	return -1, false
}

// The world Pose of the named Joint of a Draw of mesh m at model and pose.
// The Pose drops the scale of the Draw and of the Joint.
attach_joint_pose :: proc(meshes: ^Mesh_Table, m: ^Mesh, pose: Draw_Pose, ground: Skin_Ground, model: Mat4, name: string) -> (world: Pose, miss: Attach_Miss) {
	if m == nil || !mesh_skinned(m) {
		return {}, .No_Skin
	}
	j, found := skin_joint(&m.skin, name)
	if !found {
		return {}, .No_Joint
	}
	skin: [MAX_JOINTS]Mat4
	skin_matrices(meshes, m, pose, &skin, ground)
	return pose_of_matrix(model * skin[j] * linalg.inverse(m.skin.joints[j].inverse_bind)), .None
}

// The translation and the rotation of an affine matrix. The axes are made
// orthonormal first, so a non-uniform scale under a rotation adds no shear.
pose_of_matrix :: proc(m: Mat4) -> Pose {
	x := v3_normalize_or_zero({m[0, 0], m[1, 0], m[2, 0]})
	y := v3_normalize_or_zero([3]f32{m[0, 1], m[1, 1], m[2, 1]} - v3_dot({m[0, 1], m[1, 1], m[2, 1]}, x) * x)
	z := v3_cross(x, y)
	axes: matrix[3, 3]f32
	for row in 0 ..< 3 {
		axes[row, 0], axes[row, 1], axes[row, 2] = x[row], y[row], z[row]
	}
	return {pos = {m[0, 3], m[1, 3], m[2, 3]}, rot = quat_normalize(linalg.quaternion_from_matrix3_f32(axes))}
}

// m is the mesh of the named Draw, or nil when no Draw has the id.
attach_log :: proc(logged: ^map[Attach_Key]struct {}, config: ^Attach_Config, m: ^Mesh, miss: Attach_Miss) {
	key := Attach_Key{config.draw, attach_joint_hash(roc_str_string(&config.joint))}
	if key in logged {
		return
	}
	logged[key] = {}
	fmt.eprintln(attach_message(config, m, miss))
}

// In the temp allocator.
attach_message :: proc(config: ^Attach_Config, m: ^Mesh, miss: Attach_Miss) -> string {
	name := roc_str_string(&config.joint)
	switch miss {
	case .None:
	case .No_Draw:
		return fmt.tprintf("an Attach names draw id %v, which the Frame did not place; joint %q places no children", config.draw, name)
	case .No_Skin:
		return fmt.tprintf("an Attach names draw id %v, whose mesh %q has no Skin; joint %q places no children", config.draw, m.name, name)
	case .No_Joint:
		return fmt.tprintf("an Attach names joint %q of draw id %v, but mesh %q has no such Joint; its Joints are %v", name, config.draw, m.name, skin_joint_names(&m.skin))
	}
	return ""
}

skin_joint_names :: proc(s: ^Skin) -> string {
	b := strings.builder_make(context.temp_allocator)
	for joint, j in s.joints {
		if j > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_quoted_string(&b, joint.name)
	}
	return strings.to_string(b)
}

// The joint proc of a walk that reads the Scene with no interpolation, such
// as the Collider and Speaker walks. It does not log, because the Frame's
// walk logs the same miss.
scene_attach_joint :: proc(walk: ^Tree_Walk, config: ^Attach_Config) -> (world: Pose, ok: bool) {
	joints := (^Scene_Joints)(walk.joint_pose_data)
	if joints.meshes == nil {
		return
	}
	d, draw_world := scene_draw(joints.nodes, config.draw, POSE_IDENTITY, false) or_return
	m := mesh_lookup(joints.meshes, d.mesh) or_return
	transform := draw_transform(d, d, draw_world, 1)
	miss: Attach_Miss
	world, miss = attach_joint_pose(joints.meshes, m, transform.pose, draw_ground(d), draw_model_matrix(transform), roc_str_string(&config.joint))
	return world, miss == .None
}

// The first Draw with the id in walk order, outside any Attach, and its world
// Pose.
@(private = "file")
scene_draw :: proc(nodes: []Node, id: u64, parent: Pose, grouped: bool) -> (d: ^Draw, world: Pose, found: bool) {
	for &node in nodes {
		#partial switch node.tag {
		case .Draw:
			if node.payload.draw.id == id {
				return &node.payload.draw, pose_under(grouped, parent, pose_of(node.payload.draw.pos, node.payload.draw.rot)), true
			}
		case .Group:
			g := &node.payload.group
			group_world := pose_under(grouped, parent, pose_of(g._0.pos, g._0.rot))
			if d, world, found = scene_draw(group_children(g), id, group_world, true); found {
				return
			}
		}
	}
	return
}
