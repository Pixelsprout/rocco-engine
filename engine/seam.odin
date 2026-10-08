package engine

import "core:time"

Game_Calls :: struct {
	init:       proc(config: Config) -> rawptr,
	step:       proc(model: rawptr, input: Input, contacts: Roc_List(Contact), dt: f32) -> rawptr,
	view:       proc(model: rawptr) -> Scene,
	drop_model: proc(model: rawptr),
}

Seam :: struct {
	calls: Game_Calls,
	model: rawptr,
	// prev is the Scene before curr. The host interpolates between them.
	prev:     Scene,
	curr:     Scene,
	has_prev: bool,
	// The next step takes these. They come from curr's colliders.
	contacts: Roc_List(Contact),
	search:   Contact_Search,
}

// Owns the one reference to the Model, the last two Scenes and the contacts.
// See the call protocol in docs/DESIGN.md section 5: Roc consumes every
// argument it gets.
seam_init :: proc(s: ^Seam, calls: Game_Calls, config: Config) {
	s.calls = calls
	contact_search_init(&s.search, context.allocator)
	s.model = s.calls.init(config)
	s.curr = seam_view(s)
}

seam_step :: proc(s: ^Seam, keys: Step_Keys, dt: f32) -> (step_time, view_time: time.Duration) {
	start := time.tick_now()

	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	// step frees the old box and consumes the contacts. Never touch either again.
	s.model = s.calls.step(s.model, input, s.contacts, dt)
	s.contacts = {}
	stepped := time.tick_now()
	if s.has_prev {
		roc_decref(s.prev)
	}
	s.prev = s.curr
	s.has_prev = true
	s.curr = seam_view(s)
	viewed := time.tick_now()
	colliders := s.curr.colliders.elements[:s.curr.colliders.length]
	s.contacts = roc_list_from_slice(contacts_find(&s.search, colliders, context.temp_allocator))

	return time.tick_diff(start, stepped), time.tick_diff(stepped, viewed)
}

// Before the first step there is one Scene, and it pairs with itself.
seam_scenes :: proc(s: ^Seam) -> (prev, curr: Scene) {
	return s.prev if s.has_prev else s.curr, s.curr
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
	roc_list_decref(s.contacts)
	s.calls.drop_model(s.model)
	contact_search_destroy(&s.search)
}
