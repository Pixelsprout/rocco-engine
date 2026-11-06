package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:strings"

POST_EFFECT_LIMIT :: 32
POST_UNIFORM_SLOTS :: 2 * POST_EFFECT_LIMIT

#assert(size_of(Post_Params) == 128)

Post_Effect :: Roc_View_Post
Post_Location :: Roc_View_Post_Location
Post_Input :: enum { Scene_Colour, Scene_Depth, Selection_Coverage, Selection_Depth }
Post_Inputs :: bit_set[Post_Input]
Resolved_Post :: struct { material: Surface_Material, location: Post_Location, inputs: Post_Inputs }
Post_Params :: struct { viewport, frame: [4]f32, reserved: [6][4]f32 }

post_log :: proc(p: ^Packs, reason: string) {
	key := fmt.tprintf("Post:%v", reason)
	if key not_in p.logged_assets { p.logged_assets[strings.clone(key, p.allocator)] = {}; fmt.eprintfln("Post: %v; effect skipped", reason) }
}

post_inputs :: proc(s: ^Shader) -> (inputs: Post_Inputs) {
	for value in shader_array(shader_interface(s)["inputs"]) {
		switch shader_text(value) {
		case "scene_colour": inputs += {.Scene_Colour}
		case "scene_depth": inputs += {.Scene_Depth}
		case "selection_coverage": inputs += {.Selection_Coverage}
		case "selection_depth": inputs += {.Selection_Depth}
		}
	}
	return
}

post_resolve :: proc(p: ^Packs, effects: []Post_Effect, scene: []Shader_Values, time: f32) -> []Resolved_Post {
	if p == nil || len(effects) == 0 { return nil }
	result := make([dynamic]Resolved_Post, 0, min(len(effects), POST_EFFECT_LIMIT), context.temp_allocator)
	for &effect in effects {
		if !effect.enabled { continue }
		if len(result) == POST_EFFECT_LIMIT { post_effect_log(p, &effect, "enabled effect capacity exceeded"); break }
		if effect.values.scope != .Draw { post_effect_log(p, &effect, "effect values require Draw scope"); continue }
		resolved, reason := surface_values_resolve(p, nil, &effect.values, scene, {effect.values}, time, false, true)
		if reason != "" { post_effect_log(p, &effect, reason); continue }
		name := "before_bloom" if effect.location == .BeforeBloom else "after_tone_map"
		permitted := false
		for location in shader_array(shader_interface(resolved.shader)["locations"]) { if shader_text(location) == name { permitted = true } }
		if !permitted { post_effect_log(p, &effect, "Shader does not declare the requested location"); continue }
		if p.shaders.uploaded { if _, ok := post_pipeline(resolved.shader, effect.location); !ok { post_effect_log(p, &effect, "pipeline creation failed"); continue } }
		append(&result, Resolved_Post{resolved, effect.location, post_inputs(resolved.shader)})
	}
	return result[:]
}

post_pipeline :: proc(s: ^Shader, location: Post_Location) -> (sg.Pipeline, bool) {
	index := 0 if location == .BeforeBloom else 1
	if s.post_pipelines[index].id != 0 { return s.post_pipelines[index], true }
	if !s.ready || s.programs[index].handle.id == 0 { return {}, false }
	format := HDR_COLOR_FORMAT if location == .BeforeBloom else TARGET_COLOR_FORMAT
	pip := sg.make_pipeline({shader = s.programs[index].handle, sample_count = 1, colors = {0 = {pixel_format = format}}, depth = {pixel_format = .NONE}, cull_mode = .NONE})
	if sg.query_pipeline_state(pip) != .VALID { sg.destroy_pipeline(pip); return {}, false }
	s.post_pipelines[index] = pip
	return pip, true
}

post_effect_log :: proc(p: ^Packs, effect: ^Post_Effect, reason: string) {
	post_log(p, fmt.tprintf("%v/%v: %v", roc_str_string(&effect.values.shader.pack), roc_str_string(&effect.values.shader.asset), reason))
}
