#+test
package engine

import clay "../clay/bindings/odin/clay-odin"
import "core:mem"
import vmem "core:mem/virtual"
import "core:slice"
import "core:sync"
import "core:testing"

RED :: Rgba{r = 1, a = 1}

// Clay keeps one current context for the process, and the test runner runs
// tests on several threads. Every test that calls Clay holds this lock.
g_clay_lock: sync.Mutex

// Holds g_clay_lock until frame_fixture_destroy_ui. A test that panics skips
// the unlock and blocks every later Clay test, so check a length before indexing.
frame_fixture_init_ui :: proc(f: ^Frame_Fixture, quad_capacity := UI_QUAD_LIMIT) {
	sync.mutex_lock(&g_clay_lock)
	f.ui = new(Ui)
	err := ui_init(f.ui, f.window.size, quad_capacity, context.allocator)
	assert(err == nil)
}

// Clay_Initialize reads the current context, so it must not point at freed memory.
frame_fixture_destroy_ui :: proc(f: ^Frame_Fixture) {
	clay.SetCurrentContext(nil)
	delete(f.ui.memory)
	delete(f.ui.quads)
	delete(f.ui.hits)
	delete(f.ui.over)
	delete(f.ui.scroll_panels)
	delete(f.ui.scrolls)
	delete(f.ui.clips)
	free(f.ui)
	sync.mutex_unlock(&g_clay_lock)
}

scene_ui :: proc(elements: []Element) -> Scene {
	return {ui = {elements = raw_data(elements), length = uint(len(elements))}}
}

// The glue orders tags by name, so a zero Box_Config floats and is not the vocabulary's default.
ui_box :: proc() -> Box_Config {
	return {overflow = {tag = .Visible}, floating = {tag = .NoFloat}, direction = .Row, child_align = {.Start, .Start}}
}

// The children list points into the temp allocator and has no refcount, so
// a Scene that the host frees must not hold it. fake_view copies g_fake.ui
// into refcounted lists for that reason.
ui_panel_of :: proc(config: Box_Config, children: ..Element) -> Element {
	kept := slice.clone(children, context.temp_allocator)
	return {tag = .Panel, payload = {panel = {_0 = config, _1 = {elements = raw_data(kept), length = uint(len(kept))}}}}
}

ui_fixed :: proc(v: f32) -> Sizing {
	return {tag = .Fixed, payload = {fixed = v}}
}

ui_floating :: proc(attach: Attach_Point) -> Floating {
	return {tag = .Float, payload = {float = {to = .Window, attach = attach, on = attach}}}
}

ui_text :: proc(str: string, size: f32) -> Element {
	return {tag = .Text, payload = {text = {str = roc_str_from_slice(str), size = size, color = RED, wrap = .Words}}}
}

expect_rect_near :: proc(t: ^testing.T, got, want: [4]f32, loc := #caller_location) {
	d := got - want
	testing.expectf(t, abs(d.x) < 1e-4 && abs(d.y) < 1e-4 && abs(d.z) < 1e-4 && abs(d.w) < 1e-4, "got %v, want %v", got, want, loc = loc)
}

ui_rect :: proc(width, height: f32) -> Box_Config {
	box := ui_box()
	box.width = ui_fixed(width)
	box.height = ui_fixed(height)
	box.background = RED
	return box
}


@(test)
test_ui_error_logs_once_per_kind :: proc(t: ^testing.T) {
	ui: Ui
	testing.expect(t, ui_error_mark_logged(&ui, .DuplicateId))
	testing.expect(t, !ui_error_mark_logged(&ui, .DuplicateId))
	testing.expect(t, ui_error_mark_logged(&ui, .ArenaCapacityExceeded))
	testing.expect_value(t, ui.errors_logged, bit_set[clay.ErrorType]{.DuplicateId, .ArenaCapacityExceeded})
}

@(test)
test_ui_init_sizes_the_arena_from_clay :: proc(t: ^testing.T) {
	sync.mutex_lock(&g_clay_lock)
	defer sync.mutex_unlock(&g_clay_lock)
	arena: vmem.Arena
	defer vmem.arena_destroy(&arena)
	defer clay.SetCurrentContext(nil)
	ui: Ui
	err := ui_init(&ui, {960, 540}, UI_QUAD_LIMIT, vmem.arena_allocator(&arena))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(ui.memory), int(clay.MinMemorySize()))
	testing.expect(t, ui.ctx != nil)
}

