# These types copy pf.Vocabulary. Keep them identical, or Scene.ui stops unifying.
Ui := [].{
	Padding : { left : F32, right : F32, top : F32, bottom : F32 }
	Offset : { x : F32, y : F32 }
	Rgba : { r : F32, g : F32, b : F32, a : F32 }
	Sizing : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]
	Align : [Start, Center, End]
	AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]
	BoxConfig : { width : Sizing, height : Sizing, pad : Padding, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, floating : [NoFloat, Float({ attach : AttachPoint, offset : Offset })] }
	Text : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }
	TextStyle : { size : F32, color : Rgba, wrap : [Words, None] }
	Element : [Open(BoxConfig), Text(Text), Close]

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

	# A box floating to the window root, at offset logical pixels from the attach point.
	float_at : AttachPoint, Offset -> BoxConfig
	float_at = |attach, offset| { ..default_box, floating: Float({ attach, offset }) }

	pad_all : F32 -> Padding
	pad_all = |n| { left: n, right: n, top: n, bottom: n }

	# Each child is a stream, so boxes and text mix in one list.
	box : BoxConfig, List(List(Element)) -> List(Element)
	box = |config, children| [Open(config)].concat(List.join(children)).append(Close)

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
