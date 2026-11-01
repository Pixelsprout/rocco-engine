package engine

import "core:mem"

// What a run reads from its environment before the build. Tests pass a literal.
Host_Options :: struct {
	mode:              Run_Mode,
	exit_after_frames: int, // 0 runs forever
	assets_dir:        string,
	seed:              u64,
	args:              []string,
	spans_csv:         string,
	debug_camera:      bool,
	alloc_report:      bool,
	read_gamepads:     bool,
	audio_device:      bool,
}

// Builds the host before the window opens: launch, the tables, then init,
// whose Loads wait in the tables for the upload. The caller owns s.mem, the
// Roc heap and the context, which launch and init already run under. A bad
// Launch names its field and rule, and leaves nothing to destroy.
host_build :: proc(s: ^State, options: Host_Options, calls: Game_Calls, run_command: Command_Runner) -> (field, rule: string, ok: bool) {
	s.mode = options.mode
	s.exit_after_frames = options.exit_after_frames
	s.use_debug_camera = options.debug_camera
	s.alloc_report = options.alloc_report
	s.read_gamepads = options.read_gamepads
	packs_init(&s.packs, options.assets_dir, context.allocator)
	s.launch = seam_launch(&s.seam, calls, host_config(s, options))
	field, rule, ok = launch_check(s.launch)
	if !ok {
		roc_decref(s.launch)
		packs_destroy(&s.packs)
		return
	}

	perm := s.mem.perm_allocator
	capacity := s.launch.capacity
	span_sink_init(&s.spans, options.spans_csv, options.exit_after_frames, context.allocator)
	audio_init(&s.audio, device = options.audio_device)
	camera_init(&s.debug_camera)
	asset_tables_init(&s.packs, &s.renderer.meshes, &s.renderer.skies, &s.renderer.images, &s.audio, capacity, perm, context.allocator)
	frame_render_init(&s.frame_render, int(capacity.draws), int(capacity.groups), s.launch.shadow_map, int(s.launch.shadow_cascades), perm)
	clock_init(&s.clock, s.launch.step_hz)
	seam_init(&s.seam, run_command, host_config(s, options), &s.packs, &s.audio)
	return
}

// Runs once sokol has set up gfx. renderer_init uploads what init loaded.
host_open_window :: proc(s: ^State, size: [2]f32) -> mem.Allocator_Error {
	renderer_init(&s.renderer, s.launch)
	perm := s.mem.perm_allocator
	ui_quads := int(s.launch.capacity.ui_quads)
	ui_init(&s.ui, size, ui_quads, perm) or_return
	ui_gpu_init(&s.renderer.ui, ui_quads, msaa_sample_count(s.launch.window.samples), perm) or_return
	s.frame_render.port = renderer_port(&s.renderer)
	if s.read_gamepads {
		gamepad_reader_init(&s.gamepad_reader)
	}
	return nil
}

// Lays out the UI with no window. A Headless run passes FRAME_RENDER_PORT_NONE.
host_open_headless :: proc(s: ^State, port: Frame_Render_Port) -> mem.Allocator_Error {
	s.window = headless_window(s.launch)
	s.frame_render.port = port
	return ui_init(&s.ui, s.window.size, int(s.launch.capacity.ui_quads), s.mem.perm_allocator)
}

// The Seam drops the Model and its Scenes before the tables that their ids name.
host_destroy :: proc(s: ^State) {
	seam_shutdown(&s.seam)
	roc_decref(s.launch)
	packs_destroy(&s.packs)
	asset_tables_destroy(&s.renderer.meshes, &s.renderer.skies, &s.renderer.images)
	audio_shutdown(&s.audio)
	frame_render_destroy(&s.frame_render)
	ui_destroy(&s.ui)
	span_sink_destroy(&s.spans)
}

// Runs after launch, because the capacities come from the Launch. audio
// must have run audio_init.
asset_tables_init :: proc(packs: ^Packs, meshes: ^Mesh_Table, skies: ^Sky_Table, images: ^Image_Table, audio: ^Audio, capacity: Capacity, perm, allocator: mem.Allocator) {
	mesh_table_init(meshes, int(capacity.meshes), perm, allocator)
	sky_table_init(skies, int(capacity.skies), perm, allocator)
	image_table_init(images, int(capacity.images), perm, allocator)
	audio_tables_init(audio, int(capacity.sounds), int(capacity.voices), perm, allocator)
	packs_attach(packs, meshes, skies, images, audio, perm)
}

// sg.shutdown frees the GPU resources. audio_shutdown frees the Sounds.
asset_tables_destroy :: proc(meshes: ^Mesh_Table, skies: ^Sky_Table, images: ^Image_Table) {
	mesh_table_destroy(meshes)
	sky_table_destroy(skies)
	image_table_destroy(images)
}

// launch and init get an equal Config. Each call consumes its own.
@(private = "file")
host_config :: proc(s: ^State, options: Host_Options) -> Config {
	return config_make(options.seed, s.packs.on_disk, options.args)
}
