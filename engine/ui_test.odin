#+test
package engine

import clay "../clay/bindings/odin/clay-odin"
import "core:mem"
import vmem "core:mem/virtual"
import "core:sync"
import "core:testing"

RED :: Rgba{r = 1, a = 1}

// Clay keeps one current context for the process, and the test runner runs
// tests on several threads. Every test that calls Clay holds this lock.
g_clay_lock: sync.Mutex

// Holds g_clay_lock until frame_fixture_destroy_ui. A test that panics skips
// the unlock and blocks every later Clay test, so check a length before indexing.
frame_fixture_init_ui :: proc(f: ^Frame_Fixture, quad_capacity := UI_QUAD_CAPACITY) {
	sync.mutex_lock(&g_clay_lock)
	f.ui = new(Ui)
	err := ui_init(f.ui, f.window.size, context.allocator, quad_capacity)
	assert(err == nil)
}

// Clay_Initialize reads the current context, so it must not point at freed memory.
frame_fixture_destroy_ui :: proc(f: ^Frame_Fixture) {
	clay.SetCurrentContext(nil)
	delete(f.ui.memory)
	delete(f.ui.quads)
	free(f.ui)
	sync.mutex_unlock(&g_clay_lock)
}

scene_ui :: proc(elements: []Element) -> Scene {
	return {ui = {elements = raw_data(elements), length = uint(len(elements))}}
}

// The glue orders tags by name, so a zero Box_Config floats and is not the vocabulary's default.
ui_box :: proc() -> Box_Config {
	return {floating = {tag = .NoFloat}, direction = .Row, child_align = {.Start, .Start}}
}

ui_open :: proc(config: Box_Config) -> Element {
	e := Element{payload = {open = config}}
	e.tag = .Open
	return e
}

ui_close :: proc() -> Element {
	return {tag = .Close}
}

ui_fixed :: proc(v: f32) -> Sizing {
	return {tag = .Fixed, payload = {fixed = v}}
}

ui_floating :: proc(attach: Attach_Point) -> Floating {
	return {tag = .Float, payload = {float = {attach = attach}}}
}

ui_text :: proc(str: string, size: f32) -> Element {
	e := Element{payload = {text = {str = roc_str_from_slice(str), size = size, color = RED, wrap = .Words}}}
	e.tag = .Text
	return e
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
	err := ui_init(&ui, {960, 540}, vmem.arena_allocator(&arena))
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(ui.memory), int(clay.MinMemorySize()))
	testing.expect(t, ui.ctx != nil)
}

@(test)
test_ui_box_floating_at_right_bottom_sits_in_that_corner_at_two_window_sizes :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	box := ui_rect(100, 50)
	box.floating = ui_floating(.RightBottom)
	elements := []Element{ui_open(box), ui_close()}
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
	box.floating = {tag = .Float, payload = {float = {attach = .RightBottom, offset = {x = -10, y = -20}}}}
	elements := []Element{ui_open(box), ui_close()}
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
	elements := []Element{ui_open(box), ui_text("A B", 32), ui_close()}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)

	if !testing.expect_value(t, len(f.rec.ui_quads), 2) {
		return
	}
	a, b := f.rec.ui_quads[0], f.rec.ui_quads[1]
	baseline := 20 + f32(24.516129)
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
	expect_rect_near(t, f.rec.ui_quads[0].rect, {-5, 24.516129 - 23, 26, 28})
}

@(test)
test_ui_ignores_a_close_with_no_open_box_and_logs_it_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	elements := []Element{ui_close(), ui_open(ui_rect(10, 10)), ui_close(), ui_close(), ui_open(ui_rect(20, 20)), ui_close()}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 2) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{0, 0, 10, 10})
	testing.expect_value(t, f.rec.ui_quads[1].rect, [4]f32{10, 0, 20, 20})
	testing.expect_value(t, f.ui.repairs_logged, bit_set[Ui_Repair]{.Extra_Close})
}

@(test)
test_ui_closes_a_box_still_open_at_the_end_and_logs_it_once :: proc(t: ^testing.T) {
	f: Frame_Fixture
	frame_fixture_init(&f)
	defer frame_fixture_destroy(&f)
	frame_fixture_init_ui(&f)
	defer frame_fixture_destroy_ui(&f)

	outer := ui_rect(40, 40)
	outer.pad = {left = 5, top = 5}
	elements := []Element{ui_open(outer), ui_open(ui_rect(10, 10))}
	scene := scene_ui(elements)
	frame_fixture_draw(&f, scene, scene, 0)
	frame_fixture_draw(&f, scene, scene, 0)
	if !testing.expect_value(t, len(f.rec.ui_quads), 2) {
		return
	}
	testing.expect_value(t, f.rec.ui_quads[0].rect, [4]f32{0, 0, 40, 40})
	testing.expect_value(t, f.rec.ui_quads[1].rect, [4]f32{5, 5, 10, 10})
	testing.expect_value(t, f.ui.repairs_logged, bit_set[Ui_Repair]{.Unclosed_Open})
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

	elements := []Element{ui_open(ui_rect(10, 10)), ui_close(), ui_text("ABCD", 32)}
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

	elements := []Element{ui_open(ui_rect(10, 10)), ui_close()}
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

	box := ui_rect(100, 100)
	box.floating = ui_floating(.CenterCenter)
	elements := []Element{ui_open(box), ui_text("Keys 3 of 5", 24), ui_close()}
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
