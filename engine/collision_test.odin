#+test
package engine

import "core:log"
import "core:math"
import "core:math/rand"
import vmem "core:mem/virtual"
import "core:testing"
import "core:time"

COLLISION_EPS :: f32(1e-4)
TIMING_COLLIDERS :: 1000
// The random scenes: spheres over a square RANDOM_HALF units from the centre.
RANDOM_SPHERES :: 3000
RANDOM_HALF :: f32(40)

test_box :: proc(id: u64, pos: [3]f32, rot: Quat, half: [3]f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, rot = rot, shape = {payload = {box = {half.x, half.y, half.z}}, tag = .Box}}
}

test_sphere :: proc(id: u64, pos: [3]f32, radius: f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, rot = IDENTITY, shape = {payload = {sphere = radius}, tag = .Sphere}}
}

contacts_of :: proc(search: ^Query_Search, colliders: ..Collider) -> []Contact {
	return contacts_find(search, colliders, context.temp_allocator)
}

expect_contact :: proc(t: ^testing.T, got: Contact, a, b: u64, normal: [3]f32, depth: f32, loc := #caller_location) {
	testing.expect_value(t, got.a, a, loc = loc)
	testing.expect_value(t, got.b, b, loc = loc)
	n := [3]f32{got.normal.x, got.normal.y, got.normal.z}
	testing.expectf(t, v3_length(n - normal) < COLLISION_EPS, "normal %v, expected %v", n, normal, loc = loc)
	testing.expectf(t, abs(got.depth - depth) < COLLISION_EPS, "depth %v, expected %v", got.depth, depth, loc = loc)
}

test_contacts_of :: proc(owner: u64) -> Query {
	return {payload = {contacts_of = owner}, tag = .ContactsOf}
}

test_ray :: proc(owner: u64, slot: u32, origin, dir: [3]f32, max_distance: f32, exclude: []u64 = nil) -> Query {
	ray := Query_Raycast {
		owner        = owner,
		slot         = slot,
		origin       = {origin.x, origin.y, origin.z},
		dir          = {dir.x, dir.y, dir.z},
		max_distance = max_distance,
		exclude      = {elements = raw_data(exclude), length = uint(len(exclude))},
	}
	return {payload = {raycast = ray}, tag = .Raycast}
}

test_turn :: proc(axis: [3]f32, rad: f32) -> Quat {
	q := quat_from_axis_angle(axis, rad)
	return {w = q.w, x = q.x, y = q.y, z = q.z}
}

// b first, then a, as Quat.mul in packages/linalg.
test_turn_then :: proc(a, b: Quat) -> Quat {
	q := quaternion(w = a.w, x = a.x, y = a.y, z = a.z) * quaternion(w = b.w, x = b.x, y = b.y, z = b.z)
	return {w = q.w, x = q.x, y = q.y, z = q.z}
}

test_capsule :: proc(id: u64, pos: [3]f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, rot = IDENTITY, shape = {payload = {capsule = {radius = 1, half_height = 1}}, tag = .Capsule}}
}

rays_of :: proc(search: ^Query_Search, colliders: []Collider, queries: ..Query) -> []Ray_Hit {
	return rays_find(search, colliders, queries, context.temp_allocator)
}

expect_ray_hit :: proc(t: ^testing.T, got: Ray_Hit, owner: u64, slot: u32, id: u64, point, normal: [3]f32, distance: f32, loc := #caller_location) {
	testing.expect_value(t, got.owner, owner, loc = loc)
	testing.expect_value(t, got.slot, slot, loc = loc)
	testing.expect_value(t, got.id, id, loc = loc)
	p := [3]f32{got.point.x, got.point.y, got.point.z}
	n := [3]f32{got.normal.x, got.normal.y, got.normal.z}
	testing.expectf(t, v3_length(p - point) < COLLISION_EPS, "point %v, expected %v", p, point, loc = loc)
	testing.expectf(t, v3_length(n - normal) < COLLISION_EPS, "normal %v, expected %v", n, normal, loc = loc)
	testing.expectf(t, abs(got.distance - distance) < COLLISION_EPS, "distance %v, expected %v", got.distance, distance, loc = loc)
}

test_overlap_box :: proc(owner: u64, slot: u32, pos, half: [3]f32, exclude: []u64 = nil) -> Query {
	overlap := Query_Overlap {
		owner   = owner,
		slot    = slot,
		shape   = {payload = {box = {half.x, half.y, half.z}}, tag = .Box},
		pos     = {pos.x, pos.y, pos.z},
		exclude = {elements = raw_data(exclude), length = uint(len(exclude))},
	}
	return {payload = {overlap = overlap}, tag = .Overlap}
}

test_overlap_sphere :: proc(owner: u64, slot: u32, pos: [3]f32, radius: f32, exclude: []u64 = nil) -> Query {
	overlap := Query_Overlap {
		owner   = owner,
		slot    = slot,
		shape   = {payload = {sphere = radius}, tag = .Sphere},
		pos     = {pos.x, pos.y, pos.z},
		exclude = {elements = raw_data(exclude), length = uint(len(exclude))},
	}
	return {payload = {overlap = overlap}, tag = .Overlap}
}

