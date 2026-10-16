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

test_box :: proc(id: u64, pos: [3]f32, yaw: f32, half: [3]f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, yaw = yaw, shape = {payload = {box = {half.x, half.y, half.z}}, tag = .Box}}
}

test_sphere :: proc(id: u64, pos: [3]f32, radius: f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, shape = {payload = {sphere = radius}, tag = .Sphere}}
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

test_capsule :: proc(id: u64, pos: [3]f32) -> Collider {
	return {id = id, pos = {pos.x, pos.y, pos.z}, shape = {payload = {capsule = {radius = 1, half_height = 1}}, tag = .Capsule}}
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

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {1.8, 0.5, 0}, 0, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.2)
}

@(test)
test_contact_search_box_box_apart_has_no_contact :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {2.5, 0, 0}, 0, {1, 1, 1}))), 0)
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {0, 2.5, 0}, 0, {1, 1, 1}))), 0)
}

@(test)
test_contact_search_box_box_stacked_pushes_along_y :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 1.9, 0}, 0, {1, 1, 1}), test_box(2, {0.2, 0, 0}, 0, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, -1, 0}, 0.1)
}

// The AABBs of these boxes overlap, but the turned box's corner stops short.
@(test)
test_contact_search_box_box_honours_yaw :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	turned := test_box(2, {2.3, 0, 2.3}, math.PI / 4, {1, 1, 1})
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), turned)), 0)

	// Turned a quarter, a long thin box covers z instead of x.
	long := test_box(4, {0.2, 0, 1.5}, math.PI / 2, {2, 1, 0.1})
	got := contacts_of(&search, test_box(3, {0, 0, 0}, 0, {1, 1, 1}), long)
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
	got := contacts_of(&search, test_box(1, {0, 0, 0}, yaw, {2, 1, 0.1}), test_sphere(2, 1.8 * along + 0.05 * across, 0.3))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, across, 0.35)
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

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {1.25, 0, 0}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.25)

	// Past the corner on the diagonal, the sphere misses the box.
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {1.4, 0, 1.4}, 0.5))), 0)
}

@(test)
test_contact_search_box_sphere_with_its_centre_inside_the_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {0, 0, -0.75}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, -1}, 0.75)
}

@(test)
test_contact_search_box_sphere_honours_yaw :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// Turned a quarter, the box's long side lies along z.
	got := contacts_of(&search, test_box(1, {0, 0, 0}, math.PI / 2, {2, 1, 0.5}), test_sphere(2, {0, 0, 2.25}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, 1}, 0.25)
}

// The normal points from the lower id to the higher, whichever shape comes first.
@(test)
test_contact_search_normal_points_from_the_lower_id :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := contacts_of(&search, test_box(9, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(3, {1.25, 0, 0}, 0.5))
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

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {0.5, 0, 5}, 0, {1, 1, 1}), test_box(3, {0.5, 5, 0}, 0, {1, 1, 1}))
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
		col = test_box(u64(i), pos, rand.float32_range(-math.PI, math.PI), {0.5, 0.5, 0.5}) if i % 2 == 0 else test_sphere(u64(i), pos, 0.5)
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
	colliders := []Collider{test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(1, {1, 0, 0}, 0, {1, 1, 1})}
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
		test_box(1, {0, 0, 0}, 0, {1, 1, 1}),
		test_box(2, {1, 0, 0}, 0, {1, 1, 1}),
		test_box(3, {10, 0, 0}, 0, {1, 1, 1}),
		test_box(4, {11, 0, 0}, 0, {1, 1, 1}),
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

	colliders := []Collider{test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {1, 0, 0}, 0, {1, 1, 1})}
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
	colliders := []Collider{test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(1, {1, 0, 0}, 0, {1, 1, 1})}
	queries := []Query{test_ray(1, 0, {0, 5, 0}, {0, -1, 0}, 10)}
	testing.expect_value(t, len(contacts_asked(&search, colliders, queries, context.temp_allocator)), 0)
	testing.expect_value(t, len(search.logged_ids), 0)
}

@(test)
test_rays_find_hits_the_top_of_a_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	got := rays_of(&search, {test_box(2, {0, 0, 0}, 0, {1, 1, 1})}, test_ray(7, 0, {0.5, 5, 0}, {0, -1, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {0.5, 1, 0}, {0, 1, 0}, 4)
}

@(test)
test_rays_find_hits_a_turned_box :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	// A quarter turn lays the long x half along z.
	got := rays_of(&search, {test_box(2, {0, 0, 0}, math.PI / 2, {2, 1, 1})}, test_ray(7, 0, {-5, 0, 0}, {1, 0, 0}, 10))

	testing.expect_value(t, len(got), 1)
	expect_ray_hit(t, got[0], 7, 0, 2, {-1, 0, 0}, {-1, 0, 0}, 4)
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

	colliders := []Collider{test_sphere(3, {0, 0, 0}, 1), test_box(4, {0, 0, 10}, 0, {1, 1, 1})}
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

	box := rays_of(&search, {test_box(2, {0, 0, 0}, 0, {1, 1, 1})}, test_ray(7, 0, {0.5, 0, 0}, {0, -1, 0}, 10))
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
	colliders := []Collider{test_box(7, {0, 0.5, 0}, 0, {0.3, 0.5, 0.3}), test_box(2, {0, -2, 0}, 0, {1, 1, 1})}
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

	colliders := []Collider{test_sphere(5, {6, 0, 0}, 1), test_box(4, {3, 0, 0}, 0, {1, 1, 1}), test_sphere(3, {0, 0, 0}, 1)}
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
		test_box(3, {1.5, 0, 0}, 0, {1, 1, 1}),
		test_sphere(4, {0, 1.5, 0}, 1),
		test_box(5, {2.5, 0, 0}, 0, {0.4, 1, 1}),
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
		test_box(4, {0, 0, 2.5}, 0, {1, 1, 1}),
		test_sphere(5, {3.5, 0, 0}, 1),
		test_box(6, {2, 0, 2}, 0, {0.5, 0.5, 0.5}),
	}
	got := overlaps_of(&search, colliders, test_overlap_sphere(9, 0, {0, 0, 0}, 2))

	expect_overlap_hits(t, got, {{owner = 9, slot = 0, id = 3}, {owner = 9, slot = 0, id = 4}})
}

@(test)
test_overlaps_find_skips_the_owners_collider :: proc(t: ^testing.T) {
	search: Query_Search
	query_search_init(&search, context.allocator)
	defer query_search_destroy(&search)

	colliders := []Collider{test_box(9, {0, 0, 0}, 0, {0.5, 0.5, 0.5}), test_sphere(3, {1, 0, 0}, 0.5)}
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
