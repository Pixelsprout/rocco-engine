package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"
import slog "../sokol-odin/sokol/log"
import "core:fmt"
import "core:mem"
import "core:time"

import "base:runtime"

State :: struct {
	mem:               Memory,
	ctx:               runtime.Context,
	pass_action:       sg.Pass_Action,
	frame_count:       int,
	clock:             Clock,
	input:             Input_Latch,
	keys:              Key_Buffers,
	renderer:          Renderer,
	debug_camera:      Debug_Camera,
	use_debug_camera:  bool,
	seam:              Seam,
	alloc_report:      bool,
	steps:             u64,
	frame_render:      Frame_Render,
	exit_after_frames: int, // 0 runs forever
}

// State is global because the sokol callbacks are "c" procs with no user data.
g_state: State

app_run :: proc() -> (err: mem.Allocator_Error) {
	memory_init(&g_state.mem) or_return

	g_state.ctx = context
	g_state.ctx.temp_allocator = g_state.mem.frame_allocator

	g_state.exit_after_frames = exit_after_frames_from_env()
	g_state.use_debug_camera = debug_camera_from_env()
	g_state.alloc_report = alloc_report_from_env()

	clock_init(&g_state.clock)
	camera_init(&g_state.debug_camera)

	context = g_state.ctx
	// Name and load the meshes before sokol starts, so the manifest does not wait on the GPU.
	mesh_table_init(&g_state.renderer.meshes, g_state.mem.perm_allocator)
	mesh_table_load_dir(&g_state.renderer.meshes, mesh_dir_from_env(), g_state.mem.level_allocator)
	frame_render_init(&g_state.frame_render, g_state.mem.perm_allocator)
	roc_heap_init(context.allocator)
	seam_init(&g_state.seam, ROC_GAME, config_make(seed_from_env(), &g_state.renderer.meshes))

	sapp.run(
		sapp.Desc {
			init_cb = init_cb,
			frame_cb = frame_cb,
			cleanup_cb = cleanup_cb,
			width = 960,
			height = 540,
			window_title = "rocco",
			logger = {func = slog.func},
			event_cb = event_cb,
		},
	)

	return
}

init_cb :: proc "c" () {
	context = g_state.ctx

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})

	// The linked sokol archive picks the backend, so check it matches the build.
	backend := sg.query_backend()
	fmt.assertf(backend == EXPECTED_BACKEND, "sokol backend is %v, expected %v", backend, EXPECTED_BACKEND)

	g_state.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.0, g = 0.0, b = 0.1, a = 1.0}}},
		depth = {load_action = .CLEAR, clear_value = 0.0},
	}

	renderer_init(&g_state.renderer)
	g_state.frame_render.submit = renderer_draw
	g_state.frame_render.submit_ctx = &g_state.renderer
}

frame_cb :: proc "c" () {
	context = g_state.ctx

	clock_add_frame(&g_state.clock, sapp.frame_duration())
	for dt in clock_next_step(&g_state.clock) {
		before := roc_heap_counters()
		step_time, view_time := seam_step(&g_state.seam, input_take(&g_state.input, &g_state.keys), dt)
		g_state.steps += 1
		if g_state.alloc_report {
			roc_heap_report_line(g_state.steps, before, time.duration_microseconds(step_time), time.duration_microseconds(view_time))
		}
	}

	sg.begin_pass({action = g_state.pass_action, swapchain = sglue.swapchain()})

	alpha := clock_alpha(&g_state.clock)
	prev, curr := seam_scenes(&g_state.seam)
	aspect := f32(sapp.width()) / f32(sapp.height())
	view_proj: Mat4
	if g_state.use_debug_camera {
		camera_look(&g_state.debug_camera, &g_state.input)
		camera_fly(&g_state.debug_camera, &g_state.input, f32(min(sapp.frame_duration(), MAX_FRAME_TIME)))
		view_proj = camera_proj(&g_state.debug_camera, aspect) * camera_view(&g_state.debug_camera)
		if !sapp.mouse_locked() {
			sapp.lock_mouse(true)
		}
	} else {
		view_proj = frame_render_camera(prev, curr, alpha, aspect)
	}

	frame_render_draw(&g_state.frame_render, prev, curr, alpha, view_proj, &g_state.renderer.meshes)

	sg.end_pass()
	sg.commit()
	g_state.frame_count += 1

	if g_state.exit_after_frames > 0 && g_state.frame_count >= g_state.exit_after_frames {
		sapp.request_quit()
	}

	frame_end(&g_state.mem)
	input_end_frame(&g_state.input)
}

cleanup_cb :: proc "c" () {
	context = g_state.ctx

	renderer_shutdown(&g_state.renderer)
	seam_shutdown(&g_state.seam)
	roc_heap_shutdown()
	frame_render_destroy(&g_state.frame_render)

	sg.shutdown()
	memory_shutdown(&g_state.mem)

	fmt.printfln("Frame Count: %v", g_state.frame_count)

	// Here we can check for any memory leaks or bad free calls
	when ODIN_DEBUG {
		for _, entry in g_track.allocation_map {
			fmt.eprintfln("LEAK %v bytes at %v", entry.size, entry.location)
		}
		for bad in g_track.bad_free_array {
			fmt.eprintfln("BAD Free at %v", bad.location)
		}
		mem.tracking_allocator_destroy(&g_track)
	}
}

// ESC quits until quit becomes a command. The game still sees the key.
event_cb :: proc "c" (event: ^sapp.Event) {
	context = g_state.ctx

	if event.type == .KEY_DOWN && event.key_code == .ESCAPE {
		sapp.request_quit()
	}
	input_on_event(&g_state.input, event)
}