overlaps_of :: proc(search: ^Query_Search, colliders: []Collider, queries: ..Query) -> []Overlap_Hit {
	return overlaps_find(search, colliders, queries, context.temp_allocator)
}

expect_overlap_hits :: proc(t: ^testing.T, got: []Overlap_Hit, want: []Overlap_Hit, loc := #caller_location) {
	if !testing.expect_value(t, len(got), len(want), loc = loc) {
		return
	}
	for hit, i in want {
		testing.expect_value(t, got[i], hit, loc = loc)
	}
}

@(test)
test_contact_search_box_box_overlap_takes_the_least_overlap_axis :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(2, {1.8, 0.5, 0}, IDENTITY, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.2)
}

@(test)
test_contact_search_box_box_apart_has_no_contact :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(2, {2.5, 0, 0}, IDENTITY, {1, 1, 1}))), 0)
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(2, {0, 2.5, 0}, IDENTITY, {1, 1, 1}))), 0)
}

@(test)
test_contact_search_box_box_stacked_pushes_along_y :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 1.9, 0}, IDENTITY, {1, 1, 1}), test_box(2, {0.2, 0, 0}, IDENTITY, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, -1, 0}, 0.1)
}

// The AABBs of these boxes overlap, but the turned box's corner stops short.
@(test)
test_contact_search_box_box_honours_yaw :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	turned := test_box(2, {2.3, 0, 2.3}, quat_yaw(math.PI / 4), {1, 1, 1})
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), turned)), 0)

	// Turned a quarter, a long thin box covers z instead of x.
	long := test_box(4, {0.2, 0, 1.5}, quat_yaw(math.PI / 2), {2, 1, 0.1})
	got := contacts_of(&search, test_box(3, {0, 0, 0}, IDENTITY, {1, 1, 1}), long)
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 3, 4, {1, 0, 0}, 0.9)
}

// At a quarter turn, +yaw and -yaw give the same axes up to sign. A sixth of
// a turn does not, so this fails if the host turns boxes the wrong way.
@(test)
test_contact_search_box_turns_the_way_a_draw_does :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	yaw := f32(math.PI / 6)
	s, c := math.sincos(yaw)
	along := [3]f32{c, 0, -s}
	across := [3]f32{s, 0, c}
	got := contacts_of(&search, test_box(1, {0, 0, 0}, quat_yaw(yaw), {2, 1, 0.1}), test_sphere(2, 1.8 * along + 0.05 * across, 0.3))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, across, 0.35)
}

// Pitched 45 degrees about x, a tall thin box leans over a small box that it
// misses when upright.
@(test)
test_contact_search_box_box_honours_pitch :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	small := test_box(2, {0, 0.55, 0.65}, IDENTITY, {1, 0.1, 0.1})
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 0.1}), small)), 0)

	pitched := test_turn({1, 0, 0}, math.PI / 4)
	got := contacts_of(&search, test_box(1, {0, 0, 0}, pitched, {1, 1, 0.1}), small)
	testing.expect_value(t, len(got), 1)
	h := f32(math.SQRT_TWO / 2)
	expect_contact(t, got[0], 1, 2, {0, -h, h}, 0.1 + 0.1 * math.SQRT_TWO - 0.1 * h)
}

// Two cubes meet edge to edge: an edge along a's z and an edge along b's y.
// No face axis of either cube separates them, so only the cross product of
// the two edges finds the gap or the overlap.
@(test)
test_contact_search_box_box_edge_axis_decides :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	turn := test_turn(UP, math.PI / 6)
	a := test_box(1, {0, 0, 0}, test_turn_then(turn, test_turn({0, 0, 1}, math.PI / 4)), {1, 1, 1})
	b_rot := test_turn_then(turn, test_turn(UP, math.PI / 4))
	s, c := math.sincos(f32(math.PI / 6))
	across := [3]f32{c, 0, -s}

	apart := test_box(2, (2 * math.SQRT_TWO + 0.1) * across, b_rot, {1, 1, 1})
	testing.expect_value(t, len(contacts_of(&search, a, apart)), 0)

	got := contacts_of(&search, a, test_box(2, (2 * math.SQRT_TWO - 0.1) * across, b_rot, {1, 1, 1}))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, across, 0.1)
}

// Rolled a quarter about z, the box's long x half stands along y.
@(test)
test_contact_search_box_sphere_honours_roll :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	sphere := test_sphere(2, {0, 2.25, 0}, 0.5)
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {2, 0.1, 0.5}), sphere)), 0)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, test_turn({0, 0, 1}, math.PI / 2), {2, 0.1, 0.5}), sphere)
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 1, 0}, 0.25)
}

@(test)
test_contact_search_sphere_sphere :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), test_sphere(2, {0, 0, 1.5}, 1))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, 1}, 0.5)

	testing.expect_value(t, len(contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), test_sphere(2, {1.5, 1.5, 0}, 1))), 0)
}

@(test)
test_contact_search_box_sphere_beside_the_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(2, {1.25, 0, 0}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.25)

	// Past the corner on the diagonal, the sphere misses the box.
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(2, {1.4, 0, 1.4}, 0.5))), 0)
}

@(test)
test_contact_search_box_sphere_with_its_centre_inside_the_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(2, {0, 0, -0.75}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, -1}, 0.75)
}

