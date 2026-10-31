package engine

import clay "../clay/bindings/odin/clay-odin"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"

// A u16 index reaches every vertex of a full buffer of this many quads, so
// the Launch check caps capacity.ui_quads here.
UI_QUAD_LIMIT :: (1 << 16) / 4
// Clay's default of 8192 elements is below the largest N of the UI bench game.
UI_ELEMENT_CAPACITY :: 32768
// Clay keeps the same ratio of measured words to elements by default.
UI_TEXT_WORD_CAPACITY :: 2 * UI_ELEMENT_CAPACITY
UI_QUAD_INDICES :: [6]u16{0, 1, 2, 0, 2, 3}
// A Scene with more tagged Panels than this grows the map once.
UI_HIT_CAPACITY :: 256
// A Scene with more nested clips or Scroll Panels than this grows the lists once.
UI_CLIP_CAPACITY :: 16

// The vocabulary and Clay name the nine points alike, but the glue orders the tags by name.
@(rodata)
UI_ATTACH := [Attach_Point]clay.FloatingAttachPointType {
	.LeftTop      = .LeftTop,
	.LeftCenter   = .LeftCenter,
	.LeftBottom   = .LeftBottom,
	.CenterTop    = .CenterTop,
	.CenterCenter = .CenterCenter,
	.CenterBottom = .CenterBottom,
	.RightTop     = .RightTop,
	.RightCenter  = .RightCenter,
	.RightBottom  = .RightBottom,
}

@(rodata)
UI_ALIGN_X := [Align]clay.LayoutAlignmentX {
	.Start  = .Left,
	.Center = .Center,
	.End    = .Right,
}

@(rodata)
UI_ALIGN_Y := [Align]clay.LayoutAlignmentY {
	.Start  = .Top,
	.Center = .Center,
	.End    = .Bottom,
}

// rect is x, y, width, height in window pixels. uv is the atlas rect of a
// glyph as u0, v0, u1, v1. A rect quad rounds its corners by radius. A
// clipped quad draws only inside clip, in window pixels.
Ui_Quad :: struct {
	rect:    [4]f32,
	uv:      [4]f32,
	color:   [4]f32,
	clip:    [4]f32,
	radius:  f32,
	glyph:   bool,
	clipped: bool,
}

Ui_Repair :: enum {
	Bad_Char,
	Quad_Cap,
	Duplicate_Id,
	Scroll_Without_Id,
}

// shape is the half size and corner radius of a rect, and w is 1 for a glyph.
Ui_Vertex :: struct {
	pos:   [2]f32,
	uv:    [2]f32,
	color: [4]f32,
	shape: [4]f32,
}

// size is in window pixels. dpi is the pixels per logical pixel.
Ui_Window :: struct {
	size: [2]f32,
	dpi:  f32,
}

// The pointer of the last step, in logical pixels.
Ui_Pointer :: struct {
	pos:    [2]f32,
	inside: bool,
}

// A tagged Panel of the last layout. layer is 0 for the window root, and a new
// number for each floating Panel, in walk order. The Panels inside a floating
// Panel share its layer.
Ui_Hit_Panel :: struct {
	id:    u64,
	layer: u32,
}

Ui_Scroll_Panel :: struct {
	id:      u64,
	clay_id: clay.ElementId,
}

Ui :: struct {
	memory:         []u8,
	ctx:            ^clay.Context,
	quads:          []Ui_Quad,
	quad_count:     int,
	errors_logged:  bit_set[clay.ErrorType],
	repairs_logged: bit_set[Ui_Repair],
	// Keyed by Clay id. ui_layout refills it.
	hits:           map[u32]Ui_Hit_Panel,
	layers:         u32,
	// The game ids under the pointer, innermost first. ui_hit_test fills it.
	over:           [dynamic]u64,
	// The tagged Scroll Panels of the last layout, and their sizes after it.
	scroll_panels:  [dynamic]Ui_Scroll_Panel,
	scrolls:        [dynamic]Scroll_Size,
	// The scissor stack while ui_frame reads the commands.
	clips:          [dynamic][4]f32,
}

