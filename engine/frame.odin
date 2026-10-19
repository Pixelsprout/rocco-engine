package engine

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

	clock_add_frame(&s.clock, platform.frame_duration)
	for dt in clock_next_step(&s.clock) {
		before := roc_heap_counters()
		step_time, view_time := seam_step(&s.seam, input_take(&s.input, &s.keys), dt)
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
		camera_fly(&s.debug_camera, &s.input, f32(min(platform.frame_duration, MAX_FRAME_TIME)))
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

	if exit_after_frames_reached(s.exit_after_frames, s.frame_count) {
		platform.request_quit()
	}

	frame_end(&s.mem)
	input_end_frame(&s.input)
}