// The UI bench game lays out up to 16,384 Panels and Texts, as many as the
// largest N of a sweep.
@(test)
test_ui_lays_out_16384_panels_and_texts_with_no_clay_error :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	root := ui_box()
	root.direction = .Col
	cells := make([]Element, 16384 / 2, context.temp_allocator)
	for &cell, i in cells {
		cell = ui_panel_of(ui_rect(120, 16), ui_text(i % 2 == 0 ? "Cell 1" : "Cell 22", 12))
	}
	roots := []Element{ui_panel_of(root, ..cells)}
	quads := ui_frame(f.ui, roots, f.window)
	testing.expect_value(t, f.ui.errors_logged, bit_set[clay.ErrorType]{})
	testing.expect(t, len(quads) > 0)
}

@(test)
test_ui_panel_floating_at_right_bottom_sits_in_that_corner_at_two_window_sizes :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	box := ui_rect(100, 50)
	box.floating = ui_floating(.RightBottom)
	elements := []Element{ui_panel_of(box)}
	scene := scene_ui(elements)

	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 1) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{860, 490, 100, 50})
	testing.expect_value(t, f.rec.ui_quads[0].color, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, f.rec.ui_screen, [2]f32{960, 540})

	f.window.size = {640, 480}
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 1) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{540, 430, 100, 50})
}

@(test)
test_ui_scales_sizes_offsets_and_radius_by_the_dpi :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.window = {size = {1920, 1080}, dpi = 2}
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	box := ui_rect(100, 50)
	box.radius = 8
	box.floating = {tag = .Float, payload = {float = {to = .Window, attach = .RightBottom, on = .RightBottom, offset = {x = -10, y = -20}}}}
	elements := []Element{ui_panel_of(box)}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 1) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{1700, 940, 200, 100})
	testing.expect_value(t, f.rec.ui_quads[0].radius, 16)
}

// The expected metrics are the A, B and space entries of engine/font_baked.odin at the bake size.
@(test)
test_ui_text_draws_one_glyph_quad_per_visible_character_from_the_baseline :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	box := ui_box()
	box.pad = {left = 10, top = 20}
	elements := []Element{ui_panel_of(box, ui_text("A B", 32))}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)

	if !testing.expect_value(t, len(f.rec.ui_quads), 2) {
		return
	}
	a, b := f.rec.ui_quads[0], f.rec.ui_quads[1]
	baseline := f32(45)
	testing.expect(t, a.glyph)
	expect_rect_near(t, a.rect, {10 - 5, baseline - 23, 26, 28})
	expect_rect_near(t, a.uv, {230.0 / 256, 64.0 / 287, 1, 92.0 / 287})
	testing.expect_value(t, a.color, [4]f32{1, 0, 0, 1})
	space := f32(7.225806)
	expect_rect_near(t, b.rect, {10 + 16.154839 + space - 4, baseline - 23, 24, 28})
	expect_rect_near(t, b.uv, {0, 94.0 / 287, 24.0 / 256, 122.0 / 287})
}

@(test)
test_ui_text_size_scales_by_the_dpi :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.window.dpi = 2
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	elements := []Element{ui_text("A", 16)}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 1) {
		return
	}
	expect_rect_near(t, f.rec.ui_quads[0].rect, {-5, 25 - 23, 26, 28})
}

// The expected metrics are the A, B and space entries of engine/font_baked.odin at the bake size.
@(test)
test_ui_text_rounds_the_line_origin_to_whole_pixels_and_keeps_fractional_advances :: proc(t: ^testing.T) {
	ui := Ui {
		quads = make([]Ui_Quad, 4, context.temp_allocator),
	}
	defer free_all(context.temp_allocator)
	str := "A B"
	data := clay.TextRenderData {
		stringContents = {length = i32(len(str)), chars = raw_data(str), baseChars = raw_data(str)},
		textColor = {1, 0, 0, 1},
		fontSize = 32,
	}

	ui_push_text(&ui, {10.4, 20.3, 100, 32}, data)

	if !testing.expect_value(t, ui.quad_count, 2) {
		return
	}
	expect_rect_near(t, ui.quads[0].rect, {10 - 5, 45 - 23, 26, 28})
	expect_rect_near(t, ui.quads[1].rect, {10 + 16.154839 + 7.225806 - 4, 45 - 23, 24, 28})
}

