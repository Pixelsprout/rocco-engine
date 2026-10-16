package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"

// What the host has logged this run, so each problem logs once.
Query_Search :: struct {
	logged_ids:     map[u64]struct {},
	logged_slots:   map[Owner_Slot]struct {},
	logged_capsule: bool,
}

// A Raycast and an Overlap may share an owner and a slot.
Owner_Slot :: struct {
	kind:  Query_Tag,
	owner: u64,
	slot:  u32,
}

// Sorting these instead of Shapes moves 8 bytes per swap, not 80.
@(private = "file")
Sweep_Key :: struct {
	min_x: f32,
	shape: i32,
}

// A Collider in world space. A box keeps its half extents in extent and its
// turned ground-plane axes in axes. A sphere keeps its radius in extent.x.
@(private = "file")
Shape :: struct {
	id:       u64,
	tag:      Collider_Shape_Tag,
	centre:   [3]f32,
	extent:   [3]f32,
	axes:     [2][3]f32,
	min, max: [3]f32,
}

query_search_init :: proc(search: ^Query_Search, allocator: mem.Allocator) {
	search.logged_ids = make(map[u64]struct {}, allocator)
	search.logged_slots = make(map[Owner_Slot]struct {}, allocator)
}

query_search_destroy :: proc(search: ^Query_Search) {
	delete(search.logged_ids)
	delete(search.logged_slots)
}

// One Contact per overlapping pair, with a < b, sorted by (a, b). Everything
// it allocates, the result included, comes from allocator.
contacts_find :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> []Contact {
	if len(colliders) == 0 {
		return nil
	}

	shapes := shapes_make(search, colliders, allocator)

	// Sweep and prune on x: once b starts past a's end, so does every later Shape.
	sweep := make([]Sweep_Key, len(shapes), allocator)
	for shape, i in shapes {
		sweep[i] = {shape.min.x, i32(i)}
	}
	heap_sort(sweep, proc(a, b: Sweep_Key) -> bool {return a.min_x < b.min_x})
	contacts := make([dynamic]Contact, allocator)
	for ka, i in sweep {
		a := &shapes[ka.shape]
		for kb in sweep[i + 1:] {
			if kb.min_x > a.max.x {
				break
			}
			b := &shapes[kb.shape]
			if b.min.y > a.max.y || a.min.y > b.max.y || b.min.z > a.max.z || a.min.z > b.max.z {
				continue
			}
			normal, depth := narrowphase(a^, b^) or_continue
			if a.id > b.id {
				append(&contacts, Contact{a = b.id, b = a.id, normal = to_vec3(-normal), depth = depth})
			} else {
				append(&contacts, Contact{a = a.id, b = b.id, normal = to_vec3(normal), depth = depth})
			}
		}
	}

	heap_sort(contacts[:], proc(x, y: Contact) -> bool {return x.a < y.a || (x.a == y.a && x.b < y.b)})
	return contacts[:]
}

// The Contacts that involve an owner of a ContactsOf Query, in the order
// contacts_find gives. With no such Query, it does no search.
contacts_asked :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Contact {
	owners := make(map[u64]struct {}, allocator)
	for query in queries {
		if query.tag == .ContactsOf {
			owners[query.payload.contacts_of] = {}
		}
	}
	if len(owners) == 0 {
		return nil
	}
	contacts := contacts_find(search, colliders, allocator)
	kept := 0
	for contact in contacts {
		if contact.a in owners || contact.b in owners {
			contacts[kept] = contact
			kept += 1
		}
	}
	return contacts[:kept]
}

// One RayHit for each Raycast that hits, in Query order. A ray that starts
// inside a Collider hits it at its origin, with the normal against dir.
rays_find :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Ray_Hit {
	shapes: [dynamic]Shape
	shapes_made := false
	hits := make([dynamic]Ray_Hit, allocator)
	asked := make(map[Owner_Slot]struct {}, allocator)
	for query in queries {
		if query.tag != .Raycast {
			continue
		}
		ray := query.payload.raycast
		if !query_slot_claim(search, &asked, {.Raycast, ray.owner, ray.slot}) {
			continue
		}
		if !shapes_made {
			shapes = shapes_make(search, colliders, allocator)
			shapes_made = true
		}
		hit, ok := ray_nearest(ray, shapes[:])
		if ok {
			append(&hits, hit)
		}
	}
	return hits[:]
}

