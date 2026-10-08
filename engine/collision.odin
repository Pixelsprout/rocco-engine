package engine

import "core:fmt"
import "core:math"
import "core:mem"

// The Collider kinds. pf.Collider names them for games. The host does not
// test capsules yet.
COLLIDER_BOX :: u8(0)
COLLIDER_SPHERE :: u8(1)
COLLIDER_CAPSULE :: u8(2)

// What the host has logged this run, so each problem logs once.
Contact_Search :: struct {
	logged_ids:   map[u64]struct {},
	logged_kinds: [256]bool,
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
	kind:     u8,
	centre:   [3]f32,
	extent:   [3]f32,
	axes:     [2][3]f32,
	min, max: [3]f32,
}

contact_search_init :: proc(search: ^Contact_Search, allocator: mem.Allocator) {
	search.logged_ids = make(map[u64]struct {}, allocator)
}

contact_search_destroy :: proc(search: ^Contact_Search) {
	delete(search.logged_ids)
}

// One Contact per overlapping pair, with a < b, sorted by (a, b). Everything
// it allocates, the result included, comes from allocator.
contacts_find :: proc(search: ^Contact_Search, colliders: []Collider, allocator: mem.Allocator) -> []Contact {
	if len(colliders) == 0 {
		return nil
	}

	shapes := make([dynamic]Shape, 0, len(colliders), allocator)
	seen := make(map[u64]struct {}, allocator)
	reserve(&seen, len(colliders))
	for col in colliders {
		if col.kind != COLLIDER_BOX && col.kind != COLLIDER_SPHERE {
			if !search.logged_kinds[col.kind] {
				search.logged_kinds[col.kind] = true
				fmt.eprintfln("collider kind %v is not tested; skipping it (first seen on collider id %v)", col.kind, col.id)
			}
			continue
		}
		// A skipped Collider does not claim its id.
		if col.id in seen {
			if col.id not_in search.logged_ids {
				search.logged_ids[col.id] = {}
				fmt.eprintfln("two colliders share id %v; the first one collides", col.id)
			}
			continue
		}
		seen[col.id] = {}
		append(&shapes, shape_make(col))
	}

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

@(private = "file")
shape_make :: proc(col: Collider) -> Shape {
	b := Shape {
		id     = col.id,
		kind   = col.kind,
		centre = {col.pos.x, col.pos.y, col.pos.z},
		extent = {col.extent.x, col.extent.y, col.extent.z},
	}
	reach: [3]f32
	if col.kind == COLLIDER_SPHERE {
		reach = b.extent.x
	} else {
		// Turned the way the host turns a Draw: +z goes to (sin, 0, cos).
		s, c := math.sincos(col.yaw)
		b.axes = {{c, 0, -s}, {s, 0, c}}
		reach = {abs(c) * b.extent.x + abs(s) * b.extent.z, b.extent.y, abs(s) * b.extent.x + abs(c) * b.extent.z}
	}
	b.min = b.centre - reach
	b.max = b.centre + reach
	return b
}

// The normal points from a to b.
@(private = "file")
narrowphase :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	switch {
	case a.kind == COLLIDER_BOX && b.kind == COLLIDER_BOX:
		return box_box(a, b)
	case a.kind == COLLIDER_SPHERE && b.kind == COLLIDER_SPHERE:
		return sphere_sphere(a, b)
	case a.kind == COLLIDER_BOX:
		return box_sphere(a, b)
	}
	normal, depth = box_sphere(b, a) or_return
	return -normal, depth, true
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
