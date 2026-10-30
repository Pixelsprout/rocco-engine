import Font

# These types copy pf.Vocabulary. Keep them identical, or a BoxConfig or a
# Text from here stops unifying with the one in an Element.
## Defaults and small helpers for the UI tree in `Scene.ui`. A game writes the
## Element tags itself, `Box(config, children)` and `Text(text)`, and takes the
## config and the Text from here. The types have the same shapes as the UI
## types in `Vocabulary`. Sizes are in logical pixels.
##
## For example, `Box(Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), [Text(Ui.label("Score"))])`
## puts one line of text in the top-left corner of the window.
Ui := [].{

	## The space between a Box's edges and its children.
	Padding : { left : F32, right : F32, top : F32, bottom : F32 }

	## A distance from an AttachPoint.
	Offset : { x : F32, y : F32 }

	## A colour with linear channels from 0 to 1. Alpha is not premultiplied.
	Rgba : { r : F32, g : F32, b : F32, a : F32 }

	## How a Box sizes along one axis. See `Vocabulary.Sizing`.
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]

	## Where a Box puts its children along one axis.
	Align : [Start, Center, End]

	## The point of a floating Box that the host puts on the same point of the
	## window.
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]

	## The layout and look of a Box. Start from `default_box`. See
	## `Vocabulary.BoxConfig`.
	BoxConfig : { width : Sizing, height : Sizing, pad : Padding, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, floating : [NoFloat, Float({ attach : AttachPoint, offset : Offset })] }

	## One string at a size and a colour. Start from `default_text` or `label`.
	## See `Vocabulary.Text`.
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }

	## Clay's defaults: fits its children, no padding, no gap, a `Row`, children
	## at the start, no background, square corners and not floating.
	default_box : BoxConfig
	default_box = {
		width: Fit({ min: 0.0, max: 0.0 }),
		height: Fit({ min: 0.0, max: 0.0 }),
		pad: { left: 0.0, right: 0.0, top: 0.0, bottom: 0.0 },
		gap: 0.0,
		direction: Row,
		child_align: { x: Start, y: Start },
		background: { r: 0.0, g: 0.0, b: 0.0, a: 0.0 },
		radius: 0.0,
		floating: NoFloat,
	}

	## An empty string, 24 pixels high, opaque white, that breaks lines between
	## words.
	default_text : Text
	default_text = { str: "", size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

	## A `default_text` that shows `str`.
	label : Str -> Text
	label = |str| { ..default_text, str }

	## A `default_box` that floats to the window. It puts its own `attach` point
	## on the window's, then moves by `offset`. It ignores its parent's layout.
	float_at : AttachPoint, Offset -> BoxConfig
	float_at = |attach, offset| { ..default_box, floating: Float({ attach, offset }) }

	## A `float_at` Box for a HUD: 8 pixels of padding, a black background at
	## half alpha and corners with a radius of 8.
	panel : AttachPoint, Offset -> BoxConfig
	panel = |attach, offset| { ..float_at(attach, offset), pad: pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }

	## The same padding on all four sides.
	pad_all : F32 -> Padding
	pad_all = |n| { left: n, right: n, top: n, bottom: n }

	## The size of one line of `text` at `size`, in logical pixels, as the host
	## measures it. A newline measures as `?`, so use `wrap` for more than one
	## line. The host rounds `size` times the DPI scale to whole pixels, so a
	## fractional size, or a whole size at a fractional DPI scale, can drift
	## from the drawn text by a fraction of a pixel per character. Use
	## whole-pixel sizes.
	measure : Str, F32 -> { width : F32, height : F32 }
	measure = |text, size| {
		scale = size / Font.bake_size
		{ width: pen_width(Str.to_utf8(text)) * scale, height: Font.line_height * scale }
	}
}

# The pen walks a line the way font_pen_next does in engine/font.odin. x is in
# pixels at Font.bake_size.
Pen : { x : F32, prev : [LineStart, After(U8)] }

pen_start : Pen
pen_start = { x: 0.0, prev: LineStart }

# Takes one byte of UTF-8. A character outside the font stands in as '?', so a
# continuation byte adds nothing. The kern goes before the advance, as in the host.
pen_byte : Pen, U8 -> Pen
pen_byte = |pen, byte|
	if byte.bitwise_and(0xC0) == 0x80 {
		pen
	} else {
		char = if (byte >= Font.first and byte <= Font.last) byte else '?'
		kerned = match pen.prev {
			LineStart => pen.x
			After(prev) => pen.x + kern(prev, char)
		}
		{ x: kerned + advance(char), prev: After(char) }
	}

pen_width : List(U8) -> F32
pen_width = |bytes| bytes.fold(pen_start, pen_byte).x

advance : U8 -> F32
advance = |char| match Font.advances.get((char - Font.first).to_u64()) {
	Ok(found) => found
	Err(_) => crash "Ui.advance: a font character is inside the table"
}

kern : U8, U8 -> F32
kern = |first, second| match Font.kerns.get((first - Font.first).to_u64()) {
	Ok(row) => row.find_first(|pair| pair.second == second).map_ok(|pair| pair.advance) ?? 0.0
	Err(_) => crash "Ui.kern: a font character is inside the table"
}

expect Ui.label("Keys") == { str: "Keys", size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

expect Ui.label("") == Ui.default_text

expect Ui.float_at(RightBottom, { x: 16.0, y: 8.0 }) == { ..Ui.default_box, floating: Float({ attach: RightBottom, offset: { x: 16.0, y: 8.0 } }) }

expect Ui.panel(LeftTop, { x: 16.0, y: 16.0 }) == {
	width: Fit({ min: 0.0, max: 0.0 }),
	height: Fit({ min: 0.0, max: 0.0 }),
	pad: { left: 8.0, right: 8.0, top: 8.0, bottom: 8.0 },
	gap: 0.0,
	direction: Row,
	child_align: { x: Start, y: Start },
	background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 },
	radius: 8.0,
	floating: Float({ attach: LeftTop, offset: { x: 16.0, y: 16.0 } }),
}

expect Ui.pad_all(4.0) == { left: 4.0, right: 4.0, top: 4.0, bottom: 4.0 }

## One glyph at the bake size measures its advance and one line height.
expect Ui.measure("A", 32.0) == { width: 16.154839, height: 32.0 }

## The width and the height scale with the size.
expect Ui.measure("A", 16.0) == { width: 16.154839 / 2.0, height: 16.0 }

## A kern pair moves the next glyph. A pair with no kern adds nothing.
expect {
	a : F32
	a = 16.154839
	av_kern : F32
	av_kern = -1.7290323
	Ui.measure("AV", 32.0).width == a + av_kern + 15.2 and Ui.measure("AB", 32.0).width == a + 15.974194
}

## An empty string is zero wide and one line high.
expect Ui.measure("", 32.0) == { width: 0.0, height: 32.0 }

## A character outside the font measures as a question mark.
expect {
	question = Ui.measure("?", 32.0)
	[Ui.measure("é", 32.0), Ui.measure("\t", 32.0), Ui.measure("\u(7f)", 32.0)] == [question, question, question]
		and Ui.measure("A€", 32.0) == Ui.measure("A?", 32.0)
}
