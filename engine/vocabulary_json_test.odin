#+test
package engine

import "core:encoding/json"
import "core:math"
import "core:strings"
import "core:testing"

@(test)
test_json_write_commands_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	commands := []Command{{tag = .Quit}, fake_load("room", "a", "b\"c"), fake_unload("room")}
	list := roc_list_from_slice(commands)
	defer roc_list_decref(list)
	b := strings.builder_make(context.temp_allocator)

	json_write_commands(&b, list)

	got := strings.to_string(b)
	testing.expect_value(t, got, `"Quit",{"Load":{"pack":"room","assets":["a","b\"c"]}},{"Unload":"room"}`)
	_, err := json.parse_string(strings.concatenate({"[", got, "]"}, context.temp_allocator), allocator = context.temp_allocator)
	testing.expect_value(t, err, nil)
}

@(test)
test_json_write_commands_writes_a_play_and_its_place :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	commands := []Command{fake_play(3, 0.5, 2, {tag = .Here}), fake_play(4, 1, 1, {tag = .At, payload = {at = {pos = {1, 2, 3}, range = 10}}})}
	b := strings.builder_make(context.temp_allocator)

	json_write_commands(&b, json_test_list(commands))

	expect_json_text(
		t,
		&b,
		`{"Play":{"sound":3,"gain":0.5,"pitch":2,"at":"Here"}},` +
		`{"Play":{"sound":4,"gain":1,"pitch":1,"at":{"At":{"pos":{"x":1,"y":2,"z":3},"range":10}}}}`,
	)
}

// The second call goes on with a comma, so the steps of a request join.
@(test)
test_json_write_commands_joins_a_second_list :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	first := roc_list_from_slice([]Command{{tag = .Quit}})
	defer roc_list_decref(first)
	empty := roc_list_from_slice([]Command{})
	defer roc_list_decref(empty)

	json_write_commands(&b, first)
	json_write_commands(&b, empty)
	json_write_commands(&b, first)

	testing.expect_value(t, strings.to_string(b), `"Quit","Quit"`)
}

@(test)
test_json_write_f32_writes_the_shortest_round_trip_and_null_for_nan_and_inf :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	values := []f32{0, -2.5, 0.1, 1e-7, 1.0 / 3.0, 1e20, math.nan_f32(), math.inf_f32(1), math.inf_f32(-1)}
	for v, i in values {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		json_write_f32(&b, v)
	}
	expect_json_text(t, &b, `0,-2.5,0.1,1e-07,0.33333334,1e+20,null,null,null`)
}

@(test)
test_json_write_light_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	lights := []Light{light_ambient({r = 1, g = 0.5, b = 0.25}), light_sun({0, -1, 0}, {1, 1, 1}), light_point({1, 2, 3}, {r = 1}, 4)}
	b := strings.builder_make(context.temp_allocator)

	json_write_list(&b, json_test_list(lights), json_write_light)

	expect_json_text(
		t,
		&b,
		`[{"Ambient":{"r":1,"g":0.5,"b":0.25}},` +
		`{"Directional":{"dir":{"x":0,"y":-1,"z":0},"color":{"r":1,"g":1,"b":1},"shadow":true}},` +
		`{"Point":{"pos":{"x":1,"y":2,"z":3},"color":{"r":1,"g":0,"b":0},"range":4}}]`,
	)
}

@(test)
test_json_write_collider_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	colliders := []Collider{test_box(1, {0, 0, 0}, 0.5, {1, 2, 3}), test_sphere(2, {1, 0, 0}, 0.5), test_capsule(3, {0, 1, 0})}
	b := strings.builder_make(context.temp_allocator)

	json_write_list(&b, json_test_list(colliders), json_write_collider)

	expect_json_text(
		t,
		&b,
		`[{"id":1,"pos":{"x":0,"y":0,"z":0},"yaw":0.5,"shape":{"Box":{"x":1,"y":2,"z":3}}},` +
		`{"id":2,"pos":{"x":1,"y":0,"z":0},"yaw":0,"shape":{"Sphere":0.5}},` +
		`{"id":3,"pos":{"x":0,"y":1,"z":0},"yaw":0,"shape":{"Capsule":{"radius":1,"half_height":1}}}]`,
	)
}

@(test)
test_json_write_query_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	queries := []Query {
		test_contacts_of(7),
		test_ray(1, 2, {0, 0, 0}, {1, 0, 0}, 10, exclude = []u64{3, 4}),
		test_overlap_box(1, 3, {0, 0, 0}, {1, 1, 1}),
		test_overlap_sphere(1, 4, {0, 1, 0}, 2, exclude = []u64{5}),
	}
	b := strings.builder_make(context.temp_allocator)

	json_write_list(&b, json_test_list(queries), json_write_query)

	expect_json_text(
		t,
		&b,
		`[{"ContactsOf":7},` +
		`{"Raycast":{"owner":1,"slot":2,"origin":{"x":0,"y":0,"z":0},"dir":{"x":1,"y":0,"z":0},"max_distance":10,"exclude":[3,4]}},` +
		`{"Overlap":{"owner":1,"slot":3,"shape":{"Box":{"x":1,"y":1,"z":1}},"pos":{"x":0,"y":0,"z":0},"exclude":[]}},` +
		`{"Overlap":{"owner":1,"slot":4,"shape":{"Sphere":2},"pos":{"x":0,"y":1,"z":0},"exclude":[5]}}]`,
	)
}

