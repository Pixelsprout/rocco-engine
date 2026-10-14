package engine

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

FAKE_KEYS_MAX :: 8
FAKE_CONTACTS_MAX :: 4
FAKE_COMMANDS_MAX :: 4
NO_MESH_DIR :: "no/such/rocco/dir"

FAKE_GAME :: Game_Calls {
	init       = fake_init,
	step       = fake_step,
	loaded     = fake_loaded,
	view       = fake_view,
	drop_model = fake_drop_model,
}

// When the fake runner ran a command, counted in steps and views.
Fake_Command_Run :: struct {
	steps: int,
	views: int,
}

Fake_Game :: struct {
	inits:           int,
	seed:            u64,
	assets:          []string,
	init_box:        rawptr,
	init_commands:   []Command,
	steps:           int,
	step_in:         rawptr,
	step_in_rc:      int,
	step_out:        rawptr,
	held:            [FAKE_KEYS_MAX]u16,
	held_len:        int,
	pressed:         [FAKE_KEYS_MAX]u16,
	pressed_len:     int,
	contacts:        [FAKE_CONTACTS_MAX]Contact,
	contacts_len:    int,
	views:           int,
	view_box:        rawptr,
	view_rc:         int,
	drops:           int,
	drop_box:        rawptr,
	drop_rc:         int,
	colliders:       []Collider,
	commands_out:    int,
	next_commands:   []Command,
	runs:            [FAKE_COMMANDS_MAX]Fake_Command_Run,
	runs_len:        int,
	loadeds:         int,
	loaded_at:       Fake_Command_Run,
	loaded_pack:     string,
	loaded_manifest: []Manifest_Line,
	loaded_out:      rawptr,
	meshes:          Mesh_Table,
	packs:           Packs,
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

// The list a game returns owns the strings, so build each Load after roc_heap_test_begin.
fake_load :: proc(pack: string, assets: ..string) -> Command {
	names := make([]Roc_Str, len(assets), context.temp_allocator)
	for name, i in assets {
		names[i] = roc_str_from_slice(name)
	}
	command := Command {
		tag = .Load,
	}
	command.payload.load = {pack = roc_str_from_slice(pack), assets = roc_list_from_slice(names)}
	return command
}

fake_unload :: proc(pack: string) -> Command {
	command := Command {
		tag = .Unload,
	}
	command.payload.unload = roc_str_from_slice(pack)
	return command
}

fake_init :: proc(config: Config) -> Init_Result {
	g_fake.inits += 1
	g_fake.seed = config.seed
	g_fake.assets = make([]string, config.assets.length, context.temp_allocator)
	for &name, i in config.assets.elements[:config.assets.length] {
		g_fake.assets[i] = strings.clone(roc_str_string(&name), context.temp_allocator)
	}
	roc_decref(config)
	g_fake.init_box = fake_box_new()
	return {model = g_fake.init_box, commands = roc_list_from_slice(g_fake.init_commands)}
}

fake_step :: proc(model: rawptr, input: Input, contacts: Roc_List(Contact), dt: f32) -> Step_Result {
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
	commands := make([dynamic]Command, context.temp_allocator)
	for _ in 0 ..< g_fake.commands_out {
		append(&commands, Command{tag = .Quit})
	}
	append(&commands, ..g_fake.next_commands)
	g_fake.next_commands = nil
	return {model = g_fake.step_out, commands = roc_list_from_slice(commands[:])}
}

fake_loaded :: proc(model: rawptr, pack: Roc_Str, manifest: Roc_List(Manifest_Entry)) -> rawptr {
	g_fake.loadeds += 1
	g_fake.loaded_at = {steps = g_fake.steps, views = g_fake.views}
	fake_box_free(model)

	name := pack
	g_fake.loaded_pack = strings.clone(roc_str_string(&name), context.temp_allocator)
	roc_decref(pack)
	g_fake.loaded_manifest = make([]Manifest_Line, manifest.length, context.temp_allocator)
	for &entry, i in manifest.elements[:manifest.length] {
		g_fake.loaded_manifest[i] = {strings.clone(roc_str_string(&entry.name), context.temp_allocator), entry.id}
	}
	roc_list_decref(manifest)

	g_fake.loaded_out = fake_box_new()
	return g_fake.loaded_out
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

fake_run_command :: proc(command: Command) {
	g_fake.runs[g_fake.runs_len] = {steps = g_fake.steps, views = g_fake.views}
	g_fake.runs_len += 1
}

fake_seam_init :: proc(s: ^Seam, seed: u64 = 0, colliders: []Collider = nil, mesh_dir := NO_MESH_DIR, init_commands: []Command = nil) {
	g_fake = {colliders = colliders, init_commands = init_commands}
	mesh_table_init(&g_fake.meshes, context.allocator)
	packs_init(&g_fake.packs, &g_fake.meshes, mesh_dir, context.allocator)
	seam_init(s, FAKE_GAME, fake_run_command, config_make(seed, g_fake.packs.on_disk), &g_fake.packs)
}

fake_seam_shutdown :: proc(s: ^Seam) {
	seam_shutdown(s)
	packs_destroy(&g_fake.packs)
	mesh_table_destroy(&g_fake.meshes)
}

// a.glb and b.glb load; broken.glb is on disk but fails.
fake_mesh_dir :: proc(t: ^testing.T) -> string {
	files := make(map[string][]byte, context.temp_allocator)
	files["a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["broken.glb"] = transmute([]byte)string("not a glb")
	return temp_mesh_dir(t, files)
}

// Steps once with commands and returns the Manifest of the last loaded.
fake_step_with :: proc(s: ^Seam, commands: ..Command) -> []Manifest_Line {
	g_fake.next_commands = slice.clone(commands, context.temp_allocator)
	seam_step(s, {}, 1.0 / 60)
	return g_fake.loaded_manifest
}

fake_draws_fallback :: proc(id: u32) -> bool {
	_, fallback := mesh_resolve(&g_fake.meshes, id, 1)
	return fallback
}

fake_mesh_name :: proc(id: u32) -> string {
	mesh, _ := mesh_resolve(&g_fake.meshes, id, 1)
	return mesh.name
}

@(test)
test_seam_init_pairs_the_first_scene_with_itself :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42)
	defer fake_seam_shutdown(&s)

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
	defer fake_seam_shutdown(&s)
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
	defer fake_seam_shutdown(&s)

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
	defer fake_seam_shutdown(&s)

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
	defer fake_seam_shutdown(&s)
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
	defer fake_seam_shutdown(&s)

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
	defer fake_seam_shutdown(&s)

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
	fake_seam_shutdown(&s)

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
	fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.drops, 1)
	testing.expect_value(t, g_fake.drop_box, g_fake.step_out)
	testing.expect_value(t, g_fake.drop_rc, 1)
	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_seam_step_runs_each_command_after_step_and_before_view :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)

	g_fake.commands_out = 3
	seam_step(&s, {}, 1.0 / 60)

	testing.expect_value(t, g_fake.runs_len, 3)
	for run in g_fake.runs[:g_fake.runs_len] {
		testing.expect_value(t, run, Fake_Command_Run{steps = 1, views = 1})
	}

	g_fake.commands_out = 0
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.runs_len, 3)
}