// The window size that the game gets in Input, in logical pixels.
ui_window_logical :: proc(window: Ui_Window) -> [2]f32 {
	return window.size / window.dpi
}

// The arena lives as long as the allocator, so there is no ui_destroy.
ui_init :: proc(ui: ^Ui, size: [2]f32, quad_capacity: int, allocator: mem.Allocator) -> mem.Allocator_Error {
	// Clay sets these on the current context, or on its defaults when there is
	// none. Initialize copies them from either, so set both before sizing.
	clay.SetMaxElementCount(UI_ELEMENT_CAPACITY)
	clay.SetMaxMeasureTextCacheWordCount(UI_TEXT_WORD_CAPACITY)
	capacity := clay.MinMemorySize()
	ui.memory = make([]u8, capacity, allocator) or_return
	ui.quads = make([]Ui_Quad, quad_capacity, allocator) or_return
	ui.hits = make(map[u32]Ui_Hit_Panel, UI_HIT_CAPACITY, allocator) or_return
	ui.over = make([dynamic]u64, 0, UI_HIT_CAPACITY, allocator) or_return
	ui.scroll_panels = make([dynamic]Ui_Scroll_Panel, 0, UI_CLIP_CAPACITY, allocator) or_return
	ui.scrolls = make([dynamic]Scroll_Size, 0, UI_CLIP_CAPACITY, allocator) or_return
	ui.clips = make([dynamic][4]f32, 0, UI_CLIP_CAPACITY, allocator) or_return
	arena := clay.CreateArenaWithCapacityAndMemory(uint(capacity), raw_data(ui.memory))
	ui.ctx = clay.Initialize(arena, {size.x, size.y}, {handler = ui_error_cb, userData = ui})
	clay.SetMeasureTextFunction(ui_measure_cb, nil)
	return nil
}

// Lays out the trees under roots against the window and returns the quads to draw, in order.
ui_frame :: proc(ui: ^Ui, roots: []Element, window: Ui_Window) -> []Ui_Quad {
	commands := ui_layout(ui, roots, window)
	ui.quad_count = 0
	clear(&ui.clips)
	for &command in commands {
		box := command.boundingBox
		rect := [4]f32{box.x, box.y, box.width, box.height}
		#partial switch command.commandType {
		case .Rectangle:
			r := command.renderData.rectangle
			ui_push(ui, {rect = rect, color = r.backgroundColor, radius = r.cornerRadius.topLeft})
		case .Text:
			ui_push_text(ui, rect, command.renderData.text)
		case .ScissorStart:
			outer := [4]f32{0, 0, window.size.x, window.size.y}
			if len(ui.clips) > 0 {
				outer = ui.clips[len(ui.clips) - 1]
			}
			append(&ui.clips, ui_rect_intersect(rect, outer))
		case .ScissorEnd:
			if len(ui.clips) > 0 {
				pop(&ui.clips)
			}
		}
	}
	return ui.quads[:ui.quad_count]
}

// Never negative in size, so an empty overlap is a valid scissor rect.
ui_rect_intersect :: proc(a, b: [4]f32) -> [4]f32 {
	x0, y0 := max(a.x, b.x), max(a.y, b.y)
	x1, y1 := min(a.x + a.z, b.x + b.z), min(a.y + a.w, b.y + b.w)
	return {x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}
}

// The end of the run of quads that share clipped and clip with quads[start].
ui_clip_run_end :: proc(quads: []Ui_Quad, start: int) -> (end: int) {
	end = start + 1
	for end < len(quads) && quads[end].clipped == quads[start].clipped && quads[end].clip == quads[start].clip {
		end += 1
	}
	return end
}

