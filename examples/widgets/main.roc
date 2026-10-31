app [init, launch, loaded, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

# A game for the Bridge check: a button, a dropdown, an accordion, focus and a
# scrolling log, all from the widget modules of packages/ui. It Tells each click
# on the port widgets.

import ui.Ui
import ui.Accordion
import ui.Button
import ui.Dropdown
import ui.Focus
import ui.Scroll
import ui.Widget
import pf.Vocabulary exposing [Command, Element, Manifest]
import pf.Config
import pf.Input
import pf.Key
import pf.Launch
import pf.MouseButton
import pf.Port
import pf.QueryResults
import pf.Scene

Model : { buttons : Button, focus : Focus, filter : Dropdown, details : Accordion, log : Scroll, lines : List(Str) }

# The Bridge check points at these ids, at the 960 by 540 window of
# Launch.default.
add_id : U64
add_id = 1

filter_id : U64
filter_id = 2

menu_id : U64
menu_id = 3

details_id : U64
details_id = 4

log_id : U64
log_id = 5

thumb_id : U64
thumb_id = 6

jobs : List({ id : U64, label : Str })
jobs = [{ id: 10, label: "All jobs" }, { id: 11, label: "Ready" }, { id: 12, label: "Claimed" }, { id: 13, label: "Merged" }]

look : Widget.Look
look = {
	idle: { r: 0.22, g: 0.24, b: 0.3, a: 1.0 },
	hover: { r: 0.25, g: 0.45, b: 0.75, a: 1.0 },
	down: { r: 0.1, g: 0.2, b: 0.4, a: 1.0 },
	focus: { r: 0.55, g: 0.4, b: 0.15, a: 1.0 },
	panel: { r: 0.08, g: 0.09, b: 0.12, a: 0.95 },
	text: { r: 0.95, g: 0.95, b: 0.95, a: 1.0 },
	size: 18.0,
	pad: 7.0,
}

body_text : Str
body_text = "Tab moves the focus. Enter clicks."

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Widgets" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = {
		buttons: Button.idle,
		focus: Focus.none,
		filter: Dropdown.new({ button: filter_id, menu: menu_id, items: jobs, selected: 0 }),
		details: Accordion.new({ header: details_id, shown: Closed }),
		log: Scroll.new({ id: log_id, thumb: thumb_id, line: 18.0, stick: StickToBottom }),
		lines: ["Line 1", "Line 2", "Line 3", "Line 4", "Line 5", "Line 6", "Line 7", "Line 8", "Line 9", "Line 10", "Line 11", "Line 12"],
	}
	{ model, commands: [] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

focus_order : Model -> List(U64)
focus_order = |model| List.join([[add_id], model.filter.focus_order(), [details_id, log_id]])

# region: widgets-step
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, _dt| {
	pointer = model.buttons.update({ input, results })
	keys = model.focus.update({ input, order: focus_order(model) })
	events = List.join([pointer.events, keys.events])
	picked = model.filter.update(events)
	next = {
		..model,
		buttons: pointer.buttons,
		focus: keys.focus,
		filter: picked.dropdown,
		details: model.details.update(events),
		log: model.log.update({ input, results, focus: keys.focus }),
		lines: if (events.contains(Clicked(add_id))) model.lines.append("Line ${(model.lines.len() + 1).to_str()}") else model.lines,
	}
	{ model: next, commands: tells(events, picked.selection) }
}

# endregion

tells : List(Widget.Event), [Selected(U64), Unchanged] -> List(Command)
tells = |events, selection| {
	clicks = events.fold(
		[],
		|commands, event| match event {
			Clicked(id) => commands.append(Port.tell("widgets", "clicked ${id.to_str()}"))
			Pressed(_) => commands
		},
	)
	match selection {
		Selected(index) => clicks.append(Port.tell("widgets", "selected ${index.to_str()}"))
		Unchanged => clicks
	}
}

# region: widgets-element
element : Ui.Node -> Element
element = |node| node.build({ panel: |config, children| Panel(config, children), text: |text| Text(text) })

# endregion

# region: widgets-view
view : Model -> Vocabulary.Scene
view = |model| {
	{ buttons, focus, .. } = model
	add = buttons.view({ id: add_id, label: "Add line", width: Fixed(160.0), look, focus })
	filter = model.filter.view({ buttons, focus, width: Fixed(160.0), look })
	details = model.details.view({ buttons, focus, label: "Details", width: Fixed(420.0), look, body: [Widget.label(look, body_text)] })
	rows = model.lines.map(|line| Widget.label(look, Ui.fit(line, { size: 18.0, width: 404.0 })))
	log = model.log.view({ rows, width: Fixed(420.0), height: Fixed(108.0), look })
	panel = Panel({ ..Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), direction: Col, gap: 8.0 }, [Panel({ ..Ui.default_panel, gap: 8.0 }, [add, filter]), details, log])
	{ ..Scene.empty, ui: [element(panel)] }
}

# endregion

left = MouseButton.code(Left)

click = { ..Input.empty, pointer: { ..Input.empty.pointer, pressed: [left], released: [left] } }

over : List(U64) -> Vocabulary.QueryResults
over = |ids| { ..QueryResults.empty, ui: { over: ids, scroll: [] } }

start = init(Config.empty).model

## A click on Add appends a line and Tells it.
expect {
	after = step(start, click, over([add_id]), 0.0)
	(after.model.lines.len(), after.commands) == (13, [Port.tell("widgets", "clicked 1")])
}

## Shift-Tab and Enter click the focused id.
expect {
	back = step({ ..start, focus: Focus.on(log_id) }, { ..Input.empty, held: [Key.code(LeftShift)], pressed: [Key.code(Tab)] }, QueryResults.empty, 0.0).model
	step(back, { ..Input.empty, pressed: [Key.code(Enter)] }, QueryResults.empty, 0.0).commands == [Port.tell("widgets", "clicked 4")]
}

## A click on an item Tells the click and then the selection.
expect {
	opened = step(start, click, over([filter_id]), 0.0).model
	step(opened, click, over([11, menu_id]), 0.0).commands == [Port.tell("widgets", "clicked 11"), Port.tell("widgets", "selected 1")]
}

## The focus order holds the items only while the menu is open.
expect (focus_order(start), focus_order(step(start, click, over([filter_id]), 0.0).model)) == ([1, 2, 4, 5], [1, 2, 10, 11, 12, 13, 4, 5])

## The view tags the two buttons of the first row.
expect
	match view(start).ui {
		[Panel(_, [Panel(_, [Panel(add, _), Panel(filter, _)]), _, _])] => (add.id, filter.id) == (add_id, filter_id)
		_ => Bool.False
	}
