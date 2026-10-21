package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"
import slog "../sokol-odin/sokol/log"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

import "base:runtime"

State :: struct {
	mem:               Memory,
	ctx:               runtime.Context,
	frame_count:       int,
	clock:             Clock,
	input:             Input_Latch,
	keys:              Key_Buffers,
	renderer:          Renderer,
	debug_camera:      Debug_Camera,
	use_debug_camera:  bool,
	seam:              Seam,
	// The game's Launch. The host owns it from before init until shutdown.
	launch:            Launch,
	packs:             Packs,
	alloc_report:      bool,
	steps:             u64,
	frame_render:      Frame_Render,
	ui:                Ui,
	exit_after_frames: int, // 0 runs forever
	mode:              Run_Mode,
	// Set by Quit in a Headless run. A windowed run asks sokol to quit instead.
	quit:              bool,
	spans:             Span_Sink,
	bridge:            Bridge,
}

// State is global because the sokol callbacks are "c" procs with no user data.
g_state: State

app_run :: proc(calls: Game_Calls) -> (err: mem.Allocator_Error) {
	memory_init(&g_state.mem) or_return

	g_state.ctx = context
	g_state.ctx.temp_allocator = g_state.mem.frame_allocator

	g_state.exit_after_frames = exit_after_frames_from_env()
	bridge_port := bridge_port_from_env()
	g_state.mode = run_mode_from_env(g_state.exit_after_frames, bridge_port > 0)
	if bridge_port > 0 {
		bridge_open_or_exit(&g_state.bridge, bridge_port, context.allocator)
	}
	span_sink_init(&g_state.spans, spans_csv_from_env(g_state.exit_after_frames), g_state.exit_after_frames, context.allocator)
	g_state.use_debug_camera = debug_camera_from_env()
	g_state.alloc_report = alloc_report_from_env()

	camera_init(&g_state.debug_camera)

	context = g_state.ctx
	perm := g_state.mem.perm_allocator
	packs_init(&g_state.packs, assets_dir_from_env(), context.allocator)
	roc_heap_init(context.allocator)
	g_state.launch = seam_launch(&g_state.seam, calls, app_config())
	launch_check_or_exit(g_state.launch)
	capacity := g_state.launch.capacity
	// init runs before sokol starts. renderer_init uploads the assets its Loads added.
	mesh_table_init(&g_state.renderer.meshes, int(capacity.meshes), perm, context.allocator)
	sky_table_init(&g_state.renderer.skies, int(capacity.skies), perm, context.allocator)
	packs_attach(&g_state.packs, &g_state.renderer.meshes, &g_state.renderer.skies, perm)
	frame_render_init(&g_state.frame_render, int(capacity.draws), perm)
	clock_init(&g_state.clock, g_state.launch.step_hz)
	seam_init(&g_state.seam, app_run_command, app_config(), &g_state.packs)

	if g_state.mode == .Headless {
		headless_init(&g_state, g_state.mem.perm_allocator) or_return
		headless_run(&g_state)
		app_shutdown()
		return
	}

	sapp.run(app_desc(g_state.launch, g_state.mode, g_state.mem.perm_allocator))

	return
}

// launch and init get an equal Config. Each call consumes its own.
app_config :: proc() -> Config {
	return config_make(seed_from_env(), g_state.packs.on_disk, args_from_env())
}

// The window the Launch asks for. Lockstep turns vsync off whatever the
// Launch says, so frame pacing does not wait inside the render Spans. sokol
// turns a swap_interval of 0 into 1, so it needs the flags. On Metal,
// CADisplayLink still calls frame_cb once per display refresh. The title is
// a fresh cstring from allocator; sokol copies it when the run starts.
app_desc :: proc(launch: Launch, mode: Run_Mode, allocator: mem.Allocator) -> sapp.Desc {
	window := launch.window
	vsync_off := mode == .Lockstep || !window.vsync
	return {
		init_cb = init_cb,
		frame_cb = frame_cb,
		cleanup_cb = cleanup_cb,
		width = i32(window.width),
		height = i32(window.height),
		// The MSAA is in the offscreen target, which the swapchain only copies.
		sample_count = 1,
		high_dpi = window.high_dpi,
		fullscreen = window.fullscreen,
		window_title = strings.clone_to_cstring(roc_str_string(&window.title), allocator),
		logger = {func = slog.func},
		event_cb = event_cb,
		disable_vsync = vsync_off,
		metal = {disable_display_sync = vsync_off},
	}
}

