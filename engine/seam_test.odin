#+test
package engine

import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

FAKE_KEYS_MAX :: 8
FAKE_CONTACTS_MAX :: 4
FAKE_RAYS_MAX :: 4
FAKE_OVERLAPS_MAX :: 4
FAKE_COMMANDS_MAX :: 4
FAKE_PORTS_MAX :: 8
NO_ASSETS_DIR :: "no/such/rocco/dir"

FAKE_GAME :: Game_Calls {
	launch     = fake_launch,
	init       = fake_init,
	step       = fake_step,
	loaded     = fake_loaded,
	view       = fake_view,
	drop_model = fake_drop_model,
}

// One pad of the last step's Input.
Fake_Pointer :: struct {
	pos:          [2]f32,
	inside:       bool,
	held:         [3]u8,
	pressed:      [3]u8,
	released:     [3]u8,
	held_len:     int,
	pressed_len:  int,
	released_len: int,
	wheel:        [2]f32,
}

Fake_Gamepad :: struct {
	slot:        u8,
	held:        [len(Gamepad_Button)]u8,
	held_len:    int,
	pressed:     [len(Gamepad_Button)]u8,
	pressed_len: int,
	axes:        Gamepad_Axes,
}

// One row of the last step's QueryResults.ports, copied out of Roc.
Fake_Port :: struct {
	port: string,
	msg:  string,
}

// When the fake runner ran a command, counted in steps and views.
Fake_Command_Run :: struct {
	steps: int,
	views: int,
}

// One Clip of a Manifest entry, with the name of its mesh.
Fake_Clip :: struct {
	mesh:     string,
	name:     string,
	id:       u32,
	duration: f32,
}

