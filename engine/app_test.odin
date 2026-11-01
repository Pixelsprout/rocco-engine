#+test
package engine

import "core:testing"

@(test)
test_app_desc_takes_the_window_from_the_launch_in_each_run_mode :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	launch := launch_default()
	launch.window = {
		width      = 1280,
		height     = 720,
		title      = roc_str_from_slice("a title longer than twenty-three bytes"),
		fullscreen = true,
		high_dpi   = false,
		samples    = .X8,
		vsync      = true,
	}
	defer roc_decref(launch)

	for mode in ([]Run_Mode{.Real_Clock, .Lockstep, .Headless}) {
		desc := app_desc(launch, mode, context.allocator)
		defer delete(desc.window_title, context.allocator)

		testing.expect_value(t, desc.width, 1280)
		testing.expect_value(t, desc.height, 720)
		testing.expect_value(t, string(desc.window_title), "a title longer than twenty-three bytes")
		testing.expect(t, desc.fullscreen)
		testing.expect(t, !desc.high_dpi)
		testing.expect_value(t, desc.sample_count, 1)
		vsync_off := mode == .Lockstep
		testing.expectf(t, desc.disable_vsync == vsync_off, "%v: disable_vsync is %v", mode, desc.disable_vsync)
		testing.expectf(t, desc.metal.disable_display_sync == vsync_off, "%v: disable_display_sync is %v", mode, desc.metal.disable_display_sync)
	}
}

@(test)
test_app_desc_turns_vsync_off_in_lockstep_whatever_the_launch_says :: proc(t: ^testing.T) {
	Case :: struct {
		mode:     Run_Mode,
		vsync:    bool,
		want_off: bool,
	}
	cases := []Case{{.Real_Clock, true, false}, {.Real_Clock, false, true}, {.Lockstep, true, true}, {.Lockstep, false, true}}
	for c in cases {
		launch := launch_default()
		launch.window.vsync = c.vsync
		desc := app_desc(launch, c.mode, context.allocator)
		defer delete(desc.window_title, context.allocator)
		testing.expectf(t, desc.disable_vsync == c.want_off, "%v with vsync %v: disable_vsync is %v", c.mode, c.vsync, desc.disable_vsync)
		testing.expectf(t, desc.metal.disable_display_sync == c.want_off, "%v with vsync %v: disable_display_sync is %v", c.mode, c.vsync, desc.metal.disable_display_sync)
	}
}

// 470 is the image pool of the default Capacity without the render target.
// A Draw takes 3 main slots and 1 shadow slot per cascade. A skinned Draw
// adds a 4096-byte skin block in the Main pass and in each cascade.
@(test)
test_app_gfx_desc_sizes_the_pools_and_the_uniform_buffer_from_the_capacity :: proc(t: ^testing.T) {
	desc := app_gfx_desc(launch_default().capacity, 1)
	testing.expect_value(t, desc.image_pool_size, 470 + TARGET_IMAGES)
	testing.expect_value(t, desc.sampler_pool_size, 470 + TARGET_IMAGES)
	testing.expect_value(t, desc.view_pool_size, 470 + MAX_CASCADES + TARGET_VIEWS)
	testing.expect_value(t, desc.uniform_buffer_size, (4 * 16384 + 16) * 256 + 2 * SKINNED_DRAW_LIMIT * 4096)

	four := app_gfx_desc(launch_default().capacity, 4)
	testing.expect_value(t, four.uniform_buffer_size, (7 * 16384 + 16) * 256 + 5 * SKINNED_DRAW_LIMIT * 4096)

	small := app_gfx_desc({meshes = 4, skies = 2, images = 2, draws = 10, ui_quads = 1}, 4)
	testing.expect_value(t, small.image_pool_size, 3 * 4 + 1 + 2 + 2 + 2 + 1 + 1 + 1 + TARGET_IMAGES)
	testing.expect_value(t, small.uniform_buffer_size, (7 * 10 + 16) * 256 + 5 * 10 * 4096)

	largest := app_gfx_desc({meshes = 4, skies = 2, draws = DRAW_LIMIT, ui_quads = 1}, MAX_CASCADES)
	testing.expect(t, largest.uniform_buffer_size > 0)
}
