package engine

import "core:math/linalg"
import "core:mem"

POSE_IDENTITY :: Pose {
	rot = 1,
}
WALK_ROOT :: Walk_Parent {
	world       = POSE_IDENTITY,
	scene_world = POSE_IDENTITY,
}

// A position and a rotation. pose_compose uses the rule of Pose.compose in
// packages/linalg, so a Roc test and the host agree on a world Pose.
Pose :: struct {
	pos: [3]f32,
	rot: quaternion128,
}

// The Group that a Node sits in. A root Node has grouped false.
Parent_Id :: struct {
	id:      u64,
	grouped: bool,
}

// The parent Group of the Nodes that a walk visits. world is its world Pose
// for this Frame, after interpolation. scene_world is its world Pose in the
// walked Scene, before interpolation. unpaired is set by the pairing build
// for a duplicate Group id or a Group past the capacity.
Walk_Parent :: struct {
	id:          Parent_Id,
	unpaired:    bool,
	world:       Pose,
	scene_world: Pose,
}

// A Node of the previous Scene to interpolate from: its parent Group id, its
// local Pose and its world Pose in that Scene.
Prev_Pose :: struct {
	parent: Parent_Id,
	local:  Pose,
	world:  Pose,
}

// Runs for every Node in depth-first pre-order, before a Group's children.
Tree_Visit :: #type proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent)

// With a pairing, the walk interpolates each Group from its partner in the
// previous Scene. Without one, world and scene_world are the same Pose.
// A Group's visit sets group_unpaired, and tree_walk moves it to that
// Group's Walk_Parent.
Tree_Walk :: struct {
	visit:          Tree_Visit,
	pairing:        ^Pairing,
	alpha:          f32,
	data:           rawptr,
	group_unpaired: bool,
}

// The parent is a pointer, because the walk passes it to every visit. Each
// caller loops over the root Nodes itself: a root Draw, Collider or Speaker is
// at its world Pose already, so only the other root Nodes need the walk.
tree_walk :: proc(walk: ^Tree_Walk, nodes: []Node, parent: ^Walk_Parent) {
	for &node in nodes {
		walk.visit(walk, &node, parent)
		if node.tag != .Group {
			continue
		}
		group := &node.payload.group
		g := &group._0
		local := pose_of(g.pos, g.rot)
		child := Walk_Parent {
			id          = {id = g.id, grouped = true},
			unpaired    = walk.group_unpaired,
			scene_world = pose_under(parent.id.grouped, parent.scene_world, local),
		}
		walk.group_unpaired = false
		if walk.pairing == nil {
			child.world = child.scene_world
		} else {
			child.world = node_world(pairing_group(walk.pairing, g.id), parent, local, walk.alpha)
		}
		tree_walk(walk, group_children(group), &child)
	}
}

group_children :: #force_inline proc(group: ^Group) -> []Node {
	return group._1.elements[:group._1.length]
}

// The Node's Pose for this Frame. If prev has the same parent Group id, the
// local Pose interpolates and then composes, so a child of a turning Group
// follows an arc. If the parent changed, the two world Poses interpolate.
// With no prev, the Node takes its local Pose under the interpolated parent.
node_world :: #force_inline proc(prev: ^Prev_Pose, parent: ^Walk_Parent, local: Pose, alpha: f32) -> Pose {
	grouped := parent.id.grouped
	switch {
	case prev == nil:
		return pose_under(grouped, parent.world, local)
	case prev.parent == parent.id:
		return pose_under(grouped, parent.world, pose_lerp(prev.local, local, alpha))
	case:
		return pose_lerp(prev.world, pose_under(grouped, parent.scene_world, local), alpha)
	}
}

// A root Node's Pose is already in the world, so it skips the arithmetic.
pose_under :: #force_inline proc(grouped: bool, parent, local: Pose) -> Pose {
	if !grouped {
		return local
	}
	return pose_compose(parent, local)
}

pose_compose :: proc(parent, local: Pose) -> Pose {
	return {pos = parent.pos + linalg.quaternion128_mul_vector3(parent.rot, local.pos), rot = parent.rot * local.rot}
}

pose_lerp :: #force_inline proc(a, b: Pose, t: f32) -> Pose {
	return {pos = linalg.lerp(a.pos, b.pos, t), rot = quat_slerp(a.rot, b.rot, t)}
}

pose_of :: #force_inline proc(pos: Vec3, rot: Quat) -> Pose {
	return {pos = vec3_array(pos), rot = quat_of(rot)}
}

// A Group moves and turns a Point and turns a Directional's dir. It does not
// change an Ambient.
light_under :: proc(light: Light, parent: ^Walk_Parent) -> Light {
	if !parent.id.grouped {
		return light
	}
	out := light
	switch light.tag {
	case .Ambient:
	case .Directional:
		dir := linalg.quaternion128_mul_vector3(parent.world.rot, vec3_array(light.payload.directional.dir))
		out.payload.directional.dir = to_vec3(dir)
	case .Point:
		pos := pose_compose(parent.world, {pos = vec3_array(light.payload.point.pos), rot = 1}).pos
		out.payload.point.pos = to_vec3(pos)
	}
	return out
}

// Each Collider of the Scene at its world Pose, in tree order. The Queries
// test these.
scene_colliders :: proc(nodes: []Node, allocator: mem.Allocator) -> []Collider {
	// A flat Scene has at most this many Colliders, so it does not grow.
	colliders := make([dynamic]Collider, 0, len(nodes), allocator)
	walk := Tree_Walk {
		visit = collider_visit,
		data  = &colliders,
	}
	root := WALK_ROOT
	// A root Collider is at its world Pose already. It goes straight into the
	// spare capacity, because append costs twice as much here.
	spare := ([^]Collider)(raw_data(colliders))
	count := 0
	for &node, i in nodes {
		#partial switch node.tag {
		case .Collider:
			if count == cap(colliders) {
				non_zero_resize(&colliders, count)
				reserve(&colliders, 2 * count)
				spare = raw_data(colliders)
			}
			spare[count] = node.payload.collider
			count += 1
		case .Group:
			non_zero_resize(&colliders, count)
			tree_walk(&walk, nodes[i:i + 1], &root)
			spare, count = raw_data(colliders), len(colliders)
		}
	}
	non_zero_resize(&colliders, count)
	return colliders[:]
}

@(private = "file")
collider_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent) {
	if node.tag != .Collider {
		return
	}
	c := node.payload.collider
	world := pose_under(parent.id.grouped, parent.scene_world, pose_of(c.pos, c.rot))
	c.pos = to_vec3(world.pos)
	c.rot = to_quat(world.rot)
	append((^[dynamic]Collider)(walk.data), c)
}