Fake_Game :: struct {
	launches:         int,
	// inits when launch ran, so 0 means launch came first.
	launch_inits:     int,
	launch_seed:      u64,
	launch_assets:    []string,
	launch_args:      []string,
	launch_out:       Launch,
	inits:            int,
	seed:             u64,
	assets:           []string,
	args:             []string,
	init_box:         rawptr,
	init_commands:    []Command,
	steps:            int,
	step_in:          rawptr,
	step_in_rc:       int,
	step_out:         rawptr,
	step_dt:          f32,
	held:             [FAKE_KEYS_MAX]u16,
	held_len:         int,
	pressed:          [FAKE_KEYS_MAX]u16,
	pressed_len:      int,
	mouse:            [2]f32,
	window:           [2]f32,
	gamepads:         [GAMEPAD_SLOTS]Fake_Gamepad,
	gamepads_len:     int,
	pointer:          Fake_Pointer,
	contacts:         [FAKE_CONTACTS_MAX]Contact,
	contacts_len:     int,
	rays:             [FAKE_RAYS_MAX]Ray_Hit,
	rays_len:         int,
	overlaps:         [FAKE_OVERLAPS_MAX]Overlap_Hit,
	overlaps_len:     int,
	ports:            [FAKE_PORTS_MAX]Fake_Port,
	ports_len:        int,
	views:            int,
	// The voices in use when view ran.
	view_voices:      int,
	view_box:         rawptr,
	view_rc:          int,
	drops:            int,
	drop_box:         rawptr,
	drop_rc:          int,
	colliders:        []Collider,
	queries:          []Query,
	ui_texts:         []string,
	// Root Elements with no Roc_Str. Each view copies their children lists
	// into Roc lists. ui_texts stays separate because each view must make its
	// strings fresh.
	ui:               []Element,
	// view returns these. With no draws, it returns one Draw whose id is the
	// view count. The root Nodes follow the Draws, the Colliders, the Lights
	// and the Speakers. Each view copies their children lists into Roc lists.
	camera:           Scene_Camera,
	draws:            []Draw,
	nodes:            []Node,
	lights:           []Light,
	speakers:         []Speaker,
	cursor:           Cursor,
	sky:              u32,
	commands_out:     int,
	next_commands:    []Command,
	runs:             [FAKE_COMMANDS_MAX]Fake_Command_Run,
	runs_len:         int,
	loadeds:          int,
	loaded_at:        Fake_Command_Run,
	loaded_pack:      string,
	loaded_manifest:  []Manifest_Line,
	loaded_durations: []f32,
	loaded_clips:     []Fake_Clip,
	loaded_out:       rawptr,
	meshes:           Mesh_Table,
	skies:            Sky_Table,
	audio:            Audio,
	packs:            Packs,
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

fake_play :: proc(sound: u32, gain, pitch: f32, at: Place) -> Command {
	command := Command {
		tag = .Play,
	}
	command.payload.play = {sound = sound, gain = gain, pitch = pitch, at = at}
	return command
}

// Copies the Config out and consumes it, as the Roc game does.
fake_config_read :: proc(config: Config) -> (seed: u64, assets, args: []string) {
	seed = config.seed
	assets = fake_strings_clone(config.assets)
	args = fake_strings_clone(config.args)
	roc_decref(config)
	return
}

fake_strings_clone :: proc(list: Roc_List(Roc_Str)) -> []string {
	out := make([]string, list.length, context.temp_allocator)
	for &str, i in list.elements[:list.length] {
		out[i] = strings.clone(roc_str_string(&str), context.temp_allocator)
	}
	return out
}

fake_launch :: proc(config: Config) -> Launch {
	g_fake.launches += 1
	g_fake.launch_inits = g_fake.inits
	g_fake.launch_seed, g_fake.launch_assets, g_fake.launch_args = fake_config_read(config)
	return launch_default()
}

fake_init :: proc(config: Config) -> Init_Result {
	g_fake.inits += 1
	g_fake.seed, g_fake.assets, g_fake.args = fake_config_read(config)
	g_fake.init_box = fake_box_new()
	return {model = g_fake.init_box, commands = roc_list_from_slice(g_fake.init_commands)}
}

fake_step :: proc(model: rawptr, input: Input, results: Query_Results, dt: f32) -> Step_Result {
	g_fake.steps += 1
	g_fake.step_in = model
	g_fake.step_in_rc = fake_refcount(model)^
	g_fake.step_dt = dt
	fake_box_free(model)

	g_fake.held_len = copy(g_fake.held[:], input.held.elements[:input.held.length])
	g_fake.pressed_len = copy(g_fake.pressed[:], input.pressed.elements[:input.pressed.length])
	g_fake.mouse = {input.mouse.dx, input.mouse.dy}
	g_fake.window = {input.window.width, input.window.height}
	g_fake.gamepads_len = int(input.gamepads.length)
	for pad, i in input.gamepads.elements[:input.gamepads.length] {
		fake := &g_fake.gamepads[i]
		fake.slot = pad.slot
		fake.held_len = copy(fake.held[:], pad.held.elements[:pad.held.length])
		fake.pressed_len = copy(fake.pressed[:], pad.pressed.elements[:pad.pressed.length])
		fake.axes = {
			left_stick    = {pad.left_stick.x, pad.left_stick.y},
			right_stick   = {pad.right_stick.x, pad.right_stick.y},
			left_trigger  = pad.left_trigger,
			right_trigger = pad.right_trigger,
		}
	}
	ptr := input.pointer
	fake_ptr := &g_fake.pointer
	fake_ptr.pos = {ptr.x, ptr.y}
	fake_ptr.inside = ptr.inside
	fake_ptr.held_len = copy(fake_ptr.held[:], ptr.held.elements[:ptr.held.length])
	fake_ptr.pressed_len = copy(fake_ptr.pressed[:], ptr.pressed.elements[:ptr.pressed.length])
	fake_ptr.released_len = copy(fake_ptr.released[:], ptr.released.elements[:ptr.released.length])
	fake_ptr.wheel = {ptr.wheel.dx, ptr.wheel.dy}
	roc_decref(input)
	g_fake.contacts_len = copy(g_fake.contacts[:], results.contacts.elements[:results.contacts.length])
	g_fake.rays_len = copy(g_fake.rays[:], results.rays.elements[:results.rays.length])
	g_fake.overlaps_len = copy(g_fake.overlaps[:], results.overlaps.elements[:results.overlaps.length])
	g_fake.ports_len = min(int(results.ports.length), FAKE_PORTS_MAX)
	for &row, i in results.ports.elements[:g_fake.ports_len] {
		g_fake.ports[i] = {
			port = strings.clone(roc_str_string(&row.port), context.temp_allocator),
			msg  = strings.clone(roc_str_string(&row.msg), context.temp_allocator),
		}
	}
	roc_decref(results)

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
	g_fake.loaded_durations = make([]f32, manifest.length, context.temp_allocator)
	clips := make([dynamic]Fake_Clip, context.temp_allocator)
	for &entry, i in manifest.elements[:manifest.length] {
		mesh := strings.clone(roc_str_string(&entry.name), context.temp_allocator)
		g_fake.loaded_manifest[i] = {mesh, entry.id}
		g_fake.loaded_durations[i] = entry.duration
		for &clip in entry.clips.elements[:entry.clips.length] {
			name := strings.clone(roc_str_string(&clip.name), context.temp_allocator)
			append(&clips, Fake_Clip{mesh, name, clip.id, clip.duration})
		}
	}
	g_fake.loaded_clips = clips[:]
	roc_list_decref(manifest)

	g_fake.loaded_out = fake_box_new()
	return g_fake.loaded_out
}

fake_view :: proc(model: rawptr) -> Scene {
	g_fake.views += 1
	g_fake.view_voices = len(g_fake.audio.voices.voices) - g_fake.audio.voices.free_count
	g_fake.view_box = model
	g_fake.view_rc = fake_refcount(model)^
	fake_refcount(model)^ -= 1
	ui := make([dynamic]Element, context.temp_allocator)
	for str in g_fake.ui_texts {
		text := Element {
			tag = .Text,
			payload = {text = {str = roc_str_from_slice(str)}},
		}
		append(&ui, Element{tag = .Box, payload = {box = {_1 = roc_list_from_slice([]Element{text})}}})
	}
	for e in g_fake.ui {
		append(&ui, fake_element_refcounted(e))
	}
	draws := g_fake.draws if g_fake.draws != nil else []Draw{{id = u64(g_fake.views)}}
	nodes := make([dynamic]Node, context.temp_allocator)
	for d in draws {
		append(&nodes, node_draw(d))
	}
	for c in g_fake.colliders {
		append(&nodes, node_collider(c))
	}
	for l in g_fake.lights {
		append(&nodes, node_light(l))
	}
	for speaker in g_fake.speakers {
		append(&nodes, node_speaker(speaker))
	}
	for n in g_fake.nodes {
		append(&nodes, fake_node_refcounted(n))
	}
	return {
		camera = g_fake.camera,
		nodes = roc_list_from_slice(nodes[:]),
		cursor = g_fake.cursor,
		sky = g_fake.sky,
		queries = roc_list_from_slice(g_fake.queries),
		ui = roc_list_from_slice(ui[:]),
	}
}

// The host frees each Scene, so every children list it gets must be a Roc allocation.
fake_element_refcounted :: proc(e: Element) -> Element {
	if e.tag != .Box {
		return e
	}
	box := e.payload.box
	old_children := box._1
	children := make([]Element, old_children.length, context.temp_allocator)
	for child, i in old_children.elements[:old_children.length] {
		children[i] = fake_element_refcounted(child)
	}
	box._1 = roc_list_from_slice(children)
	return {tag = .Box, payload = {box = box}}
}

// The host frees each Scene, so every Group's children list it gets must be a Roc allocation.
fake_node_refcounted :: proc(n: Node) -> Node {
	if n.tag != .Group {
		return n
	}
	group := n.payload.group
	old_children := group._1
	children := make([]Node, old_children.length, context.temp_allocator)
	for child, i in old_children.elements[:old_children.length] {
		children[i] = fake_node_refcounted(child)
	}
	group._1 = roc_list_from_slice(children)
	return {tag = .Group, payload = {group = group}}
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

fake_seam_init :: proc(s: ^Seam, seed: u64 = 0, colliders: []Collider = nil, queries: []Query = nil, assets_dir := NO_ASSETS_DIR, init_commands: []Command = nil, args: []string = nil, ui: []Element = nil) {
	g_fake = {colliders = colliders, queries = queries, init_commands = init_commands, ui = ui}
	packs_init(&g_fake.packs, assets_dir, context.allocator)
	g_fake.launch_out = seam_launch(s, FAKE_GAME, config_make(seed, g_fake.packs.on_disk, args))
	mesh_table_init(&g_fake.meshes, SMALL_MESHES, context.allocator, context.allocator)
	sky_table_init(&g_fake.skies, SMALL_SKIES, context.allocator, context.allocator)
	audio_init(&g_fake.audio, device = false)
	audio_tables_init(&g_fake.audio, SMALL_SOUNDS, SMALL_VOICES, context.allocator, context.allocator)
	packs_attach(&g_fake.packs, &g_fake.meshes, &g_fake.skies, &g_fake.audio, context.allocator)
	seam_init(s, fake_run_command, config_make(seed, g_fake.packs.on_disk, args), &g_fake.packs, &g_fake.audio)
}

fake_seam_shutdown :: proc(s: ^Seam) {
	seam_shutdown(s)
	roc_decref(g_fake.launch_out)
	packs_destroy(&g_fake.packs)
	mesh_table_destroy(&g_fake.meshes)
	sky_table_destroy(&g_fake.skies)
	audio_shutdown(&g_fake.audio)
}

// Meshes a and b load; broken is on disk but fails. Sky clear loads; torn
// has no nz face. Sound blip loads and sound broken fails.
fake_assets_dir :: proc(t: ^testing.T) -> string {
	files := make(map[string][]byte, context.temp_allocator)
	files["meshes/a.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["meshes/b.glb"] = triangle_glb(TRIANGLE_PRIMITIVES)
	files["meshes/broken.glb"] = transmute([]byte)string("not a glb")
	face := png_make(2, 2, PNG_RGBA, make([]byte, 2 * 2 * 4, context.temp_allocator))
	for name in SKY_FACES {
		files[fmt.tprintf("sky/clear/%v.png", name)] = face
		if name != "nz" {
			files[fmt.tprintf("sky/torn/%v.png", name)] = face
		}
	}
	files["sound/blip.wav"] = wav_make(1, {0, 8192, 16384})
	files["sound/broken.wav"] = transmute([]byte)string("not a wav")
	return temp_assets_dir(t, files)
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

// "" when the id draws no sky.
fake_sky_name :: proc(id: u32) -> string {
	sky, ok := sky_resolve(&g_fake.skies, id)
	return sky.name if ok else ""
}

// "" when the id plays nothing.
fake_sound_name :: proc(id: u32) -> string {
	sound, ok := sound_resolve(&g_fake.audio.sounds, id)
	return sound.name if ok else ""
}

@(test)
test_seam_init_pairs_the_first_scene_with_itself :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42)
	defer fake_seam_shutdown(&s)

	prev, curr := seam_scenes(&s)
	testing.expect_value(t, prev.nodes.elements, curr.nodes.elements)
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
	testing.expect_value(t, prev.nodes.elements, first.nodes.elements)
	testing.expect(t, curr.nodes.elements != first.nodes.elements)
	testing.expect_value(t, curr.nodes.elements[0].payload.draw.id, 2)
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
test_seam_step_frees_the_text_strings_of_the_last_scene :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	g_fake.ui_texts = {"a string longer than twenty-three bytes", "Keys"}
	seam_step(&s, {}, 1.0 / 60)
	seam_step(&s, {}, 1.0 / 60)

	_, curr := seam_scenes(&s)
	testing.expect_value(t, curr.ui.length, 2)
	children := curr.ui.elements[0].payload.box._1
	testing.expect_value(t, children.length, 1)
	testing.expect_value(t, children.elements[0].tag, Element_Tag.Text)
	testing.expect_value(t, roc_str_string(&children.elements[0].payload.text.str), "a string longer than twenty-three bytes")

	// Each step frees the box, the nodes list, the ui list, two children lists and one long string.
	before := roc_heap_counters()
	seam_step(&s, {}, 1.0 / 60)
	after := roc_heap_counters()
	testing.expect_value(t, after.allocs - before.allocs, 6)
	testing.expect_value(t, after.deallocs - before.deallocs, 6)
	testing.expect_value(t, after.reallocs - before.reallocs, 0)
	testing.expect_value(t, after.live, before.live)

	fake_seam_shutdown(&s)
	testing.expect_value(t, roc_heap_counters().live, 0)
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
test_seam_step_hands_the_pending_results_to_step_once :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)

	s.results.contacts = roc_list_from_slice([]Contact{{a = 1, b = 2, depth = 0.25}})
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
	fake_seam_init(&s, colliders = touching, queries = []Query{test_contacts_of(7)})
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
test_seam_step_hands_step_the_ray_hits_of_the_last_scene :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	colliders := []Collider{test_box(7, {0, 0.5, 0}, IDENTITY, {0.3, 0.5, 0.3}), test_box(2, {0, -2, 0}, IDENTITY, {1, 1, 1})}
	fake_seam_init(&s, colliders = colliders, queries = []Query{test_ray(7, 0, {0, 0.5, 0}, {0, -1, 0}, 10)})
	defer fake_seam_shutdown(&s)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.rays_len, 0)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.rays_len, 1)
	testing.expect_value(t, g_fake.rays[0].id, 2)
	testing.expect_value(t, g_fake.rays[0].distance, 1.5)
}