@(test)
test_contact_search_box_sphere_honours_yaw :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// Turned a quarter, the box's long side lies along z.
	got := contacts_of(&search, test_box(1, {0, 0, 0}, quat_yaw(math.PI / 2), {2, 1, 0.5}), test_sphere(2, {0, 0, 2.25}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, 1}, 0.25)
}

// The normal points from the lower id to the higher, whichever shape comes first.
@(test)
test_contact_search_normal_points_from_the_lower_id :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(9, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(3, {1.25, 0, 0}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 3, 9, {-1, 0, 0}, 0.25)
}

@(test)
test_contacts_find_are_sorted_by_a_then_b :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A row of spheres where neighbours touch, listed out of order.
	got := contacts_of(
		&search,
		test_sphere(30, {2.7, 0, 0}, 0.5),
		test_sphere(10, {0, 0, 0}, 0.5),
		test_sphere(40, {-0.9, 0, 0}, 0.5),
		test_sphere(20, {1.8, 0, 0}, 0.5),
		test_sphere(50, {0.9, 0, 0}, 0.5),
	)

	want := [][2]u64{{10, 40}, {10, 50}, {20, 30}, {20, 50}}
	testing.expect_value(t, len(got), len(want))
	for w, i in want {
		if i < len(got) {
			testing.expect_value(t, [2]u64{got[i].a, got[i].b}, w)
		}
	}
}

// Overlap on x alone is not a contact: the scan still tests y and z.
@(test)
test_contact_search_broadphase_needs_overlap_on_every_axis :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(2, {0.5, 0, 5}, IDENTITY, {1, 1, 1}), test_box(3, {0.5, 5, 0}, IDENTITY, {1, 1, 1}))
	testing.expect_value(t, len(got), 0)
}

@(test)
test_contact_search_duplicate_id_keeps_the_first_and_logs_once :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	first := test_sphere(1, {0, 0, 0}, 0.5)
	second := test_sphere(1, {5, 0, 0}, 0.5)
	near_second := test_sphere(2, {5.5, 0, 0}, 0.5)

	testing.expect_value(t, len(contacts_of(&search, first, second, near_second)), 0)
	testing.expect_value(t, len(contacts_of(&search, first, second, near_second)), 0)
	testing.expect_value(t, len(search.logged_ids), 1)
}

@(test)
test_contact_search_capsule_is_skipped :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	testing.expect_value(t, len(contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), test_capsule(2, {0, 0, 0}))), 0)
	testing.expect(t, search.logged_capsule)
}

@(test)
test_contact_search_no_colliders_gives_no_contacts :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	testing.expect_value(t, len(contacts_find(&search, nil, context.temp_allocator)), 0)
}

// Times the host at 1,000 colliders on a static arena, as the frame arena is.
// docs/DESIGN.md section 10 records the result.
@(test)
test_contact_search_timing_at_1000_colliders :: proc(t: ^testing.T) {
	arena: vmem.Arena
	testing.expect_value(t, vmem.arena_init_static(&arena, FRAME_ARENA_RESERVE), nil)
	defer vmem.arena_destroy(&arena)

	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	r := rand.create(1)
	context.random_generator = rand.default_random_generator(&r)
	colliders := make([]Collider, TIMING_COLLIDERS, context.temp_allocator)
	for &col, i in colliders {
		pos := [3]f32{rand.float32_range(-50, 50), 0.5, rand.float32_range(-50, 50)}
		col = test_box(u64(i), pos, quat_yaw(rand.float32_range(-math.PI, math.PI)), {0.5, 0.5, 0.5}) if i % 2 == 0 else test_sphere(u64(i), pos, 0.5)
	}

	RUNS :: 50
	contacts := 0
	start := time.tick_now()
	for _ in 0 ..< RUNS {
		contacts = len(contacts_find(&search, colliders, vmem.arena_allocator(&arena)))
		vmem.arena_free_all(&arena)
	}
	mean := time.duration_microseconds(time.tick_since(start)) / RUNS

	log.infof("%v colliders, %v contacts, mean %.1f us", TIMING_COLLIDERS, contacts, mean)
	testing.expect(t, contacts > 0)
}

@(test)
test_contacts_asked_with_no_contacts_of_query_is_empty :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A search would log the shared id.
	colliders := []Collider{test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(1, {1, 0, 0}, IDENTITY, {1, 1, 1})}
	testing.expect_value(t, len(contacts_asked(&search, colliders, nil, context.temp_allocator)), 0)
	testing.expect_value(t, len(search.logged_ids), 0)
}

@(test)
test_contacts_asked_keeps_only_the_pairs_of_an_asking_owner :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// 1 touches 2, and 3 touches 4. Only 4 asks.
	colliders := []Collider {
		test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}),
		test_box(2, {1, 0, 0}, IDENTITY, {1, 1, 1}),
		test_box(3, {10, 0, 0}, IDENTITY, {1, 1, 1}),
		test_box(4, {11, 0, 0}, IDENTITY, {1, 1, 1}),
	}
	got := contacts_asked(&search, colliders, []Query{test_contacts_of(4)}, context.temp_allocator)

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 3, 4, {1, 0, 0}, 1)
}