@(test)
test_json_write_element_uses_the_vocabulary_tags :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	column := Box_Config {
		width       = {tag = .Fit, payload = {fit = {min = 1, max = 2}}},
		height      = {tag = .Grow},
		pad         = {left = 1, right = 2, top = 3, bottom = 4},
		gap         = 5,
		direction   = .Col,
		child_align = {.Center, .End},
		background  = {r = 1, a = 0.5},
		radius      = 6,
		floating    = {tag = .NoFloat},
	}
	corner := ui_box()
	corner.width = ui_fixed(100)
	corner.height = {tag = .Percent, payload = {percent = 0.5}}
	corner.floating = {tag = .Float, payload = {float = {attach = .RightBottom, offset = {2, -3}}}}
	// A short string is stored inline, so it needs no Roc heap.
	text := Element {
		payload = {text = {str = roc_str_from_slice(`say "hi"`), size = 16, color = {r = 1, g = 1, b = 1, a = 1}, wrap = .Words}},
	}
	text.tag = .Text
	elements := []Element{ui_open(column), ui_open(corner), text, ui_close()}
	b := strings.builder_make(context.temp_allocator)

	json_write_list(&b, json_test_list(elements), json_write_element)

	expect_json_text(
		t,
		&b,
		`[{"Open":{"width":{"Fit":{"min":1,"max":2}},"height":{"Grow":{"min":0,"max":0}},` +
		`"pad":{"left":1,"right":2,"top":3,"bottom":4},"gap":5,"direction":"Col","child_align":{"x":"Center","y":"End"},` +
		`"background":{"r":1,"g":0,"b":0,"a":0.5},"radius":6,"floating":"NoFloat"}},` +
		`{"Open":{"width":{"Fixed":100},"height":{"Percent":0.5},` +
		`"pad":{"left":0,"right":0,"top":0,"bottom":0},"gap":0,"direction":"Row","child_align":{"x":"Start","y":"Start"},` +
		`"background":{"r":0,"g":0,"b":0,"a":0},"radius":0,"floating":{"Float":{"attach":"RightBottom","offset":{"x":2,"y":-3}}}}},` +
		`{"Text":{"str":"say \"hi\"","size":16,"color":{"r":1,"g":1,"b":1,"a":1},"wrap":"Words"}},` +
		`"Close"]`,
	)
}

@(test)
test_json_write_scene_writes_every_field_with_the_vocabulary_names :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	draws := []Draw{{id = 7, mesh = 3, pos = {1, 2, 3}, scale = {1, 1, 1}, rot = {w = 1}, scale_rot = {w = 1}, tint = {r = 1, g = 0.5, b = 0.25}}}
	loops := []Loop {
		{id = 9, sound = 2, gain = 0.5, pitch = 1, at = {tag = .Here}},
		{id = 10, sound = 3, gain = 1, pitch = 2, at = {tag = .At, payload = {at = {pos = {0, 1, 0}, range = 4}}}},
	}
	scene := Scene {
		camera = {eye = {0, 2, 5}, up = {0, 1, 0}, fov_y = 1},
		draws  = json_test_list(draws),
		cursor = .Locked,
		sky    = 2,
		loops  = json_test_list(loops),
	}
	b := strings.builder_make(context.temp_allocator)

	json_write_scene(&b, &scene)

	expect_json_text(
		t,
		&b,
		`{"camera":{"eye":{"x":0,"y":2,"z":5},"target":{"x":0,"y":0,"z":0},"up":{"x":0,"y":1,"z":0},"fov_y":1},` +
		`"draws":[{"id":7,"mesh":3,"pos":{"x":1,"y":2,"z":3},"scale":{"x":1,"y":1,"z":1},` +
		`"rot":{"x":0,"y":0,"z":0,"w":1},"scale_rot":{"x":0,"y":0,"z":0,"w":1},"tint":{"r":1,"g":0.5,"b":0.25}}],` +
		`"colliders":[],"lights":[],"cursor":"Locked","sky":2,"ui":[],"queries":[],` +
		`"loops":[{"id":9,"sound":2,"gain":0.5,"pitch":1,"at":"Here"},` +
		`{"id":10,"sound":3,"gain":1,"pitch":2,"at":{"At":{"pos":{"x":0,"y":1,"z":0},"range":4}}}]}`,
	)
}

@(test)
test_json_write_query_results_writes_every_row_with_the_vocabulary_names :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	contacts := []Contact{{a = 1, b = 2, normal = {1, 0, 0}, depth = 0.5}}
	rays := []Ray_Hit{{owner = 1, slot = 2, id = 3, point = {1, 2, 3}, normal = {0, 1, 0}, distance = 4}}
	overlaps := []Overlap_Hit{{owner = 1, slot = 3, id = 2}}
	results := Query_Results {
		contacts = json_test_list(contacts),
		rays     = json_test_list(rays),
		overlaps = json_test_list(overlaps),
	}
	b := strings.builder_make(context.temp_allocator)

	json_write_query_results(&b, &results)

	expect_json_text(
		t,
		&b,
		`{"contacts":[{"a":1,"b":2,"normal":{"x":1,"y":0,"z":0},"depth":0.5}],` +
		`"rays":[{"owner":1,"slot":2,"id":3,"point":{"x":1,"y":2,"z":3},"normal":{"x":0,"y":1,"z":0},"distance":4}],` +
		`"overlaps":[{"owner":1,"slot":3,"id":2}]}`,
	)
}

// The writers only read, so the list can borrow the slice.
@(private = "file")
json_test_list :: proc(s: []$T) -> Roc_List(T) {
	return {elements = raw_data(s), length = uint(len(s))}
}

@(private = "file")
expect_json_text :: proc(t: ^testing.T, b: ^strings.Builder, want: string, loc := #caller_location) {
	got := strings.to_string(b^)
	testing.expect_value(t, got, want, loc = loc)
	_, err := json.parse_string(strings.concatenate({"[", got, "]"}, context.temp_allocator), allocator = context.temp_allocator)
	testing.expectf(t, err == nil, "%q is not JSON: %v", got, err, loc = loc)
}
