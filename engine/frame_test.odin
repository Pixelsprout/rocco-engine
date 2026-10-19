#+test
package engine

import clay "../clay/bindings/odin/clay-odin"
import "core:sync"
import "core:testing"

FAKE_WINDOW :: Ui_Window{size = {960, 540}, dpi = 1}

Fake_Platform_Calls :: struct {
	commits: int,
	quits:   int,
}

// Guarded by the Roc heap test lock, as g_fake is.
g_fake_platform: Fake_Platform_Calls

// Holds g_clay_lock until fake_frame_state_destroy, because the render lays out the UI.
fake_frame_state_init :: proc(s: ^State, exit_after_frames := 0) {
	g_fake_platform = {}
	err := memory_init(&s.mem)
	assert(err == nil)
	clock_init(&s.clock)
	s.exit_after_frames = exit_after_frames
	fake_seam_init(&s.seam)
	mesh_table_init(&s.renderer.meshes, context.allocator)
	sky_table_init(&s.renderer.skies, context.allocator)
	frame_render_init(&s.frame_render, context.allocator)
	s.frame_render.begin_pass = proc(ctx: rawptr, pass: Pass, view: int) {}
	s.frame_render.end_pass = proc(ctx: rawptr) {}
	s.frame_render.submit_shadow = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params) {}
	s.frame_render.submit = proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params) {}
	s.frame_render.submit_lights = proc(ctx: rawptr, lights: Fs_Lights) {}
	s.frame_render.submit_sky = proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {}
	s.frame_render.submit_ui = proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {}
	sync.mutex_lock(&g_clay_lock)
	ui_err := ui_init(&s.ui, FAKE_WINDOW.size, context.allocator)
	assert(ui_err == nil)
}

fake_frame_state_destroy :: proc(s: ^State) {
	clay.SetCurrentContext(nil)
	delete(s.ui.memory)
	delete(s.ui.quads)
	sync.mutex_unlock(&g_clay_lock)
	frame_render_destroy(&s.frame_render)
	mesh_table_destroy(&s.renderer.meshes)
	sky_table_destroy(&s.renderer.skies)
	fake_seam_shutdown(&s.seam)
	memory_shutdown(&s.mem)
}

fake_platform :: proc(frame_duration: f64) -> Frame_Platform {
	return {
		frame_duration = frame_duration,
		window = FAKE_WINDOW,
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
		frame_run(&s, fake_platform(FIXED_DT))
	}

	testing.expect_value(t, g_fake.steps, 5)
	// init made the first view.
	testing.expect_value(t, g_fake.views, 6)
	testing.expect_value(t, s.steps, 5)
	testing.expect_value(t, s.frame_count, 5)
	testing.expect_value(t, g_fake_platform.commits, 5)
}

@(test)
test_frame_run_runs_every_fixed_step_the_frame_time_holds :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	s: State
	fake_frame_state_init(&s)
	defer fake_frame_state_destroy(&s)

	frame_run(&s, fake_platform(3 * FIXED_DT))

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

	frame_run(&s, fake_platform(FIXED_DT / 2))

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
		frame_run(&s, fake_platform(FIXED_DT))
	}

	testing.expect_value(t, g_fake_platform.quits, 1)
	testing.expect_value(t, s.frame_count, 2)
	testing.expect_value(t, g_fake.steps, 2)
	testing.expect_value(t, g_fake_platform.commits, 2)
}