@(test)
test_contacts_asked_gives_a_pair_of_two_asking_owners_once :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(2, {1, 0, 0}, IDENTITY, {1, 1, 1})}
	got := contacts_asked(&search, colliders, []Query{test_contacts_of(2), test_contacts_of(1), test_contacts_of(2)}, context.temp_allocator)

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 1)
}

@(test)
test_contacts_asked_are_in_id_order :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider {
		test_sphere(9, {0, 0, 0}, 1),
		test_sphere(5, {1, 0, 0}, 1),
		test_sphere(7, {2, 0, 0}, 1),
		test_sphere(2, {1, 1, 0}, 1),
	}
	got := contacts_asked(&search, colliders, []Query{test_contacts_of(9), test_contacts_of(5)}, context.temp_allocator)

	pairs := make([][2]u64, len(got), context.temp_allocator)
	for c, i in got {
		pairs[i] = {c.a, c.b}
	}
	// 7 and 2 touch, but neither asks.
	testing.expect_value(t, len(pairs), 4)
	want := [][2]u64{{2, 5}, {2, 9}, {5, 7}, {5, 9}}
	for p, i in want {
		if i < len(pairs) {
			testing.expect_value(t, pairs[i], p)
		}
	}
}

@(test)
test_contacts_asked_with_only_a_raycast_does_no_search :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A search would log the shared id.
	colliders := []Collider{test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_box(1, {1, 0, 0}, IDENTITY, {1, 1, 1})}
	queries := []Query{test_ray(1, 0, {0, 5, 0}, {0, -1, 0}, 10)}
	testing.expect_value(t, len(contacts_asked(&search, colliders, queries, context.temp_allocator)), 0)
	testing.expect_value(t, len(search.logged_ids), 0)
}

@(test)
test_rays_find_hits_the_top_of_a_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := rays_of(&search, {test_box(2, {0, 0, 0}, IDENTITY, {1, 1, 1})}, test_ray(7, 0, {0.5, 5, 0}, {0, -1, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {0.5, 1, 0}, {0, 1, 0}, 4)
}

@(test)
test_rays_find_hits_a_turned_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A quarter turn lays the long x half along z.
	got := rays_of(&search, {test_box(2, {0, 0, 0}, quat_yaw(math.PI / 2), {2, 1, 1})}, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {-1, 0, 0}, {-1, 0, 0}, 4)
}

@(test)
test_rays_find_hits_a_pitched_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A quarter turn about x lays the long y half along z.
	got := rays_of(&search, {test_box(2, {0, 0, 0}, test_turn({1, 0, 0}, math.PI / 2), {1, 2, 1})}, test_ray(7, 0, {0, 0, -5}, {0, 0, 1}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {0, 0, -2}, {0, 0, -1}, 3)
}

@(test)
test_rays_find_hits_a_sphere :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := rays_of(&search, {test_sphere(3, {0, 0, 0}, 1)}, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 3, {-1, 0, 0}, {-1, 0, 0}, 4)
}

@(test)
test_rays_find_measures_distance_in_world_units :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := rays_of(&search, {test_sphere(3, {0, 0, 0}, 1)}, test_ray(7, 0, {-5, 0, 0}, {3, 0, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 3, {-1, 0, 0}, {-1, 0, 0}, 4)
}

@(test)
test_rays_find_misses_past_max_distance_beside_behind_or_with_no_dir :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1), test_box(4, {0, 0, 10}, IDENTITY, {1, 1, 1})}
	testing.expect_value(t, len(rays_of(&search, colliders, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 3.9))), 0)
	testing.expect_value(t, len(rays_of(&search, colliders, test_ray(7, 0, {-5, 2, 0}, {1, 0, 0}, 10))), 0)
	testing.expect_value(t, len(rays_of(&search, colliders, test_ray(7, 0, {-5, 0, 0}, {-1, 0, 0}, 10))), 0)
	testing.expect_value(t, len(rays_of(&search, colliders, test_ray(7, 0, {0, 5, 10}, {0, 1, 0}, 10))), 0)
	testing.expect_value(t, len(rays_of(&search, colliders, test_ray(7, 0, {-5, 0, 0}, {0, 0, 0}, 10))), 0)
}

@(test)
test_rays_find_from_inside_a_collider_hits_it_at_the_origin :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	box := rays_of(&search, {test_box(2, {0, 0, 0}, IDENTITY, {1, 1, 1})}, test_ray(7, 0, {0.5, 0, 0}, {0, -1, 0}, 10))
	testing.expect_value(t, len(box), 1)
	expect_ray_hit(t, box[0], 7, 0, 2, {0.5, 0, 0}, {0, 1, 0}, 0)

	sphere := rays_of(&search, {test_sphere(3, {0, 0, 0}, 1)}, test_ray(7, 0, {0.5, 0, 0}, {0, -1, 0}, 10))
	testing.expect_value(t, len(sphere), 1)
	expect_ray_hit(t, sphere[0], 7, 0, 3, {0.5, 0, 0}, {0, 1, 0}, 0)
}