// One OverlapHit for each Collider an Overlap touches, in Query order and
// then id order. Touching faces do not overlap.
overlaps_find :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Overlap_Hit {
	shapes: [dynamic]Shape
	shapes_made := false
	hits := make([dynamic]Overlap_Hit, allocator)
	asked := make(map[Owner_Slot]struct {}, allocator)
	for query in queries {
		if query.tag != .Overlap {
			continue
		}
		overlap := query.payload.overlap
		if !query_slot_claim(search, &asked, {.Overlap, overlap.owner, overlap.slot}) {
			continue
		}
		if !shapes_made {
			shapes = shapes_make(search, colliders, allocator)
			shapes_made = true
		}
		probe := overlap_shape_make(overlap)
		exclude := overlap.exclude.elements[:overlap.exclude.length]
		first := len(hits)
		for &shape in shapes {
			if shape.id == overlap.owner || slice.contains(exclude, shape.id) {
				continue
			}
			if _, _, ok := narrowphase(probe, shape); ok {
				append(&hits, Overlap_Hit{owner = overlap.owner, slot = overlap.slot, id = shape.id})
			}
		}
		heap_sort(hits[first:], proc(x, y: Overlap_Hit) -> bool {return x.id < y.id})
	}
	return hits[:]
}

// false for a second Query with the same owner and slot. It logs each once.
@(private = "file")
query_slot_claim :: proc(search: ^Query_Search, asked: ^map[Owner_Slot]struct {}, key: Owner_Slot) -> bool {
	if key in asked {
		if key not_in search.logged_slots {
			search.logged_slots[key] = {}
			fmt.eprintfln("two queries share owner %v and slot %v; the first one is answered", key.owner, key.slot)
		}
		return false
	}
	asked[key] = {}
	return true
}

@(private = "file")
ray_nearest :: proc(ray: Query_Raycast, shapes: []Shape) -> (hit: Ray_Hit, ok: bool) {
	dir := [3]f32{ray.dir.x, ray.dir.y, ray.dir.z}
	length := v3_length(dir)
	if length == 0 {
		return {}, false
	}
	dir /= length
	origin := [3]f32{ray.origin.x, ray.origin.y, ray.origin.z}
	exclude := ray.exclude.elements[:ray.exclude.length]

	nearest := ray.max_distance
	normal: [3]f32
	for &shape in shapes {
		if shape.id == ray.owner || slice.contains(exclude, shape.id) {
			continue
		}
		distance, n := ray_shape(origin, dir, shape) or_continue
		// Equal distances go to the lower id, so the Collider order does not matter.
		if distance < nearest || (distance == nearest && (!ok || shape.id < hit.id)) {
			nearest = distance
			normal = n
			hit.id = shape.id
			ok = true
		}
	}
	if !ok {
		return {}, false
	}
	hit.owner = ray.owner
	hit.slot = ray.slot
	hit.point = to_vec3(origin + dir * nearest)
	hit.normal = to_vec3(normal)
	hit.distance = nearest
	return hit, true
}

// dir is a unit vector. shape_make never makes a capsule.
@(private = "file")
ray_shape :: proc(origin, dir: [3]f32, shape: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	switch shape.tag {
	case .Box:
		return ray_box(origin, dir, shape)
	case .Sphere:
		return ray_sphere(origin, dir, shape)
	case .Capsule:
	}
	return 0, {}, false
}