@(test)
test_seam_step_hands_step_the_overlaps_of_the_last_scene :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	colliders := []Collider{test_box(7, {0, 0.5, 0}, IDENTITY, {0.3, 0.5, 0.3}), test_sphere(2, {1, 0.5, 0}, 0.4)}
	fake_seam_init(&s, colliders = colliders, queries = []Query{test_overlap_sphere(7, 0, {0, 0.5, 0}, 1)})
	defer fake_seam_shutdown(&s)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.overlaps_len, 0)

	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.overlaps_len, 1)
	testing.expect_value(t, g_fake.overlaps[0], Overlap_Hit{owner = 7, slot = 0, id = 2})
}

// The Group turns the box at local (0, 0, 2) to (2, 0, 0), where it touches
// the box at the root.
@(test)
test_seam_step_answers_the_queries_against_the_world_poses_of_grouped_colliders :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	inner := []Node{node_collider(test_box(7, {0, 0, 2}, IDENTITY, {0.5, 0.5, 0.5}))}
	s: Seam
	fake_seam_init(&s, colliders = []Collider{test_box(3, {2.5, 0, 0}, IDENTITY, {0.5, 0.5, 0.5})}, queries = []Query{test_contacts_of(7)})
	g_fake.nodes = {node_group(1, {}, quat_yaw(math.PI / 2), inner)}

	seam_step(&s, {}, 1.0 / 60)
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 1)
	testing.expect_value(t, [2]u64{g_fake.contacts[0].a, g_fake.contacts[0].b}, [2]u64{3, 7})

	// The Group's children list is one more allocation, and the host frees it.
	before := roc_heap_counters()
	seam_step(&s, {}, 1.0 / 60)
	after := roc_heap_counters()
	testing.expect_value(t, after.allocs - before.allocs, after.deallocs - before.deallocs)
	testing.expect_value(t, after.live, before.live)
	fake_seam_shutdown(&s)
	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_seam_step_without_a_contacts_of_query_hands_step_no_contacts :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	touching := []Collider{test_sphere(7, {0, 0, 0}, 1), test_sphere(3, {1, 0, 0}, 1)}
	s: Seam
	fake_seam_init(&s, colliders = touching)
	defer fake_seam_shutdown(&s)

	seam_step(&s, {}, 1.0 / 60)
	seam_step(&s, {}, 1.0 / 60)
	testing.expect_value(t, g_fake.contacts_len, 0)
}

