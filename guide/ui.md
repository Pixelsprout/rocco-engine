---
title: The UI
summary: Why the host lays out the UI, how a game writes it as a tree of Panels and Text, the ui package's defaults and helpers, and the layout rules.
order: 9
---

# The UI

A score, a pause banner or a list of controls needs layout: text that
centres, panels that stick to a corner, sizes that follow the window.

The host does that layout. Your game describes the UI in the `ui` field
of the [Scene], and the host lays it out and draws it flat over the 3D
view. When your game needs to choose what to show, such as how much of a
long line fits in a Panel, it can measure a string first with
[`Ui.measure`][Ui.measure]. Like the rest of the Scene, the UI is a Description: your game builds
it again at each step from the Model. A game with no UI keeps the empty
list of `Scene.empty`, which costs nothing.

A UI is nested by nature. A scoreboard is a panel; inside the panel sits a
row of cells; inside each cell sits a number. So your game writes the UI as
a tree, and the host gets that same tree.

## Panels and Text

The tree is made of two kinds of [Element]:

```roc
Element := [Panel(PanelConfig, List(Element)), Text(Text)]
```

- A `Panel` is a rectangle. Its [PanelConfig] says how it sizes and looks, and
  its list holds its children, laid out in order inside it.
- A `Text` draws one string. It has no children.

`Scene.ui` is a list of the root Elements. You write the tags yourself,
just as you would write any other value:

```roc
ui: [Panel(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text(Ui.label("Score: 3"))])]
```

That is one Panel in the top-left corner of the window, holding one line of
text.

