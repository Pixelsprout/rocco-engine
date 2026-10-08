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
	return {id = id, kind = COLLIDER_BOX, pos = {pos.x, pos.y, pos.z}, yaw = yaw, extent = {half.x, half.y, half.z}}
}

test_sphere :: proc(id: u64, pos: [3]f32, radius: f32) -> Collider {
	return {id = id, kind = COLLIDER_SPHERE, pos = {pos.x, pos.y, pos.z}, extent = {x = radius}}
}

contacts_of :: proc(search: ^Contact_Search, colliders: ..Collider) -> []Contact {
	return contacts_find(search, colliders, context.temp_allocator)
}

expect_contact :: proc(t: ^testing.T, got: Contact, a, b: u64, normal: [3]f32, depth: f32, loc := #caller_location) {
	testing.expect_value(t, got.a, a, loc = loc)
	testing.expect_value(t, got.b, b, loc = loc)
	n := [3]f32{got.normal.x, got.normal.y, got.normal.z}
	testing.expectf(t, v3_length(n - normal) < COLLISION_EPS, "normal %v, expected %v", n, normal, loc = loc)
	testing.expectf(t, abs(got.depth - depth) < COLLISION_EPS, "depth %v, expected %v", got.depth, depth, loc = loc)
}

@(test)
test_contact_search_box_box_overlap_takes_the_least_overlap_axis :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {1.8, 0.5, 0}, 0, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.2)
}

@(test)
test_contact_search_box_box_apart_has_no_contact :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {2.5, 0, 0}, 0, {1, 1, 1}))), 0)
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {0, 2.5, 0}, 0, {1, 1, 1}))), 0)
}

@(test)
test_contact_search_box_box_stacked_pushes_along_y :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 1.9, 0}, 0, {1, 1, 1}), test_box(2, {0.2, 0, 0}, 0, {1, 1, 1}))

	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, -1, 0}, 0.1)
}

// The AABBs of these boxes overlap, but the turned box's corner stops short.
@(test)
test_contact_search_box_box_honours_yaw :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

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
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

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
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), test_sphere(2, {0, 0, 1.5}, 1))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, 1}, 0.5)

	testing.expect_value(t, len(contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), test_sphere(2, {1.5, 1.5, 0}, 1))), 0)
}

@(test)
test_contact_search_box_sphere_beside_the_box :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {1.25, 0, 0}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {1, 0, 0}, 0.25)

	// Past the corner on the diagonal, the sphere misses the box.
	testing.expect_value(t, len(contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {1.4, 0, 1.4}, 0.5))), 0)
}

@(test)
test_contact_search_box_sphere_with_its_centre_inside_the_box :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(2, {0, 0, -0.75}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, -1}, 0.75)
}

@(test)
test_contact_search_box_sphere_honours_yaw :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	// Turned a quarter, the box's long side lies along z.
	got := contacts_of(&search, test_box(1, {0, 0, 0}, math.PI / 2, {2, 1, 0.5}), test_sphere(2, {0, 0, 2.25}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 1, 2, {0, 0, 1}, 0.25)
}

// The normal points from the lower id to the higher, whichever shape comes first.
@(test)
test_contact_search_normal_points_from_the_lower_id :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(9, {0, 0, 0}, 0, {1, 1, 1}), test_sphere(3, {1.25, 0, 0}, 0.5))
	testing.expect_value(t, len(got), 1)
	expect_contact(t, got[0], 3, 9, {-1, 0, 0}, 0.25)
}

@(test)
test_contacts_find_are_sorted_by_a_then_b :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

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
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	got := contacts_of(&search, test_box(1, {0, 0, 0}, 0, {1, 1, 1}), test_box(2, {0.5, 0, 5}, 0, {1, 1, 1}), test_box(3, {0.5, 5, 0}, 0, {1, 1, 1}))
	testing.expect_value(t, len(got), 0)
}

@(test)
test_contact_search_duplicate_id_keeps_the_first_and_logs_once :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	first := test_sphere(1, {0, 0, 0}, 0.5)
	second := test_sphere(1, {5, 0, 0}, 0.5)
	near_second := test_sphere(2, {5.5, 0, 0}, 0.5)

	testing.expect_value(t, len(contacts_of(&search, first, second, near_second)), 0)
	testing.expect_value(t, len(contacts_of(&search, first, second, near_second)), 0)
	testing.expect_value(t, len(search.logged_ids), 1)
}

@(test)
test_contact_search_unknown_kind_is_skipped_and_logged_once :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	capsule := Collider {
		id     = 2,
		kind   = COLLIDER_CAPSULE,
		extent = {x = 1, y = 1},
	}
	testing.expect_value(t, len(contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), capsule)), 0)
	testing.expect_value(t, len(contacts_of(&search, test_sphere(1, {0, 0, 0}, 1), capsule)), 0)
	testing.expect(t, search.logged_kinds[COLLIDER_CAPSULE])
	testing.expect(t, !search.logged_kinds[COLLIDER_SPHERE])
}

@(test)
test_contact_search_no_colliders_gives_no_contacts :: proc(t: ^testing.T) {
	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

	testing.expect_value(t, len(contacts_find(&search, nil, context.temp_allocator)), 0)
}

// Times the host at 1,000 colliders on a static arena, as the frame arena is.
// docs/DESIGN.md section 10 records the result.
@(test)
test_contact_search_timing_at_1000_colliders :: proc(t: ^testing.T) {
	arena: vmem.Arena
	testing.expect_value(t, vmem.arena_init_static(&arena, FRAME_ARENA_RESERVE), nil)
	defer vmem.arena_destroy(&arena)

	search: Contact_Search
	contact_search_init(&search, context.allocator)
	defer contact_search_destroy(&search)

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
