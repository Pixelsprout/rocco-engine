import Focus
import Seam
import Ui
import Widget

## The hover and the press of the left button, for every button of one UI.
## Keep one Button in your Model and call `update` once per step. A button
## clicks when the left button goes up over the Panel it went down on. This is
## a UI button, not a button of a gamepad.
Button :: { hover : Widget.Target, press : [Up, Down(Widget.Target)] }.{

	## No Panel under the pointer and the left button up.
	idle : Button
	idle = { hover: Nowhere, press: Up }

	## Reads the left button and the hit, and gives at most one `Pressed` and
	## one `Clicked`. The events name the innermost tagged Panel only, so one
	## click reaches one widget. A press over nothing, or a release over
	## another Panel, clicks nothing.
	update : Button, { input : Widget.Input(_, _), results : Widget.Results(_, _) } -> { buttons : Button, events : List(Widget.Event) }
	update = |buttons, { input, results }| {
		hit = Widget.hit(results)
		is_pressed = Seam.is_button_pressed(input, Left)
		press = if (is_pressed) Down(hit) else buttons.press
		pressed = if (is_pressed) [Pressed(hit)] else []
		if (Seam.is_button_released(input, Left)) {
			clicked = match (press, hit) {
				(Down(Over(down)), Over(up)) => if (down == up) [Clicked(up)] else []
				_ => []
			}
			{ buttons: { hover: hit, press: Up }, events: List.join([pressed, clicked]) }
		} else {
			{ buttons: { hover: hit, press }, events: pressed }
		}
	}

	## The Panel of the button `id`, padded by `look.pad` with its child centred
	## on the y axis. The height fits the label. The background is `look.down`
	## while the left button is held over it, `look.hover` while the pointer
	## is over it, `look.focus` while it has the focus, and `look.idle` else.
	panel : Button, { id : U64, width : Ui.Sizing, look : Widget.Look, focus : Focus } -> Ui.PanelConfig
	panel = |buttons, { id, width, look, focus }| {
		is_hovered = buttons.hover == Over(id)
		background =
			if (is_hovered and buttons.press == Down(Over(id))) {
				look.down
			} else if (is_hovered) {
				look.hover
			} else if (focus.is_on(id)) {
				look.focus
			} else {
				look.idle
			}
		{
			..Ui.default_panel,
			id,
			width,
			pad: { left: look.pad, right: look.pad, top: look.pad, bottom: look.pad },
			child_align: { x: Start, y: Center },
			radius: 4.0,
			background,
		}
	}

	## A button Panel that holds one label.
	view : Button, { id : U64, label : Str, width : Ui.Sizing, look : Widget.Look, focus : Focus } -> Ui.Node
	view = |buttons, { id, label, width, look, focus }| Panel(buttons.panel({ id, width, look, focus }), [Widget.label(look, label)])

	## Two Buttons are equal when their states are equal.
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

left : { held : List(Seam.MouseButton), pressed : List(Seam.MouseButton), released : List(Seam.MouseButton) } -> Seam.TestInput
left = |{ held, pressed, released }| { ..Seam.input, pointer: { ..Seam.input.pointer, held: held.map(Seam.button_code), pressed: pressed.map(Seam.button_code), released: released.map(Seam.button_code) } }

over : List(U64) -> Seam.TestResults
over = |ids| { ..Seam.results, ui: { over: ids, scroll: [] } }

press = left({ held: [Left], pressed: [Left], released: [] })

release = left({ held: [], pressed: [], released: [Left] })

tap = left({ held: [], pressed: [Left], released: [Left] })

## A tap in one step over a Panel presses and clicks it.
expect Button.idle.update({ input: tap, results: over([7]) }).events == [Pressed(Over(7)), Clicked(7)]

## A press and a release over the same Panel click on the release.
expect {
	down = Button.idle.update({ input: press, results: over([7]) })
	up = down.buttons.update({ input: release, results: over([7]) })
	(down.events, up.events) == ([Pressed(Over(7))], [Clicked(7)])
}

## A release over another Panel clicks nothing.
expect Button.idle.update({ input: press, results: over([7]) }).buttons.update({ input: release, results: over([8]) }).events == []

## A press over nothing and a release over a Panel click nothing.
expect {
	down = Button.idle.update({ input: press, results: over([]) })
	(down.events, down.buttons.update({ input: release, results: over([7]) }).events) == ([Pressed(Nowhere)], [])
}

## Only the innermost tagged Panel gets the click.
expect Button.idle.update({ input: tap, results: over([11, 3]) }).events == [Pressed(Over(11)), Clicked(11)]

## The right button does nothing.
expect Button.idle.update({ input: left({ held: [Right], pressed: [Right], released: [] }), results: over([7]) }).events == []

## The look: down, then hover, then focus, then idle.
expect {
	held = Button.idle.update({ input: press, results: over([7]) }).buttons
	hovered = Button.idle.update({ input: Seam.input, results: over([7]) }).buttons
	backgrounds = [
		held.panel({ id: 7, width: Fixed(160.0), look, focus: Focus.none }),
		hovered.panel({ id: 7, width: Fixed(160.0), look, focus: Focus.on(7) }),
		Button.idle.panel({ id: 7, width: Fixed(160.0), look, focus: Focus.on(7) }),
		Button.idle.panel({ id: 7, width: Fixed(160.0), look, focus: Focus.none }),
	].map(|config| config.background)
	backgrounds == [look.down, look.hover, look.focus, look.idle]
}

## The view is a tagged Panel that holds one label.
expect
	match Button.idle.view({ id: 7, label: "Add line", width: Fixed(160.0), look, focus: Focus.none }) {
		Panel(config, [Text(text)]) => (config.id, config.width, text.str) == (7, Fixed(160.0), "Add line")
		_ => Bool.False
	}
