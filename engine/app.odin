package engine

import sapp "../sokol-odin/sokol/app"
import sg "../sokol-odin/sokol/gfx"
import sglue "../sokol-odin/sokol/glue"
import slog "../sokol-odin/sokol/log"
import "core:fmt"
import "core:mem"

import "base:runtime"

LIGHT_DIR :: [4]f32{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0, 0} // 4 + 9 + 36 = 49, so |L| = 1 exactly
SCENE_NEAR :: f32(0.1)
UP :: [3]f32{0, 1, 0}

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
	script:            Script,
	exit_after_frames: int, // 0 runs forever
}

// State is global because the sokol callbacks are "c" procs with no user data.
g_state: State

app_run :: proc() -> (err: mem.Allocator_Error) {
	memory_init(&g_state.mem) or_return

	g_state.ctx = context
	// Map the frame allocator to the temp allocator
	g_state.ctx.temp_allocator = g_state.mem.frame_allocator

	g_state.exit_after_frames = exit_after_frames_from_env()
	g_state.use_debug_camera = debug_camera_from_env()

	clock_init(&g_state.clock)
	camera_init(&g_state.debug_camera)

	context = g_state.ctx
	script_init(&g_state.script, seed_from_env())

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
}

frame_cb :: proc "c" () {
	context = g_state.ctx

	clock_add_frame(&g_state.clock, sapp.frame_duration())
	for dt in clock_next_step(&g_state.clock) {
		script_step(&g_state.script, input_take(&g_state.input, &g_state.keys), dt)
	}

	sg.begin_pass({action = g_state.pass_action, swapchain = sglue.swapchain()})

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
		view_proj = scene_view_proj(g_state.script.scene.camera, aspect)
	}

	draw_scene(&g_state.renderer, g_state.script.scene, view_proj)

	sg.end_pass()
	sg.commit()
	g_state.frame_count += 1

	if g_state.exit_after_frames > 0 && g_state.frame_count >= g_state.exit_after_frames {
		sapp.request_quit()
	}

	frame_end(&g_state.mem)
	input_end_frame(&g_state.input)
}

scene_view_proj :: proc(camera: Scene_Camera, aspect: f32) -> Mat4 {
	eye := [3]f32{camera.eye.x, camera.eye.y, camera.eye.z}
	target := [3]f32{camera.target.x, camera.target.y, camera.target.z}
	return mat4_perspective_reversed_infinite(camera.fov_y, aspect, SCENE_NEAR) * mat4_look_at(eye, target, UP)
}

// Every mesh id draws as the cube until the mesh table exists.
draw_scene :: proc(r: ^Renderer, scene: Scene, view_proj: Mat4) {
	for d in scene.draws.elements[:scene.draws.length] {
		model := transform_to_mat4(
			{
				position = {d.pos.x, d.pos.y, d.pos.z},
				rotation = quat_from_axis_angle(UP, d.yaw),
				scale = {d.scale.x, d.scale.y, d.scale.z},
			},
		)
		renderer_draw(
			r,
			vs_params = {mvp = view_proj * model, model = model},
			fs_params = {
				light_dir = LIGHT_DIR,
				light_color = [4]f32{1, 1, 1, 1},
				ambient = [4]f32{0.1, 0.1, 0.1, 1},
				tint = [4]f32{d.tint.x, d.tint.y, d.tint.z, 1},
			},
		)
	}
}

cleanup_cb :: proc "c" () {
	context = g_state.ctx

	renderer_shutdown(&g_state.renderer)
	script_shutdown(&g_state.script)

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
