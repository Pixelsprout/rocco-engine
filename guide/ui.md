---
title: The UI
summary: Why the host lays out the UI, how a game writes it as a tree of Boxes and Text, the ui package's defaults and helpers, and the layout rules.
order: 8
---

# The UI

A score, a pause banner or a list of controls needs layout: text that
centres, panels that stick to a corner, sizes that follow the window. Your
game can't do that layout itself, because it never learns the size of the
window or how wide a string is.

So the host does the layout. Your game describes the UI in the `ui` field
of the [Scene], and the host lays it out and draws it flat over the 3D
view. Like the rest of the Scene, the UI is a Description: your game builds
it again at each step from the Model. A game with no UI keeps the empty
list of `Scene.empty`, which costs nothing.

A UI is nested by nature. A scoreboard is a panel; inside the panel sits a
row of cells; inside each cell sits a number. So your game writes the UI as
a tree, and the host gets that same tree.

## Boxes and Text

The tree is made of two kinds of [Element]:

```roc
Element := [Box(BoxConfig, List(Element)), Text(Text)]
```

- A `Box` is a rectangle. Its [BoxConfig] says how it sizes and looks, and
  its list holds its children, laid out in order inside it.
- A `Text` draws one string. It has no children.

`Scene.ui` is a list of the root Elements. You write the tags yourself,
just as you would write any other value:

```roc
ui: [Box(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text(Ui.label("Score: 3"))])]
```

That is one Box in the top-left corner of the window, holding one line of
text. The config type is called `BoxConfig` because the `Box` tag, and
Roc's builtin `Box`, already have the name.

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
centred : Ui.BoxConfig
centred = { ..Ui.default_box, child_align: { x: Center, y: Center } }

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
	cell = |own, other| Box({ ..centred, width: Fixed(48.0) }, [Text({ ..Ui.label(own.to_str()), color: score_color(state, own, other) })])
	Box(
		{ ..Ui.panel(CenterTop, { x: 0.0, y: 16.0 }), gap: 8.0, child_align: { x: Center, y: Center } },
		[cell(score.left, score.right), Text(Ui.label(":")), cell(score.right, score.left)],
	)
}

banner : GameState, Score -> List(Element)
banner = |state, score| match state {
	Running => []
	Paused => [banner_box("Paused", white_text, "Space to resume")]
	EndGame => {
		winner = if score.left > score.right "Left" else "Right"
		[banner_box("${winner} wins", green_text, "Space to play again")]
	}
}

# Percent sizes the banner against the window. Grow stretches each row across
# the banner, so the text centres and the hint wraps inside it.
banner_box : Str, Rgba, Str -> Element
banner_box = |title, color, hint| {
	row = |child| Box({ ..centred, width: Grow({ min: 0.0, max: 0.0 }) }, [child])
	Box(
		{ ..Ui.panel(CenterCenter, { x: 0.0, y: 0.0 }), width: Percent(0.3), direction: Col, gap: 8.0, pad: Ui.pad_all(16.0) },
		[row(Text({ ..Ui.label(title), size: 40.0, color })), row(Text(Ui.label(hint)))],
	)
}

# The engine adds the offset at the same corner of the window and the box, so
# a bottom or right corner needs a negative offset.
hints : List(Element)
hints = [
	Box(Ui.panel(LeftBottom, { x: 16.0, y: -16.0 }), [Text(Ui.label("W / S"))]),
	Box(Ui.panel(RightBottom, { x: -16.0, y: -16.0 }), [Text(Ui.label("Up / Down"))]),
]

hud : Model -> List(Element)
hud = |m| [scoreboard(m.state, m.score)].concat(banner(m.state, m.score)).concat(hints)
```
<!-- endregion -->

Each function returns a value with the shape that it draws. `scoreboard`
gives one Box, a panel that holds a cell, a colon and a cell. `banner`
gives a list, empty while the game runs, so `hud` can join the roots with
`concat`. Each Box's list of children is built once, and nothing
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
		Box(_, [Box(_, [Text(left)]), Text(colon), Box(_, [Text(right)])]) => left.str == "3" and colon.str == ":" and right.str == "0"
		_ => Bool.False
	}
```
<!-- endregion -->

If the scoreboard ever gains a fourth child, or a cell holds something
other than one Text, the pattern stops matching and the test fails.

## The ui package

You write the tags yourself, so the [ui package][Ui] gives only the
starting values and a few small helpers:

- [`Ui.default_box`][Ui.default_box] is the BoxConfig to start from. It
  holds Clay's defaults: it fits its children, with no padding, no gap and
  no background, and lays them out in a `Row`.
- [`Ui.default_text`][Ui.default_text] is the Text to start from: an
  empty string, 24 pixels high, opaque white, that wraps between words.
- [`Ui.label(str)`][Ui.label] is a `default_text` that shows `str`. Change
  the rest with a record update, such as
  `Text({ ..Ui.label("Paused"), size: 40.0 })`.
- [`Ui.float_at(attach, offset)`][Ui.float_at] gives a BoxConfig that
  floats over the window at one of its points.
- [`Ui.panel(attach, offset)`][Ui.panel] is a `float_at` Box for a HUD,
  with padding, a see-through black background and round corners.
- [`Ui.pad_all(n)`][Ui.pad_all] gives the same padding on all four sides.

## The layout rules

The host lays out the UI with Clay, so the field names and the defaults
are Clay's.

- All sizes are logical pixels. The host multiplies each size by the DPI
  scale of the display.
- A Box lays out its children in a `Row`, from left to right, or in a
  `Col`, from top to bottom.
- `pad` is the space between the edges of a Box and its children. `gap` is
  the space between two children.
- `child_align` puts the children at the `Start`, the `Center` or the `End`
  of the Box, on each axis.
- A `Fit` size fits the children. A `Grow` size fills the free space in the
  parent. A `Fixed` size is the number that you give. A `Percent` size is a
  fraction of the parent, from 0 to 1.
- A Box with a `Float` attaches to the window, never to another Element,
  and ignores the layout of its parent.
- A floating Box puts its `attach` point on the same point of the window,
  then moves by `offset`. +x is to the right and +y is down, so a Box at a
  right or a bottom point needs a negative offset to move into the window.
- A Text with `wrap` set to `Words` breaks its lines between words, inside
  the width of its parent.

Your game never gets the size of the window, and no layout result comes
back to it. Use `Grow` and `Percent` to fit the UI to the window.

## Text

The host draws all Text in one font, Atkinson Hyperlegible. The font has
the ASCII characters 32 to 126, and the host draws `?` for any other
character. The host rounds the size of a Text to a whole number of pixels,
after the DPI scale.

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

The host also logs each kind of Clay error once, such as a `Percent` above
1, and draws what fits.

## Limits

The UI has no pointer input, no clipping and no scrolling yet.

[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Element]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Element
[BoxConfig]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.BoxConfig
[Ui]: https://pixelsprout.dev/projects/rocco/api/ui/
[Ui.default_box]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_box
[Ui.default_text]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_text
[Ui.label]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.label
[Ui.float_at]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.float_at
[Ui.panel]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.panel
[Ui.pad_all]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.pad_all