@(test)
test_rays_find_skips_the_owners_collider :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// The ray starts inside the owner's box.
	colliders := []Collider{test_box(7, {0, 0.5, 0}, IDENTITY, {0.3, 0.5, 0.3}), test_box(2, {0, -2, 0}, IDENTITY, {1, 1, 1})}
	got := rays_of(&search, colliders, test_ray(7, 0, {0, 0.5, 0}, {0, -1, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {0, -1, 0}, {0, 1, 0}, 1.5)
}

@(test)
test_rays_find_skips_each_excluded_id :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1), test_sphere(4, {3, 0, 0}, 1), test_sphere(5, {6, 0, 0}, 1)}
	got := rays_of(&search, colliders, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 20, {3, 4}))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 5, {5, 0, 0}, {-1, 0, 0}, 10)
}

@(test)
test_rays_find_gives_only_the_nearest_hit :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(5, {6, 0, 0}, 1), test_box(4, {3, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(3, {0, 0, 0}, 1)}
	got := rays_of(&search, colliders, test_ray(7, 0, {10, 0, 0}, {-1, 0, 0}, 20))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 5, {7, 0, 0}, {1, 0, 0}, 3)
}

@(test)
test_rays_find_gives_rows_in_query_order_and_no_row_for_a_miss :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1)}
	got := rays_of(
		&search,
		colliders,
		test_ray(9, 1, {0, 5, 0}, {0, -1, 0}, 10),
		test_contacts_of(9),
		test_ray(9, 2, {0, 5, 0}, {0, 1, 0}, 10),
		test_ray(8, 0, {-5, 0, 0}, {1, 0, 0}, 10),
	)

	testing.expect_value(t, len(got), 2)
	if len(got) == 2 {
		expect_ray_hit(t, got[0], 9, 1, 3, {0, 1, 0}, {0, 1, 0}, 4)
		expect_ray_hit(t, got[1], 8, 0, 3, {-1, 0, 0}, {-1, 0, 0}, 4)
	}
}

@(test)
test_rays_find_duplicate_owner_and_slot_keeps_the_first_and_logs_once :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1)}
	queries := []Query {
		test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10),
		test_ray(7, 0, {0, 5, 0}, {0, -1, 0}, 10),
		test_ray(7, 1, {0, 5, 0}, {0, -1, 0}, 10),
	}

	for _ in 0 ..< 2 {
		got := rays_find(&search, colliders, queries, context.temp_allocator)
		testing.expect_value(t, len(got), 2)
		if len(got) == 2 {
			expect_ray_hit(t, got[0], 7, 0, 3, {-1, 0, 0}, {-1, 0, 0}, 4)
			expect_ray_hit(t, got[1], 7, 1, 3, {0, 1, 0}, {0, 1, 0}, 4)
		}
	}
	testing.expect_value(t, len(search.logged_slots), 1)
}

@(test)
test_rays_find_skips_a_capsule_and_logs_it :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_capsule(3, {0, 0, 0}), test_sphere(4, {3, 0, 0}, 1)}
	got := rays_of(&search, colliders, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 4, {2, 0, 0}, {-1, 0, 0}, 7)
	testing.expect(t, search.logged_capsule)
}

@(test)
test_overlaps_find_box_touches_boxes_and_spheres :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider {
		test_box(3, {1.5, 0, 0}, IDENTITY, {1, 1, 1}),
		test_sphere(4, {0, 1.5, 0}, 1),
		test_box(5, {2.5, 0, 0}, IDENTITY, {0.4, 1, 1}),
		test_sphere(6, {0, 0, 2.5}, 1),
	}
	got := overlaps_of(&search, colliders, test_overlap_box(9, 0, {0, 0, 0}, {1, 1, 1}))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 3}, {owner = 9, slot = 0, id = 4}})
}

@(test)
test_overlaps_find_box_does_not_turn :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// The corner of an unturned 2 by 2 box reaches (1, 1); a turned one would not.
	colliders := []Collider{test_sphere(3, {1.2, 0, 1.2}, 0.3)}
	got := overlaps_of(&search, colliders, test_overlap_box(9, 0, {0, 0, 0}, {1, 1, 1}))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 3}})
}

@(test)
test_overlaps_find_sphere_touches_boxes_and_spheres :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider {
		test_sphere(3, {2.5, 0, 0}, 1),
		test_box(4, {0, 0, 2.5}, IDENTITY, {1, 1, 1}),
		test_sphere(5, {3.5, 0, 0}, 1),
		test_box(6, {2, 0, 2}, IDENTITY, {0.5, 0.5, 0.5}),
	}
	got := overlaps_of(&search, colliders, test_overlap_sphere(9, 0, {0, 0, 0}, 2))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 3}, {owner = 9, slot = 0, id = 4}})
}

@(test)
test_overlaps_find_skips_the_owners_collider :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_box(9, {0, 0, 0}, IDENTITY, {0.5, 0.5, 0.5}), test_sphere(3, {1, 0, 0}, 0.5)}
	got := overlaps_of(&search, colliders, test_overlap_sphere(9, 0, {0, 0, 0}, 2))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 3}})
}

@(test)
test_overlaps_find_skips_each_excluded_id :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {1, 0, 0}, 0.5), test_sphere(4, {-1, 0, 0}, 0.5), test_sphere(5, {0, 1, 0}, 0.5)}
	got := overlaps_of(&search, colliders, test_overlap_sphere(9, 0, {0, 0, 0}, 2, {3, 5}))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 4}})
}

