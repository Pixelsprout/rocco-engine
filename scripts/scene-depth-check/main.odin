package main

import engine "../../engine"
import sapp "../../sokol-odin/sokol/app"
import sg "../../sokol-odin/sokol/gfx"
import sglue "../../sokol-odin/sokol/glue"
import slog "../../sokol-odin/sokol/log"
import "base:runtime"
import "core:fmt"
import "core:os"

SAMPLES :: [4]engine.Msaa{.Off, .X2, .X4, .X8}

saved_context: runtime.Context
errors: int
renderer: engine.Renderer
packs: engine.Packs
frame_render: engine.Frame_Render
launch: engine.Launch
ids: [5]u32
skin: engine.Skin_Params
audio: engine.Audio

main :: proc() {
	assert(len(os.args) == 3 || len(os.args) == 4)
	probe_parse()
	saved_context = context
	sapp.run({init_cb = init, frame_cb = frame, cleanup_cb = cleanup, width = 480, height = 360, window_title = "Scene depth parity", sample_count = 1, logger = {func = log_item}, gl = {major_version = 4, minor_version = 3}})
	assert(errors == 0)
}

log_item :: proc "c" (tag: cstring, level, item: u32, message: cstring, line: u32, file: cstring, user: rawptr) {
	context = saved_context
	slog.func(tag, level, item, message, line, file, user)
	if level <= 1 { errors += 1 }
}

init :: proc "c" () {
	context = saved_context
	launch = engine.launch_default()
	launch.capacity = {meshes = 16, skies = 2, images = 2, draws = 128, groups = 4, ui_quads = 1}
	launch.shadow_map, launch.shadow_cascades = 32, 4
	gfx := engine.app_gfx_desc(launch.capacity, 4)
	gfx.environment, gfx.logger = sglue.environment(), {func = log_item}
	sg.setup(gfx)
	for &joint in skin.joints { joint = engine.mat4_identity() }
}

values :: proc(name: string) -> engine.Shader_Values {
	return {shader = {pack = engine.roc_str_from_slice("fixture"), asset = engine.roc_str_from_slice(name)}, scope = .Material}
}

prepare :: proc(samples: engine.Msaa) {
	launch.window.samples = samples
	allocator := context.allocator
	engine.mesh_table_init(&renderer.meshes, int(launch.capacity.meshes), allocator, allocator)
	engine.sky_table_init(&renderer.skies, int(launch.capacity.skies), allocator, allocator)
	engine.image_table_init(&renderer.images, int(launch.capacity.images), allocator, allocator)
	engine.packs_init(&packs, os.args[1], allocator)
	engine.packs_attach(&packs, &renderer.meshes, &renderer.skies, &renderer.images, &audio, allocator)
	lines, loaded := engine.pack_load(&packs, "fixture", {"tree", "pip", "shader/Foliage", "shader/RigidFoliage", "shader/Inspect"}, context.temp_allocator)
	assert(loaded)
	for line, i in lines { ids[i] = line.id; assert(line.id != 0) }
	renderer.shaders = &packs.shaders
	engine.renderer_init(&renderer, launch)
	engine.frame_render_init(&frame_render, int(launch.capacity.draws), 4, 32, 4, allocator)
	frame_render.submits = engine.renderer_submits(&renderer)
	frame_render.submits.submit_surface = fixture_surface
}

placed_draws :: proc(time: f32) -> []engine.Draw_Params {
	positions := [8][3]f32{{-2.6, 0.5, 0}, {-1.8, 0, 0}, {-0.5, 0, 0}, {0.8, 0, 0}, {2.0, 0, 0}, {3, 0, 0}, {0, 0.5, 1}, {100, 0, 0}}
	draws := make([]engine.Draw_Params, len(positions), context.temp_allocator)
	for position, i in positions {
		mesh_id := u32(engine.Primitive.Cube) if i == 0 || i >= 6 else ids[1] if i == 5 else ids[0]
		mesh, found := engine.mesh_lookup(&renderer.meshes, mesh_id)
		assert(found)
		draw := engine.Draw{id = u64(i+1), mesh = mesh_id, tint = {1, 1, 1}, scale = {0.8, 0.9, 0.7}, rot = {w = 1}, scale_rot = {w = 1}}
		if i == 2 || i == 3 { draw.material.surface = {tag = .Surface, payload = {surface = values("shader/Foliage")}} }
		if i == 4 { draw.material.surface = {tag = .Surface, payload = {surface = values("shader/RigidFoliage")}} }
		parts := engine.surface_resolve_parts(&packs, &draw, mesh, nil, time)
		assert(len(parts) > 0)
		if i == 3 { for &part in parts { if part.surface != nil { part.surface.vertex[4] = 0.7 } } }
		if i == 6 { for &part in parts { part.material.alpha_mode = .Blend } }
		x := engine.Draw_Transform{position = position, scale = {0.8, 0.9, 0.7}, rotation = engine.quat_from_axis_angle({0, 1, 0}, f32(i) * 0.11), scale_rotation = 1}
		p := new(engine.Placed, context.temp_allocator)
		p^ = {mesh = mesh, parts = parts, model = engine.draw_model_matrix(x), transform = x, tint = {1, 1, 1}, camera_visible = i != 7, selected = i == 2 || i == 5}
		if i == 5 { p.skin = &skin }
		vs, fs := engine.placed_draw_params(p, camera().view_proj)
		draws[i] = {p, vs, fs}
	}
	return draws
}