// The commands point into Clay's arena and into the roots, so they last until the next layout.
ui_layout :: proc(ui: ^Ui, roots: []Element, window: Ui_Window) -> []clay.RenderCommand {
	clay.SetCurrentContext(ui.ctx)
	clay.SetLayoutDimensions({window.size.x, window.size.y})
	clear(&ui.hits)
	clear(&ui.scroll_panels)
	clear(&ui.scrolls)
	ui.layers = 0
	clay.BeginLayout()
	for &e in roots {
		ui_layout_element(ui, &e, window.dpi, 0)
	}
	commands := clay.EndLayout(0)
	for panel in ui.scroll_panels {
		data := clay.GetScrollContainerData(panel.clay_id)
		if data.found {
			view, content := data.scrollContainerDimensions, data.contentDimensions
			append(&ui.scrolls, Scroll_Size{id = panel.id, view = {width = view.width / window.dpi, height = view.height / window.dpi}, content = {width = content.width / window.dpi, height = content.height / window.dpi}})
		}
	}
	// Clay holds at most 100 clip records, and only its scroll update removes
	// them. The first call removes the records of Panels that are gone and
	// marks the rest, and the second removes the rest. A record kept into the
	// next layout points at a reused element and takes a new Panel's sizes.
	// Drag is off and the delta is zero, so neither call moves anything.
	clay.UpdateScrollContainers(false, {0, 0}, 0)
	clay.UpdateScrollContainers(false, {0, 0}, 0)
	return commands.internalArray[:commands.length]
}

ui_layout_element :: proc(ui: ^Ui, e: ^Element, dpi: f32, layer: u32) {
	switch e.tag {
	case .Panel:
		config, children := e.payload.panel._0, e.payload.panel._1
		layer := layer
		if config.floating.tag == .Float {
			ui.layers += 1
			layer = ui.layers
		}
		clay_id, tagged := ui_open_panel(ui, config.id, layer)
		if config.overflow.tag == .Scroll {
			if config.id == 0 {
				ui_repair(ui, .Scroll_Without_Id)
			} else if tagged {
				append(&ui.scroll_panels, Ui_Scroll_Panel{id = config.id, clay_id = clay_id})
			}
		}
		d := ui_declaration(config, dpi)
		if config.floating.tag == .Float {
			// Clay reads the mode when the Panel opens, before its children.
			d.floating.pointerCaptureMode = .Capture if ui_has_hit_id(e) else .Passthrough
		}
		clay.ConfigureOpenElement(d)
		for &child in children.elements[:children.length] {
			ui_layout_element(ui, &child, dpi, layer)
		}
		clay._CloseElement()
	case .Text:
		text := &e.payload.text
		clay.TextDynamic(roc_str_string(&text.str), {textColor = ui_color(text.color), fontSize = ui_px(text.size, dpi), wrapMode = .Words if text.wrap == .Words else .None})
	}
}

// A repeated id opens with Clay's automatic id, so Clay never sees it twice.
@(private = "file")
ui_open_panel :: proc(ui: ^Ui, id: u64, layer: u32) -> (clay_id: clay.ElementId, tagged: bool) {
	if id == 0 {
		clay._OpenElement()
		return
	}
	clay_id = ui_clay_id(id)
	if clay_id.id in ui.hits {
		ui_repair(ui, .Duplicate_Id)
		clay._OpenElement()
		return
	}
	ui.hits[clay_id.id] = {id = id, layer = layer}
	clay._OpenElementWithId(clay_id)
	return clay_id, true
}

// The splitmix64 finalizer folded to 32 bits. Two ids that fold to one Clay id
// count as a repeat. Clay's ids are never 0.
ui_clay_id :: proc(id: u64) -> clay.ElementId {
	z := id
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	z ~= z >> 31
	folded := u32(z) ~ u32(z >> 32)
	return {id = folded if folded != 0 else 1}
}

ui_has_hit_id :: proc(e: ^Element) -> bool {
	if e.tag != .Panel {
		return false
	}
	if e.payload.panel._0.id != 0 {
		return true
	}
	children := e.payload.panel._1
	for &child in children.elements[:children.length] {
		if ui_has_hit_id(&child) {
			return true
		}
	}
	return false
}