An Element has no id. Its place in the tree is its identity, and the host
keeps nothing from one step to the next. The 3D part of the Scene is a
tree too, in `Scene.nodes`, but there a Group pairs by its Group id. See
[Groups](scene.md#groups).

## A first UI

Add `ui: "{{ui_url}}"` to the header of your app, then write
`import ui.Ui`. On GitHub, get the URL as
[Shipping a game](shipping.md#the-header) explains. Expose `Element` from
`pf.Vocabulary` so that you can write it in your types.

Pong shows its score at the top, a banner when it is paused or won, and
its keys in the bottom corners:

<!-- region: examples/pong/main.roc#ui -->
```roc
centred : Ui.PanelConfig
centred = { ..Ui.default_panel, child_align: { x: Center, y: Center } }

score_color : GameState, U64, U64 -> Rgba
score_color = |state, own, other| {
	if state == EndGame {
		if own > other {
			green_text
		} else {
			red_text
		}
	} else {
		white_text
	}
}

# Fixed cells keep the colon still when a score gains a digit.
scoreboard : GameState, Score -> Element
scoreboard = |state, score| {
	cell = |own, other| Panel({ ..centred, width: Fixed(48.0) }, [Text({ ..Ui.label(own.to_str()), color: score_color(state, own, other) })])
	Panel(
		{ ..Ui.panel(CenterTop, { x: 0.0, y: 16.0 }), gap: 8.0, child_align: { x: Center, y: Center } },
		[cell(score.left, score.right), Text(Ui.label(":")), cell(score.right, score.left)],
	)
}

banner : GameState, Score -> List(Element)
banner = |state, score| match state {
	Running => []
	Paused => [banner_panel("Paused", white_text, "Space to resume")]
	EndGame => {
		winner = if score.left > score.right "Left" else "Right"
		[banner_panel("${winner} wins", green_text, "Space to play again")]
	}
}

# Percent sizes the banner against the window. Grow stretches each row across
# the banner, so the text centres and the hint wraps inside it.
banner_panel : Str, Rgba, Str -> Element
banner_panel = |title, color, hint| {
	row = |child| Panel({ ..centred, width: Grow({ min: 0.0, max: 0.0 }) }, [child])
	Panel(
		{ ..Ui.panel(CenterCenter, { x: 0.0, y: 0.0 }), width: Percent(0.3), direction: Col, gap: 8.0, pad: Ui.pad_all(16.0) },
		[row(Text({ ..Ui.label(title), size: 40.0, color })), row(Text(Ui.label(hint)))],
	)
}

# The engine adds the offset at the same corner of the window and the Panel, so
# a bottom or right corner needs a negative offset.
hints : List(Element)
hints = [
	Panel(Ui.panel(LeftBottom, { x: 16.0, y: -16.0 }), [Text(Ui.label("W / S"))]),
	Panel(Ui.panel(RightBottom, { x: -16.0, y: -16.0 }), [Text(Ui.label("Up / Down"))]),
]

hud : Model -> List(Element)
hud = |m| [scoreboard(m.state, m.score)].concat(banner(m.state, m.score)).concat(hints)
```
<!-- endregion -->

Each function returns a value with the shape that it draws. `scoreboard`
gives one Panel that holds a cell, a colon and a cell. `banner`
gives a list, empty while the game runs, so `hud` can join the roots with
`concat`. Each Panel's list of children is built once, and nothing
flattens the tree.

## Testing a UI

Because the UI is a plain value, a test can match its shape with a
pattern. This test from pong reads the scoreboard without the host:

<!-- region: examples/pong/main.roc#ui-test -->
```roc
# The scoreboard is a panel of a cell, a colon and a cell, and each cell holds
# one Text.
expect
	match scoreboard(Running, { left: 3, right: 0 }) {
		Panel(_, [Panel(_, [Text(left)]), Text(colon), Panel(_, [Text(right)])]) => left.str == "3" and colon.str == ":" and right.str == "0"
		_ => Bool.False
	}
```
<!-- endregion -->

If the scoreboard ever gains a fourth child, or a cell holds something
other than one Text, the pattern stops matching and the test fails.

## The ui package

You write the tags yourself, so the [ui package][Ui] gives only the
starting values and a few small helpers:

- [`Ui.default_panel`][Ui.default_panel] is the PanelConfig to start from. It
  holds Clay's defaults: it fits its children, with no padding, no gap and
  no background, and lays them out in a `Row`.
- [`Ui.default_text`][Ui.default_text] is the Text to start from: an
  empty string, 24 pixels high, opaque white, that wraps between words.
- [`Ui.label(str)`][Ui.label] is a `default_text` that shows `str`. Change
  the rest with a record update, such as
  `Text({ ..Ui.label("Paused"), size: 40.0 })`.
- [`Ui.float_at(attach, offset)`][Ui.float_at] gives a PanelConfig that
  floats over the window at one of its points.
- [`Ui.panel(attach, offset)`][Ui.panel] is a `float_at` Panel for a HUD,
  with padding, a see-through black background and round corners.
- [`Ui.pad_all(n)`][Ui.pad_all] gives the same padding on all four sides.
- [`Ui.measure`][Ui.measure], [`Ui.fit`][Ui.fit] and [`Ui.wrap`][Ui.wrap]
  measure, cut and wrap text with the host's numbers. See "Measure, fit
  and wrap" below.
- [`Ui.Node`][Ui.Node] is a UI tree that the widget modules build. See
  "Widgets" below.

## Widgets

The ui package also gives five widget modules: [`Button`][Button],
[`Focus`][Focus], [`Dropdown`][Dropdown], [`Accordion`][Accordion] and
[`Scroll`][Scroll]. [`Widget`][Widget] holds the types they share. Import
them as `import ui.Button` and so on. Each widget is a state that you keep
in your Model, an `update` that you call in `step`, and a `view` that
builds its part of the UI. The engine has no widget and no focus: the
modules are plain Roc, and you give every id.

`Button` keeps the hover and the press of the left button for every button
of one UI, so keep one in your Model. Its `update` reads the pointer and
`results.ui.over`, and gives `Pressed` and `Clicked` events. A button
clicks when the left button goes up over the Panel it went down on.
`Button.view` draws one button with the idle, hover, down or focus colour
of the `Widget.Look`. It is a UI button, not the button of a gamepad.

`Focus` is the Panel that the keys act on. Give its `update` the ids that
take the focus, in Tab order. Tab and Shift-Tab move it, and Enter or
Space gives a `Clicked` event for the focused id, the same event as a
click.

`Dropdown` is a button that opens a menu of items. The menu floats under
the button. A click on an item selects it and closes the menu, and a press
outside the menu closes it. `Accordion` is a header button that shows or
hides a body. Both read only the events of `Button` and `Focus`.

`Scroll` is a Panel that scrolls its rows, with a scrollbar thumb that the
person can drag. The wheel scrolls it by `line` pixels per step, and Page
Up, Page Down, Home and End move it while it has the focus. It reads its
sizes from `results.ui.scroll`.

Give each `update` the Input and the QueryResults that `step` gets. The
widgets read only the fields they need, so the package does not copy
those types.

The widgets example runs every widget. Its `step` passes the events of the
buttons and the keys to each widget:

<!-- region: examples/widgets/main.roc#widgets-step -->
```roc
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
```
<!-- endregion -->

A package cannot name the platform's `Element`, so each `view` returns a
[`Ui.Node`][Ui.Node], a tree of the same shape. Your game turns a Node
into an Element once, where it goes into `Scene.ui`, with
[`Node.build`][Ui.Node] and the Element tags:

<!-- region: examples/widgets/main.roc#widgets-element -->
```roc
element : Ui.Node -> Element
element = |node| node.build({ panel: |config, children| Panel(config, children), text: |text| Text(text) })
```
<!-- endregion -->

Build the whole widget panel as a Node, then call `element` on it:

<!-- region: examples/widgets/main.roc#widgets-view -->
```roc
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
```
<!-- endregion -->

One click reaches one widget. A press and a click belong to the innermost
tagged Panel under the pointer, and each widget acts only on the events
that name its own ids. An open menu floats, so it hides the Panels under
it, and a click on an item does not also reach the header under it.

Agent Town's log is a `Scroll` with `StickToBottom` and a `line` of 18,
for text of size 18. With the engine's one font, a Text's line height is
its size. The log stays at the bottom as lines arrive, one step after
their size arrives. When the person scrolls up, it keeps its place, and it
sticks again when they scroll back to the bottom.

The widgets have no text input and no kinetic scrolling.

## The layout rules

The host lays out the UI with Clay, so the field names and the defaults
are Clay's.

- All sizes are logical pixels. The host multiplies each size by the DPI
  scale of the display.
- A Panel lays out its children in a `Row`, from left to right, or in a
  `Col`, from top to bottom.
- `pad` is the space between the edges of a Panel and its children. `gap` is
  the space between two children.
- `child_align` puts the children at the `Start`, the `Center` or the `End`
  of the Panel, on each axis.
- A `Fit` size fits the children. A `Grow` size fills the free space in the
  parent. A `Fixed` size is the number that you give. A `Percent` size is a
  fraction of the parent, from 0 to 1.
- A Panel with a `Float` ignores the layout of its parent. With `to: Window`
  it floats on the window, and with `to: Parent` it floats on its parent
  Panel. A root Panel with `to: Parent` floats on the window.
- A floating Panel puts its `attach` point on the `on` point of the window or
  of its parent, then moves by `offset`. +x is to the right and +y is down,
  so a Panel at a right or a bottom point needs a negative offset to move
  into the window. `Ui.float_at` uses the same point for both.
- A Text with `wrap` set to `Words` breaks its lines between words, inside
  the width of its parent. [`Ui.wrap`][Ui.wrap] gives the same lines.

Use `Grow` and `Percent` to fit the UI to the window. The only layout
results that come back to your game are the Panels under the pointer and
the sizes of the Scroll Panels. See below.

## The pointer and tagged Panels

Give a Panel a non-zero `id` to tag it. After each layout, the host finds the
tagged Panels under the pointer and gives them to the next step in
`results.ui.over`, innermost first. A button is a tagged Panel, and a click
on it is a `MouseButton.released` while its id is in `over`:

```roc
clicks : Vocabulary.Input, Vocabulary.QueryResults -> List(Command)
clicks = |input, results| if MouseButton.released(input, Left) and List.contains(results.ui.over, button_id) {
	[Port.tell("click", button_id.to_str())]
} else {
	[]
}
```

Give each tagged Panel its own id. If two Panels share an id, the host logs
once and only the first Panel is ever in `over`.

A floating Panel hides the Panels under it when it, or any Panel inside it, has
an id. So an open menu over a button gives only the menu's ids, and a click
on a menu item does not also reach the button. A floating Panel with no
tagged Panel inside it, such as a label, lets the pointer through to the
Panels under it.

A menu that drops down under its button floats on its parent:
`floating: Float({ to: Parent, attach: LeftTop, on: LeftBottom, offset: { x: 0.0, y: 4.0 } })`
puts the menu's top left corner 4 pixels under the button's bottom left
corner.

## Clip and scroll

`overflow` says what a Panel does with children that reach past its edges:

- `Visible`, the default, draws them.
- `Clip` cuts them at the edges of the Panel.
- `Scroll({ x, y })` cuts them and moves them by the offset. A negative `y`
  moves them up, so later content shows.

Your game owns the scroll offset. Keep it in the Model, change it on
`input.pointer.wheel` while the Panel is in `over`, and keep it in range with
the sizes in `results.ui.scroll`. Each row there has the `id` of a tagged
Scroll Panel, its `view` size and its `content` size, in logical pixels. The
furthest that `y` goes is `view.height - content.height`. A Scroll Panel
needs an `id`. Without one, the host logs once, still scrolls the Panel, but
lists no sizes for it.

## Text

The host draws all Text in one font, Atkinson Hyperlegible. The font has
the ASCII characters 32 to 126, and the host draws `?` for any other
character. The host rounds the size of a Text to a whole number of pixels,
after the DPI scale.

### Measure, fit and wrap

The ui package carries a copy of the host's font table, so your game can
measure text in pure Roc and get the host's numbers.

[`Ui.measure(text, size)`][Ui.measure] gives the width and the height of
one line of text, in logical pixels. A newline measures as `?`, so use
`Ui.wrap` for more than one line.

[`Ui.fit(text, { size, width })`][Ui.fit] cuts a line to a width and ends
it with `...`. A string that fits comes back unchanged. A HUD feed in a 420
pixel Panel keeps each line on one row like this:

```roc
Text({ ..Ui.label(Ui.fit(line, { size: 18.0, width: 416.0 })), size: 18.0, wrap: None })
```

In Agent Town this replaces the feed's cut at 48 characters.

[`Ui.wrap(text, { size, width })`][Ui.wrap] gives the lines that the host
draws for a `Words` Text, where `width` is the room for the text: the Panel
width minus its padding. A word wider than `width` takes a line of its
own, and the other lines then wrap at that word's width.

The numbers match the host for whole-pixel sizes at a whole DPI scale. At
a fractional DPI scale the host rounds the size, so the drawn text can
drift from `Ui.measure` by a fraction of a pixel. Use whole-pixel sizes,
and leave a few pixels of margin in a `fit` width.

## Draw order and time

The host draws the UI after the meshes and the sky. The UI has no depth
test, so it is always in front of the meshes.

The UI does not interpolate. Like the Lights, it changes once in each fixed
step.

## Errors

A mistake in the UI does not stop the game. The host logs each of these
errors once, and keeps drawing:

- a character that the font does not have: the host draws `?`.
- more quads than `capacity.ui_quads` of the [Launch]: the host drops the
  rest.
- two Panels with the same `id`: the host hit tests only the first.
- a Scroll Panel with id 0: the host lists no sizes for it.

The host also logs each kind of Clay error once, such as a `Percent` above
1, and draws what fits.

[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Element]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Element
[PanelConfig]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.PanelConfig
[Ui]: https://pixelsprout.dev/projects/rocco/api/ui/
[Ui.default_panel]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_panel
[Ui.default_text]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_text
[Ui.label]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.label
[Ui.float_at]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.float_at
[Ui.panel]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.panel
[Ui.pad_all]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.pad_all
[Ui.measure]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.measure
[Ui.fit]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.fit
[Ui.wrap]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.wrap
[Ui.Node]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.Node
[Widget]: https://pixelsprout.dev/projects/rocco/api/ui/Widget/
[Button]: https://pixelsprout.dev/projects/rocco/api/ui/Button/
[Focus]: https://pixelsprout.dev/projects/rocco/api/ui/Focus/
[Dropdown]: https://pixelsprout.dev/projects/rocco/api/ui/Dropdown/
[Accordion]: https://pixelsprout.dev/projects/rocco/api/ui/Accordion/
[Scroll]: https://pixelsprout.dev/projects/rocco/api/ui/Scroll/