@(test)
test_overlaps_find_gives_rows_in_query_order_then_id_order :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(5, {1, 0, 0}, 0.5), test_sphere(3, {-1, 0, 0}, 0.5), test_sphere(4, {10, 0, 0}, 0.5)}
	got := overlaps_of(
		&search,
		colliders,
		test_overlap_sphere(9, 1, {0, 0, 0}, 2),
		test_ray(9, 1, {0, 5, 0}, {0, -1, 0}, 10),
		test_overlap_sphere(8, 0, {20, 0, 0}, 1),
		test_overlap_box(8, 1, {10, 0, 0}, {1, 1, 1}),
	)

	expect_overlap_hits(t, got, {{owner = 9, slot = 1, id = 3}, {owner = 9, slot = 1, id = 5}, {owner = 8, slot = 1, id = 4}})
}

@(test)
test_overlaps_find_duplicate_owner_and_slot_keeps_the_first_and_logs_once :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {1, 0, 0}, 0.5), test_sphere(4, {10, 0, 0}, 0.5)}
	queries := []Query {
		test_overlap_sphere(7, 0, {0, 0, 0}, 1),
		test_overlap_sphere(7, 0, {10, 0, 0}, 1),
		test_overlap_sphere(7, 1, {10, 0, 0}, 1),
	}

	for _ in 0 ..< 2 {
		got := overlaps_find(&search, colliders, queries, context.temp_allocator)
		expect_overlap_hits(t, got, {{owner = 7, slot = 0, id = 3}, {owner = 7, slot = 1, id = 4}})
	}
	testing.expect_value(t, len(search.logged_slots), 1)
}

@(test)
test_overlaps_find_and_rays_find_keep_their_slots_apart :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1)}
	queries := []Query{test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10), test_overlap_sphere(7, 0, {0, 0, 0}, 1)}

	testing.expect_value(t, len(rays_find(&search, colliders, queries, context.temp_allocator)), 1)
	expect_overlap_hits(t, overlaps_find(&search, colliders, queries, context.temp_allocator), {{owner = 7, slot = 0, id = 3}})
	testing.expect_value(t, len(search.logged_slots), 0)
}

@(test)
test_overlaps_find_skips_a_capsule_and_logs_it :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_capsule(3, {0, 0, 0}), test_sphere(4, {1, 0, 0}, 0.5)}
	got := overlaps_of(&search, colliders, test_overlap_sphere(7, 0, {0, 0, 0}, 2))

	expect_overlap_hits(t, got, {{owner = 7, slot = 0, id = 4}})
	testing.expect(t, search.logged_capsule)
}

// Spheres of radius 0.3 to 0.8 with ids 1 to n, from the context generator.
random_spheres :: proc(n: int) -> []Collider {
	spheres := make([]Collider, n, context.temp_allocator)
	for &sphere, i in spheres {
		pos := [3]f32{rand.float32_range(-RANDOM_HALF, RANDOM_HALF), rand.float32_range(-1, 1), rand.float32_range(-RANDOM_HALF, RANDOM_HALF)}
		sphere = test_sphere(u64(i + 1), pos, rand.float32_range(0.3, 0.8))
	}
	return spheres
}

sphere_centre :: proc(col: Collider) -> [3]f32 {
	return {col.pos.x, col.pos.y, col.pos.z}
}

// The oracle for a sphere: the distance along a unit dir to its surface, from
// the foot of the perpendicular from its centre to the ray.
sphere_ray_distance :: proc(origin, dir: [3]f32, sphere: Collider) -> (distance: f32, ok: bool) {
	to_centre := sphere_centre(sphere) - origin
	radius := sphere.shape.payload.sphere
	if v3_dot(to_centre, to_centre) <= radius * radius {
		return 0, true
	}
	foot := v3_dot(to_centre, dir)
	miss := v3_length(to_centre - dir * foot)
	if foot <= 0 || miss >= radius {
		return 0, false
	}
	return foot - math.sqrt(radius * radius - miss * miss), true
}

@(test)
test_contacts_find_matches_sphere_distances_in_a_random_scene :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)
	r := rand.create(2)
	context.random_generator = rand.default_random_generator(&r)

	spheres := random_spheres(RANDOM_SPHERES)
	// Ids rise with the index, so this order is the (a, b) order.
	want := make([dynamic][2]u64, context.temp_allocator)
	for a, i in spheres {
		for b in spheres[i + 1:] {
			if v3_length(sphere_centre(b) - sphere_centre(a)) < a.shape.payload.sphere + b.shape.payload.sphere {
				append(&want, [2]u64{a.id, b.id})
			}
		}
	}
	got := contacts_find(&search, spheres, context.temp_allocator)

	testing.expect(t, len(want) > 100)
	if !testing.expect_value(t, len(got), len(want)) {
		return
	}
	for pair, i in want {
		testing.expect_value(t, [2]u64{got[i].a, got[i].b}, pair)
	}
}

