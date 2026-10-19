package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"
import slog "../sokol-odin/sokol/log"
import "core:fmt"
import "core:mem"

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
	packs:             Packs,
	alloc_report:      bool,
	steps:             u64,
	frame_render:      Frame_Render,
	ui:                Ui,
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
	// init runs before sokol starts. renderer_init uploads the assets its Loads added.
	mesh_table_init(&g_state.renderer.meshes, context.allocator)
	sky_table_init(&g_state.renderer.skies, context.allocator)
	packs_init(&g_state.packs, &g_state.renderer.meshes, &g_state.renderer.skies, assets_dir_from_env(), context.allocator)
	frame_render_init(&g_state.frame_render, g_state.mem.perm_allocator)
	roc_heap_init(context.allocator)
	config := config_make(seed_from_env(), g_state.packs.on_disk, args_from_env())
	seam_init(&g_state.seam, ROC_GAME, app_run_command, config, &g_state.packs)

	sapp.run(
		sapp.Desc {
			init_cb = init_cb,
			frame_cb = frame_cb,
			cleanup_cb = cleanup_cb,
			width = 960,
			height = 540,
			sample_count = SAMPLE_COUNT,
			window_title = "rocco",
			logger = {func = slog.func},
			event_cb = event_cb,
		},
	)

	return
}

init_cb :: proc "c" () {
	context = g_state.ctx

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}, image_pool_size = TEXTURE_POOL_SIZE, sampler_pool_size = TEXTURE_POOL_SIZE})

	// The linked sokol archive picks the backend, so check it matches the build.
	backend := sg.query_backend()
	fmt.assertf(backend == EXPECTED_BACKEND, "sokol backend is %v, expected %v", backend, EXPECTED_BACKEND)

	renderer_init(&g_state.renderer)
	ui_err := ui_init(&g_state.ui, {f32(sapp.width()), f32(sapp.height())}, g_state.mem.perm_allocator)
	fmt.assertf(ui_err == nil, "the Clay arena did not allocate: %v", ui_err)
	fmt.assertf(g_state.ui.ctx != nil, "Clay did not initialise")
	ui_gpu_err := ui_gpu_init(&g_state.renderer.ui, UI_QUAD_CAPACITY, g_state.mem.perm_allocator)
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

	renderer_shutdown(&g_state.renderer)
	seam_shutdown(&g_state.seam)
	packs_destroy(&g_state.packs)
	roc_heap_shutdown()
	frame_render_destroy(&g_state.frame_render)

	sg.shutdown()
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
}

event_cb :: proc "c" (event: ^sapp.Event) {
	context = g_state.ctx

	input_on_event(&g_state.input, event)
}

// Quit lets the current frame finish.
app_run_command :: proc(command: Command) {
	if command.tag == .Quit {
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
