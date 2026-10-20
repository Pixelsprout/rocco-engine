package engine

import clay "../clay/bindings/odin/clay-odin"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"

// A u16 index reaches every vertex of a full buffer of this many quads, so
// the Launch check caps capacity.ui_quads here.
UI_QUAD_LIMIT :: (1 << 16) / 4
// Clay's default of 8192 elements is below the largest N of the UI bench game.
UI_ELEMENT_CAPACITY :: 32768
// Clay keeps the same ratio of measured words to elements by default.
UI_TEXT_WORD_CAPACITY :: 2 * UI_ELEMENT_CAPACITY
UI_QUAD_INDICES :: [6]u16{0, 1, 2, 0, 2, 3}

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
// glyph as u0, v0, u1, v1. A rect quad rounds its corners by radius.
Ui_Quad :: struct {
	rect:   [4]f32,
	uv:     [4]f32,
	color:  [4]f32,
	radius: f32,
	glyph:  bool,
}

Ui_Repair :: enum {
	Extra_Close,
	Unclosed_Open,
	Bad_Char,
	Quad_Cap,
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

Ui :: struct {
	memory:        []u8,
	ctx:           ^clay.Context,
	quads:         []Ui_Quad,
	quad_count:    int,
	errors_logged: bit_set[clay.ErrorType],
	repairs_logged: bit_set[Ui_Repair],
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
	arena := clay.CreateArenaWithCapacityAndMemory(uint(capacity), raw_data(ui.memory))
	ui.ctx = clay.Initialize(arena, {size.x, size.y}, {handler = ui_error_cb, userData = ui})
	clay.SetMeasureTextFunction(ui_measure_cb, nil)
	return nil
}

// Lays out elements against the window and returns the quads to draw, in order.
ui_frame :: proc(ui: ^Ui, elements: []Element, window: Ui_Window) -> []Ui_Quad {
	commands := ui_layout(ui, elements, window)
	ui.quad_count = 0
	for &command in commands {
		box := command.boundingBox
		rect := [4]f32{box.x, box.y, box.width, box.height}
		#partial switch command.commandType {
		case .Rectangle:
			r := command.renderData.rectangle
			ui_push(ui, {rect = rect, color = r.backgroundColor, radius = r.cornerRadius.topLeft})
		case .Text:
			ui_push_text(ui, rect, command.renderData.text)
		}
	}
	return ui.quads[:ui.quad_count]
}

// The commands point into Clay's arena and into the elements, so they last until the next layout.
ui_layout :: proc(ui: ^Ui, elements: []Element, window: Ui_Window) -> []clay.RenderCommand {
	clay.SetCurrentContext(ui.ctx)
	clay.SetLayoutDimensions({window.size.x, window.size.y})
	clay.BeginLayout()
	depth := 0
	for &e in elements {
		switch e.tag {
		case .Open:
			clay._OpenElement()
			clay.ConfigureOpenElement(ui_declaration(e.payload.open, window.dpi))
			depth += 1
		case .Text:
			text := &e.payload.text
			clay.TextDynamic(roc_str_string(&text.str), {textColor = ui_color(text.color), fontSize = ui_px(text.size, window.dpi), wrapMode = .Words if text.wrap == .Words else .None})
		case .Close:
			if depth == 0 {
				ui_repair(ui, .Extra_Close)
				continue
			}
			clay._CloseElement()
			depth -= 1
		}
	}
	if depth > 0 {
		ui_repair(ui, .Unclosed_Open)
		for _ in 0 ..< depth {
			clay._CloseElement()
		}
	}
	commands := clay.EndLayout(0)
	return commands.internalArray[:commands.length]
}

ui_declaration :: proc(box: Box_Config, dpi: f32) -> clay.ElementDeclaration {
	d := clay.ElementDeclaration {
		layout = {
			sizing = {width = ui_sizing(box.width, dpi), height = ui_sizing(box.height, dpi)},
			padding = {left = ui_px(box.pad.left, dpi), right = ui_px(box.pad.right, dpi), top = ui_px(box.pad.top, dpi), bottom = ui_px(box.pad.bottom, dpi)},
			childGap = ui_px(box.gap, dpi),
			childAlignment = {x = UI_ALIGN_X[box.child_align.x], y = UI_ALIGN_Y[box.child_align.y]},
			layoutDirection = .LeftToRight if box.direction == .Row else .TopToBottom,
		},
		backgroundColor = ui_color(box.background),
		cornerRadius = clay.CornerRadiusAll(box.radius * dpi),
	}
	if box.floating.tag == .Float {
		f := box.floating.payload.float
		point := UI_ATTACH[f.attach]
		d.floating = {offset = {f.offset.x * dpi, f.offset.y * dpi}, attachTo = .Root, attachment = {element = point, parent = point}}
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
	baseline := rect.y + FONT_ASCENT * scale
	pen := Font_Pen{text = str}
	for g, pen_x, replaced in font_pen_next(&pen) {
		if replaced {
			ui_repair(ui, .Bad_Char)
		}
		if g.rect.z > 0 {
			x, y, w, h := f32(g.rect.x), f32(g.rect.y), f32(g.rect.z), f32(g.rect.w)
			ui_push(ui, {
				rect = {rect.x + (pen_x + f32(g.bearing.x)) * scale, baseline + f32(g.bearing.y) * scale, w * scale, h * scale},
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
	case .Extra_Close:
		fmt.eprintln("a Scene's ui has a Close with no open Box; the host ignores it")
	case .Unclosed_Open:
		fmt.eprintln("a Scene's ui ends with a Box still open; the host closes it")
	case .Bad_Char:
		fmt.eprintfln("a Text has a character outside ASCII %v to %v; the host draws ?", FONT_FIRST, FONT_LAST)
	case .Quad_Cap:
		fmt.eprintfln("a Scene's ui needs more than %v quads; the host drops the rest", len(ui.quads))
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
