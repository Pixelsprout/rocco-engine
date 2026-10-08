package engine

import "core:slice"
import "core:testing"

FAKE_KEYS_MAX :: 8
FAKE_CONTACTS_MAX :: 4

FAKE_GAME :: Game_Calls {
	init       = fake_init,
	step       = fake_step,
	view       = fake_view,
	drop_model = fake_drop_model,
}

Fake_Game :: struct {
	inits:        int,
	seed:         u64,
	init_box:     rawptr,
	steps:        int,
	step_in:      rawptr,
	step_in_rc:   int,
	step_out:     rawptr,
	held:         [FAKE_KEYS_MAX]u16,
	held_len:     int,
	pressed:      [FAKE_KEYS_MAX]u16,
	pressed_len:  int,
	contacts:     [FAKE_CONTACTS_MAX]Contact,
	contacts_len: int,
	views:        int,
	view_box:     rawptr,
	view_rc:      int,
	drops:        int,
	drop_box:     rawptr,
	drop_rc:      int,
	colliders:    []Collider,
}

// Guarded by the Roc heap test lock. Call fake_seam_init after roc_heap_test_begin.
g_fake: Fake_Game

fake_refcount :: proc(box: rawptr) -> ^int {
	return (^int)(uintptr(box) - size_of(int))
}

// A Roc box: an 8 byte refcount header in front of the payload.
fake_box_new :: proc() -> rawptr {
	base := roc_alloc(size_of(int) + size_of(u64), align_of(int))
	box := rawptr(uintptr(base) + size_of(int))
	fake_refcount(box)^ = 1
	return box
}

fake_box_free :: proc(box: rawptr) {
	roc_dealloc(rawptr(uintptr(box) - size_of(int)), align_of(int))
}

fake_init :: proc(config: Config) -> rawptr {
	g_fake.inits += 1
	g_fake.seed = config.seed
	roc_decref(config)
	g_fake.init_box = fake_box_new()
	return g_fake.init_box
}

fake_step :: proc(model: rawptr, input: Input, contacts: Roc_List(Contact), dt: f32) -> rawptr {
	g_fake.steps += 1
	g_fake.step_in = model
	g_fake.step_in_rc = fake_refcount(model)^
	fake_box_free(model)

	g_fake.held_len = copy(g_fake.held[:], input.held.elements[:input.held.length])
	g_fake.pressed_len = copy(g_fake.pressed[:], input.pressed.elements[:input.pressed.length])
	roc_decref(input)
	g_fake.contacts_len = copy(g_fake.contacts[:], contacts.elements[:contacts.length])
	roc_list_decref(contacts)

	g_fake.step_out = fake_box_new()
	return g_fake.step_out
}

fake_view :: proc(model: rawptr) -> Scene {
	g_fake.views += 1
	g_fake.view_box = model
	g_fake.view_rc = fake_refcount(model)^
	fake_refcount(model)^ -= 1
	return {
		draws = roc_list_from_slice([]Draw{{id = u64(g_fake.views)}}),
		colliders = roc_list_from_slice(g_fake.colliders),
	}
}

fake_drop_model :: proc(model: rawptr) {
	g_fake.drops += 1
	g_fake.drop_box = model
	g_fake.drop_rc = fake_refcount(model)^
	fake_box_free(model)
}

fake_seam_init :: proc(s: ^Seam, seed: u64 = 0, colliders: []Collider = nil) {
	g_fake = {colliders = colliders}
	seam_init(s, FAKE_GAME, Config{seed = seed})
}

@(test)
test_seam_init_pairs_the_first_scene_with_itself :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42)
	defer seam_shutdown(&s)

	prev, curr := seam_scenes(&s)
	testing.expect_value(t, prev.draws.elements, curr.draws.elements)
	testing.expect_value(t, g_fake.inits, 1)
	testing.expect_value(t, g_fake.seed, 42)
	testing.expect_value(t, g_fake.views, 1)
	testing.expect_value(t, g_fake.view_box, g_fake.init_box)
}

