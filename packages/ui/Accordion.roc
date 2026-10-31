import Button
import Focus
import Seam
import Ui
import Widget

## A header button that shows or hides a body. Keep one Accordion in your
## Model, and give `update` the events of `Button.update` and
## `Focus.update`.
Accordion :: { header : U64, shown : [Open, Closed] }.{

	## An Accordion whose header Panel is tagged `header`.
	new : { header : U64, shown : [Open, Closed] } -> Accordion
	new = |{ header, shown }| { header, shown }

	## Each click on the header opens a closed body and closes an open one.
	update : Accordion, List(Widget.Event) -> Accordion
	update = |accordion, events|
		events.fold(
			accordion,
			|acc, event| match (event, acc.shown) {
				(Clicked(id), Open) => if (id == acc.header) { ..acc, shown: Closed } else acc
				(Clicked(id), Closed) => if (id == acc.header) { ..acc, shown: Open } else acc
				(Pressed(_), _) => acc
			},
		)

	## True while the body shows.
	is_open : Accordion -> Bool
	is_open = |accordion| accordion.shown == Open

	## A column of the header button and, while open, a padded Panel of
	## `width` in the `panel` colour that holds `body`.
	view : Accordion, { buttons : Button, focus : Focus, label : Str, width : Ui.Sizing, look : Widget.Look, body : List(Ui.Node) } -> Ui.Node
	view = |accordion, { buttons, focus, label, width, look, body }| {
		header = buttons.view({ id: accordion.header, label, width, look, focus })
		children = match accordion.shown {
			Open => [header, Panel({ ..Ui.default_panel, width, pad: { left: look.pad, right: look.pad, top: look.pad, bottom: look.pad }, background: look.panel }, body)]
			Closed => [header]
		}
		Panel({ ..Ui.default_panel, direction: Col }, children)
	}

	## Two Accordions are equal when their states are equal.
	is_eq : _
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

details = Accordion.new({ header: 4, shown: Closed })

## A click on the header opens the body, and a second one closes it.
expect details.update([Clicked(4)]).is_open() and !details.update([Clicked(4), Clicked(4)]).is_open()

## A click or a press on another id does nothing.
expect details.update([Pressed(Over(4)), Clicked(11), Pressed(Over(11))]) == details

## A tap on an item that lies over the header reaches the item only, so the header stays closed.
expect {
	tap = { ..Seam.input, pointer: { ..Seam.input.pointer, pressed: [Seam.button_code(Left)], released: [Seam.button_code(Left)] } }
	events = Button.idle.update({ input: tap, results: { ..Seam.results, ui: { over: [11, 4], scroll: [] } } }).events
	!details.update(events).is_open()
}

## The view shows the body only while open.
expect {
	props = { buttons: Button.idle, focus: Focus.none, label: "Details", width: Fixed(420.0), look, body: [Widget.label(look, "Body")] }
	children = |element| match element {
		Panel(_, list) => list.len()
		Text(_) => 0
	}
	(children(details.view(props)), children(details.update([Clicked(4)]).view(props))) == (1, 2)
}
