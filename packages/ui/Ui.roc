# These types copy pf.Vocabulary. Keep them identical, or Scene.ui stops unifying.
## Builds the flat list of Elements in `Scene.ui` from nested code. The types
## have the same shapes as the UI types in `Vocabulary`. Sizes are in logical
## pixels.
##
## For example, `Ui.box(Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), [Ui.text("Score", style)])`
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

	## One string at a size and a colour. Build one with `text`.
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }

	## The size, colour and wrap mode that `text` gives a string.
	TextStyle : { size : F32, color : Rgba, wrap : [Words, None] }

	## One entry in `Scene.ui`: an `Open`, a `Text` or a `Close`.
	Element : [Open(BoxConfig), Text(Text), Close]

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

	## A `default_box` that floats to the window. It puts its own `attach` point
	## on the window's, then moves by `offset`. It ignores its parent's layout.
	float_at : AttachPoint, Offset -> BoxConfig
	float_at = |attach, offset| { ..default_box, floating: Float({ attach, offset }) }

	## The same padding on all four sides.
	pad_all : F32 -> Padding
	pad_all = |n| { left: n, right: n, top: n, bottom: n }

	## A Box around its children. Each child is a list of Elements, so boxes
	## and text mix in one list.
	box : BoxConfig, List(List(Element)) -> List(Element)
	box = |config, children| [Open(config)].concat(List.join(children)).append(Close)

	## One string in the engine's font.
	text : Str, TextStyle -> List(Element)
	text = |str, style| [Text({ str, size: style.size, color: style.color, wrap: style.wrap })]
}

style : Ui.TextStyle
style = { size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

panel : Ui.BoxConfig
panel = { ..Ui.default_box, gap: 8.0 }

expect Ui.text("Keys", style) == [Text({ str: "Keys", size: 24.0, color: style.color, wrap: Words })]

expect Ui.box(panel, []) == [Open(panel), Close]

expect {
	Ui.box(panel, [Ui.text("a", style), Ui.box(Ui.default_box, [Ui.text("b", style)]), Ui.text("c", style)])
		== [
			Open(panel),
			Text({ str: "a", size: 24.0, color: style.color, wrap: Words }),
			Open(Ui.default_box),
			Text({ str: "b", size: 24.0, color: style.color, wrap: Words }),
			Close,
			Text({ str: "c", size: 24.0, color: style.color, wrap: Words }),
			Close,
		]
}

expect Ui.float_at(RightBottom, { x: 16.0, y: 8.0 }) == { ..Ui.default_box, floating: Float({ attach: RightBottom, offset: { x: 16.0, y: 8.0 } }) }

expect Ui.pad_all(4.0) == { left: 4.0, right: 4.0, top: 4.0, bottom: 4.0 }
