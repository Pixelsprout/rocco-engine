#+test
package engine

import clay "../clay/bindings/odin/clay-odin"
import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import "core:sync"
import "core:testing"
import "core:time"

// Far longer than the fake render work, so a Span that holds the wait shows it.
FAKE_PASS_WAIT :: 30 * time.Millisecond

Fake_Platform_Calls :: struct {
	commits: int,
	quits:   int,
	submits: int,
}

// Guarded by the Roc heap test lock, as g_fake is.
g_fake_platform: Fake_Platform_Calls

// Holds g_clay_lock until fake_frame_state_destroy, because the render lays out the UI.
fake_frame_state_init :: proc(s: ^State, exit_after_frames := 0, mode := Run_Mode.Real_Clock, colliders: []Collider = nil, queries: []Query = nil, launch: Maybe(Launch) = nil, ui: []Element = nil) {
	g_fake_platform = {}
	err := memory_init(&s.mem)
	assert(err == nil)
	s.exit_after_frames = exit_after_frames
	s.mode = mode
	s.launch = launch.? or_else launch_default()
	clock_init(&s.clock, s.launch.step_hz)
	span_sink_init(&s.spans, "", exit_after_frames, context.allocator)
	fake_seam_init(&s.seam, colliders = colliders, queries = queries, ui = ui)
	capacity := s.launch.capacity
	mesh_table_init(&s.renderer.meshes, int(capacity.meshes), context.allocator, context.allocator)
	sky_table_init(&s.renderer.skies, int(capacity.skies), context.allocator, context.allocator)
	frame_render_init(&s.frame_render, int(capacity.draws), int(capacity.groups), context.allocator)
	sync.mutex_lock(&g_clay_lock)
	ui_err := headless_init(s, context.allocator)
	assert(ui_err == nil)
	s.frame_render.begin_pass = proc(ctx: rawptr, pass: Pass, view: int) {}
	s.frame_render.end_pass = proc(ctx: rawptr) {}
	s.frame_render.submit_shadow = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {}
	s.frame_render.submit = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {}
	s.frame_render.submit_lights = proc(ctx: rawptr, lights: Fs_Lights) {g_fake_platform.submits += 1}
	s.frame_render.submit_sky = proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {}
	s.frame_render.submit_ui = proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {}
}

fake_frame_state_destroy :: proc(s: ^State) {
	clay.SetCurrentContext(nil)
	delete(s.ui.memory)
	delete(s.ui.quads)
	delete(s.ui.hits)
	delete(s.ui.over)
	delete(s.ui.scroll_boxes)
	delete(s.ui.scrolls)
	delete(s.ui.clips)
	sync.mutex_unlock(&g_clay_lock)
	frame_render_destroy(&s.frame_render)
	mesh_table_destroy(&s.renderer.meshes)
	sky_table_destroy(&s.renderer.skies)
	fake_seam_shutdown(&s.seam)
	roc_decref(s.launch)
	span_sink_destroy(&s.spans)
	memory_shutdown(&s.mem)
}

fake_platform :: proc(frame_duration: f64) -> Frame_Platform {
	return {
		frame_duration = frame_duration,
		window = headless_window(launch_default()),
		lock_mouse = proc(locked: bool) {},
		commit = proc() {g_fake_platform.commits += 1},
		request_quit = proc() {g_fake_platform.quits += 1},
	}
}

@(test)
test_frame_run_steps_once_and_views_once_per_frame_at_the_fixed_dt :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)

	for _ in 0 ..< 5 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
	}

	testing.expect_value(t, g_fake.steps, 5)
	// init made the first view.
	testing.expect_value(t, g_fake.views, 6)
	testing.expect_value(t, s.steps, 5)
	testing.expect_value(t, s.frame_count, 5)
	testing.expect_value(t, g_fake_platform.commits, 5)
}

// The game picks its step rate, so the interval and the dt follow step_hz.
@(test)
test_frame_run_at_60_hz_steps_once_per_interval_with_a_dt_of_one_over_60 :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.step_hz = 60
	s: State
	fake_frame_state_init(&s, launch = launch)
	defer fake_frame_state_destroy(&s)

	for _ in 0 ..< 5 {
		frame_run(&s, fake_platform(1.0 / 60))
	}
	frame_run(&s, fake_platform(1.0 / 120))

	testing.expect_value(t, g_fake.steps, 5)
	testing.expect_value(t, g_fake.step_dt, f32(1.0 / 60))
}

@(test)
test_frame_run_runs_every_fixed_step_the_frame_time_holds :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(3 * s.clock.fixed_dt))

	testing.expect_value(t, g_fake.steps, 3)
	testing.expect_value(t, g_fake.views, 4)
	testing.expect_value(t, g_fake_platform.commits, 1)
}

@(test)
test_frame_run_shorter_than_a_fixed_step_renders_without_a_step :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(s.clock.fixed_dt / 2))

	testing.expect_value(t, g_fake.steps, 0)
	testing.expect_value(t, g_fake.views, 1)
	testing.expect_value(t, s.frame_count, 1)
	testing.expect_value(t, g_fake_platform.commits, 1)
}