camera :: proc() -> engine.Frame_View {
	pose := engine.Camera_Pose{eye = {0, 2.5, 8}, target = {0, 0.8, 0}, up = {0, 1, 0}, fov_y = 0.85}
	return {camera = pose, view_proj = engine.scene_view_proj(pose, 4.0/3.0), aspect = 4.0/3.0}
}

render :: proc(draws: []engine.Draw_Params, individual: bool, mode: int) {
	ctx := rawptr(&renderer)
	view := camera()
	frame_render.submits.submit_instances = nil if individual else engine.renderer_instances
	engine.renderer_begin_pass(ctx, .Main, 0, {0.08, 0.1, 0.15})
	lights := engine.Fs_Lights{ambient = {0.7, 0.7, 0.7, 0}, camera_pos = {0, 2.5, 8, 0}}
	clusters := engine.cluster_build(nil, view, {480, 360})
	engine.renderer_lights(ctx, lights, clusters)
	for d in draws {
		if !d.p.camera_visible { continue }
		for &part in d.p.parts {
			pipeline, writes := engine.part_pipeline(part.material)
			if !writes { continue }
			fs := engine.frame_render_part_params(d.fs_params, &part)
			if part.surface != nil { fixture_surface(ctx, .Colour, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
			else { engine.renderer_draw(ctx, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
		}
	}
	engine.renderer_end_pass(ctx)
	shader, valid := engine.shader_lookup(&packs.shaders, ids[4]); assert(valid)
	effects := [1]engine.Resolved_Post{{material = {shader = shader}, location = .AfterToneMap, inputs = {.Scene_Colour, .Scene_Depth, .Selection_Coverage, .Selection_Depth}}}
	effects[0].material.fragment[0] = f32(mode)
	engine.renderer_prepare_post(ctx, effects[:])
	span := engine.span_open()
	engine.frame_render_depth(&frame_render, draws, view.view_proj, &span)
	engine.frame_render_selection(&frame_render, draws, &span)
	engine.renderer_begin_pass(ctx, .Post, 0, {})
	engine.renderer_tone_map(ctx, {exposure = 1})
	engine.renderer_post(ctx, effects[:], .AfterToneMap, 0)
	engine.renderer_end_pass(ctx)
	sg.commit()
}

frame :: proc "c" () {
	context = saved_context
	info := driver_info()
	skip := ""
	if probe_mode != .Baseline && info.backend != "GLCORE" { skip = "diagnostic controls require GL" }
	if probe_mode == .Zero_To_One && !info.clip_control { skip = "GL clip control is unsupported" }
	write_json(fmt.tprintf("%v/metadata.json", os.args[2]), Probe_Metadata{probe_mode, info, skip})
	if skip != "" { fmt.println("SCENE_DEPTH_SKIPPED", skip); sapp.request_quit(); return }
	for samples in SAMPLES {
		count := engine.msaa_sample_count(samples)
		if !supported(count) || probe_mode != .Baseline && count != 1 { continue }
		probe_samples = count
		prepare(samples)
		if probe_mode == .Zero_To_One { probe_clip_control(true) }
		write_json(fmt.tprintf("%v/driver-%v.json", os.args[2], count), driver_info())
		for time, pose in ([2]f32{0.25, 1.75}) {
			draws := placed_draws(time)
			probe_inputs(draws, pose)
			if probe_mode != .Baseline { draws = draws[3:4] }
			for mode in 0 ..< 4 {
				for individual in ([2]bool{true, false}) {
					if probe_mode == .Zero_To_One { probe_clip_control(true) }
					render(draws, individual, mode)
					if mode == 0 {
						write_json(fmt.tprintf("%v/active-driver-%v-%v-%v.json", os.args[2], count, pose, "individual" if individual else "batched"), driver_info())
						probe_read_depth(fmt.tprintf("%v/%v-%v-depth-%v.f32", os.args[2], count, pose, "individual" if individual else "batched"))
					}
					rgba := make([]byte, 480*360*4, context.temp_allocator)
					assert(engine.platform_read_target(renderer.target.color.image, {480, 360}, rgba) == "")
					path := fmt.tprintf("%v/%v-%v-%v-%v.png", os.args[2], count, pose, mode, "individual" if individual else "batched")
					png := engine.png_encode(480, 360, rgba, allocator = context.temp_allocator)
					assert(os.write_entire_file(path, png) == nil)
				}
			}
		}
		fmt.printfln("SCENE_DEPTH_SAMPLES %v", count)
		if probe_mode == .Zero_To_One { probe_clip_control(false) }
		engine.frame_render_destroy(&frame_render)
		engine.packs_destroy(&packs)
		engine.mesh_table_destroy(&renderer.meshes)
		engine.sky_table_destroy(&renderer.skies)
		engine.image_table_destroy(&renderer.images)
		sg.shutdown()
		gfx := engine.app_gfx_desc(launch.capacity, 4)
		gfx.environment, gfx.logger = sglue.environment(), {func = log_item}
		sg.setup(gfx)
		renderer = {}
		frame_render = {}
	}
	assert(errors == 0)
	fmt.println("PASS: scene-depth native differential fixture")
	sapp.request_quit()
}

cleanup :: proc "c" () { context = saved_context; sg.shutdown() }