// Every third sphere asks, so many pairs have two asking owners.
@(test)
test_contacts_asked_matches_sphere_distances_in_a_random_scene :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)
	r := rand.create(5)
	context.random_generator = rand.default_random_generator(&r)

	spheres := random_spheres(RANDOM_SPHERES)
	queries := make([dynamic]Query, context.temp_allocator)
	for id := u64(3); id <= RANDOM_SPHERES; id += 3 {
		append(&queries, test_contacts_of(id))
	}
	want := make([dynamic][2]u64, context.temp_allocator)
	for a, i in spheres {
		for b in spheres[i + 1:] {
			asked := a.id % 3 == 0 || b.id % 3 == 0
			if asked && v3_length(sphere_centre(b) - sphere_centre(a)) < a.shape.payload.sphere + b.shape.payload.sphere {
				append(&want, [2]u64{a.id, b.id})
			}
		}
	}
	got := contacts_asked(&search, spheres, queries[:], context.temp_allocator)

	testing.expect(t, len(want) > 100)
	if !testing.expect_value(t, len(got), len(want)) {
		return
	}
	for pair, i in want {
		testing.expect_value(t, [2]u64{got[i].a, got[i].b}, pair)
	}
}

@(test)
test_overlaps_find_matches_sphere_distances_in_a_random_scene :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)
	r := rand.create(3)
	context.random_generator = rand.default_random_generator(&r)

	spheres := random_spheres(RANDOM_SPHERES)
	PROBES :: 16
	queries := make([]Query, PROBES, context.temp_allocator)
	want := make([dynamic]Overlap_Hit, context.temp_allocator)
	for &query, slot in queries {
		pos := [3]f32{rand.float32_range(-RANDOM_HALF - 5, RANDOM_HALF + 5), 0, rand.float32_range(-RANDOM_HALF - 5, RANDOM_HALF + 5)}
		radius := rand.float32_range(0.5, 6)
		query = test_overlap_sphere(0, u32(slot), pos, radius)
		for sphere in spheres {
			if v3_length(sphere_centre(sphere) - pos) < radius + sphere.shape.payload.sphere {
				append(&want, Overlap_Hit{owner = 0, slot = u32(slot), id = sphere.id})
			}
		}
	}

	testing.expect(t, len(want) > PROBES)
	expect_overlap_hits(t, overlaps_find(&search, spheres, queries, context.temp_allocator), want[:])
}

@(test)
test_rays_find_matches_sphere_distances_in_a_random_scene :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)
	r := rand.create(4)
	context.random_generator = rand.default_random_generator(&r)

	spheres := random_spheres(RANDOM_SPHERES)
	RAYS :: 40
	MAX_DISTANCE :: f32(200)
	queries := make([]Query, RAYS, context.temp_allocator)
	origins := make([][3]f32, RAYS, context.temp_allocator)
	dirs := make([][3]f32, RAYS, context.temp_allocator)
	for &query, slot in queries {
		// Rays start inside and outside the square, and some run along an axis.
		origin := [3]f32{rand.float32_range(-60, 60), rand.float32_range(-1, 1), rand.float32_range(-60, 60)}
		dir := [3]f32{rand.float32_range(-1, 1), rand.float32_range(-0.05, 0.05), rand.float32_range(-1, 1)}
		switch slot % 5 {
		case 0:
			dir = {1, 0, 0}
		case 1:
			dir = {0, 0, -1}
		}
		dir /= v3_length(dir)
		origins[slot], dirs[slot] = origin, dir
		query = test_ray(0, u32(slot), origin, dir, MAX_DISTANCE)
	}

	got := rays_find(&search, spheres, queries, context.temp_allocator)

	row := 0
	hits := 0
	for slot in 0 ..< RAYS {
		nearest := MAX_DISTANCE
		id: u64
		for sphere in spheres {
			distance := sphere_ray_distance(origins[slot], dirs[slot], sphere) or_continue
			if distance <= nearest {
				nearest, id = distance, sphere.id
			}
		}
		if id == 0 {
			continue
		}
		hits += 1
		if !testing.expectf(t, row < len(got) && got[row].slot == u32(slot), "slot %v has no hit", slot) {
			return
		}
		testing.expect_value(t, got[row].id, id)
		testing.expectf(t, abs(got[row].distance - nearest) < 1e-3, "slot %v distance %v, expected %v", slot, got[row].distance, nearest)
		row += 1
	}
	testing.expect_value(t, len(got), row)
	testing.expect(t, hits > RAYS / 2)
}

// The pair overlaps on every axis, so the host must give it once at any size.
@(test)
test_contacts_find_gives_a_large_pair_once :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	for half in ([]f32{0.3, 1, 4}) {
		colliders := make([dynamic]Collider, context.temp_allocator)
		// Small spheres 1 unit apart that do not touch, under the pair.
		for i in 0 ..< 400 {
			append(&colliders, test_sphere(u64(10 + i), {f32(i % 20) - 10, 0, f32(i / 20) - 10}, 0.1))
		}
		append(&colliders, test_box(1, {0, 5, 0}, IDENTITY, {half, 0.5, half}), test_box(2, {half * 0.5, 5, half * 0.5}, quat_yaw(0.3), {half, 0.5, half}))

		got := contacts_find(&search, colliders[:], context.temp_allocator)

		if testing.expectf(t, len(got) == 1, "half %v gives %v contacts", half, len(got)) {
			testing.expect_value(t, [2]u64{got[0].a, got[0].b}, [2]u64{1, 2})
		}
	}
}