@(test)
test_frame_run_requests_quit_at_the_limit_and_skips_later_frames :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 2)
	defer fake_frame_state_destroy(&s)

	for _ in 0 ..< 4 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
	}

	testing.expect_value(t, g_fake_platform.quits, 1)
	testing.expect_value(t, s.frame_count, 2)
	testing.expect_value(t, g_fake.steps, 2)
	testing.expect_value(t, g_fake_platform.commits, 2)
}

@(test)
test_frame_run_in_lockstep_runs_one_fixed_step_whatever_the_frame_time :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(3 * s.clock.fixed_dt))
	frame_run(&s, fake_platform(s.clock.fixed_dt / 2))
	frame_run(&s, fake_platform(0))

	testing.expect_value(t, g_fake.steps, 3)
	testing.expect_value(t, g_fake.views, 4)
	testing.expect_value(t, g_fake_platform.commits, 3)
}

@(test)
test_frame_run_in_lockstep_at_60_hz_runs_one_step_per_frame_with_a_dt_of_one_over_60 :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.step_hz = 60
	s: State
	fake_frame_state_init(&s, mode = .Lockstep, launch = launch)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(3.0 / 60))
	frame_run(&s, fake_platform(1.0 / 120))
	frame_run(&s, fake_platform(0))

	testing.expect_value(t, g_fake.steps, 3)
	testing.expect_value(t, g_fake.step_dt, f32(1.0 / 60))
}

@(test)
test_headless_run_steps_and_views_once_per_frame_and_stops_at_the_limit :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 7, mode = .Headless)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, s.frame_count, 7)
	testing.expect_value(t, g_fake.steps, 7)
	testing.expect_value(t, g_fake.views, 8)
}

@(test)
test_headless_run_at_60_hz_steps_once_per_frame_at_the_launch_interval :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.step_hz = 60
	s: State
	fake_frame_state_init(&s, exit_after_frames = 3, mode = .Headless, launch = launch)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, g_fake.steps, 3)
	testing.expect_value(t, g_fake.step_dt, f32(1.0 / 60))
	testing.expect_value(t, headless_platform(&s).frame_duration, 1.0 / 60)
}

@(test)
test_frame_run_gives_step_the_window_in_logical_pixels :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)
	platform.window = {size = {2560, 1600}, dpi = 2}

	frame_run(&s, platform)

	testing.expect_value(t, g_fake.window, [2]f32{1280, 800})
}

@(test)
test_frame_gives_step_the_pointer_in_logical_pixels :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)
	platform.window = {size = {1920, 1080}, dpi = 2}
	move := sapp.Event{type = .MOUSE_MOVE, mouse_x = 200, mouse_y = 100}
	input_on_event(&s.input, &move)
	down := sapp.Event{type = .MOUSE_DOWN, mouse_button = .LEFT}
	input_on_event(&s.input, &down)

	frame_run(&s, platform)

	testing.expect_value(t, g_fake.pointer.pos, [2]f32{100, 50})
	testing.expect(t, g_fake.pointer.inside)
	testing.expect_value(t, g_fake.pointer.held_len, 1)
	testing.expect_value(t, g_fake.pointer.held[0], 0)
	testing.expect_value(t, g_fake.pointer.pressed_len, 1)
	testing.expect_value(t, g_fake.pointer.pressed[0], 0)
}

@(test)
test_frame_pointer_past_the_window_edge_is_not_inside :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)
	platform.window = {size = {1920, 1080}, dpi = 2}
	move := sapp.Event{type = .MOUSE_MOVE, mouse_x = 2000, mouse_y = 100}
	input_on_event(&s.input, &move)

	frame_run(&s, platform)

	testing.expect(t, !g_fake.pointer.inside)
	testing.expect_value(t, g_fake.pointer.pos, [2]f32{1000, 50})
}

@(test)
test_frame_pointer_with_the_mouse_locked_is_not_inside :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)
	platform.mouse_locked = true
	move := sapp.Event{type = .MOUSE_MOVE, mouse_x = 200, mouse_y = 100}
	input_on_event(&s.input, &move)

	frame_run(&s, platform)

	testing.expect(t, !g_fake.pointer.inside)
}

@(test)
test_headless_run_gives_step_the_launch_window :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.window.width = 1280
	launch.window.height = 800
	s: State
	fake_frame_state_init(&s, exit_after_frames = 1, mode = .Headless, launch = launch)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, g_fake.window, [2]f32{1280, 800})
}

@(test)
test_headless_run_never_calls_sokol :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 3, mode = .Headless)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, s.frame_count, 3)
	testing.expect_value(t, g_fake_platform.submits, 0)
	testing.expect_value(t, g_fake_platform.commits, 0)
	testing.expect_value(t, g_fake_platform.quits, 0)
	testing.expect(t, !sapp.isvalid())
	testing.expect(t, !sg.isvalid())
}

@(test)
test_headless_run_stops_after_a_quit :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 5, mode = .Headless)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, headless_platform(&s))
	s.quit = true
	headless_run(&s)

	testing.expect_value(t, s.frame_count, 1)
}

