package engine

import "core:fmt"
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

// The Group or Attach that a Node sits in. A root Node has grouped false.
// An Attach has the draw id and its joint hash, and a Group has joint 0.
Parent_Id :: struct {
	id:      u64,
	grouped:    bool,
	joint_hash: u64,
}

// The parent Group of the Nodes that a walk visits. world is its world Pose
// for this Frame, after interpolation. scene_world is its world Pose in the
// walked Scene, before interpolation. unpaired is set by the pairing build
// for a duplicate Group id or a Group past the capacity. no_world marks the
// Nodes under an Attach in a walk with no joint proc, whose world Pose is
// not known.
Walk_Parent :: struct {
	id:          Parent_Id,
	unpaired:    bool,
	no_world:    bool,
	selected:    bool,
	world:       Pose,
	scene_world: Pose,
}

// A Node of the previous Scene to interpolate from: its parent Group id, its
// local Pose and its world Pose in that Scene. Under an Attach the world Pose
// is not known, so no_world is set.
Prev_Pose :: struct {
	parent:   Parent_Id,
	local:    Pose,
	world:    Pose,
	no_world: bool,
}

// Runs for every Node in depth-first pre-order, before a Group's children.
Tree_Visit :: #type proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent)
// The world Pose of an Attach's Joint. Not ok omits its children.
Attach_Joint :: #type proc(walk: ^Tree_Walk, config: ^Attach_Config) -> (world: Pose, ok: bool)

// With a pairing, the walk interpolates each Group from its partner in the
// previous Scene. Without one, world and scene_world are the same Pose.
// A Group's visit sets group_unpaired, and tree_walk moves it to that
// Group's Walk_Parent. An Attach waits in attaches until the caller runs
// tree_walk_attached after the root Nodes.
Tree_Walk :: struct {
	visit:          Tree_Visit,
	pairing:        ^Pairing,
	alpha:          f32,
	data:           rawptr,
	group_unpaired: bool,
	joint_pose:      Attach_Joint,
	joint_pose_data: rawptr,
	attaches:       [dynamic]Attach_Pending,
}

// Maps each draw id of the previous Scene to its index in prev_draws, and
// each Group id to that Group's Pose. Rebuilt every Frame with clear, so the
// maps keep the capacity init reserved. The Group map takes no more than
// group_capacity Groups, so it never grows. The draw map holds an index, not
// the Draw, so its small value keeps the robin hood moves of an insert short.
Pairing :: struct {
	draws:                  map[u64]i32,
	prev_draws:             [dynamic]Prev_Draw,
	groups:                 map[u64]Prev_Pose,
	logged:                 map[u64]struct {},
	capacity:               int,
	group_capacity:         int,
	draws_seen:             int,
	over_capacity_logged:   bool,
	groups_full_logged:     bool,
	group_duplicate_logged: bool,
}

// A Draw of the previous Scene. pairing_draw makes its Pose when it pairs.
Prev_Draw :: struct {
	draw:            ^Draw,
	parent:          Parent_Id,
	parent_unpaired: bool,
}

