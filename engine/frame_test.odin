#+test
package engine

import clay "../clay/bindings/odin/clay-odin"
import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:os"
import "core:slice"
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

// The host owns launch. Holds g_clay_lock until fake_host_destroy, because
// the render lays out the UI.
fake_host_init :: proc(s: ^State, exit_after_frames := 0, mode := Run_Mode.Real_Clock, colliders: []Collider = nil, queries: []Query = nil, launch: Maybe(Launch) = nil, ui: []Element = nil, assets_dir := NO_ASSETS_DIR, init_commands: []Command = nil, submits: Maybe(Frame_Render_Submits) = nil) {
	g_fake_platform = {}
	g_fake = {colliders = colliders, queries = queries, init_commands = init_commands, ui = ui, launch_in = launch}
	err := memory_init(&s.mem)
	assert(err == nil)
	field, rule, ok := host_build(s, {mode = mode, exit_after_frames = exit_after_frames, assets_dir = assets_dir}, FAKE_GAME, fake_run_command)
	fmt.assertf(ok, "Launch.%v %v", field, rule)
	sync.mutex_lock(&g_clay_lock)
	ui_err := host_open_headless(s, submits.? or_else fake_submits())
	assert(ui_err == nil)
}

fake_host_destroy :: proc(s: ^State) {
	host_destroy(s)
	sync.mutex_unlock(&g_clay_lock)
	memory_shutdown(&s.mem)
}

// Submits nothing and counts the submit_lights calls in g_fake_platform.
fake_submits :: proc() -> Frame_Render_Submits {
	submits := FRAME_RENDER_SUBMITS_NONE
	submits.submit_lights = proc(ctx: rawptr, lights: Fs_Lights) {g_fake_platform.submits += 1}
	return submits
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
	fake_host_init(&s)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, launch = launch)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 2)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, mode = .Lockstep)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, mode = .Lockstep, launch = launch)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 7, mode = .Headless)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 3, mode = .Headless, launch = launch)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s)
	defer fake_host_destroy(&s)
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
	fake_host_init(&s)
	defer fake_host_destroy(&s)
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
	fake_host_init(&s)
	defer fake_host_destroy(&s)
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
	fake_host_init(&s)
	defer fake_host_destroy(&s)
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
	fake_host_init(&s, exit_after_frames = 1, mode = .Headless, launch = launch)
	defer fake_host_destroy(&s)

	headless_run(&s)

	testing.expect_value(t, g_fake.window, [2]f32{1280, 800})
}

@(test)
test_headless_run_never_calls_sokol :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init(&s, exit_after_frames = 3, mode = .Headless)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 5, mode = .Headless)
	defer fake_host_destroy(&s)

	frame_run(&s, headless_platform(&s))
	s.quit = true
	headless_run(&s)

	testing.expect_value(t, s.frame_count, 1)
}

// Headless has no window, so a 100 by 50 Panel floating at the right bottom
// shows the window it laid out against and the dpi.
@(test)
test_headless_lays_out_the_ui_against_the_launch_window_at_dpi_1 :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.window.width = 1280
	launch.window.height = 720
	launch.window.high_dpi = true
	config := ui_rect(100, 50)
	config.floating = ui_floating(.RightBottom)
	s: State
	fake_host_init(&s, exit_after_frames = 1, mode = .Headless, launch = launch, ui = {ui_panel_of(config)})
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 2, mode = .Headless, colliders = colliders, queries = queries)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 4, mode = .Headless)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 2)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 3, mode = .Lockstep)
	defer fake_host_destroy(&s)

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
	fake_host_init(&s, exit_after_frames = 3, mode = .Headless)
	defer fake_host_destroy(&s)

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
	slow := fake_submits()
	slow.begin_pass = proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb) {time.sleep(FAKE_PASS_WAIT)}
	fake_host_init(&s, exit_after_frames = 1, mode = .Lockstep, submits = slow)
	defer fake_host_destroy(&s)

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

