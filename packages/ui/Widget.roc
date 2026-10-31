import Seam
import Ui

## The types that the widget modules share: `Button`, `Focus`, `Dropdown`,
## `Accordion` and `Scroll`. A widget keeps its state in your Model, updates it
## from Input and QueryResults in `step`, and builds a `Ui.Node` in `view`.
## The engine has no widget.
Widget := [].{

	## The fields of `Vocabulary.Input` that the widgets read. Give `update`
	## the Input that `step` gets.
	Input(input, pointer) : { held : List(U16), pressed : List(U16), pointer : { x : F32, y : F32, held : List(U8), pressed : List(U8), released : List(U8), wheel : { dx : F32, dy : F32 }, ..pointer }, ..input }

	## The fields of `Vocabulary.QueryResults` that the widgets read. Give
	## `update` the QueryResults that `step` gets.
	Results(results, ui) : { ui : { over : List(U64), scroll : List({ id : U64, view : { width : F32, height : F32 }, content : { width : F32, height : F32 } }), ..ui }, ..results }

	## What a press lands on: the tagged Panel with that id, or no tagged Panel.
	Target : [Over(U64), Nowhere]

	## What the buttons and the keys did in one step. `Pressed` comes on the
	## step that the left button went down, with the hit. `Clicked` comes when
	## the left button goes up over the Panel it went down on, or when Enter or
	## Space acts on the focused id.
	Event : [Pressed(Target), Clicked(U64)]

	## The colours and sizes of every widget. `idle`, `hover`, `down` and
	## `focus` colour a button and the scrollbar thumb. `panel` colours a menu,
	## an accordion body, a Scroll Panel and its track. `text`, `size` and `pad`
	## set every label: its colour, its height in pixels and the space around it.
	Look : { idle : Ui.Rgba, hover : Ui.Rgba, down : Ui.Rgba, focus : Ui.Rgba, panel : Ui.Rgba, text : Ui.Rgba, size : F32, pad : F32 }

	## The innermost tagged Panel under the pointer, the first id of
	## `ui.over`, or `Nowhere`.
	hit : Widget.Results(_, _) -> Target
	hit = |results| match results.ui.over {
		[id, ..] => Over(id)
		[] => Nowhere
	}

	## One line of `str` in the look's size and text colour. It does not wrap.
	label : Look, Str -> Ui.Node
	label = |look, str| Text({ str, size: look.size, color: look.text, wrap: None })
}

look : Widget.Look
look = {
	idle: { r: 0.2, g: 0.2, b: 0.2, a: 1.0 },
	hover: { r: 0.3, g: 0.3, b: 0.3, a: 1.0 },
	down: { r: 0.1, g: 0.1, b: 0.1, a: 1.0 },
	focus: { r: 0.2, g: 0.2, b: 0.5, a: 1.0 },
	panel: { r: 0.05, g: 0.05, b: 0.05, a: 1.0 },
	text: { r: 1.0, g: 1.0, b: 1.0, a: 1.0 },
	size: 18.0,
	pad: 7.0,
}

## The hit is the innermost tagged Panel under the pointer, the first id of over.
expect Widget.hit({ ..Seam.results, ui: { over: [11, 3], scroll: [] } }) == Over(11)

## No tagged Panel under the pointer is no hit.
expect Widget.hit(Seam.results) == Nowhere

## A label is one line of text in the look's size and colour.
expect Widget.label(look, "Go") == Text({ str: "Go", size: 18.0, color: look.text, wrap: None })
