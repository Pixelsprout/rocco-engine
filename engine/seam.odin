package engine

import "core:time"

Seam :: struct {
	model: rawptr,
	// prev is the Scene before curr. The host interpolates between them.
	prev:     Scene,
	curr:     Scene,
	has_prev: bool,
}

// Owns the one reference to the Model and the last two Scenes. See the call
// protocol in docs/DESIGN.md section 5: Roc consumes every argument it gets.
seam_init :: proc(s: ^Seam, seed: u64, table: ^Mesh_Table) {
	s.model = roc_init(config_make(seed, table))
	s.curr = seam_view(s)
}

seam_step :: proc(s: ^Seam, keys: Step_Keys, dt: f32) -> (step, view: time.Duration) {
	start := time.tick_now()

	input := Input {
		held    = roc_list_from_slice(keys.held),
		pressed = roc_list_from_slice(keys.pressed),
		mouse   = {dx = keys.mouse.x, dy = keys.mouse.y},
	}
	// roc_step frees the old box. Never touch the old pointer again.
	s.model = roc_step(s.model, input, dt)
	stepped := time.tick_now()
	if s.has_prev {
		roc_decref(s.prev)
	}
	s.prev = s.curr
	s.has_prev = true
	s.curr = seam_view(s)
	viewed := time.tick_now()

	return time.tick_diff(start, stepped), time.tick_diff(stepped, viewed)
}

// Before the first step there is one Scene, and it pairs with itself.
seam_scenes :: proc(s: ^Seam) -> (prev, curr: Scene) {
	return s.prev if s.has_prev else s.curr, s.curr
}

// roc_view consumes one reference, so give it one and keep ours.
@(private = "file")
seam_view :: proc(s: ^Seam) -> Scene {
	roc_incref_box(s.model)
	return roc_view(s.model)
}

seam_shutdown :: proc(s: ^Seam) {
	if s.has_prev {
		roc_decref(s.prev)
	}
	roc_decref(s.curr)
	roc_drop_model(s.model)
}