@(test)
test_seam_step_releases_the_commands_list :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)
	seam_step(&s, {}, 1.0 / 60)

	g_fake.commands_out = 2
	before := roc_heap_counters()
	seam_step(&s, {}, 1.0 / 60)
	after := roc_heap_counters()

	testing.expect_value(t, after.allocs - before.allocs, 3)
	testing.expect_value(t, after.deallocs - before.deallocs, 3)
	testing.expect_value(t, after.live, before.live)
}

@(test)
test_seam_step_returns_non_negative_durations :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)

	step_time, view_time := seam_step(&s, {}, 1.0 / 60)
	testing.expect(t, step_time >= 0)
	testing.expect(t, view_time >= 0)
}

@(test)
test_seam_init_runs_its_load_and_calls_loaded_before_the_first_view :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("start", "a")})
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.loadeds, 1)
	testing.expect_value(t, g_fake.loaded_at, Fake_Command_Run{steps = 0, views = 0})
	testing.expect_value(t, g_fake.loaded_pack, "start")
	testing.expect(t, slice.equal(g_fake.loaded_manifest, []Manifest_Line{{"a", len(Primitive)}}))
	testing.expect_value(t, g_fake.views, 1)
	testing.expect_value(t, g_fake.view_box, g_fake.loaded_out)
}

