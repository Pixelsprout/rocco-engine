package engine

import "core:strings"
import "core:time"

Game_Calls :: struct {
	launch:     proc(config: Config) -> Launch,
	init:       proc(config: Config) -> Init_Result,
	step:       proc(model: rawptr, input: Input, results: Query_Results, dt: f32) -> Step_Result,
	loaded:     proc(model: rawptr, pack: Roc_Str, manifest: Roc_List(Manifest_Entry)) -> rawptr,
	view:       proc(model: rawptr) -> Scene,
	drop_model: proc(model: rawptr),
}

// Runs Quit. The Seam runs Load and Unload itself, because loaded must reach
// the game before the next view.
Command_Runner :: #type proc(command: Command)

Seam :: struct {
	calls:       Game_Calls,
	run_command: Command_Runner,
	packs:       ^Packs,
	audio:       ^Audio,
	model:       rawptr,
	// prev is the Scene before curr. The host interpolates between them.
	prev:     Scene,
	curr:     Scene,
	has_prev: bool,
	// The next step takes these. They answer curr's queries.
	results: Query_Results,
	search:  Query_Search,
}

// The Queries' answers before the copy into Roc lists.
Query_Answers :: struct {
	contacts: []Contact,
	rays:     []Ray_Hit,
	overlaps: []Overlap_Hit,
}

// The first Game call. ADR 0007 puts launch before init, so the host holds
// the Launch before init's Commands run. It binds the Game calls that
// seam_init then uses.
seam_launch :: proc(s: ^Seam, calls: Game_Calls, config: Config) -> Launch {
	s.calls = calls
	return s.calls.launch(config)
}

// Owns the one reference to the Model, the last two Scenes and the QueryResults.
// See the call protocol in docs/DESIGN.md section 5: Roc consumes every
// argument it gets.
seam_init :: proc(s: ^Seam, run_command: Command_Runner, config: Config, packs: ^Packs, audio: ^Audio) {
	assert(s.calls.init != nil, "seam_launch binds the Game calls and runs first")
	s.run_command = run_command
	s.packs = packs
	s.audio = audio
	query_search_init(&s.search, context.allocator)
	started := s.calls.init(config)
	s.model = started.model
	_, plays := seam_run_commands(s, started.commands)
	s.curr = seam_view(s)
	seam_sound(s, plays)
}

// The Spans split the work finer than step_time and view_time, which the
// alloc report keeps. With commands_json, it appends the step's Commands
// there, because the host frees them after it runs them. quit is true when
// the game returned Quit.
seam_step :: proc(s: ^Seam, keys: Step_Keys, dt: f32, spans: ^Span_Sink = nil, commands_json: ^strings.Builder = nil) -> (step_time, view_time: time.Duration, quit: bool) {
	start := time.tick_now()
	span := span_open()

	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	span = span_close(spans, .Input, span)
	// step frees the old box and consumes the results. Never touch either again.
	result := s.calls.step(s.model, input, s.results, dt)
	s.model = result.model
	s.results = {}
	span = span_close(spans, .Step, span)
	stepped := time.tick_now()
	if commands_json != nil {
		json_write_commands(commands_json, result.commands)
	}
	plays: []Play_Command
	quit, plays = seam_run_commands(s, result.commands)
	span = span_close(spans, .Commands, span)
	if s.has_prev {
		roc_decref(s.prev)
	}
	s.prev = s.curr
	s.has_prev = true
	s.curr = seam_view(s)
	seam_sound(s, plays)
	span = span_close(spans, .View, span)
	viewed := time.tick_now()
	answers := seam_query_search(s)
	span = span_close(spans, .Queries, span)
	s.results = {
		contacts = roc_list_from_slice(answers.contacts),
		rays     = roc_list_from_slice(answers.rays),
		overlaps = roc_list_from_slice(answers.overlaps),
	}
	span_close(spans, .Query_Results, span)

	return time.tick_diff(start, stepped), time.tick_diff(stepped, viewed), quit
}

// Before the first step there is one Scene, and it pairs with itself.
seam_scenes :: proc(s: ^Seam) -> (prev, curr: Scene) {
	return s.prev if s.has_prev else s.curr, s.curr
}

// The answers and the world-space Colliders live in the Frame allocator
// until the copy into Roc.
@(private = "file")
seam_query_search :: proc(s: ^Seam) -> Query_Answers {
	colliders := scene_colliders(s.curr.nodes.elements[:s.curr.nodes.length], context.temp_allocator)
	queries := s.curr.queries.elements[:s.curr.queries.length]
	return queries_answer(&s.search, colliders, queries, context.temp_allocator)
}

// The host owns the commands list and frees it after running it, so every
// string a command holds is only borrowed until then. The Plays come back in
// the Frame allocator, because they start after view.
@(private = "file")
seam_run_commands :: proc(s: ^Seam, commands: Roc_List(Command)) -> (quit: bool, plays: []Play_Command) {
	pending := make([dynamic]Play_Command, context.temp_allocator)
	for &command in commands.elements[:commands.length] {
		switch command.tag {
		case .Load:
			seam_load(s, &command.payload.load)
		case .Unload:
			pack_unload(s.packs, roc_str_string(&command.payload.unload))
		case .Quit:
			quit = true
			s.run_command(command)
		case .Play:
			append(&pending, command.payload.play)
		}
	}
	roc_list_decref(commands)
	return quit, pending[:]
}

// A device mixes a voice as soon as it starts, so the Listener moves to the
// new Camera before the Plays start.
@(private = "file")
seam_sound :: proc(s: ^Seam, plays: []Play_Command) {
	audio_listen(s.audio, s.curr.camera)
	for play in plays {
		audio_play(s.audio, play)
	}
	audio_loops(s.audio, s.curr.loops.elements[:s.curr.loops.length])
}

// loaded consumes the box, the pack name and the manifest, as step does.
@(private = "file")
seam_load :: proc(s: ^Seam, load: ^Load_Command) {
	pack := roc_str_string(&load.pack)
	assets := make([]string, load.assets.length, context.temp_allocator)
	for &name, i in load.assets.elements[:load.assets.length] {
		assets[i] = roc_str_string(&name)
	}
	lines, ok := pack_load(s.packs, pack, assets, context.temp_allocator)
	if !ok {
		return
	}

	entries := make([]Manifest_Entry, len(lines), context.temp_allocator)
	for line, i in lines {
		entries[i] = {name = roc_str_from_slice(line.name), id = line.id}
	}
	s.model = s.calls.loaded(s.model, roc_str_from_slice(pack), roc_list_from_slice(entries))
}

// view consumes one reference, so give it one and keep ours.
@(private = "file")
seam_view :: proc(s: ^Seam) -> Scene {
	roc_incref_box(s.model)
	return s.calls.view(s.model)
}

seam_shutdown :: proc(s: ^Seam) {
	if s.has_prev {
		roc_decref(s.prev)
	}
	roc_decref(s.curr)
	roc_decref(s.results)
	s.calls.drop_model(s.model)
	query_search_destroy(&s.search)
}
