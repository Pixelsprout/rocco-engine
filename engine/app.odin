package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"
import slog "../sokol-odin/sokol/log"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"

import "base:runtime"

State :: struct {
	mem:               Memory,
	ctx:               runtime.Context,
	frame_count:       int,
	clock:             Clock,
	input:             Input_Latch,
	input_buffers:     Input_Buffers,
	gamepad_reader:    Gamepad_Reader,
	read_gamepads:     bool,
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
	particles:         Particles,
	exit_after_frames: int, // 0 runs forever
	mode:              Run_Mode,
	// Set by Quit in a Headless run. A windowed run asks sokol to quit instead.
	quit:              bool,
	spans:             Span_Sink,
	bridge:            Bridge,
	audio:             Audio,
	// The pointer of the last step taken, for the hit test after the layout.
	pointer:           Ui_Pointer,
	// The window of the last Frame. The inject op reads its dpi.
	window:            Ui_Window,
}

// State is global because the sokol callbacks are "c" procs with no user data.
g_state: State

app_run :: proc(calls: Game_Calls) -> (err: mem.Allocator_Error) {
	memory_init(&g_state.mem) or_return

	g_state.ctx = context
	g_state.ctx.temp_allocator = g_state.mem.frame_allocator
	context = g_state.ctx

	bridge_port := bridge_port_from_env()
	options := host_options_from_env(bridge = bridge_port > 0)
	if bridge_port > 0 {
		bridge_open_or_exit(&g_state.bridge, bridge_port, context.allocator)
	}
	roc_heap_init(context.allocator)
	// A bad Launch ends the run, so a typo cannot change the run silently.
	if field, rule, ok := host_build(&g_state, options, calls, app_run_command); !ok {
		fmt.eprintfln("Launch.%v %v, so the run ends", field, rule)
		os.exit(1)
	}

	if g_state.mode == .Headless {
		host_open_headless(&g_state, FRAME_RENDER_SUBMITS_NONE) or_return
		headless_run(&g_state)
		app_shutdown()
		return
	}

	sapp.run(app_desc(g_state.launch, g_state.mode, g_state.mem.perm_allocator))

	return
}

host_options_from_env :: proc(bridge: bool) -> Host_Options {
	exit_after_frames := exit_after_frames_from_env()
	mode := run_mode_from_env(exit_after_frames, bridge)
	return {
		mode = mode,
		exit_after_frames = exit_after_frames,
		assets_dir = assets_dir_from_env(),
		seed = seed_from_env(),
		args = args_from_env(),
		spans_csv = spans_csv_from_env(exit_after_frames),
		debug_camera = debug_camera_from_env(),
		alloc_report = alloc_report_from_env(),
		read_gamepads = !no_gamepads_from_env(),
		audio_device = mode != .Headless,
	}
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
		// The MSAA is in the render target, which the swapchain only copies.
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
app_gfx_desc :: proc(capacity: Capacity, cascades: int) -> sg.Desc {
	textures := texture_pool_size(capacity)
	return {
		logger = {func = slog.func},
		buffer_pool_size = 3 * i32(capacity.meshes) + 5 + 1,
		shader_pool_size = SHADER_ASSET_LIMIT * 9 + 32 + 1 + 3,
		pipeline_pool_size = SHADER_ASSET_LIMIT * SHADER_PIPELINE_LIMIT + 64 + 2 + 7,
		image_pool_size = textures,
		sampler_pool_size = textures,
		view_pool_size = view_pool_size(capacity),
		uniform_buffer_size = uniform_buffer_size(capacity, cascades),
	}
}

init_cb :: proc "c" () {
	context = g_state.ctx

	gfx := app_gfx_desc(g_state.launch.capacity, int(g_state.launch.shadow_cascades))
	gfx.environment = sglue.environment()
	sg.setup(gfx)

	// The linked sokol archive picks the backend, so check it matches the build.
	backend := sg.query_backend()
	fmt.assertf(backend == EXPECTED_BACKEND, "sokol backend is %v, expected %v", backend, EXPECTED_BACKEND)

	limits := sg.query_limits()
	if field, rule, ok := launch_device_check(g_state.launch, limits.max_image_size_array, limits.max_image_array_layers); !ok {
		fmt.eprintfln("Launch.%v %v, so the run ends", field, rule)
		os.exit(1)
	}

	err := host_open_window(&g_state, {f32(sapp.width()), f32(sapp.height())})
	fmt.assertf(err == nil, "the UI did not allocate: %v", err)
	fmt.assertf(g_state.ui.ctx != nil, "Clay did not initialise")
}

frame_cb :: proc "c" () {
	context = g_state.ctx

	if bridge_paused(&g_state.bridge) {
		time.sleep(BRIDGE_PAUSE_WAIT)
	}
	// The first Frame draws before any request is read, so a screenshot
	// always has a Frame to read.
	if g_state.frame_count > 0 {
		bridge_poll(&g_state, wait = false)
	}
	if g_state.bridge.quit {
		sapp.request_quit()
	}
	if g_state.read_gamepads {
		gamepads_poll(&g_state.input.gamepads, &g_state.gamepad_reader)
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
	bridge_close(&g_state.bridge)
	host_destroy(&g_state)
	roc_heap_shutdown()

	if g_state.mode != .Headless {
		if g_state.read_gamepads {
			gamepad_reader_shutdown(&g_state.gamepad_reader)
		}
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