@(test)
test_seam_shutdown_releases_results_no_step_took :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	s.results.contacts = roc_list_from_slice([]Contact{{a = 1, b = 2}})
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
test_seam_step_logs_a_play_of_an_unknown_sound_id_and_does_not_quit :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)

	g_fake.next_commands = {fake_play(1, 1, 1, {tag = .Here})}
	_, _, quit := seam_step(&s, {}, 1.0 / 60)

	testing.expect(t, !quit)
	testing.expect_value(t, g_fake.runs_len, 0)
	testing.expect(t, 1 in g_fake.audio.sounds.logged)
	testing.expect_value(t, g_fake.audio.voices.free_count, SMALL_VOICES)
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

	step_time, view_time, _ := seam_step(&s, {}, 1.0 / 60)
	testing.expect(t, step_time >= 0)
	testing.expect(t, view_time >= 0)
}

@(test)
test_seam_init_runs_its_load_and_calls_loaded_before_the_first_view :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("start", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42, assets_dir = dir)
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.seed, 42)
	testing.expect(t, slice.equal(g_fake.assets, []string{"a", "b", "broken", "sky/clear", "sky/torn", "sound/blip", "sound/broken"}))
	testing.expect_value(t, g_fake.meshes.count, len(Primitive))
	testing.expect_value(t, g_fake.skies.count, 1)
	testing.expect_value(t, g_fake.audio.sounds.count, 1)
	testing.expect_value(t, g_fake.loadeds, 0)
}

