package engine

import sg "../sokol-odin/sokol/gfx"
import "system"

POST_TARGET_IMAGES :: 4 + 2 * 3
POST_TARGET_VIEWS :: 4 * 2 + 2 * 5

Coverage_Target :: struct { coverage, depth: Target_Layer, test: sg.Image }
Post_Targets :: struct {
	hdr, ldr: [2]Target_Layer,
	scene, selection: Coverage_Target,
	available: Post_Inputs,
	failed_logged: bool,
}

coverage_target_destroy :: proc(t: ^Coverage_Target) {
	target_layer_destroy(&t.coverage)
	target_layer_destroy(&t.depth)
	sg.destroy_image(t.test)
	t^ = {}
}

post_targets_destroy :: proc(t: ^Post_Targets) {
	for &layer in t.hdr { target_layer_destroy(&layer) }
	for &layer in t.ldr { target_layer_destroy(&layer) }
	coverage_target_destroy(&t.scene)
	coverage_target_destroy(&t.selection)
	t.available = {}
}

coverage_target_fit :: proc(t: ^Coverage_Target, size: [2]i32, enabled: bool) -> bool {
	if !enabled { coverage_target_destroy(t); return false }
	if t.test.id == 0 {
		t.coverage = target_layer_make(size, 1, .R8, "post-coverage", "")
		t.depth = target_layer_make(size, 1, .R32F, "post-depth", "")
		t.test = sg.make_image({usage = {depth_stencil_attachment = true}, width = size.x, height = size.y, pixel_format = .DEPTH, sample_count = 1, label = "post-depth-test"})
		t.coverage.attachments.colors[1] = t.depth.attachments.colors[0]
		t.coverage.attachments.depth_stencil = sg.make_view({depth_stencil_attachment = {image = t.test}})
	}
	return target_layer_valid(t.coverage) && target_layer_valid(t.depth) && sg.query_image_state(t.test) == .VALID && sg.query_view_state(t.coverage.attachments.depth_stencil) == .VALID
}

coverage_pass_action :: proc() -> sg.Pass_Action {
	return {colors = {0 = {load_action = .CLEAR, clear_value = {}}, 1 = {load_action = .CLEAR, clear_value = {}}}, depth = {load_action = .CLEAR, clear_value = 0}}
}

post_layers_fit :: proc(layers: ^[2]Target_Layer, size: [2]i32, format: sg.Pixel_Format, enabled: bool) {
	for &layer in layers {
		if !enabled { target_layer_destroy(&layer) } else if layer.image.id == 0 { layer = target_layer_make(size, 1, format, "post-effect", "") }
	}
}

target_layer_valid :: proc(layer: Target_Layer) -> bool {
	return sg.query_image_state(layer.image) == .VALID && sg.query_view_state(layer.texture) == .VALID && sg.query_view_state(layer.attachments.colors[0]) == .VALID
}

renderer_prepare_post :: proc(ctx: rawptr, effects: []Resolved_Post) -> Post_Inputs {
	r := (^Renderer)(ctx)
	t := &r.target
	t.hdr_read = t.hdr.texture
	inputs: Post_Inputs
	hdr, ldr: bool
	for effect in effects { inputs += effect.inputs; if effect.location == .BeforeBloom { hdr = true } else { ldr = true } }
	post_layers_fit(&t.post.hdr, t.size, HDR_COLOR_FORMAT, hdr)
	post_layers_fit(&t.post.ldr, t.size, TARGET_COLOR_FORMAT, ldr)
	t.post.available = {.Scene_Colour}
	if coverage_target_fit(&t.post.scene, t.size, .Scene_Depth in inputs) { t.post.available += {.Scene_Depth} }
	if coverage_target_fit(&t.post.selection, t.size, .Selection_Coverage in inputs || .Selection_Depth in inputs) {
		t.post.available += {.Selection_Coverage, .Selection_Depth}
	}
	return t.post.available
}

renderer_post :: proc(ctx: rawptr, effects: []Resolved_Post, location: Post_Location, time: f32) {
	r := (^Renderer)(ctx)
	t := &r.target
	read := t.hdr_read if location == .BeforeBloom else t.color.texture
	layers := &t.post.hdr if location == .BeforeBloom else &t.post.ldr
	output := 0
	active := false
	for &effect in effects {
		if effect.location != location { continue }
		if effect.inputs - t.post.available != {} { renderer_post_log(r, "declared input could not be allocated"); continue }
		layer := layers[output]
		if !target_layer_valid(layer) { renderer_post_log(r, "effect target could not be allocated"); continue }
		pip, valid := post_pipeline(effect.material.shader, location)
		if !valid { renderer_post_log(r, "pipeline creation failed"); continue }
		if !active && location == .AfterToneMap { gfx_end_pass() }
		active = true
		label: cstring = "game-post"
		when GPU_TIMING { label = "game-post-hdr" if location == .BeforeBloom else "game-post-ldr" }
		gfx_begin_pass({action = t.post_action, attachments = layer.attachments, label = label})
		sg.apply_pipeline(pip)
		program := effect.material.shader.programs[0 if location == .BeforeBloom else 1]
		bindings: sg.Bindings
		views := [4]sg.View{read, t.post.scene.depth.texture, t.post.selection.coverage.texture, t.post.selection.depth.texture}
		for view in shader_array(program.reflection["views"]) {
			slot := shader_int(shader_object(shader_object(view)["texture"])["slot"])
			bindings.views[slot] = views[slot] if slot < 4 else effect.material.textures[slot-8].view
		}
		for sampler in shader_array(program.reflection["samplers"]) {
			slot := shader_int(shader_object(sampler)["slot"])
			bindings.samplers[slot] = t.sampler if slot < 4 else effect.material.shader.samplers[slot-8]
		}
		sg.apply_bindings(bindings)
		params := Post_Params{viewport = {f32(t.size.x), f32(t.size.y), 1/f32(t.size.x), 1/f32(t.size.y)}, frame = {time, 0, 0, 0}}
		for block in shader_array(program.reflection["uniform_blocks"]) {
			slot := shader_int(shader_object(block)["slot"])
			if slot == 1 { sg.apply_uniforms(slot, {ptr = &params, size = size_of(params)}) }
			if slot == 5 { sg.apply_uniforms(slot, {ptr = &effect.material.fragment, size = size_of(effect.material.fragment)}) }
		}
		sg.draw(0, 3, 1)
		gfx_end_pass()
		read = layer.texture
		output = 1-output
	}
	if location == .BeforeBloom { t.hdr_read = read }
	if active && location == .AfterToneMap {
		render_target_begin_post(t)
		sg.apply_pipeline(t.composite)
		sg.apply_bindings({views = {VIEW_blit_tex = read}, samplers = {SMP_blit_smp = t.sampler}})
		sg.draw(0, 3, 1)
	}
}

renderer_post_log :: proc(r: ^Renderer, reason: string) {
	if !r.target.post.failed_logged { r.target.post.failed_logged = true; system.eprintfln("Post: %v; effect skipped", reason) }
}