// A tagged Panel at the top left, 100 by 100, with the pointer at (50, 50).
fake_host_init_pointing :: proc(s: ^State, mode := Run_Mode.Real_Clock) {
	// g_fake keeps the roots past this call.
	roots := slice.clone([]Element{ui_panel_of(ui_tagged(7, 100, 100))}, context.temp_allocator)
	fake_host_init(s, mode = mode, ui = roots)
	move := sapp.Event{type = .MOUSE_MOVE, mouse_x = 50, mouse_y = 50}
	input_on_event(&s.input, &move)
}

@(test)
test_frame_gives_the_next_step_the_panels_under_the_pointer :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init_pointing(&s)
	defer fake_host_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)

	frame_run(&s, platform)
	testing.expect_value(t, g_fake.over_len, 0)

	frame_run(&s, platform)
	if testing.expect_value(t, g_fake.over_len, 1) {
		testing.expect_value(t, g_fake.over[0], 7)
	}
}

@(test)
test_frame_gives_every_step_of_a_frame_the_same_ui :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init_pointing(&s)
	defer fake_host_destroy(&s)

	frame_run(&s, fake_platform(s.clock.fixed_dt))
	frame_run(&s, fake_platform(3 * s.clock.fixed_dt))

	testing.expect_value(t, g_fake.steps, 4)
	testing.expectf(t, slice.equal(g_fake.step_over_lens[1:4], []int{1, 1, 1}), "over lengths %v", g_fake.step_over_lens[:4])
	testing.expect_value(t, g_fake.over[0], 7)
}

@(test)
test_frame_lists_the_scroll_sizes_in_headless :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init(&s, exit_after_frames = 2, mode = .Headless, ui = {ui_scroll_rows(9, 200, 100, 10)})
	defer fake_host_destroy(&s)

	headless_run(&s)

	if testing.expect_value(t, g_fake.scroll_len, 1) {
		testing.expect_value(t, g_fake.scroll[0], Scroll_Size{id = 9, view = {width = 200, height = 100}, content = {width = 200, height = 200}})
	}
}

@(test)
test_frame_with_the_mouse_locked_gives_an_empty_over :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init_pointing(&s)
	defer fake_host_destroy(&s)
	platform := fake_platform(s.clock.fixed_dt)
	platform.mouse_locked = true

	frame_run(&s, platform)
	frame_run(&s, platform)

	testing.expect_value(t, g_fake.over_len, 0)
}

@(test)
test_frame_ui_lists_leak_nothing :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_host_init(&s, ui = {ui_panel_of(ui_scroll(ui_tagged(7, 100, 100), {0, 0}), ui_panel_of(ui_rect(100, 200)))})
	defer fake_host_destroy(&s)
	move := sapp.Event{type = .MOUSE_MOVE, mouse_x = 50, mouse_y = 50}
	input_on_event(&s.input, &move)
	platform := fake_platform(s.clock.fixed_dt)

	for _ in 0 ..< 5 {
		frame_run(&s, platform)
	}

	testing.expect_value(t, g_fake.over_len, 1)
	testing.expect_value(t, g_fake.scroll_len, 1)
}

@(test)
test_frame_draws_the_mesh_that_init_loaded :: proc(t: ^testing.T) {
	dir := fake_assets_dir(t)
	defer os.remove_all(dir)
	roc_heap_test_begin()
	defer roc_heap_test_end()
	rec: Recorder
	defer recorder_destroy(&rec)
	s: State
	fake_host_init(&s, mode = .Lockstep, assets_dir = dir, init_commands = {fake_load("A", "a")}, submits = recorder_submits(&rec))
	defer fake_host_destroy(&s)
	g_fake.camera = {eye = {0, 0, 5}, up = {y = 1}, fov_y = 1}
	g_fake.draws = []Draw{{id = 1, mesh = g_fake.loaded_manifest[0].id}}

	frame_run(&s, fake_platform(s.clock.fixed_dt))
	clear(&rec.submits)
	frame_run(&s, fake_platform(s.clock.fixed_dt))

	testing.expect_value(t, len(rec.submits), 1)
	testing.expect_value(t, rec.submits[0].mesh.name, "a")
}
