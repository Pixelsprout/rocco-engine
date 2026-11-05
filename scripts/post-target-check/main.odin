package main

import engine "../../engine"
import sapp "../../sokol-odin/sokol/app"
import sg "../../sokol-odin/sokol/gfx"
import sglue "../../sokol-odin/sokol/glue"
import slog "../../sokol-odin/sokol/log"
import "core:fmt"
import "base:runtime"

SAMPLES :: [4]i32{1, 2, 4, 8}

saved_context: runtime.Context
errors: int

main :: proc() {
	saved_context = context
	sapp.run({init_cb = init, frame_cb = frame, cleanup_cb = cleanup, width = 64, height = 64, window_title = "Post target check", sample_count = 1, logger = {func = log_item}, gl = {major_version = 4, minor_version = 3}})
	assert(errors == 0)
}

log_item :: proc "c" (tag: cstring, level, item: u32, message: cstring, line: u32, file: cstring, user: rawptr) {
	context = saved_context
	slog.func(tag, level, item, message, line, file, user)
	if level <= 1 { errors += 1 }
}

init :: proc "c" () {
	context = saved_context
	sg.setup({environment = sglue.environment(), logger = {func = log_item}, image_pool_size = 256, view_pool_size = 512, shader_pool_size = 64, pipeline_pool_size = 64})
}

check_layer :: proc(layer: engine.Target_Layer, size: [2]i32, samples: i32) {
	assert(engine.target_layer_valid(layer))
	desc := sg.query_image_desc(layer.image)
	assert(desc.width == size.x && desc.height == size.y && desc.sample_count == 1)
	if samples > 1 { assert(sg.query_image_desc(layer.msaa).sample_count == samples) }
}

frame :: proc "c" () {
	context = saved_context
	fmt.print("POST_SAMPLES [")
	first := true
	for samples in SAMPLES {
		if !supported(samples) { continue }
		if !first { fmt.print(",") }
		first = false
		fmt.print(samples)
		r: engine.Renderer
		engine.render_target_init(&r.target, samples)
		for size, i in ([3][2]i32{{320, 240}, {480, 270}, {320, 240}}) {
			dpi := f32(1) if i == 0 else 2
			engine.render_target_fit(&r.target, size, dpi)
			check_layer(r.target.hdr, size, samples)
			check_layer(r.target.color, size, samples)
			assert(r.target.post.scene.test.id == 0)
			effects := []engine.Resolved_Post{{location = .BeforeBloom, inputs = {.Scene_Depth}}, {location = .AfterToneMap, inputs = {.Selection_Coverage, .Selection_Depth}}}
			inputs := engine.renderer_prepare_post(&r, effects)
			assert(inputs == {.Scene_Colour, .Scene_Depth, .Selection_Coverage, .Selection_Depth})
			for layer in r.target.post.hdr { check_layer(layer, size, 1) }
			for layer in r.target.post.ldr { check_layer(layer, size, 1) }
			assert(r.target.post.hdr[0].image != r.target.hdr.image && r.target.post.hdr[0].image != r.target.post.hdr[1].image)
			assert(r.target.post.ldr[0].image != r.target.color.image && r.target.post.ldr[0].image != r.target.post.ldr[1].image)
			check_layer(r.target.post.scene.depth, size, 1)
			check_layer(r.target.post.selection.coverage, size, 1)
			assert(sg.query_image_desc(r.target.post.scene.test).sample_count == 1)
			sg.begin_pass({action = engine.coverage_pass_action(), attachments = r.target.post.scene.coverage.attachments})
			sg.end_pass()
			sg.commit()
			engine.renderer_prepare_post(&r, nil)
			assert(r.target.post.scene.test.id == 0 && r.target.post.selection.test.id == 0)
			assert(r.target.post.hdr[0].image.id == 0 && r.target.post.ldr[0].image.id == 0)
		}
		// A DPI change also replaces optional inputs when physical size stays equal.
		effects := []engine.Resolved_Post{{location = .BeforeBloom, inputs = {.Scene_Depth}}}
		engine.renderer_prepare_post(&r, effects)
		old := r.target.post.scene.depth.image
		engine.render_target_fit(&r.target, r.target.size, 1)
		engine.renderer_prepare_post(&r, effects)
		assert(r.target.post.scene.depth.image != old)
		engine.render_target_destroy(&r.target)
		sg.commit()
	}
	fmt.println("]")
	assert(errors == 0)
	fmt.println("PASS: Post resize, DPI, optional inputs, single-sample depth, and separate colour targets")
	sapp.request_quit()
}

cleanup :: proc "c" () {
	context = saved_context
	sg.shutdown()
}