// Runs after ui_layout and before the next one. Clay walks the roots from the
// top one down, a parent before its child, and stops after the first Capture
// root under the pointer. Reversing each layer's run gives innermost first.
ui_hit_test :: proc(ui: ^Ui, pointer: Ui_Pointer, window: Ui_Window) {
	clear(&ui.over)
	if !pointer.inside {
		return
	}
	clay.SetCurrentContext(ui.ctx)
	clay.SetPointerState(pointer.pos * window.dpi, false)
	ids := clay.GetPointerOverIds()
	run_start := 0
	run_layer: u32
	for clay_id in ids.internalArray[:ids.length] {
		hit, ok := ui.hits[clay_id.id]
		if !ok {
			continue
		}
		if len(ui.over) > run_start && hit.layer != run_layer {
			slice.reverse(ui.over[run_start:])
			run_start = len(ui.over)
		}
		run_layer = hit.layer
		append(&ui.over, hit.id)
	}
	slice.reverse(ui.over[run_start:])
}

// Empty lists allocate nothing.
ui_results :: proc(ui: ^Ui) -> Ui_Results {
	return {over = roc_list_from_slice(ui.over[:]), scroll = roc_list_from_slice(ui.scrolls[:])}
}

ui_declaration :: proc(config: Panel_Config, dpi: f32) -> clay.ElementDeclaration {
	d := clay.ElementDeclaration {
		layout = {
			sizing = {width = ui_sizing(config.width, dpi), height = ui_sizing(config.height, dpi)},
			padding = {left = ui_px(config.pad.left, dpi), right = ui_px(config.pad.right, dpi), top = ui_px(config.pad.top, dpi), bottom = ui_px(config.pad.bottom, dpi)},
			childGap = ui_px(config.gap, dpi),
			childAlignment = {x = UI_ALIGN_X[config.child_align.x], y = UI_ALIGN_Y[config.child_align.y]},
			layoutDirection = .LeftToRight if config.direction == .Row else .TopToBottom,
		},
		backgroundColor = ui_color(config.background),
		cornerRadius = clay.CornerRadiusAll(config.radius * dpi),
	}
	switch config.overflow.tag {
	case .Visible:
	case .Clip:
		d.clip = {horizontal = true, vertical = true}
	case .Scroll:
		offset := config.overflow.payload.scroll
		d.clip = {horizontal = true, vertical = true, childOffset = {offset.x * dpi, offset.y * dpi}}
	}
	if config.floating.tag == .Float {
		f := config.floating.payload.float
		// clipTo stays None, so a menu that floats out of a Scroll Panel is not cut.
		d.floating = {
			offset = {f.offset.x * dpi, f.offset.y * dpi},
			attachTo = .Root if f.to == .Window else .Parent,
			attachment = {element = UI_ATTACH[f.attach], parent = UI_ATTACH[f.on]},
		}
	}
	return d
}

// A max of 0 is Clay's no limit, and stays 0 when scaled.
ui_sizing :: proc(s: Sizing, dpi: f32) -> clay.SizingAxis {
	switch s.tag {
	case .Fit:
		return clay.SizingFit({s.payload.fit.min * dpi, s.payload.fit.max * dpi})
	case .Grow:
		return clay.SizingGrow({s.payload.grow.min * dpi, s.payload.grow.max * dpi})
	case .Fixed:
		return clay.SizingFixed(s.payload.fixed * dpi)
	case .Percent:
		return clay.SizingPercent(s.payload.percent)
	}
	return {}
}

// Clay takes padding and gaps in whole pixels.
ui_px :: proc(v, dpi: f32) -> u16 {
	return u16(clamp(math.round(v * dpi), 0, f32(max(u16))))
}

// The glue orders Rgba's fields by name.
ui_color :: proc(c: Rgba) -> clay.Color {
	return {c.r, c.g, c.b, c.a}
}