// The parent is a pointer, because the walk passes it to every visit. Each
// caller loops over the root Nodes itself: a root Draw, Collider or Speaker is
// at its world Pose already, so only the other root Nodes need the walk.
tree_walk :: proc(walk: ^Tree_Walk, nodes: []Node, parent: ^Walk_Parent) {
	for &node in nodes {
		walk.visit(walk, &node, parent)
		if node.tag == .Attach {
			if walk.attaches == nil {
				walk.attaches = make([dynamic]Attach_Pending, 0, 4, context.temp_allocator)
			}
			append(&walk.attaches, Attach_Pending{attach = &node.payload.attach, selected = parent.selected})
			continue
		}
		if node.tag != .Group {
			continue
		}
		group := &node.payload.group
		g := &group._0
		local := pose_of(g.pos, g.rot)
		child := Walk_Parent {
			id          = {id = g.id, grouped = true},
			unpaired    = walk.group_unpaired,
			no_world    = parent.no_world,
			selected    = parent.selected || g.selected,
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
	case prev.no_world:
		return pose_under(grouped, parent.world, local)
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
scene_colliders :: proc(nodes: []Node, meshes: ^Mesh_Table, allocator: mem.Allocator) -> []Collider {
	// A flat Scene has at most this many Colliders, so it does not grow.
	colliders := make([dynamic]Collider, 0, len(nodes), allocator)
	joints := Scene_Joints{meshes, nodes}
	walk := Tree_Walk {
		visit      = collider_visit,
		data       = &colliders,
		joint_pose      = scene_attach_joint,
		joint_pose_data = &joints,
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
		case .Group, .Attach:
			non_zero_resize(&colliders, count)
			tree_walk(&walk, nodes[i:i + 1], &root)
			spare, count = raw_data(colliders), len(colliders)
		}
	}
	non_zero_resize(&colliders, count)
	tree_walk_attached(&walk)
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

pairing_init :: proc(p: ^Pairing, capacity, group_capacity: int, allocator: mem.Allocator) {
	p.capacity = capacity
	p.group_capacity = group_capacity
	p.draws = make(map[u64]i32, allocator)
	map_reserve_unfilled(&p.draws, capacity)
	p.prev_draws = make([dynamic]Prev_Draw, 0, capacity, allocator)
	p.groups = make(map[u64]Prev_Pose, allocator)
	map_reserve_unfilled(&p.groups, group_capacity)
	p.logged = make(map[u64]struct {}, allocator)
}

pairing_destroy :: proc(p: ^Pairing) {
	delete(p.draws)
	delete(p.prev_draws)
	delete(p.groups)
	delete(p.logged)
}

// On a duplicate draw id the first Draw in walk order wins, and each
// duplicate id is logged once per run. On a duplicate Group id the first
// Group wins, and the first duplicate of the run is logged. Past
// group_capacity, the first Groups pair.
pairing_build :: proc(p: ^Pairing, nodes: []Node) {
	clear(&p.draws)
	clear(&p.prev_draws)
	clear(&p.groups)
	p.draws_seen = 0
	walk := Tree_Walk {
		visit = pairing_visit,
		data  = p,
	}
	root := WALK_ROOT
	for &node, i in nodes {
		if node.tag == .Draw {
			pairing_add(p, &node.payload.draw, root.id, false)
		} else {
			tree_walk(&walk, nodes[i:i + 1], &root)
		}
	}
	tree_walk_attached(&walk)
	if p.draws_seen > p.capacity && !p.over_capacity_logged {
		p.over_capacity_logged = true
		fmt.eprintfln("a Scene has %v draws; the pairing map allocates past %v", p.draws_seen, p.capacity)
	}
}

@(private = "file")
pairing_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent) {
	p := (^Pairing)(walk.data)
	switch node.tag {
	case .Draw:
		pairing_add(p, &node.payload.draw, parent.id, parent.unpaired || parent.no_world)
	case .Group:
		g := node.payload.group._0
		if g.id in p.groups {
			if !p.group_duplicate_logged {
				p.group_duplicate_logged = true
				fmt.eprintfln("two groups share id %v; the first one pairs", g.id)
			}
			walk.group_unpaired = true
			return
		}
		if len(p.groups) == p.group_capacity {
			if !p.groups_full_logged {
				p.groups_full_logged = true
				fmt.eprintfln("a Scene has more than %v groups; the host pairs the first %v", p.group_capacity, p.group_capacity)
			}
			walk.group_unpaired = true
			return
		}
		local := pose_of(g.pos, g.rot)
		p.groups[g.id] = {parent = parent.id, local = local, world = pose_under(parent.id.grouped, parent.scene_world, local), no_world = parent.no_world}
	case .Attach, .Light, .Collider, .Speaker:
	}
}

// An `in` test and an insert cost less here than map_entry.
pairing_add :: #force_inline proc(p: ^Pairing, d: ^Draw, parent: Parent_Id, parent_unpaired: bool) {
	p.draws_seen += 1
	if d.id in p.draws {
		if d.id not_in p.logged {
			p.logged[d.id] = {}
			fmt.eprintfln("two draws share id %v; the first one pairs", d.id)
		}
		return
	}
	p.draws[d.id] = i32(len(p.prev_draws))
	append(&p.prev_draws, Prev_Draw{draw = d, parent = parent, parent_unpaired = parent_unpaired})
}

// The previous Draw with this id and its Pose, for a Draw whose parent is
// now. Not paired when the previous Scene has no such Draw, or when the
// parent changed and the previous parent Group did not pair, so its world
// Pose is unknown.
pairing_draw :: #force_inline proc(p: ^Pairing, id: u64, now: Parent_Id) -> (draw: ^Draw, prev: Prev_Pose, paired: bool) {
	index := p.draws[id] or_return
	entry := &p.prev_draws[index]
	prev = {parent = entry.parent, local = pose_of(entry.draw.pos, entry.draw.rot)}
	prev.world = prev.local
	if entry.parent != now && entry.parent.grouped {
		if entry.parent_unpaired {
			return
		}
		prev.world = pose_compose(pairing_group(p, entry.parent.id).world, prev.local)
	}
	return entry.draw, prev, true
}

// nil when the previous Scene has no paired Group with this id.
pairing_group :: proc(p: ^Pairing, id: u64) -> ^Prev_Pose {
	if found, ok := &p.groups[id]; ok {
		return found
	}
	return nil
}