@(test)
test_init_gets_the_asset_names_on_disk_and_only_the_primitives_are_loaded :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42, mesh_dir = dir)
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.seed, 42)
	testing.expect(t, slice.equal(g_fake.assets, []string{"a", "b", "broken"}))
	testing.expect_value(t, g_fake.meshes.count, len(Primitive))
	testing.expect_value(t, g_fake.loadeds, 0)
}

@(test)
test_seam_step_runs_a_load_after_step_and_calls_loaded_before_view :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir)
	defer fake_seam_shutdown(&s)

	g_fake.next_commands = {fake_load("room", "b")}
	seam_step(&s, {}, 1.0 / 60)

	testing.expect_value(t, g_fake.loadeds, 1)
	testing.expect_value(t, g_fake.loaded_at, Fake_Command_Run{steps = 1, views = 1})
	testing.expect_value(t, g_fake.views, 2)
	testing.expect_value(t, g_fake.view_box, g_fake.loaded_out)
}

@(test)
test_loaded_gets_every_asked_for_name_and_a_missing_or_broken_one_has_id_0 :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir)
	defer fake_seam_shutdown(&s)

	g_fake.next_commands = {fake_load("room", "b", "nope", "primitive/cube", "broken", "a")}
	seam_step(&s, {}, 1.0 / 60)

	want := []Manifest_Line{{"b", len(Primitive)}, {"nope", 0}, {"primitive/cube", 1}, {"broken", 0}, {"a", len(Primitive) + 1}}
	testing.expect_value(t, g_fake.loaded_pack, "room")
	testing.expect(t, slice.equal(g_fake.loaded_manifest, want))
	testing.expect_value(t, len(g_fake.packs.logged_assets), 2)

	g_fake.next_commands = {fake_load("hall", "nope", "broken", "b")}
	seam_step(&s, {}, 1.0 / 60)
	testing.expect(t, slice.equal(g_fake.loaded_manifest, []Manifest_Line{{"nope", 0}, {"broken", 0}, {"b", len(Primitive)}}))
	testing.expect_value(t, len(g_fake.packs.logged_assets), 2)
	testing.expect_value(t, g_fake.meshes.count, len(Primitive) + 2)
}

@(test)
test_a_repeated_load_logs_once_and_does_not_call_loaded_again :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("start", "a")})
	defer fake_seam_shutdown(&s)

	g_fake.next_commands = {fake_load("room", "b"), fake_load("room", "b")}
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.loadeds, 2)
	testing.expect_value(t, len(g_fake.packs.logged_packs), 1)

	g_fake.next_commands = {fake_load("start", "a"), fake_load("room")}
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.loadeds, 2)
	testing.expect_value(t, len(g_fake.packs.logged_packs), 2)
	testing.expect_value(t, g_fake.loaded_pack, "room")
}

@(test)
test_loads_release_every_roc_block_by_shutdown :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	long_name := "a pack name longer than twenty-three bytes"
	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load(long_name, "a", "a mesh name longer than twenty-three bytes")})
	g_fake.next_commands = {fake_load(long_name, "b"), fake_load("room", "b")}
	seam_step(&s, {}, 1.0 / 60)
	fake_seam_shutdown(&s)

	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_a_swap_draws_the_fallback_for_the_old_pack_and_the_new_pack_meshes :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("A", "a")})
	defer fake_seam_shutdown(&s)
	a := g_fake.loaded_manifest[0].id

	b := fake_step_with(&s, fake_load("B", "b"))[0].id
	fake_step_with(&s, fake_unload("A"))

	testing.expect(t, fake_draws_fallback(a))
	testing.expect(t, !fake_draws_fallback(b))
	testing.expect_value(t, fake_mesh_name(b), "b")
}