// rect is one line of text. Clay has already split the lines.
ui_push_text :: proc(ui: ^Ui, rect: [4]f32, text: clay.TextRenderData) {
	str := string(text.stringContents.chars[:text.stringContents.length])
	scale := f32(text.fontSize) / FONT_BAKE_SIZE
	// A whole-pixel origin puts a glyph at the bake size on the atlas texel grid.
	origin_x := math.round(rect.x)
	baseline := math.round(rect.y + FONT_ASCENT * scale)
	pen := Font_Pen{text = str}
	for g, pen_x, replaced in font_pen_next(&pen) {
		if replaced {
			ui_repair(ui, .Bad_Char)
		}
		if g.rect.z > 0 {
			x, y, w, h := f32(g.rect.x), f32(g.rect.y), f32(g.rect.z), f32(g.rect.w)
			ui_push(ui, {
				rect = {origin_x + (pen_x + f32(g.bearing.x)) * scale, baseline + f32(g.bearing.y) * scale, w * scale, h * scale},
				uv = {x / FONT_ATLAS_WIDTH, y / FONT_ATLAS_HEIGHT, (x + w) / FONT_ATLAS_WIDTH, (y + h) / FONT_ATLAS_HEIGHT},
				color = text.textColor,
				glyph = true,
			})
		}
	}
}

// Corners go clockwise from the top left. UI_QUAD_INDICES draws them as two triangles.
ui_quad_vertices :: proc(q: Ui_Quad) -> [4]Ui_Vertex {
	x0, y0 := q.rect.x, q.rect.y
	x1, y1 := x0 + q.rect.z, y0 + q.rect.w
	uv, shape: [4]f32
	if q.glyph {
		uv = q.uv
		shape = {0, 0, 0, 1}
	} else {
		half := q.rect.zw / 2
		uv = {-half.x, -half.y, half.x, half.y}
		shape = {half.x, half.y, q.radius, 0}
	}
	return {
		{pos = {x0, y0}, uv = {uv[0], uv[1]}, color = q.color, shape = shape},
		{pos = {x1, y0}, uv = {uv[2], uv[1]}, color = q.color, shape = shape},
		{pos = {x1, y1}, uv = {uv[2], uv[3]}, color = q.color, shape = shape},
		{pos = {x0, y1}, uv = {uv[0], uv[3]}, color = q.color, shape = shape},
	}
}

ui_repair :: proc(ui: ^Ui, repair: Ui_Repair) {
	if repair in ui.repairs_logged {
		return
	}
	ui.repairs_logged += {repair}
	switch repair {
	case .Bad_Char:
		fmt.eprintfln("a Text has a character outside ASCII %v to %v; the host draws ?", FONT_FIRST, FONT_LAST)
	case .Quad_Cap:
		fmt.eprintfln("a Scene's ui needs more than %v quads; the host drops the rest", len(ui.quads))
	case .Duplicate_Id:
		fmt.eprintln("two Panels in a Scene's ui share an id; the host hit tests only the first")
	case .Scroll_Without_Id:
		fmt.eprintln("a Scroll Panel has id 0; the host scrolls it but lists no sizes for it")
	}
}

ui_measure_cb :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, user_data: rawptr) -> clay.Dimensions {
	context = runtime.default_context()
	size := font_measure(string(text.chars[:text.length]), f32(config.fontSize))
	return {size.x, size.y}
}

ui_push :: proc(ui: ^Ui, quad: Ui_Quad) {
	if ui.quad_count == len(ui.quads) {
		ui_repair(ui, .Quad_Cap)
		return
	}
	quad := quad
	if len(ui.clips) > 0 {
		quad.clip = ui.clips[len(ui.clips) - 1]
		quad.clipped = true
	}
	ui.quads[ui.quad_count] = quad
	ui.quad_count += 1
}

ui_error_mark_logged :: proc(ui: ^Ui, kind: clay.ErrorType) -> bool {
	if kind in ui.errors_logged {
		return false
	}
	ui.errors_logged += {kind}
	return true
}

ui_error_cb :: proc "c" (data: clay.ErrorData) {
	context = runtime.default_context()
	ui := (^Ui)(data.userData)
	if ui_error_mark_logged(ui, data.errorType) {
		fmt.eprintfln("clay %v: %s", data.errorType, string(data.errorText.chars[:data.errorText.length]))
	}
}