@(test)
test_launch_runs_once_before_init_with_the_config_init_gets :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, 42, assets_dir = dir, args = {"--fullscreen", "an arg longer than twenty-three bytes"})
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, g_fake.launches, 1)
	testing.expect_value(t, g_fake.launch_inits, 0)
	testing.expect_value(t, g_fake.inits, 1)
	testing.expect_value(t, g_fake.launch_seed, 42)
	testing.expect_value(t, g_fake.launch_seed, g_fake.seed)
	testing.expect(t, slice.equal(g_fake.launch_assets, g_fake.assets))
	testing.expect(t, slice.equal(g_fake.launch_args, g_fake.args))
}

@(test)
test_init_gets_the_args_in_the_order_typed :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, args = {"--draws", "4096", "an arg longer than twenty-three bytes"})
	defer fake_seam_shutdown(&s)

	testing.expect(t, slice.equal(g_fake.args, []string{"--draws", "4096", "an arg longer than twenty-three bytes"}))
}

@(test)
test_init_gets_no_args_as_an_empty_list :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s)
	defer fake_seam_shutdown(&s)

	testing.expect_value(t, len(g_fake.args), 0)
}

@(test)
test_seam_step_runs_a_load_after_step_and_calls_loaded_before_view :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
	defer fake_seam_shutdown(&s)

	g_fake.next_commands = {fake_load("room", "b")}
	seam_step(&s, {}, 1.0 / 60)

	testing.expect_value(t, g_fake.loadeds, 1)
	testing.expect_value(t, g_fake.loaded_at, Fake_Command_Run{steps = 1, views = 1})
	testing.expect_value(t, g_fake.views, 2)
	testing.expect_value(t, g_fake.view_box, g_fake.loaded_out)
}

