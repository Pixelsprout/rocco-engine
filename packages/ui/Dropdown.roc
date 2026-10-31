import Button
import Focus
import Ui
import Widget

## A button that opens a menu of items. The menu floats under the button, so
## the Boxes under it get no click. A press outside the menu closes it. Keep
## one Dropdown in your Model, and give `update` the events of
## `Button.update` and `Focus.update`.
Dropdown :: { button : U64, menu : U64, items : List({ id : U64, label : Str }), selected : U64, shown : [Open, Closed] }.{

	## A closed Dropdown. `button` tags the button, `menu` tags the menu Box
	## and each item's `id` tags its row. `selected` is the index of the item
	## that the button shows. It crashes when `selected` is past the last item.
	new : { button : U64, menu : U64, items : List({ id : U64, label : Str }), selected : U64 } -> Dropdown
	new = |{ button, menu, items, selected }|
		if (selected >= items.len()) {
			crash "Dropdown.new: selected is past the last item"
		} else {
			{ button, menu, items, selected, shown: Closed }
		}

	## Acts on each event in order. A click on the button opens or closes the
	## menu. A click on an item of the open menu selects it, closes the menu
	## and gives `Selected` with the item's index. A press on anything but the
	## button, the menu or an item closes the menu. A closed Dropdown ignores
	## its items.
	update : Dropdown, List(Widget.Event) -> { dropdown : Dropdown, selection : [Selected(U64), Unchanged] }
	update = |dropdown, events| events.fold({ dropdown, selection: Unchanged }, |acc, event| act(acc, event))

	## The index of the selected item.
	selected : Dropdown -> U64
	selected = |dropdown| dropdown.selected

	## True while the menu shows.
	is_open : Dropdown -> Bool
	is_open = |dropdown| dropdown.shown == Open

	## The ids that take the focus, in Tab order: the button, then the items
	## while the menu shows.
	focus_order : Dropdown -> List(U64)
	focus_order = |dropdown| match dropdown.shown {
		Open => List.join([[dropdown.button], dropdown.items.map(|item| item.id)])
		Closed => [dropdown.button]
	}

	## The button, with the label of the selected item, and the menu under it
	## while it shows. The menu has the button's `width`, and each item fills
	## it.
	view : Dropdown, { buttons : Button, focus : Focus, width : Ui.Sizing, look : Widget.Look } -> Ui.Node
	view = |dropdown, { buttons, focus, width, look }| {
		label = match dropdown.items.get(dropdown.selected) {
			Ok(item) => Widget.label(look, item.label)
			Err(_) => crash "Dropdown.view: selected is past the last item"
		}
		menu = Box(
			{
				..Ui.default_box,
				id: dropdown.menu,
				width,
				direction: Col,
				background: look.panel,
				floating: Float({ to: Parent, attach: LeftTop, on: LeftBottom, offset: { x: 0.0, y: 0.0 } }),
			},
			dropdown.items.map(|item| buttons.view({ id: item.id, label: item.label, width: Grow({ min: 0.0, max: 0.0 }), look, focus })),
		)
		children = match dropdown.shown {
			Open => [label, menu]
			Closed => [label]
		}
		Box(buttons.box({ id: dropdown.button, width, look, focus }), children)
	}

	## Two Dropdowns are equal when their states are equal.
	is_eq : _
}

act : { dropdown : Dropdown, selection : [Selected(U64), Unchanged] }, Widget.Event -> { dropdown : Dropdown, selection : [Selected(U64), Unchanged] }
act = |{ dropdown, selection }, event| {
	closed = { ..dropdown, shown: Closed }
	is_own = |id| id == dropdown.button or id == dropdown.menu or dropdown.items.any(|item| item.id == id)
	match (event, dropdown.shown) {
		(Clicked(id), Closed) => if (id == dropdown.button) { dropdown: { ..dropdown, shown: Open }, selection } else { dropdown, selection }
		(Clicked(id), Open) =>
			if (id == dropdown.button) {
				{ dropdown: closed, selection }
			} else {
				match dropdown.items.find_first_index(|item| item.id == id) {
					Ok(index) => { dropdown: { ..closed, selected: index }, selection: Selected(index) }
					Err(_) => { dropdown, selection }
				}
			}
		(Pressed(Over(id)), Open) => if (is_own(id)) { dropdown, selection } else { dropdown: closed, selection }
		(Pressed(Nowhere), Open) => { dropdown: closed, selection }
		(Pressed(_), Closed) => { dropdown, selection }
	}
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

items = [{ id: 10, label: "All jobs" }, { id: 11, label: "Ready" }, { id: 12, label: "Claimed" }, { id: 13, label: "Merged" }]

closed = Dropdown.new({ button: 2, menu: 3, items, selected: 0 })

opened = closed.update([Clicked(2)]).dropdown

## A click on the button opens the menu, and a second one closes it.
expect opened.is_open() and !opened.update([Pressed(Over(2)), Clicked(2)]).dropdown.is_open()

## A click on an item selects it and closes the menu.
expect {
	picked = opened.update([Pressed(Over(12)), Clicked(12)])
	(picked.selection, picked.dropdown.selected(), picked.dropdown.is_open()) == (Selected(2), 2, Bool.False)
}

## A press outside the dropdown closes the menu and selects nothing.
expect [opened.update([Pressed(Nowhere)]), opened.update([Pressed(Over(4))])].map(|after| (after.dropdown.is_open(), after.selection)) == [(Bool.False, Unchanged), (Bool.False, Unchanged)]

## A press on the menu's own padding keeps it open.
expect opened.update([Pressed(Over(3))]).dropdown.is_open()

## A closed dropdown ignores a click on an item.
expect closed.update([Clicked(12)]) == { dropdown: closed, selection: Unchanged }

## The focus order holds the items only while the menu is open.
expect (closed.focus_order(), opened.focus_order()) == ([2], [2, 10, 11, 12, 13])

## The closed view shows the selected label and no menu.
expect
	match closed.view({ buttons: Button.idle, focus: Focus.none, width: Fixed(160.0), look }) {
		Box(config, [Text(text)]) => (config.id, text.str) == (2, "All jobs")
		_ => Bool.False
	}

## The open view floats a tagged menu of tagged items under the button.
expect
	match opened.view({ buttons: Button.idle, focus: Focus.none, width: Fixed(160.0), look }) {
		Box(_, [Text(_), Box(menu, rows)]) => (menu.id, menu.floating, rows.len()) == (3, Float({ to: Parent, attach: LeftTop, on: LeftBottom, offset: { x: 0.0, y: 0.0 } }), 4)
		_ => Bool.False
	}