@(test)
test_ui_lays_out_a_panel_inside_its_parent_and_the_next_root_after_the_parent :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	outer := ui_rect(40, 40)
	outer.pad = {left = 5, top = 5}
	elements := []Element{ui_panel_of(outer, ui_panel_of(ui_rect(10, 10))), ui_panel_of(ui_rect(20, 20))}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 3) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{0, 0, 40, 40})
	testing.expect_value(t, f.rec.ui_quads[1].rect, [4]f32{5, 5, 10, 10})
	testing.expect_value(t, f.rec.ui_quads[2].rect, [4]f32{40, 0, 20, 20})
	testing.expect_value(t, f.ui.repairs_logged, bit_set[Ui_Repair]{})
}

// A Panel's children list holds refcounted Elements, so the generated release
// procs walk the tree. A long Text string is its own allocation.
@(test)
test_ui_tree_frees_every_allocation_with_the_generated_release_procs :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()

	long := "a string longer than twenty-three bytes"
	inner := Element {
		tag = .Panel,
		payload = {panel = {_0 = ui_box(), _1 = roc_list_from_slice([]Element{ui_text(long, 16), ui_text("ok", 16)})}},
	}
	outer := Element {
		tag = .Panel,
		payload = {panel = {_0 = ui_box(), _1 = roc_list_from_slice([]Element{ui_text(long, 16), inner})}},
	}
	roots := roc_list_from_slice([]Element{outer, ui_text(long, 16)})
	testing.expect_value(t, roc_heap_counters().allocs, 6)

	roc_list_decref(roots)
	testing.expect_value(t, roc_heap_counters(), Roc_Heap_Counters{allocs = 6, deallocs = 6})
}

@(test)
test_ui_draws_a_character_outside_ascii_as_a_question_mark_and_logs_it_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	elements := []Element{ui_text("é", 32)}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 1) {
		return
	}
	expect_rect_near(t, f.rec.ui_quads[0].uv, {178.0 / 256, 64.0 / 287, 200.0 / 256, 93.0 / 287})
	testing.expect_value(t, f.ui.repairs_logged, bit_set[Ui_Repair]{.Bad_Char})
}

@(test)
test_ui_drops_quads_past_the_cap_and_logs_it_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f, quad_capacity = 3)
	defer frame_fixture_destroy_ui(&f)

	elements := []Element{ui_panel_of(ui_rect(10, 10)), ui_text("ABCD", 32)}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 3) {
		return
	}
	testing.expect(t, !f.rec.ui_quads[0].glyph)
	testing.expect(t, f.rec.ui_quads[2].glyph)
	testing.expect_value(t, f.ui.repairs_logged, bit_set[Ui_Repair]{.Quad_Cap})
}

@(test)
test_ui_submits_once_after_the_sky_and_not_at_all_when_empty :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	elements := []Element{ui_panel_of(ui_rect(10, 10))}
	scene := scene_ui(elements)
	scene.sky = frame_fixture_sky(&f)
	frame_fixture_draw(&f, scene, scene, 0)
	testing.expect_value(t, f.rec.ui_calls, 1)
	testing.expect_value(t, f.rec.ui_after_sky, 1)

	frame_fixture_draw(&f, {}, {}, 0)
	testing.expect_value(t, f.rec.ui_calls, 0)
}

@(test)
test_ui_frame_allocates_nothing :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	box := ui_scroll(ui_tagged(1, 100, 100), {0, -4})
	box.floating = ui_floating(.CenterCenter)
	elements := []Element{ui_panel_of(box, ui_text("Keys 3 of 5", 24))}
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)
	context.temp_allocator = mem.tracking_allocator(&track)

	ui_frame(f.ui, elements, f.window)
	ui_frame(f.ui, elements, f.window)
	testing.expect_value(t, track.total_allocation_count, 0)
}

// A rect's uv is its offset from the centre, so the shader can round its corners.
@(test)
test_ui_rect_quad_vertices_carry_the_offset_from_the_centre :: proc(t: ^testing.T) {
	v := ui_quad_vertices({rect = {10, 20, 100, 50}, color = {1, 0, 0, 1}, radius = 8})
	testing.expect_value(t, v[0], Ui_Vertex{pos = {10, 20}, uv = {-50, -25}, color = {1, 0, 0, 1}, shape = {50, 25, 8, 0}})
	testing.expect_value(t, v[1].pos, [2]f32{110, 20})
	testing.expect_value(t, v[1].uv, [2]f32{50, -25})
	testing.expect_value(t, v[2].pos, [2]f32{110, 70})
	testing.expect_value(t, v[2].uv, [2]f32{50, 25})
	testing.expect_value(t, v[3].pos, [2]f32{10, 70})
	testing.expect_value(t, v[3].uv, [2]f32{-50, 25})
}