@(test)
test_loaded_lists_the_clips_of_each_skinned_mesh_with_ids_unique_across_the_pack :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["meshes/pip.glb"] = PIP_GLB
	files["meshes/strip.glb"] = SKINNED_GLB
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
	defer fake_seam_shutdown(&s)

	fake_step_with(&s, fake_load("room", "pip", "primitive/cube", "strip"))
	want := []Fake_Clip{{"pip", "Idle", 1, 2}, {"pip", "Walk", 2, 1}, {"strip", "Bend", 3, 1}}
	testing.expectf(t, slice.equal(g_fake.loaded_clips, want), "the Clips are %v", g_fake.loaded_clips)

	fake_step_with(&s, fake_load("hall", "strip"))
	testing.expect(t, slice.equal(g_fake.loaded_clips, want[2:]))
}

@(test)
test_loaded_gets_every_asked_for_name_and_a_missing_or_broken_one_has_id_0 :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("start", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	long_name := "a pack name longer than twenty-three bytes"
	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load(long_name, "a", "a mesh name longer than twenty-three bytes")})
	g_fake.next_commands = {fake_load(long_name, "b"), fake_load("room", "b")}
	seam_step(&s, {}, 1.0 / 60)
	fake_seam_shutdown(&s)

	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_a_swap_draws_the_fallback_for_the_old_pack_and_the_new_pack_meshes :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "a")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "a", "primitive/cube")})
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
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	long_name := "a pack name longer than twenty-three bytes"
	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load(long_name, "a")})
	fake_step_with(&s, fake_unload(long_name), fake_unload(long_name))
	fake_seam_shutdown(&s)

	testing.expect_value(t, roc_heap_counters().live, 0)
}

