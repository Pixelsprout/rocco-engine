package engine

import "core:time"

Game_Calls :: struct {
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
	model:       rawptr,
	// prev is the Scene before curr. The host interpolates between them.
	prev:     Scene,
	curr:     Scene,
	has_prev: bool,
	// The next step takes these. They answer curr's queries.
	results: Query_Results,
	search:  Query_Search,
}

// Owns the one reference to the Model, the last two Scenes and the QueryResults.
// See the call protocol in docs/DESIGN.md section 5: Roc consumes every
// argument it gets.
seam_init :: proc(s: ^Seam, calls: Game_Calls, run_command: Command_Runner, config: Config, packs: ^Packs) {
	s.calls = calls
	s.run_command = run_command
	s.packs = packs
	query_search_init(&s.search, context.allocator)
	started := s.calls.init(config)
	s.model = started.model
	seam_run_commands(s, started.commands)
	s.curr = seam_view(s)
}

seam_step :: proc(s: ^Seam, keys: Step_Keys, dt: f32) -> (step_time, view_time: time.Duration) {
	start := time.tick_now()

	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	// step frees the old box and consumes the results. Never touch either again.
	result := s.calls.step(s.model, input, s.results, dt)
	s.model = result.model
	s.results = {}
	stepped := time.tick_now()
	seam_run_commands(s, result.commands)
	if s.has_prev {
		roc_decref(s.prev)
	}
	s.prev = s.curr
	s.has_prev = true
	s.curr = seam_view(s)
	viewed := time.tick_now()
	s.results = seam_query_results(s)

	return time.tick_diff(start, stepped), time.tick_diff(stepped, viewed)
}

// Before the first step there is one Scene, and it pairs with itself.
seam_scenes :: proc(s: ^Seam) -> (prev, curr: Scene) {
	return s.prev if s.has_prev else s.curr, s.curr
}

@(private = "file")
seam_query_results :: proc(s: ^Seam) -> Query_Results {
	colliders := s.curr.colliders.elements[:s.curr.colliders.length]
	queries := s.curr.queries.elements[:s.curr.queries.length]
	return {
		contacts = roc_list_from_slice(contacts_asked(&s.search, colliders, queries, context.temp_allocator)),
		rays = roc_list_from_slice(rays_find(&s.search, colliders, queries, context.temp_allocator)),
		overlaps = roc_list_from_slice(overlaps_find(&s.search, colliders, queries, context.temp_allocator)),
	}
}

// The host owns the commands list and frees it after running it, so every
// string a command holds is only borrowed until then.
@(private = "file")
seam_run_commands :: proc(s: ^Seam, commands: Roc_List(Command)) {
	for &command in commands.elements[:commands.length] {
		switch command.tag {
		case .Load:
			seam_load(s, &command.payload.load)
		case .Unload:
			pack_unload(s.packs, roc_str_string(&command.payload.unload))
		case .Quit:
			s.run_command(command)
		}
	}
	roc_list_decref(commands)
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