@(test)
test_ui_glyph_quad_vertices_carry_the_atlas_uv :: proc(t: ^testing.T) {
	v := ui_quad_vertices({rect = {0, 0, 4, 2}, uv = {0.1, 0.2, 0.3, 0.4}, glyph = true})
	testing.expect_value(t, v[0].uv, [2]f32{0.1, 0.2})
	testing.expect_value(t, v[1].uv, [2]f32{0.3, 0.2})
	testing.expect_value(t, v[2].uv, [2]f32{0.3, 0.4})
	testing.expect_value(t, v[3].uv, [2]f32{0.1, 0.4})
	testing.expect_value(t, v[0].shape, [4]f32{0, 0, 0, 1})
}

ui_tagged :: proc(id: u64, width, height: f32) -> Box_Config {
	box := ui_rect(width, height)
	box.id = id
	return box
}

ui_float_box :: proc(id: u64, to: Float_To, attach, on: Attach_Point, offset: [2]f32, width, height: f32) -> Box_Config {
	box := ui_tagged(id, width, height)
	box.floating = {tag = .Float, payload = {float = {to = to, attach = attach, on = on, offset = {x = offset.x, y = offset.y}}}}
	return box
}

// Lays out the roots, then hit tests the pointer, in logical pixels.
ui_test_over :: proc(f: ^Frame_Fixture, roots: []Element, pos: [2]f32, inside := true) -> []u64 {
	ui_frame(f.ui, roots, f.window)
	ui_hit_test(f.ui, {pos = pos, inside = inside}, f.window)
	return f.ui.over[:]
}

expect_over :: proc(t: ^testing.T, got: []u64, want: []u64, loc := #caller_location) {
	testing.expectf(t, slice.equal(got, want), "over %v, want %v", got, want, loc = loc)
}

@(test)
test_ui_clay_id_is_stable_distinct_and_never_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, ui_clay_id(7), ui_clay_id(7))
	testing.expect(t, ui_clay_id(7).id != ui_clay_id(8).id)
	testing.expect(t, ui_clay_id(0).id != 0)
	testing.expect(t, ui_clay_id(1).id != 0)
	testing.expect(t, ui_clay_id(max(u64)).id != 0)
}

@(test)
test_ui_hit_lists_the_tagged_panels_under_the_pointer_innermost_first :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_tagged(1, 200, 200), ui_panel_of(ui_tagged(2, 100, 100), ui_panel_of(ui_rect(50, 50))))}

	expect_over(t, ui_test_over(&f, roots, {10, 10}), {2, 1})
	expect_over(t, ui_test_over(&f, roots, {150, 150}), {1})
	expect_over(t, ui_test_over(&f, roots, {300, 300}), {})
}

@(test)
test_ui_hit_a_tagged_floating_panel_blocks_the_panels_under_it :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element {
		ui_panel_of(ui_tagged(1, 200, 200)),
		ui_panel_of(ui_float_box(3, .Window, .LeftTop, .LeftTop, {50, 50}, 100, 100), ui_panel_of(ui_tagged(4, 20, 20))),
		ui_panel_of(ui_float_box(5, .Window, .LeftTop, .LeftTop, {60, 60}, 100, 100)),
	}

	expect_over(t, ui_test_over(&f, roots, {65, 65}), {5})
	expect_over(t, ui_test_over(&f, roots, {55, 55}), {4, 3})
	expect_over(t, ui_test_over(&f, roots, {180, 180}), {1})
}

@(test)
test_ui_hit_an_open_dropdown_gives_only_the_menu_ids :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	col := ui_box()
	col.direction = .Col
	menu := ui_panel_of(ui_float_box(0, .Parent, .LeftTop, .LeftBottom, {0, 0}, 120, 60), ui_panel_of(ui_tagged(11, 120, 20)))
	roots := []Element{ui_panel_of(col, ui_panel_of(ui_tagged(1, 120, 40), menu), ui_panel_of(ui_tagged(2, 120, 40)))}

	expect_over(t, ui_test_over(&f, roots, {10, 50}), {11})
}