// A slab test in the box's frame.
@(private = "file")
ray_box :: proc(origin, dir: [3]f32, box: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	d := origin - box.centre
	local_origin := [3]f32{v3_dot(d, box.axes[0]), d.y, v3_dot(d, box.axes[1])}
	local_dir := [3]f32{v3_dot(dir, box.axes[0]), dir.y, v3_dot(dir, box.axes[1])}

	enter, exit := min(f32), max(f32)
	local_normal: [3]f32
	for i in 0 ..< 3 {
		if local_dir[i] == 0 {
			if abs(local_origin[i]) > box.extent[i] {
				return 0, {}, false
			}
			continue
		}
		near := (-math.sign(local_dir[i]) * box.extent[i] - local_origin[i]) / local_dir[i]
		far := (math.sign(local_dir[i]) * box.extent[i] - local_origin[i]) / local_dir[i]
		if near > enter {
			enter = near
			local_normal = {}
			local_normal[i] = -math.sign(local_dir[i])
		}
		exit = min(exit, far)
	}
	if exit < max(enter, 0) {
		return 0, {}, false
	}
	if enter <= 0 {
		return 0, -dir, true
	}
	return enter, local_normal.x * box.axes[0] + local_normal.y * UP + local_normal.z * box.axes[1], true
}

@(private = "file")
ray_sphere :: proc(origin, dir: [3]f32, sphere: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	d := origin - sphere.centre
	radius := sphere.extent.x
	inside := v3_dot(d, d) - radius * radius
	if inside <= 0 {
		return 0, -dir, true
	}
	along := v3_dot(d, dir)
	disc := along * along - inside
	if along >= 0 || disc < 0 {
		return 0, {}, false
	}
	distance = -along - math.sqrt(disc)
	return distance, (d + dir * distance) / radius, true
}

// Each Collider the host can test, with each id once. It logs a capsule and
// a shared id once each.
@(private = "file")
shapes_make :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> [dynamic]Shape {
	shapes := make([dynamic]Shape, 0, len(colliders), allocator)
	seen := make(map[u64]struct {}, allocator)
	reserve(&seen, len(colliders))
	for col in colliders {
		// A skipped Collider does not claim its id.
		shape, ok := shape_make(col)
		if !ok {
			if !search.logged_capsule {
				search.logged_capsule = true
				fmt.eprintfln("collider %v is a capsule; queries skip capsules", col.id)
			}
			continue
		}
		if col.id in seen {
			if col.id not_in search.logged_ids {
				search.logged_ids[col.id] = {}
				fmt.eprintfln("two colliders share id %v; the first one collides", col.id)
			}
			continue
		}
		seen[col.id] = {}
		append(&shapes, shape)
	}
	return shapes
}

// ok is false for a capsule: the host does not test capsules yet.
@(private = "file")
shape_make :: proc(col: Collider) -> (b: Shape, ok: bool) {
	b = Shape {
		id     = col.id,
		tag    = col.shape.tag,
		centre = {col.pos.x, col.pos.y, col.pos.z},
	}
	reach: [3]f32
	switch col.shape.tag {
	case .Box:
		half := col.shape.payload.box
		b.extent = {half.x, half.y, half.z}
		// Turned the way the host turns a Draw: +z goes to (sin, 0, cos).
		s, c := math.sincos(col.yaw)
		b.axes = {{c, 0, -s}, {s, 0, c}}
		reach = {abs(c) * b.extent.x + abs(s) * b.extent.z, b.extent.y, abs(s) * b.extent.x + abs(c) * b.extent.z}
	case .Sphere:
		b.extent.x = col.shape.payload.sphere
		reach = b.extent.x
	case .Capsule:
		return {}, false
	}
	b.min = b.centre - reach
	b.max = b.centre + reach
	return b, true
}

// An Overlap box does not turn.
@(private = "file")
overlap_shape_make :: proc(overlap: Query_Overlap) -> Shape {
	shape := Shape {
		centre = {overlap.pos.x, overlap.pos.y, overlap.pos.z},
		axes   = {{1, 0, 0}, {0, 0, 1}},
	}
	switch overlap.shape.tag {
	case .Box:
		half := overlap.shape.payload.box
		shape.tag = .Box
		shape.extent = {half.x, half.y, half.z}
	case .Sphere:
		shape.tag = .Sphere
		shape.extent.x = overlap.shape.payload.sphere
	}
	return shape
}

