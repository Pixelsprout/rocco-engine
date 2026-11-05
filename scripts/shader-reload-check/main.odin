package main

import engine "../../engine"
import sapp "../../sokol-odin/sokol/app"
import sg "../../sokol-odin/sokol/gfx"
import sglue "../../sokol-odin/sokol/glue"
import slog "../../sokol-odin/sokol/log"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"

saved_context: runtime.Context
errors, expected_errors: int
expect_failure: bool
tracker: mem.Tracking_Allocator

main :: proc() {
	saved_context = context
	assert(len(os.args) == 2)
	sapp.run({init_cb = init, frame_cb = frame, cleanup_cb = cleanup, width = 64, height = 64, window_title = "Shader reload check", sample_count = 1, logger = {func = log_item}, gl = {major_version = 4, minor_version = 3}})
	assert(errors == 0)
}

log_item :: proc "c" (tag: cstring, level, item: u32, message: cstring, line: u32, file: cstring, user: rawptr) {
	context = saved_context
	slog.func(tag, level, item, message, line, file, user)
	if level <= 1 { if expect_failure { expected_errors += 1 } else { errors += 1 } }
}

init :: proc "c" () {
	context = saved_context
	sg.setup({environment = sglue.environment(), logger = {func = log_item}, image_pool_size = 256, view_pool_size = 512, sampler_pool_size = 256, shader_pool_size = 128, pipeline_pool_size = 256})
	sg.enable_stats()
	mem.tracking_allocator_init(&tracker, context.allocator)
}

stage :: proc(table: ^engine.Shader_Table, name, file: string, active: ^engine.Shader) -> int {
	bytes, read := engine.shader_read_file(fmt.tprintf("%v/%v.shaderpack", os.args[1], file), table.allocator, 18*1024*1024)
	assert(read)
	slot, reason := engine.shader_candidate_stage(table, name, bytes, active)
	assert(slot != 0, reason)
	_, found := engine.shader_table_find(table, name); assert(found)
	return slot
}

assert_resources :: proc(expected: sg.Total_Stats) {
	actual := sg.query_stats().total
	assert(actual.shaders.alive == expected.shaders.alive)
	assert(actual.pipelines.alive == expected.pipelines.alive)
	assert(actual.samplers.alive == expected.samplers.alive)
	assert(actual.images.alive == expected.images.alive)
	assert(actual.views.alive == expected.views.alive)
}

drain :: proc(table: ^engine.Shader_Table) {
	for _ in 0 ..< 3 { sg.commit(); engine.shader_table_frame(table) }
}

exercise :: proc(table: ^engine.Shader_Table, id: u32, name: string) {
	active, found := engine.shader_lookup(table, id); assert(found)
	baseline := sg.query_stats().total
	old_program := active.programs[0].handle
	slot := stage(table, name, "Bad" if !active.package_data.post else "BadPost", active)
	expect_failure = true
	assert(!engine.shader_candidate_validate(table, &table.assets[slot], active))
	expect_failure = false
	engine.shader_candidate_destroy(table, slot)
	assert(active.programs[0].handle == old_program)
	assert_resources(baseline)
	for _ in 0 ..< 12 {
		slot = stage(table, name, "Foliage" if !active.package_data.post else "Outline", active)
		candidate := &table.assets[slot]
		assert(engine.shader_upload(table, candidate))
		reserved := make([dynamic]sg.Pipeline, 0, 256, context.temp_allocator)
		remaining := sg.query_stats().total.pipelines.free
		for _ in 0 ..< remaining { handle := sg.alloc_pipeline(); assert(handle.id != 0); append(&reserved, handle) }
		expect_failure = true
		assert(!engine.shader_candidate_validate(table, candidate, active))
		expect_failure = false
		engine.shader_candidate_destroy(table, slot)
		for pipeline in reserved { sg.dealloc_pipeline(pipeline) }
		assert(active.programs[0].handle == old_program)
		assert_resources(baseline)
		slot = stage(table, name, "Foliage" if !active.package_data.post else "Outline", active)
		candidate = &table.assets[slot]
		assert(engine.shader_candidate_validate(table, candidate, active))
		assert(len(candidate.pipelines) == len(active.pipelines))
		for pipeline, index in active.post_pipelines { if pipeline.id != 0 { assert(candidate.post_pipelines[index].id != 0) } }
		assert(engine.shader_candidate_publish(table, slot, engine.mesh_slot(id)) == id)
		assert(table.assets[slot].retiring)
		old_program = active.programs[0].handle
		drain(table)
		assert(!table.assets[slot].retiring)
		assert_resources(baseline)
	}
}

frame :: proc "c" () {
	context = saved_context
	allocator := mem.tracking_allocator(&tracker)
	baseline := sg.query_stats().total
	table: engine.Shader_Table; engine.shader_table_init(&table, allocator)
	surface, reason, ok := engine.shader_load_file(&table, os.args[1], "shader/Foliage"); assert(ok, reason)
	post, post_reason, post_ok := engine.shader_load_file(&table, os.args[1], "shader/Outline"); assert(post_ok, post_reason)
	engine.shader_table_upload(&table, 1)
	s, _ := engine.shader_lookup(&table, surface); assert(s.ready)
	for layout in engine.Shader_Layout { for pass in engine.Surface_Pass { for alpha in engine.Alpha_Mode { for cull in ([]sg.Cull_Mode{.BACK, .FRONT, .NONE}) {
		_, valid := engine.shader_pipeline(&table, s, {pass, layout, alpha, cull}); assert(valid)
	} } } }
	p, _ := engine.shader_lookup(&table, post); assert(p.ready)
	for location in ([]engine.Post_Location{.BeforeBloom, .AfterToneMap}) { _, valid := engine.post_pipeline(p, location); assert(valid) }
	exercise(&table, surface, "shader/Foliage")
	exercise(&table, post, "shader/Outline")
	engine.shader_table_remove(&table, engine.mesh_slot(surface)); engine.shader_table_remove(&table, engine.mesh_slot(post))
	drain(&table); engine.shader_table_destroy(&table)
	assert_resources(baseline)
	assert(tracker.current_memory_allocated == 0 && len(tracker.bad_free_array) == 0)
	assert(errors == 0 && expected_errors >= 26)
	totals := sg.query_stats().total
	fmt.printfln("RELOAD_RESOURCES shaders=%v pipelines=%v samplers=%v images=%v views=%v cpu_bytes=%v", totals.shaders.alive, totals.pipelines.alive, totals.samplers.alive, totals.images.alive, totals.views.alive, tracker.current_memory_allocated)
	fmt.println("PASS: native Shader reload, Surface and Post pipeline failure, program failure, recovery, retirement, and resource counts")
	sapp.request_quit()
}

cleanup :: proc "c" () {
	context = saved_context
	mem.tracking_allocator_destroy(&tracker)
	sg.shutdown()
}
