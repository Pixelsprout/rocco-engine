package engine

import sapp "../sokol/app"
import sg "../sokol/gfx"
import sglue "../sokol/glue"
import slog "../sokol/log"
import "core:fmt"
import "core:math"
import "core:mem"

import "base:runtime"

ROTATION_DURATION := 5.0
ANGULAR_SPEED := 2.0 * math.PI / ROTATION_DURATION
SPIN_AXIS :: [3]f32{1, 1, 1}
SWING_AXIS :: [3]f32{1, 2, 3}
SWING_ARC :: f32(170)
SWING_PERIOD :: f32(4)
KEY_A: quaternion128 : 1

CUBE_COUNT :: 3
SCENE :: [3]Transform {
	{position = {0,  2.2, -2.5}, rotation = 1, scale = {1, 1, 1}}, // spins
	{position = {0,  0.8, -2.5}, rotation = 1, scale = {1, 1, 1}}, // raw
	{position = {0, -0.6, -2.5}, rotation = 1, scale = {1, 1, 1}}, // interpolated
}
LIGHT_DIR :: [4]f32{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0, 0} // 4 + 9 + 36 = 49, so |L| = 1 exactly


State :: struct {
	mem:              Memory,
	ctx:              runtime.Context,
	pass_action:      sg.Pass_Action,
	frame_count:      int,
	clock:            Clock,
	input:            Input,
	renderer:         Renderer,
	camera:           Camera,
	toggled_pipeline: bool,
	scene:            [3]Transform,
	script:			  Script,
}



// State is global as we cannot captrue anthing due to the "C" callback
g_state: State
next_report: f64 // keeps track of the next time to report
triangle_rotation: f64 // the radians to rotate the triangle

app_run :: proc() -> (err: mem.Allocator_Error) {
	memory_init(&g_state.mem) or_return

	g_state.ctx = context

	g_state.scene = SCENE

	clock_init(&g_state.clock) // setup the clock
	script_init(&g_state.script, CUBE_COUNT)
	camera_init(&g_state.camera)

	// Map the frame allocator to the temp allocator
	g_state.ctx.temp_allocator = g_state.mem.frame_allocator

	sapp.run(
		sapp.Desc {
			init_cb = init_cb,
			frame_cb = frame_cb,
			cleanup_cb = cleanup_cb,
			width = 960,
			height = 540,
			window_title = "Odin Game Engine",
			logger = {func = slog.func},
			event_cb = event_cb,
		},
	)

	return
}

init_cb :: proc "c" () {
	context = g_state.ctx

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})

	g_state.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.0, g = 0.0, b = 0.1, a = 1.0}}},
		depth = {load_action = .CLEAR, clear_value = 0.0},
	}

	// setup renderer
	renderer_init(&g_state.renderer)
}

frame_cb :: proc "c" () {
	context = g_state.ctx

	// ======================================================
	// Clock Advance
	// ======================================================
	if g_state.clock.real_time >= next_report {
		// fmt.printfln("real_time: %v, game_time: %v, steps_taken: %v", g_state.clock.real_time, g_state.clock.game_time, g_state.clock.steps_taken)
		next_report += 1.0
	}

	// Manage game clock
	clock_add_frame(&g_state.clock, sapp.frame_duration())
	steps := 0
	for dt in clock_next_step(&g_state.clock) {
		script_step(&g_state.script, dt)
		steps += 1
	}

	alpha := clock_alpha(&g_state.clock)

	// ======================================================
	// Render Pass
	// ======================================================
	sg.begin_pass({action = g_state.pass_action, swapchain = sglue.swapchain()})

	// with the game clock we want to pass our model matrix to the shader
	mvp := mat4_identity()

	// animate the model matrix with the clock
	spin := f32(ANGULAR_SPEED * clock_render_time(&g_state.clock))
	g_state.scene[0].rotation = quat_from_axis_angle(SPIN_AXIS, spin)

	g_state.scene[0].position.x = script_render_x(&g_state.script, 0, alpha)
	g_state.scene[1].position.x = script_body(&g_state.script, 1).x
	g_state.scene[2].position.x = script_render_x(&g_state.script, 2, alpha)

	// Move the camera and orient it
	camera_look(&g_state.camera, &g_state.input)
	camera_fly(&g_state.camera, &g_state.input, f32(min(sapp.frame_duration(), MAX_FRAME_TIME)))

	// Camera setup
	aspect := f32(sapp.width()) / f32(sapp.height())
	view := camera_view(&g_state.camera)
	proj := camera_proj(&g_state.camera, aspect)

	// Draw the scene
	for &t in g_state.scene {
		model := transform_to_mat4(t)

		mvp = proj * view * model

		renderer_draw(
			&g_state.renderer,
			vs_params = {mvp = mvp, model = model},
			fs_params = {
				light_dir = LIGHT_DIR,
				light_color = [4]f32{1, 1, 1, 1},
				ambient = [4]f32{0.1, 0.1, 0.1, 1},
			},
		)
	}


	// ======================================================
	// Probes
	// ======================================================
	if g_state.frame_count == 0 {
		probe_dump(view, proj, mvp, aspect)
	}
	probe_interp(steps, alpha)

	// ======================================================
	// End the pass, commit and increment the frame count
	// ======================================================
	sg.end_pass()
	sg.commit()
	g_state.frame_count += 1

	// ======================================================
	// Handle input events
	// ======================================================
	if input_pressed(&g_state.input, sapp.Keycode.ESCAPE) {
		// quit the application
		sapp.request_quit()
	}

	if input_pressed(&g_state.input, sapp.Keycode.C) {
		g_state.toggled_pipeline = !g_state.toggled_pipeline
	}

	if input_pressed(&g_state.input, sapp.Keycode.SPACE) {
		if g_state.clock.time_scale == 1.0 {
			g_state.clock.time_scale = 0.0
		} else {
			g_state.clock.time_scale = 1.0
		}
	}

	// handle the lock for mouse movement
	if !sapp.mouse_locked() {
		sapp.lock_mouse(true)
	}


	// ======================================================
	// Free any temporary allocations at the end of the frame
	// ======================================================
	frame_end(&g_state.mem)

	input_end_frame(&g_state.input)

	// ** Uncomment to exit early **
	// 	if g_state.frame_count >= 120 {
	// 		sapp.request_quit() // exit after 120 frames
	// 	}
}