// The normal points from a to b. shape_make never makes a capsule.
@(private = "file")
narrowphase :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	switch a.tag {
	case .Box:
		switch b.tag {
		case .Box:
			return box_box(a, b)
		case .Sphere:
			return box_sphere(a, b)
		case .Capsule:
		}
	case .Sphere:
		switch b.tag {
		case .Box:
			normal, depth = box_sphere(b, a) or_return
			return -normal, depth, true
		case .Sphere:
			return sphere_sphere(a, b)
		case .Capsule:
		}
	case .Capsule:
	}
	return {}, 0, false
}

// A separating axis test on y and the ground-plane axes of each box. A box
// only turns about y, so no edge cross product can separate them.
@(private = "file")
box_box :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := b.centre - a.centre
	depth = max(f32)
	for axis in ([5][3]f32{UP, a.axes[0], a.axes[1], b.axes[0], b.axes[1]}) {
		along := v3_dot(d, axis)
		overlap := box_reach(a, axis) + box_reach(b, axis) - abs(along)
		if overlap <= 0 {
			return {}, 0, false
		}
		if overlap < depth {
			depth = overlap
			normal = axis if along >= 0 else -axis
		}
	}
	return normal, depth, true
}

@(private = "file")
box_reach :: proc(box: Shape, axis: [3]f32) -> f32 {
	return box.extent.x * abs(v3_dot(box.axes[0], axis)) + box.extent.y * abs(axis.y) + box.extent.z * abs(v3_dot(box.axes[1], axis))
}

// Two spheres at the same centre push apart along +y.
@(private = "file")
sphere_sphere :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := b.centre - a.centre
	dist := v3_length(d)
	depth = a.extent.x + b.extent.x - dist
	if depth <= 0 {
		return {}, 0, false
	}
	return d / dist if dist > 0 else UP, depth, true
}

// The normal points from the box to the sphere. A sphere whose centre is
// inside the box leaves through the face nearest its centre.
@(private = "file")
box_sphere :: proc(box, sphere: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := sphere.centre - box.centre
	local := [3]f32{v3_dot(d, box.axes[0]), d.y, v3_dot(d, box.axes[1])}
	off := local - [3]f32{clamp(local.x, -box.extent.x, box.extent.x), clamp(local.y, -box.extent.y, box.extent.y), clamp(local.z, -box.extent.z, box.extent.z)}
	dist := v3_length(off)
	radius := sphere.extent.x

	local_normal: [3]f32
	if dist > 0 {
		if dist >= radius {
			return {}, 0, false
		}
		local_normal = off / dist
		depth = radius - dist
	} else {
		depth = max(f32)
		for i in 0 ..< 3 {
			through := box.extent[i] - abs(local[i]) + radius
			if through < depth {
				depth = through
				local_normal = {}
				local_normal[i] = 1 if local[i] >= 0 else -1
			}
		}
	}
	return local_normal.x * box.axes[0] + local_normal.y * UP + local_normal.z * box.axes[1], depth, true
}

// slice.sort_by calls less through a pointer and swaps bytes. This one is
// built per element type and less.
@(private = "file")
heap_sort :: proc(data: []$T, $less: proc(a, b: T) -> bool) {
	sift :: #force_inline proc(data: []T, root, n: int) {
		root := root
		for {
			child := 2 * root + 1
			if child >= n {
				return
			}
			if child + 1 < n && less(data[child], data[child + 1]) {
				child += 1
			}
			if !less(data[root], data[child]) {
				return
			}
			data[root], data[child] = data[child], data[root]
			root = child
		}
	}
	n := len(data)
	for i := n / 2 - 1; i >= 0; i -= 1 {
		sift(data, i, n)
	}
	for end := n - 1; end > 0; end -= 1 {
		data[0], data[end] = data[end], data[0]
		sift(data, 0, end)
	}
}

@(private = "file")
to_vec3 :: proc(v: [3]f32) -> Vec3 {
	return {v.x, v.y, v.z}
}