@(test)
test_seam_step_rotates_the_scenes_and_hands_the_new_box_to_view :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)
	_, first := seam_scenes(&s)

	seam_step(&s, {}, 1.0 / 60)

	prev, curr := seam_scenes(&s)
	testing.expect_value(t, prev.draws.elements, first.draws.elements)
	testing.expect(t, curr.draws.elements != first.draws.elements)
	testing.expect_value(t, curr.draws.elements[0].id, 2)
	testing.expect_value(t, g_fake.step_in, g_fake.init_box)
	testing.expect_value(t, g_fake.step_in_rc, 1)
	testing.expect_value(t, g_fake.view_box, g_fake.step_out)
	testing.expect_value(t, g_fake.view_rc, 2)
	testing.expect_value(t, fake_refcount(g_fake.step_out)^, 1)
}

@(test)
test_seam_step_never_passes_a_consumed_box :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)

	last := g_fake.init_box
	for i in 0 ..< 5 {
		seam_step(&s, {}, 1.0 / 60)
		testing.expectf(t, g_fake.step_in == last, "step %v got %v, the game last returned %v", i, g_fake.step_in, last)
		testing.expect_value(t, g_fake.step_in_rc, 1)
		testing.expect_value(t, fake_refcount(g_fake.step_out)^, 1)
		last = g_fake.step_out
	}
}

// scripts/alloc-check.sh checks the same rule on the real games.
@(test)
test_seam_step_with_empty_input_makes_two_allocs_and_two_frees :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)

	live: uint
	for i in 0 ..< 5 {
		before := roc_heap_counters()
		seam_step(&s, {}, 1.0 / 60)
		after := roc_heap_counters()

		// The first step has no previous Scene to drop.
		want_frees: uint = 1 if i == 0 else 2
		testing.expect_value(t, after.allocs - before.allocs, 2)
		testing.expect_value(t, after.deallocs - before.deallocs, want_frees)
		testing.expect_value(t, after.reallocs - before.reallocs, 0)
		if i == 1 {
			live = after.live
		} else if i > 1 {
			testing.expect_value(t, after.live, live)
		}
	}
}

@(test)
test_seam_step_delivers_the_held_and_pressed_keys :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)
	seam_step(&s, {}, 1.0 / 60)

	held := []u16{3, 4}
	pressed := []u16{5}
	before := roc_heap_counters()
	seam_step(&s, {held = held, pressed = pressed}, 1.0 / 60)
	after := roc_heap_counters()

	testing.expect(t, slice.equal(g_fake.held[:g_fake.held_len], held))
	testing.expect(t, slice.equal(g_fake.pressed[:g_fake.pressed_len], pressed))
	testing.expect_value(t, after.allocs - before.allocs, 4)
	testing.expect_value(t, after.deallocs - before.deallocs, 4)
}

@(test)
test_seam_step_hands_the_pending_contacts_to_step_once :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)

	s.contacts = roc_list_from_slice([]Contact{{a = 1, b = 2, depth = 0.25}})
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 1)
	testing.expect_value(t, g_fake.contacts[0].b, 2)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)
}

@(test)
test_seam_step_hands_step_the_contacts_of_the_last_scene :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	touching := []Collider{test_sphere(7, {0, 0, 0}, 1), test_sphere(3, {1, 0, 0}, 1)}
	s: Seam
	fake_seam_init(&s, colliders = touching)
	defer seam_shutdown(&s)

	// The Scene from init touches, but the first step still gets no contacts.
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 1)
	testing.expect_value(t, [2]u64{g_fake.contacts[0].a, g_fake.contacts[0].b}, [2]u64{3, 7})

	g_fake.colliders = nil
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 1)
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)
}

@(test)
test_seam_shutdown_releases_contacts_no_step_took :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	s.contacts = roc_list_from_slice([]Contact{{a = 1, b = 2}})
	seam_shutdown(&s)

	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_seam_shutdown_drops_the_model_once_and_leaves_no_live_block :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	seam_step(&s, {}, 1.0 / 60)
	seam_step(&s, {}, 1.0 / 60)
	seam_shutdown(&s)

	testing.expect_value(t, g_fake.drops, 1)
	testing.expect_value(t, g_fake.drop_box, g_fake.step_out)
	testing.expect_value(t, g_fake.drop_rc, 1)
	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_seam_step_returns_non_negative_durations :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer seam_shutdown(&s)

	step_time, view_time := seam_step(&s, {}, 1.0 / 60)
	testing.expect(t, step_time >= 0)
	testing.expect(t, view_time >= 0)
}