cleanup_cb :: proc "c" () {
	context = g_state.ctx

	renderer_shutdown(&g_state.renderer) // tear down resources

	// free any memory allocated by the script
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
// ======================================================
// ================== Input Handeling ===================
// ======================================================
event_cb :: proc "c" (event: ^sapp.Event) {
	context = g_state.ctx

	// write to out input state arrays
	input_on_event(&g_state.input, event)
}

probe_dump :: proc(view, proj, mvp: Mat4, aspect: f32) {

	fmt.printfln("CUBE_VERTICES: %v", size_of(CUBE_VERTICES))
	fmt.printfln("CUBE_INDICES: %v", size_of(CUBE_INDICES))

	e := g_state.camera.eye
	probe_point("view * eye", view, {e.x, e.y, e.z, 1})
	probe_point("view * origin", view, {0, 0, 0, 1})
	probe_basis("view", view)

	f, r, u := camera_basis(&g_state.camera)
	fmt.printfln("basis f %+.5f r %+.5f u %+.5f", f, r, u)

	fmt.printfln("fovy %v near %v apect %v", g_state.camera.fovy, g_state.camera.near, aspect)

	fmt.printfln("eye %v", g_state.camera.eye)

	// depth probe
	probe_point("z = -0.1 near", proj, {0, 0, -0.1, 1})
	probe_point("z = -0.2", proj, {0, 0, -0.2, 1})
	probe_point("z - -1", proj, {0, 0, -1, 1})
	probe_point("z = -50", proj, {0, 0, -50, 1})
	probe_point("z = -100 far", proj, {0, 0, -100, 1})
}

probe_interp :: proc(steps: int, alpha: f32) {
	if g_state.frame_count >= 120 {
		return
	}

	@(static) prev_raw: f32
	@(static) prev_lerp: f32
	@(static) prev_render_time: f64
	@(static) prev_game_time: f64


	raw := script_body(&g_state.script, 2).x
	lerp := script_render_x(&g_state.script, 2, alpha)

	raw_delta := raw - prev_raw
	lerp_delta := lerp - prev_lerp

	render_time := clock_render_time(&g_state.clock)
	game_time := g_state.clock.game_time
	spin_render := math.to_degrees(ANGULAR_SPEED * (render_time - prev_render_time))
	spin_game := math.to_degrees(ANGULAR_SPEED * (game_time - prev_game_time))

	if g_state.frame_count == 0 {
		fmt.printfln("| frame | steps | alpha  |   raw x |  d raw  |  lerp x | d lerp  | d spin | d spin_q |")
		fmt.printfln("|-------|-------|--------|---------|---------|---------|---------|--------|----------|")
	}
	fmt.printfln("| %5d | %5d | %.4f | %+7.4f | %+7.5f | %+7.4f | %+7.5f | %.4f | %8.4f |", g_state.frame_count, steps, alpha, raw, raw_delta, lerp, lerp_delta, spin_render, spin_game)

	prev_raw = raw
	prev_lerp = lerp
	prev_render_time = render_time
	prev_game_time = game_time
}
