#+test
package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_bridge_scene_replies_every_scene_field_and_the_results_the_next_step_gets :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	colliders := []Collider{test_box(1, {0, 0, 0}, IDENTITY, {1, 1, 1}), test_sphere(2, {1.5, 0, 0}, 1), test_capsule(3, {10, 0, 0})}
	queries := []Query{test_contacts_of(1), test_ray(4, 2, {5, 0, 0}, {-1, 0, 0}, 20), test_overlap_sphere(4, 3, {0, 0, 0}, 0.25)}
	corner := ui_box()
	corner.width = ui_fixed(40)
	corner.floating = ui_floating(.LeftTop)
	ui := []Element{ui_box_of(corner, ui_box_of(ui_box()))}
	s: State
	fake_frame_state_init(&s, mode = .Lockstep, colliders = colliders, queries = queries, ui = ui)
	defer fake_frame_state_destroy(&s)
	g_fake.camera = {eye = {0, 2, 5}, up = {0, 1, 0}, fov_y = 1}
	g_fake.draws = []Draw{{id = 7, mesh = 3, pos = {1, 2, 3}, scale = {1, 1, 1}, rot = {w = 1}, scale_rot = {w = 1}}}
	g_fake.lights = []Light{light_ambient({r = 0.1, g = 0.1, b = 0.1}), light_sun({0, -1, 0}, {1, 1, 1}), light_point({0, 3, 0}, {r = 1}, 5)}
	g_fake.loops = []Loop{{id = 4, sound = 6, gain = 1, pitch = 1, at = {tag = .Here}}}
	g_fake.cursor = .Locked
	g_fake.sky = 2
	g_fake.ui_texts = {"Pip"}
	frame_run(&s, fake_platform(s.clock.fixed_dt))

	reply := scene_reply(t, &s)

	testing.expect_value(t, reply["ok"].(json.Boolean), true)
	testing.expect_value(t, reply["steps"].(json.Float), 1)
	scene := reply["scene"].(json.Object)
	camera := scene["camera"].(json.Object)
	testing.expect_value(t, camera["eye"].(json.Object)["z"].(json.Float), 5)
	testing.expect_value(t, camera["fov_y"].(json.Float), 1)
	draw := scene["draws"].(json.Array)[0].(json.Object)
	testing.expect_value(t, draw["id"].(json.Float), 7)
	testing.expect_value(t, draw["mesh"].(json.Float), 3)
	testing.expect_value(t, draw["pos"].(json.Object)["y"].(json.Float), 2)
	testing.expect_value(t, draw["rot"].(json.Object)["w"].(json.Float), 1)
	testing.expect_value(t, scene["cursor"].(json.String), "Locked")
	testing.expect_value(t, scene["sky"].(json.Float), 2)
	shapes := make(json.Array, 0, 3, context.temp_allocator)
	for collider in scene["colliders"].(json.Array) {
		append(&shapes, collider.(json.Object)["shape"])
	}
	expect_tags(t, shapes, {"Box", "Sphere", "Capsule"})
	expect_tags(t, scene["lights"].(json.Array), {"Ambient", "Directional", "Point"})
	expect_tags(t, scene["queries"].(json.Array), {"ContactsOf", "Raycast", "Overlap"})
	loops := scene["loops"].(json.Array)
	testing.expect_value(t, len(loops), 1)
	testing.expect_value(t, loops[0].(json.Object)["id"].(json.Float), 4)
	testing.expect_value(t, loops[0].(json.Object)["sound"].(json.Float), 6)
	testing.expect_value(t, loops[0].(json.Object)["at"].(json.String), "Here")
	// fake_view puts the ui_texts Box before the Elements of g_fake.ui.
	elements := scene["ui"].(json.Array)
	expect_tags(t, elements, {"Box", "Box"})
	pip := expect_tag(t, elements[0], "Box").(json.Object)["children"].(json.Array)
	expect_tags(t, pip, {"Text"})
	testing.expect_value(t, expect_tag(t, pip[0], "Text").(json.Object)["str"].(json.String), "Pip")
	corner_json := expect_tag(t, elements[1], "Box").(json.Object)
	float := expect_tag(t, corner_json["config"].(json.Object)["floating"], "Float").(json.Object)
	testing.expect_value(t, float["attach"].(json.String), "LeftTop")
	nested := corner_json["children"].(json.Array)
	expect_tags(t, nested, {"Box"})
	testing.expect_value(t, len(expect_tag(t, nested[0], "Box").(json.Object)["children"].(json.Array)), 0)

	results := reply["results"].(json.Object)
	contacts := results["contacts"].(json.Array)
	testing.expect_value(t, len(contacts), 1)
	testing.expect_value(t, contacts[0].(json.Object)["b"].(json.Float), 2)
	rays := results["rays"].(json.Array)
	testing.expect_value(t, len(rays), 1)
	testing.expect_value(t, rays[0].(json.Object)["id"].(json.Float), 2)
	testing.expect_value(t, rays[0].(json.Object)["distance"].(json.Float), 2.5)
	overlaps := results["overlaps"].(json.Array)
	testing.expect_value(t, len(overlaps), 1)
	testing.expect_value(t, overlaps[0].(json.Object)["id"].(json.Float), 1)
	testing.expect_value(t, overlaps[0].(json.Object)["slot"].(json.Float), 3)
}