// Headless has no window, so a 100 by 50 Box floating at the right bottom
// shows the window it laid out against and the dpi.
@(test)
test_headless_lays_out_the_ui_against_the_launch_window_at_dpi_1 :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.window.width = 1280
	launch.window.height = 720
	launch.window.high_dpi = true
	box := ui_rect(100, 50)
	box.floating = ui_floating(.RightBottom)
	s: State
	fake_frame_state_init(&s, exit_after_frames = 1, mode = .Headless, launch = launch, ui = {ui_box_of(box)})
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	quads := s.ui.quads[:s.ui.quad_count]
	if testing.expect_value(t, len(quads), 1) {
		testing.expect_value(t, quads[0].rect, [4]f32{1180, 670, 100, 50})
	}
}

@(test)
test_headless_run_answers_queries :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	colliders := []Collider{test_box(7, {0, 0.5, 0}, IDENTITY, {0.3, 0.5, 0.3}), test_box(2, {0, -2, 0}, IDENTITY, {1, 1, 1})}
	queries := []Query{test_ray(7, 0, {0, 0.5, 0}, {0, -1, 0}, 10)}
	fake_frame_state_init(&s, exit_after_frames = 2, mode = .Headless, colliders = colliders, queries = queries)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, g_fake.rays_len, 1)
	testing.expect_value(t, g_fake.rays[0].id, 2)
	testing.expect_value(t, g_fake.rays[0].distance, 1.5)
}

@(test)
test_frame_run_records_one_span_row_per_frame_only_in_a_spans_build :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 4, mode = .Headless)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	rows := span_rows(&s.spans)
	when SPANS {
		testing.expect_value(t, len(rows), 4)
		for row, i in rows {
			testing.expect_value(t, row.frame, i + 1)
			testing.expect_value(t, row.steps, 1)
			for us, span in row.us {
				testing.expectf(t, us >= 0, "frame %v span %v is %v", row.frame, span, us)
			}
		}
	} else {
		testing.expect_value(t, len(rows), 0)
		testing.expect_value(t, size_of(Span_Sink), 0)
		testing.expect_value(t, size_of(Span_Tick), 0)
	}
}

@(test)
test_frame_run_span_row_counts_every_fixed_step_of_the_frame :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 2)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(3 * s.clock.fixed_dt))
	frame_run(&s, fake_platform(s.clock.fixed_dt / 2))

	when SPANS {
		rows := span_rows(&s.spans)
		testing.expect_value(t, len(rows), 2)
		testing.expect_value(t, rows[0].steps, 3)
		testing.expect_value(t, rows[1].steps, 0)
		testing.expect_value(t, rows[0].closes[.Step], 3)
		testing.expect_value(t, rows[1].closes[.Step], 0)
		testing.expect_value(t, rows[1].us[.Step], 0)
		testing.expect_value(t, rows[1].closes[.Commit], 1)
	} else {
		testing.expect_value(t, len(span_rows(&s.spans)), 0)
	}
}

@(test)
test_frame_run_closes_every_span_once_per_frame_and_per_step :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 3, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)

	for _ in 0 ..< 3 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
	}

	rows := span_rows(&s.spans)
	when SPANS {
		testing.expect_value(t, len(rows), 3)
		for row in rows {
			testing.expect_value(t, row.closes, [Span]int{.Input ..= .Commit = 1})
			for us, span in row.us {
				testing.expectf(t, us >= 0, "frame %v span %v is %v", row.frame, span, us)
			}
		}
	} else {
		testing.expect_value(t, len(rows), 0)
	}
}

@(test)
test_headless_rows_leave_the_render_spans_at_zero :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 3, mode = .Headless)
	defer fake_frame_state_destroy(&s)

	headless_run(&s)

	when SPANS {
		rows := span_rows(&s.spans)
		testing.expect_value(t, len(rows), 3)
		for row in rows {
			testing.expect_value(t, row.closes, #partial [Span]int{.Input ..= .Ui_Layout = 1})
			testing.expect_value(t, row.us[.Render_Submit], 0)
			testing.expect_value(t, row.us[.Commit], 0)
		}
	} else {
		testing.expect_value(t, len(span_rows(&s.spans)), 0)
	}
}

@(test)
test_render_submit_span_leaves_out_the_wait_in_begin_pass :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s, exit_after_frames = 1, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)
	s.frame_render.begin_pass = proc(ctx: rawptr, pass: Pass, view: int) {time.sleep(FAKE_PASS_WAIT)}

	frame_run(&s, fake_platform(s.clock.fixed_dt))

	when SPANS {
		rows := span_rows(&s.spans)
		testing.expect_value(t, len(rows), 1)
		testing.expect_value(t, rows[0].closes[.Render_Submit], 1)
		testing.expectf(t, rows[0].us[.Render_Submit] < time.duration_microseconds(FAKE_PASS_WAIT), "render_submit is %v us", rows[0].us[.Render_Submit])
	} else {
		testing.expect_value(t, len(span_rows(&s.spans)), 0)
	}
}