@(test)
test_a_name_that_found_the_table_full_loads_after_an_unload_frees_a_slot :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
	defer fake_seam_shutdown(&s)
	g_fake.meshes.count = SMALL_MESHES - 1

	a := fake_step_with(&s, fake_load("A", "a"))[0].id
	testing.expect_value(t, mesh_slot(a), SMALL_MESHES - 1)
	testing.expect_value(t, fake_step_with(&s, fake_load("B", "b"))[0].id, 0)
	testing.expect_value(t, fake_step_with(&s, fake_load("C", "b"))[0].id, 0)
	testing.expect_value(t, len(g_fake.packs.logged_full), 1)

	fake_step_with(&s, fake_unload("A"))
	b := fake_step_with(&s, fake_load("D", "b"))[0].id
	testing.expect_value(t, mesh_slot(b), SMALL_MESHES - 1)
	testing.expect_value(t, fake_mesh_name(b), "b")
}

@(test)
test_a_sky_name_in_a_load_gets_a_sky_id :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sky/clear", "a")})
	defer fake_seam_shutdown(&s)

	sky := g_fake.loaded_manifest[0].id
	testing.expect(t, sky != 0)
	testing.expect_value(t, fake_sky_name(sky), "sky/clear")
	testing.expect_value(t, g_fake.loaded_manifest[1].id, len(Primitive))
}

@(test)
test_a_stale_sky_id_draws_no_sky :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sky/clear")})
	defer fake_seam_shutdown(&s)
	old := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_unload("A"))
	fresh := fake_step_with(&s, fake_load("B", "sky/clear"))[0].id

	testing.expect_value(t, sky_slot(fresh), sky_slot(old))
	testing.expect(t, fresh != old)
	testing.expect_value(t, fake_sky_name(old), "")
	testing.expect_value(t, fake_sky_name(fresh), "sky/clear")
	testing.expect_value(t, len(g_fake.skies.logged), 1)
}

@(test)
test_a_sky_with_a_missing_face_logs_and_gets_id_0 :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sky/torn", "sky/nope")})
	defer fake_seam_shutdown(&s)

	testing.expect(t, slice.equal(g_fake.loaded_manifest, []Manifest_Line{{"sky/torn", 0}, {"sky/nope", 0}}))
	testing.expect_value(t, len(g_fake.packs.logged_assets), 2)
	testing.expect_value(t, g_fake.skies.count, 1)
}

@(test)
test_a_sky_in_two_packs_keeps_one_id_until_its_last_pack_unloads :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sky/clear")})
	defer fake_seam_shutdown(&s)
	in_a := g_fake.loaded_manifest[0].id

	testing.expect_value(t, fake_step_with(&s, fake_load("B", "sky/clear", "sky/clear"))[1].id, in_a)
	fake_step_with(&s, fake_unload("A"))
	testing.expect_value(t, fake_sky_name(in_a), "sky/clear")

	fake_step_with(&s, fake_unload("B"))
	testing.expect_value(t, fake_sky_name(in_a), "")
}

@(test)
test_a_sky_that_found_the_table_full_gets_id_0_and_logs_once :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
	defer fake_seam_shutdown(&s)
	g_fake.skies.count = SMALL_SKIES

	testing.expect_value(t, fake_step_with(&s, fake_load("A", "sky/clear"))[0].id, 0)
	testing.expect_value(t, fake_step_with(&s, fake_load("B", "sky/clear"))[0].id, 0)
	testing.expect_value(t, len(g_fake.packs.logged_full), 1)
}