// Lockstep's Alpha is 0. Without the pause rule the window would draw the
// Draw at the init view's place, one step behind scene.
@(test)
test_bridge_paused_render_draws_the_scene_that_scene_replies :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	s: State
	fake_frame_state_init(&s, mode = .Lockstep)
	defer fake_frame_state_destroy(&s)
	err := bridge_open(&s.bridge, 0, context.allocator)
	testing.expect_value(t, err, nil)
	defer bridge_close(&s.bridge)
	// The init view has Draw 1 at the origin. Every later view has it at x = 2.
	g_fake.draws = []Draw{{id = 1, pos = {2, 0, 0}, scale = {1, 1, 1}, rot = {w = 1}, scale_rot = {w = 1}}}
	step_request := strings.builder_make(context.temp_allocator)
	testing.expect_value(t, bridge_handle(&s, `{"op":"step"}`, &step_request), Bridge_Next.Hold)

	for _ in 0 ..< 2 {
		frame_run(&s, fake_platform(s.clock.fixed_dt))
		testing.expect_value(t, len(s.frame_render.placed), 1)
		testing.expect_value(t, s.frame_render.placed[0].transform.position, [3]f32{2, 0, 0})
	}

	testing.expect_value(t, g_fake.steps, 1)
	reply := scene_reply(t, &s)
	pos := reply["scene"].(json.Object)["draws"].(json.Array)[0].(json.Object)["pos"].(json.Object)
	testing.expect_value(t, pos["x"].(json.Float), 2)
}

@(private = "file")
scene_reply :: proc(t: ^testing.T, s: ^State) -> json.Object {
	reply, next := driver_answer(t, s, `{"op":"scene"}`, parse_integers = false)
	testing.expect_value(t, next, Bridge_Next.Read)
	return reply
}

// A tag with no payload is a string. A tag with a payload is an object with
// one key, and this returns the payload.
@(private = "file")
expect_tag :: proc(t: ^testing.T, value: json.Value, tag: string, loc := #caller_location) -> (payload: json.Value) {
	#partial switch v in value {
	case json.String:
		testing.expect_value(t, v, tag, loc = loc)
		return nil
	case json.Object:
		got, ok := v[tag]
		testing.expectf(t, ok && len(v) == 1, "got %v, want one key %q", v, tag, loc = loc)
		return got
	}
	testing.expectf(t, false, "got %v, want the tag %q", value, tag, loc = loc)
	return nil
}

@(private = "file")
expect_tags :: proc(t: ^testing.T, values: json.Array, tags: []string, loc := #caller_location) {
	testing.expect_value(t, len(values), len(tags), loc = loc)
	for value, i in values[:min(len(values), len(tags))] {
		expect_tag(t, value, tags[i], loc)
	}
}