@(test)
test_ui_hit_an_untagged_floating_label_lets_the_pointer_through :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	label := ui_panel_of(ui_float_box(0, .Window, .LeftTop, .LeftTop, {20, 20}, 100, 30), ui_text("Hi", 16))
	roots := []Element{ui_panel_of(ui_tagged(1, 200, 200)), label}

	expect_over(t, ui_test_over(&f, roots, {30, 30}), {1})
}

@(test)
test_ui_has_hit_id_finds_a_tagged_panel_at_any_depth :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	deep := ui_panel_of(ui_box(), ui_panel_of(ui_box(), ui_panel_of(ui_tagged(9, 10, 10))))
	text := ui_panel_of(ui_box(), ui_text("Hi", 16))

	testing.expect(t, ui_has_hit_id(&deep))
	testing.expect(t, !ui_has_hit_id(&text))
}

@(test)
test_ui_hit_with_the_pointer_outside_lists_nothing :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_tagged(1, 100, 100))}

	expect_over(t, ui_test_over(&f, roots, {10, 10}, inside = false), {})
}

@(test)
test_ui_hit_uses_physical_pixels_at_dpi_2 :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.window = {size = {1920, 1080}, dpi = 2}
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_tagged(1, 100, 100))}

	expect_over(t, ui_test_over(&f, roots, {90, 90}), {1})
	expect_over(t, ui_test_over(&f, roots, {110, 110}), {})
}

@(test)
test_ui_repeated_id_hit_tests_the_first_panel_and_logs_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_box(), ui_panel_of(ui_tagged(7, 100, 100)), ui_panel_of(ui_tagged(7, 100, 100)))}

	expect_over(t, ui_test_over(&f, roots, {50, 50}), {7})
	expect_over(t, ui_test_over(&f, roots, {150, 50}), {})
	testing.expect(t, .Duplicate_Id in f.ui.repairs_logged)
	testing.expect(t, .DuplicateId not_in f.ui.errors_logged)
}

ui_clip :: proc(box: Box_Config) -> Box_Config {
	box := box
	box.overflow = {tag = .Clip}
	return box
}

ui_scroll :: proc(box: Box_Config, offset: [2]f32) -> Box_Config {
	box := box
	box.overflow = {tag = .Scroll, payload = {scroll = {x = offset.x, y = offset.y}}}
	return box
}

// A Col of rows Fixed width by 20, in a Scroll Panel Fixed width by height.
ui_scroll_rows :: proc(id: u64, width, height: f32, rows: int) -> Element {
	box := ui_scroll(ui_tagged(id, width, height), {0, 0})
	box.direction = .Col
	children := make([]Element, rows, context.temp_allocator)
	for &row in children {
		row = ui_panel_of(ui_rect(width, 20))
	}
	return ui_panel_of(box, ..children)
}

@(test)
test_ui_clip_cuts_the_children_at_the_panel_edges :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_clip(ui_rect(100, 50)), ui_panel_of(ui_rect(200, 200)))}

	quads := ui_frame(f.ui, roots, f.window)

	if !testing.expect_value(t, len(quads), 2) {
		return
	}
	// Clay opens the scissor before the Panel's own rect, which the clip leaves whole.
	testing.expect_value(t, quads[0].rect, [4]f32{0, 0, 100, 50})
	testing.expect(t, quads[1].clipped)
	testing.expect_value(t, quads[1].clip, [4]f32{0, 0, 100, 50})
}

@(test)
test_ui_scroll_moves_the_children_by_the_offset_in_physical_pixels :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.window = {size = {1920, 1080}, dpi = 2}
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_scroll(ui_tagged(9, 100, 100), {0, -20}), ui_panel_of(ui_rect(100, 300)))}

	quads := ui_frame(f.ui, roots, f.window)

	if !testing.expect_value(t, len(quads), 2) {
		return
	}
	testing.expect_value(t, quads[1].rect.y, -40)
	testing.expect_value(t, quads[1].clip, [4]f32{0, 0, 200, 200})
}

@(test)
test_ui_nested_clips_intersect :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	inner := ui_panel_of(ui_clip(ui_rect(200, 40)), ui_panel_of(ui_rect(300, 300)))
	roots := []Element{ui_panel_of(ui_clip(ui_rect(100, 100)), inner)}

	quads := ui_frame(f.ui, roots, f.window)

	if !testing.expect_value(t, len(quads), 3) {
		return
	}
	testing.expect(t, quads[2].clipped)
	testing.expect_value(t, quads[2].clip, [4]f32{0, 0, 100, 40})
}

