package engine

import "core:mem"
import "core:time"

// Headless lays out the UI against this size, because it has no window.
HEADLESS_WINDOW :: Ui_Window {
	size = {960, 540},
	dpi  = 1,
}

// Holds no sokol call, so a Headless run needs no window and no GPU.
HEADLESS_PLATFORM :: Frame_Platform {
	frame_duration = FIXED_DT,
	window         = HEADLESS_WINDOW,
	lock_mouse     = headless_lock_mouse,
	commit         = headless_commit,
	request_quit   = headless_request_quit,
}

// What one Frame reads from the window and asks of it. Tests pass fakes, so a
// Frame runs without sokol.
Frame_Platform :: struct {
	frame_duration: f64,
	window:         Ui_Window,
	mouse_locked:   bool,
	lock_mouse:     proc(locked: bool),
	commit:         proc(),
	request_quit:   proc(),
}

// Runs one Frame: the fixed steps through the Seam's Game calls, their
// Commands and Queries, then the render.
frame_run :: proc(s: ^State, platform: Frame_Platform) {
	// The win32 loop runs one more frame after request_quit, before it reads
	// WM_CLOSE. Skip it, so Frame Count matches the limit on every OS.
	if exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		return
	}

	// One FIXED_DT leaves the accumulator at zero after the step, so Lockstep
	// runs exactly one fixed step per Frame.
	frame_time := platform.frame_duration if s.mode == .Real_Clock else FIXED_DT
	clock_add_frame(&s.clock, frame_time)
	steps := 0
	for dt in clock_next_step(&s.clock) {
		before := roc_heap_counters()
		step_time, view_time := seam_step(&s.seam, input_take(&s.input, &s.keys), dt)
		span_add(&s.spans, .Step, step_time)
		span_add(&s.spans, .View, view_time)
		steps += 1
		s.steps += 1
		if s.alloc_report {
			roc_heap_report_line(s.steps, before, time.duration_microseconds(step_time), time.duration_microseconds(view_time))
		}
	}

	alpha := clock_alpha(&s.clock)
	prev, curr := seam_scenes(&s.seam)
	aspect := platform.window.size.x / platform.window.size.y
	view_proj: Mat4
	eye: [3]f32
	if s.use_debug_camera {
		camera_look(&s.debug_camera, &s.input)
		camera_fly(&s.debug_camera, &s.input, f32(min(frame_time, MAX_FRAME_TIME)))
		view_proj = camera_proj(&s.debug_camera, aspect) * camera_view(&s.debug_camera)
		eye = s.debug_camera.eye
	} else {
		view_proj, eye = frame_render_camera(&s.frame_render, prev, curr, alpha, aspect)
	}
	cursor := Cursor.Locked if s.use_debug_camera else curr.cursor
	if (cursor == .Locked) != platform.mouse_locked {
		platform.lock_mouse(cursor == .Locked)
	}

	frame_render_draw(&s.frame_render, prev, curr, alpha, view_proj, eye, &s.renderer.meshes, &s.renderer.skies, &s.ui, platform.window)

	platform.commit()
	s.frame_count += 1
	span_frame_end(&s.spans, s.frame_count, steps)

	if exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		platform.request_quit()
	}

	frame_end(&s.mem)
	input_end_frame(&s.input)
}

// Points the render at no-op submits and lays out the UI with no window.
headless_init :: proc(s: ^State, allocator: mem.Allocator) -> mem.Allocator_Error {
	s.frame_render.begin_pass = proc(ctx: rawptr, pass: Pass, view: int) {}
	s.frame_render.end_pass = proc(ctx: rawptr) {}
	s.frame_render.submit_shadow = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params) {}
	s.frame_render.submit = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params) {}
	s.frame_render.submit_lights = proc(ctx: rawptr, lights: Fs_Lights) {}
	s.frame_render.submit_sky = proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {}
	s.frame_render.submit_ui = proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {}
	return ui_init(&s.ui, HEADLESS_WINDOW.size, allocator)
}

// Runs Frames until the Frame limit or a Quit, then returns.
headless_run :: proc(s: ^State) {
	for !s.quit && !exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		frame_run(s, HEADLESS_PLATFORM)
	}
}

@(private = "file")
headless_lock_mouse :: proc(locked: bool) {}

@(private = "file")
headless_commit :: proc() {}

// headless_run stops at the Frame limit itself.
@(private = "file")
headless_request_quit :: proc() {}
