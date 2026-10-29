package engine

import "core:mem"
import "core:strings"
import "core:time"

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

	// One fixed interval leaves the accumulator at zero after the step, so
	// Lockstep runs exactly one fixed step per Frame.
	frame_time := platform.frame_duration if s.mode == .Real_Clock else s.clock.fixed_dt
	clock_add_frame(&s.clock, bridge_clock_time(&s.bridge, frame_time))
	steps := 0
	for dt in clock_next_step(&s.clock) {
		before := roc_heap_counters()
		// Under the Bridge, only the Driver gives step its Input. The real
		// devices still reach the latch, which the debug camera reads.
		step_input: Step_Input
		commands_json: ^strings.Builder
		if s.bridge.on {
			// curr is the Scene the window shows, whose QueryResults this
			// step gets, so a tell followed by a step is delivered in it.
			seam_set_ports(&s.seam, bridge_ports_deliver(&s.bridge.ports, s.seam.curr.queries.elements[:s.seam.curr.queries.length]))
			step_input = bridge_input_take(&s.bridge, &s.input_buffers)
			commands_json = &s.bridge.commands
		} else {
			step_input = input_take(&s.input, &s.input_buffers)
		}
		step_time, view_time, quit := seam_step(&s.seam, step_input, dt, &s.spans, commands_json)
		audio_advance(&s.audio, dt)
		steps += 1
		s.steps += 1
		alloc := roc_heap_report(s.steps, before, time.duration_microseconds(step_time), time.duration_microseconds(view_time))
		if s.alloc_report {
			alloc_report_print(alloc)
		}
		if s.bridge.on {
			bridge_step_taken(s, alloc, quit)
		}
	}

	alpha := clock_alpha(&s.clock)
	prev, curr := seam_scenes(&s.seam)
	// Lockstep's Alpha is 0, which draws prev.
	if bridge_paused(&s.bridge) {
		prev = curr
	}
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

	// Headless submits nothing, so its render Spans stay at zero.
	renders := s.mode != .Headless
	frame_render_draw(&s.frame_render, prev, curr, alpha, view_proj, eye, &s.renderer.meshes, &s.renderer.skies, &s.ui, platform.window, &s.spans, renders)
	if renders {
		span := span_open()
		platform.commit()
		span_close(&s.spans, .Commit, span)
	}
	s.frame_count += 1
	span_frame_end(&s.spans, s.frame_count, steps)

	if exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		bridge_frame_limit_reached(s)
		platform.request_quit()
	}

	frame_end(&s.mem)
	// Under the Bridge no step takes the real latch, so it drops what a step
	// would take.
	if s.bridge.on {
		input_drop(&s.input)
	}
	input_end_frame(&s.input)
}

// With no display the dpi is 1, and the rest of the Launch's window has no reader.
headless_window :: proc(launch: Launch) -> Ui_Window {
	return {size = {f32(launch.window.width), f32(launch.window.height)}, dpi = 1}
}

// Holds no sokol call, so a Headless run needs no window and no GPU.
headless_platform :: proc(s: ^State) -> Frame_Platform {
	return {frame_duration = s.clock.fixed_dt, window = headless_window(s.launch), lock_mouse = headless_lock_mouse, request_quit = headless_request_quit}
}

// Lays out the UI with no window. frame_run never submits in Headless.
headless_init :: proc(s: ^State, allocator: mem.Allocator) -> mem.Allocator_Error {
	return ui_init(&s.ui, headless_window(s.launch).size, int(s.launch.capacity.ui_quads), allocator)
}

// Runs Frames until the Frame limit or a Quit, then returns.
headless_run :: proc(s: ^State) {
	platform := headless_platform(s)
	for !s.quit && !exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		bridge_wait_for_steps(s)
		if s.bridge.quit {
			return
		}
		frame_run(s, platform)
	}
}

@(private = "file")
headless_lock_mouse :: proc(locked: bool) {}

// headless_run stops at the Frame limit itself.
@(private = "file")
headless_request_quit :: proc() {}