@(test)
test_ui_clip_run_end_splits_on_a_clip_change :: proc(t: ^testing.T) {
	small := Ui_Quad{clipped = true, clip = {0, 0, 10, 10}}
	big := Ui_Quad{clipped = true, clip = {0, 0, 20, 20}}
	quads := []Ui_Quad{{}, {}, small, small, small, big}

	testing.expect_value(t, ui_clip_run_end(quads, 0), 2)
	testing.expect_value(t, ui_clip_run_end(quads, 2), 5)
	testing.expect_value(t, ui_clip_run_end(quads, 5), 6)
}

@(test)
test_ui_scroll_sizes_list_each_tagged_scroll_panel_in_logical_pixels :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	f.window = {size = {1920, 1080}, dpi = 2}
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	untagged := ui_panel_of(ui_scroll(ui_rect(50, 50), {0, 0}), ui_panel_of(ui_rect(50, 80)))
	roots := []Element{ui_panel_of(ui_box(), ui_scroll_rows(9, 200, 100, 10), ui_panel_of(ui_clip(ui_tagged(5, 50, 50))), untagged)}

	ui_frame(f.ui, roots, f.window)

	if testing.expect_value(t, len(f.ui.scrolls), 1) {
		testing.expect_value(t, f.ui.scrolls[0], Scroll_Size{id = 9, view = {width = 200, height = 100}, content = {width = 200, height = 200}})
	}
	testing.expect(t, .Scroll_Without_Id in f.ui.repairs_logged)
}

// Clay holds at most 100 clip records, and only its scroll update removes
// the records of Panels that are gone.
@(test)
test_ui_scroll_sizes_stay_right_past_100_scroll_ids :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	for i in 0 ..< 150 {
		id := u64(i + 1)
		roots := []Element{ui_panel_of(ui_scroll(ui_tagged(id, 100, 50), {0, 0}), ui_panel_of(ui_rect(100, 80)))}
		ui_frame(f.ui, roots, f.window)
		if !testing.expectf(t, len(f.ui.scrolls) == 1, "layout %v has %v scroll rows", i, len(f.ui.scrolls)) {
			return
		}
		want := Scroll_Size{id = id, view = {width = 100, height = 50}, content = {width = 100, height = 80}}
		if !testing.expect_value(t, f.ui.scrolls[0], want) {
			return
		}
	}
	testing.expect(t, .InternalError not_in f.ui.errors_logged)
}

@(test)
test_ui_hit_skips_a_child_clipped_out_of_its_panel :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_clip(ui_tagged(1, 100, 100)), ui_panel_of(ui_tagged(2, 100, 300)))}

	expect_over(t, ui_test_over(&f, roots, {50, 50}), {2, 1})
	expect_over(t, ui_test_over(&f, roots, {50, 150}), {})
}

@(test)
test_ui_parent_float_sits_on_the_on_point_of_its_parent :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	root := ui_box()
	root.pad = {left = 100, top = 50}
	menu := ui_panel_of(ui_float_box(8, .Parent, .LeftTop, .LeftBottom, {0, 4}, 120, 30))
	roots := []Element{ui_panel_of(root, ui_panel_of(ui_tagged(7, 120, 40), menu))}

	quads := ui_frame(f.ui, roots, f.window)

	if testing.expect_value(t, len(quads), 2) {
		expect_rect_near(t, quads[1].rect, {100, 94, 120, 30})
	}
	expect_over(t, ui_test_over(&f, roots, {110, 100}), {8})
}

@(test)
test_ui_window_float_with_another_on_point :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_float_box(0, .Window, .CenterCenter, .LeftTop, {0, 0}, 100, 100))}

	quads := ui_frame(f.ui, roots, f.window)

	if testing.expect_value(t, len(quads), 1) {
		expect_rect_near(t, quads[0].rect, {-50, -50, 100, 100})
	}
}

@(test)
test_ui_root_float_to_parent_floats_on_the_window :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)
	roots := []Element{ui_panel_of(ui_float_box(0, .Parent, .RightBottom, .RightBottom, {0, 0}, 100, 100))}

	quads := ui_frame(f.ui, roots, f.window)

	if testing.expect_value(t, len(quads), 1) {
		expect_rect_near(t, quads[0].rect, {860, 440, 100, 100})
	}
}
