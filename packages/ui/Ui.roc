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
}

expect Ui.label("Keys") == { str: "Keys", size: 24.0, color: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }, wrap: Words }

expect Ui.label("") == Ui.default_text

expect Ui.float_at(RightBottom, { x: 16.0, y: 8.0 }) == { ..Ui.default_box, floating: Float({ attach: RightBottom, offset: { x: 16.0, y: 8.0 } }) }

expect {
	p = Ui.panel(LeftTop, { x: 16.0, y: 16.0 })
	p == { ..Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), pad: Ui.pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }
}

expect Ui.pad_all(4.0) == { left: 4.0, right: 4.0, top: 4.0, bottom: 4.0 }