@(test)
test_a_sound_name_in_a_load_gets_a_sound_id :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/blip", "a")})
	defer fake_seam_shutdown(&s)

	id := g_fake.loaded_manifest[0].id
	testing.expect(t, id != 0)
	testing.expect_value(t, fake_sound_name(id), "sound/blip")
	sound, _ := sound_resolve(&g_fake.audio.sounds, id)
	testing.expect_value(t, sound.channels, 1)
	testing.expect_value(t, sound.frames, 3)
	testing.expect_value(t, g_fake.loaded_manifest[1].id, len(Primitive))
}

@(test)
test_a_missing_or_broken_sound_gets_id_0_and_logs_once :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/nope", "sound/broken")})
	defer fake_seam_shutdown(&s)

	testing.expect(t, slice.equal(g_fake.loaded_manifest, []Manifest_Line{{"sound/nope", 0}, {"sound/broken", 0}}))
	testing.expect_value(t, len(g_fake.packs.logged_assets), 2)

	again := fake_step_with(&s, fake_load("B", "sound/broken", "sound/nope"))
	testing.expect(t, slice.equal(again, []Manifest_Line{{"sound/broken", 0}, {"sound/nope", 0}}))
	testing.expect_value(t, len(g_fake.packs.logged_assets), 2)
	testing.expect_value(t, g_fake.audio.sounds.count, 1)
}

// The decoder reads a file by its bytes, so a stereo wav named hum.ogg shows
// which of the two files loaded.
@(test)
test_a_shared_sound_stem_loads_the_first_file_in_sorted_order_and_logs_once :: proc(t: ^testing.T) {
	files := make(map[string][]byte, context.temp_allocator)
	files["sound/hum.wav"] = wav_make(1, {0, 0})
	files["sound/hum.ogg"] = wav_make(2, {0, 0, 0, 0})
	dir := temp_assets_dir(t, files)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/hum")})
	defer fake_seam_shutdown(&s)

	testing.expect(t, slice.equal(g_fake.assets, []string{"sound/hum"}))
	testing.expect_value(t, len(g_fake.packs.logged_stems), 1)
	sound, ok := sound_resolve(&g_fake.audio.sounds, g_fake.loaded_manifest[0].id)
	testing.expect(t, ok)
	testing.expect_value(t, sound.channels, 2)
}

@(test)
test_a_sound_in_two_packs_keeps_one_id_until_its_last_pack_unloads :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/blip")})
	defer fake_seam_shutdown(&s)
	in_a := g_fake.loaded_manifest[0].id

	testing.expect_value(t, fake_step_with(&s, fake_load("B", "sound/blip", "sound/blip"))[1].id, in_a)
	fake_step_with(&s, fake_unload("A"))
	testing.expect_value(t, fake_sound_name(in_a), "sound/blip")

	fake_step_with(&s, fake_unload("B"))
	testing.expect_value(t, fake_sound_name(in_a), "")
	testing.expect_value(t, g_fake.audio.sounds.free_count, 1)
}

@(test)
test_a_stale_sound_id_resolves_to_nothing_and_logs_once :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir, init_commands = {fake_load("A", "sound/blip")})
	defer fake_seam_shutdown(&s)
	old := g_fake.loaded_manifest[0].id

	fake_step_with(&s, fake_unload("A"))
	fresh := fake_step_with(&s, fake_load("B", "sound/blip"))[0].id

	testing.expect_value(t, sound_slot(fresh), sound_slot(old))
	testing.expect(t, fresh != old)
	testing.expect_value(t, fake_sound_name(old), "")
	testing.expect_value(t, fake_sound_name(old), "")
	testing.expect_value(t, fake_sound_name(fresh), "sound/blip")
	testing.expect_value(t, len(g_fake.audio.sounds.logged), 1)
}

@(test)
test_a_sound_that_found_the_table_full_gets_id_0_and_logs_once :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()

	s: Seam
	fake_seam_init(&s, assets_dir = dir)
	defer fake_seam_shutdown(&s)
	g_fake.audio.sounds.count = SMALL_SOUNDS

	testing.expect_value(t, fake_step_with(&s, fake_load("A", "sound/blip"))[0].id, 0)
	testing.expect_value(t, fake_step_with(&s, fake_load("B", "sound/blip"))[0].id, 0)
	testing.expect_value(t, len(g_fake.packs.logged_full), 1)
}