@(test)
test_an_asset_in_two_packs_keeps_one_id_until_its_last_pack_unloads :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("A", "a")})
	defer fake_seam_shutdown(&s)
	in_a := g_fake.loaded_manifest[0].id

	in_b := fake_step_with(&s, fake_load("B", "b", "a"))[1].id
	testing.expect_value(t, in_b, in_a)

	fake_step_with(&s, fake_unload("A"))
	testing.expect(t, !fake_draws_fallback(in_a))
	testing.expect_value(t, fake_mesh_name(in_a), "a")

	fake_step_with(&s, fake_unload("B"))
	testing.expect(t, fake_draws_fallback(in_a))
}

@(test)
test_a_freed_slot_is_reused_and_the_old_id_stays_stale :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("A", "a")})
	defer fake_seam_shutdown(&s)
	old := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_unload("A"))
	fresh := fake_step_with(&s, fake_load("C", "b"))[0].id

	testing.expect_value(t, mesh_slot(fresh), mesh_slot(old))
	testing.expect(t, fresh != old)
	testing.expect(t, fake_draws_fallback(old))
	testing.expect_value(t, fake_mesh_name(fresh), "b")
}

@(test)
test_an_unload_of_an_unknown_pack_logs_once_and_does_nothing :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("A", "a")})
	defer fake_seam_shutdown(&s)
	a := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_unload("nope"), fake_unload("nope"))
	fake_step_with(&s, fake_unload("nope"))
	testing.expect_value(t, len(g_fake.packs.logged_unloads), 1)
	testing.expect_value(t, fake_mesh_name(a), "a")

	fake_step_with(&s, fake_unload("A"), fake_unload("A"))
	testing.expect_value(t, len(g_fake.packs.logged_unloads), 2)
	testing.expect_value(t, g_fake.loadeds, 1)
}

@(test)
test_unloading_every_pack_keeps_the_primitive_ids :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load("A", "a", "primitive/cube")})
	defer fake_seam_shutdown(&s)
	fake_step_with(&s, fake_load("B", "primitive/sphere", "b", "primitive/fallback"))
	fake_step_with(&s, fake_unload("B"), fake_unload("A"))

	for name, want in ([]string{"primitive/fallback", "primitive/cube", "primitive/sphere", "primitive/plane"}) {
		id, found := mesh_table_find(&g_fake.meshes, name)
		testing.expectf(t, found, "expected %v in the mesh table", name)
		testing.expect_value(t, id, u32(want))
		testing.expect_value(t, fake_mesh_name(id), name)
	}
	again := fake_step_with(&s, fake_load("C", "a", "b"))
	for line in again {
		testing.expectf(t, mesh_slot(line.id) >= len(Primitive), "%v took a primitive slot", line)
	}
}

@(test)
test_unloads_release_every_roc_block_by_shutdown :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	long_name := "a pack name longer than twenty-three bytes"
	s: Seam
	fake_seam_init(&s, mesh_dir = dir, init_commands = {fake_load(long_name, "a")})
	fake_step_with(&s, fake_unload(long_name), fake_unload(long_name))
	fake_seam_shutdown(&s)

	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_a_name_that_found_the_table_full_loads_after_an_unload_frees_a_slot :: proc(t: ^testing.T) {
	dir := fake_mesh_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, mesh_dir = dir)
	defer fake_seam_shutdown(&s)
	g_fake.meshes.count = MESH_CAPACITY - 1

	fake_step_with(&s, fake_load("A", "a"))
	testing.expect_value(t, fake_step_with(&s, fake_load("B", "b"))[0].id, 0)
	testing.expect_value(t, fake_step_with(&s, fake_load("C", "b"))[0].id, 0)
	testing.expect_value(t, len(g_fake.packs.logged_full), 1)

	fake_step_with(&s, fake_unload("A"))
	b := fake_step_with(&s, fake_load("D", "b"))[0].id
	testing.expect_value(t, fake_mesh_name(b), "b")
}