// A 10 by 10 square of spheres, 5 units apart, sinks 0.1 into a wide ground box.
@(test)
test_queries_find_a_ground_box_under_every_sphere :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := make([dynamic]Collider, context.temp_allocator)
	append(&colliders, test_box(1, {0, 0, 0}, IDENTITY, {50, 0.5, 50}))
	for i in 0 ..< 100 {
		append(&colliders, test_sphere(u64(2 + i), {f32(i % 10) * 5 - 25, 0.9, f32(i / 10) * 5 - 25}, 0.5))
	}

	contacts := contacts_find(&search, colliders[:], context.temp_allocator)
	if testing.expect_value(t, len(contacts), 100) {
		for contact, i in contacts {
			testing.expect_value(t, [2]u64{contact.a, contact.b}, [2]u64{1, u64(2 + i)})
		}
	}

	asked := contacts_asked(&search, colliders[:], []Query{test_contacts_of(2)}, context.temp_allocator)
	if testing.expect_value(t, len(asked), 1) {
		testing.expect_value(t, [2]u64{asked[0].a, asked[0].b}, [2]u64{1, 2})
	}
	testing.expect_value(t, len(contacts_asked(&search, colliders[:], []Query{test_contacts_of(1)}, context.temp_allocator)), 100)

	// Sphere 2 is at (-25, 0.9, -25). A gap between spheres is at (-22.5, -22.5).
	rays := rays_of(&search, colliders[:], test_ray(0, 0, {-25, 10, -25}, {0, -1, 0}, 20), test_ray(0, 1, {-22.5, 10, -22.5}, {0, -1, 0}, 20))
	if testing.expect_value(t, len(rays), 2) {
		expect_ray_hit(t, rays[0], 0, 0, 2, {-25, 1.4, -25}, {0, 1, 0}, 8.6)
		expect_ray_hit(t, rays[1], 0, 1, 1, {-22.5, 0.5, -22.5}, {0, 1, 0}, 9.5)
	}

	overlaps := overlaps_of(&search, colliders[:], test_overlap_sphere(0, 0, {-22.5, 0.5, -22.5}, 1), test_overlap_sphere(0, 1, {-25, 0.5, -25}, 1))
	expect_overlap_hits(t, overlaps, {{owner = 0, slot = 0, id = 1}, {owner = 0, slot = 1, id = 1}, {owner = 0, slot = 1, id = 2}})
}

// A straight-down ray that misses with no distance limit must still end.
@(test)
test_rays_find_a_vertical_ray_with_no_limit_that_misses :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_sphere(1, {0, 0, 0}, 0.5), test_sphere(2, {5, 0, 5}, 0.5)}
	queries := []Query{test_ray(0, 0, {2.5, 10, 2.5}, {0, -1, 0}, math.INF_F32), test_ray(0, 1, {0, 10, 0}, {0, -1, 0}, math.INF_F32)}

	got := rays_find(&search, colliders, queries, context.temp_allocator)

	if testing.expect_value(t, len(got), 1) {
		expect_ray_hit(t, got[0], 0, 1, 1, {0, 0.5, 0}, {0, 1, 0}, 9.5)
	}
}

// A Collider at infinity or with a negative size is still tested, as every
// Collider is, and the others still collide.
@(test)
test_queries_still_test_colliders_with_odd_sizes :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider {
		test_sphere(1, {0, 0, 0}, 0.5),
		test_sphere(2, {0.5, 0, 0}, 0.5),
		test_sphere(3, {math.INF_F32, 0, 0}, 0.5),
		// A negative radius counts against the other radius: 3 - 0.5 > 2.
		test_sphere(4, {0, 0, 2}, -0.5),
	}

	contacts := contacts_find(&search, colliders, context.temp_allocator)
	if testing.expect_value(t, len(contacts), 1) {
		testing.expect_value(t, [2]u64{contacts[0].a, contacts[0].b}, [2]u64{1, 2})
	}
	overlaps := overlaps_of(&search, colliders, test_overlap_sphere(0, 0, {0, 0, 0}, 3))
	expect_overlap_hits(t, overlaps, {{owner = 0, slot = 0, id = 1}, {owner = 0, slot = 0, id = 2}, {owner = 0, slot = 0, id = 4}})
}

@(test)
test_queries_find_two_clusters_far_apart :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider {
		test_sphere(1, {-10000, 0, 0}, 0.5),
		test_sphere(2, {-9999.5, 0, 0}, 0.5),
		test_sphere(3, {10000, 0, 3}, 0.5),
		test_sphere(4, {10000, 0, 3.5}, 0.5),
	}

	contacts := contacts_find(&search, colliders, context.temp_allocator)
	if testing.expect_value(t, len(contacts), 2) {
		testing.expect_value(t, [2]u64{contacts[0].a, contacts[0].b}, [2]u64{1, 2})
		testing.expect_value(t, [2]u64{contacts[1].a, contacts[1].b}, [2]u64{3, 4})
	}

	// f32 loses a sphere's radius over a long ray, so this one starts near.
	rays := rays_of(&search, colliders, test_ray(0, 0, {9990, 0, 3}, {1, 0, 0}, 30000))
	if testing.expect_value(t, len(rays), 1) {
		testing.expect_value(t, rays[0].id, 3)
		testing.expectf(t, abs(rays[0].distance - 9.5) < 0.01, "distance %v", rays[0].distance)
	}
}