// The sokol sizes the capacities need. The caller sets the environment,
// because only a running sokol app has one.
app_gfx_desc :: proc(capacity: Capacity) -> sg.Desc {
	textures := texture_pool_size(capacity)
	return {
		logger = {func = slog.func},
		image_pool_size = textures,
		sampler_pool_size = textures,
		view_pool_size = view_pool_size(capacity),
		uniform_buffer_size = uniform_buffer_size(capacity),
	}
}

init_cb :: proc "c" () {
	context = g_state.ctx

	gfx := app_gfx_desc(g_state.launch.capacity)
	gfx.environment = sglue.environment()
	sg.setup(gfx)

	// The linked sokol archive picks the backend, so check it matches the build.
	backend := sg.query_backend()
	fmt.assertf(backend == EXPECTED_BACKEND, "sokol backend is %v, expected %v", backend, EXPECTED_BACKEND)

	renderer_init(&g_state.renderer, g_state.launch)
	ui_quads := int(g_state.launch.capacity.ui_quads)
	ui_err := ui_init(&g_state.ui, {f32(sapp.width()), f32(sapp.height())}, ui_quads, g_state.mem.perm_allocator)
	fmt.assertf(ui_err == nil, "the Clay arena did not allocate: %v", ui_err)
	fmt.assertf(g_state.ui.ctx != nil, "Clay did not initialise")
	ui_gpu_err := ui_gpu_init(&g_state.renderer.ui, ui_quads, msaa_sample_count(g_state.launch.window.samples), g_state.mem.perm_allocator)
	fmt.assertf(ui_gpu_err == nil, "the UI vertices did not allocate: %v", ui_gpu_err)
	g_state.frame_render.begin_pass = renderer_begin_pass
	g_state.frame_render.end_pass = renderer_end_pass
	g_state.frame_render.submit_shadow = renderer_shadow
	g_state.frame_render.submit = renderer_draw
	g_state.frame_render.submit_lights = renderer_lights
	g_state.frame_render.submit_sky = renderer_sky
	g_state.frame_render.submit_ui = renderer_ui
	g_state.frame_render.submit_ctx = &g_state.renderer
}

frame_cb :: proc "c" () {
	context = g_state.ctx

	// The first Frame draws before any request is read, so a screenshot
	// always has a Frame to read.
	if g_state.frame_count > 0 {
		bridge_poll(&g_state, wait = false)
	}
	if g_state.bridge.quit {
		sapp.request_quit()
	}
	frame_run(
		&g_state,
		{
			frame_duration = sapp.frame_duration(),
			window = {size = {f32(sapp.width()), f32(sapp.height())}, dpi = sapp.dpi_scale()},
			mouse_locked = sapp.mouse_locked(),
			lock_mouse = app_lock_mouse,
			commit = app_commit,
			request_quit = app_request_quit,
		},
	)
}

cleanup_cb :: proc "c" () {
	context = g_state.ctx

	app_shutdown()
}

// A Headless run never set up sokol, so it must not shut it down. A bench run
// with no Spans CSV must fail, so a failed write exits with 1 at the end.
app_shutdown :: proc() {
	spans_err := span_sink_write(&g_state.spans)
	if spans_err != nil {
		fmt.eprintfln("the Spans CSV did not write: %v", spans_err)
	}
	span_sink_destroy(&g_state.spans)
	bridge_close(&g_state.bridge)

	renderer_shutdown(&g_state.renderer)
	seam_shutdown(&g_state.seam)
	roc_decref(g_state.launch)
	packs_destroy(&g_state.packs)
	roc_heap_shutdown()
	frame_render_destroy(&g_state.frame_render)

	if g_state.mode != .Headless {
		sg.shutdown()
	}
	memory_shutdown(&g_state.mem)

	fmt.printfln("Frame Count: %v", g_state.frame_count)

	when TRACK_ALLOC {
		for _, entry in g_track.allocation_map {
			fmt.eprintfln("LEAK %v bytes at %v", entry.size, entry.location)
		}
		for bad in g_track.bad_free_array {
			fmt.eprintfln("BAD Free at %v", bad.location)
		}
		mem.tracking_allocator_destroy(&g_track)
	}
	if spans_err != nil {
		os.exit(1)
	}
}

event_cb :: proc "c" (event: ^sapp.Event) {
	context = g_state.ctx

	input_on_event(&g_state.input, event)
}

// Quit lets the current frame finish.
app_run_command :: proc(command: Command) {
	if command.tag != .Quit {
		return
	}
	if g_state.mode == .Headless {
		g_state.quit = true
	} else {
		sapp.request_quit()
	}
}

app_lock_mouse :: proc(locked: bool) {
	sapp.lock_mouse(locked)
}

app_commit :: proc() {
	sg.commit()
}

app_request_quit :: proc() {
	sapp.request_quit()
}
