---
title: The UI
summary: Why the host lays out the UI, how the ui package builds Boxes and Text from nested code, and the layout rules.
order: 8
---

# The UI

A score, a pause banner or a list of controls needs layout: text that
centres, panels that stick to a corner, sizes that follow the window. Your
game can't do that layout itself, because it never learns the size of the
window or how wide a string is.

So the host does the layout. Your game describes the UI in the `ui` field
of the [Scene], as a list of [Element]s, and the host lays them out and
draws them flat over the 3D view. Like the rest of the Scene, the UI is a
Description: your game builds it again at each step from the Model. A game
with no UI keeps the empty list of `Scene.empty`.

## A first UI

Add `ui: "{{ui_url}}"` to the header of your app, then write
`import ui.Ui`. On GitHub, get the URL as
[Shipping a game](shipping.md#the-header) explains.

Pong shows its score at the top, a banner when it is paused or won, and
its keys in the bottom corners:

<!-- region: examples/pong/main.roc#ui -->
```roc
label : Ui.TextStyle
label = { size: 24.0, color: white_text, wrap: Words }

panel : Ui.AttachPoint, Ui.Offset -> Ui.BoxConfig
panel = |attach, offset| { ..Ui.float_at(attach, offset), pad: Ui.pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }

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
scoreboard : GameState, Score -> List(Element)
scoreboard = |state, score| {
	cell = |own, other| Ui.box({ ..centred, width: Fixed(48.0) }, [Ui.text(own.to_str(), { ..label, color: score_color(state, own, other) })])
	Ui.box(
		{ ..panel(CenterTop, { x: 0.0, y: 16.0 }), gap: 8.0, child_align: { x: Center, y: Center } },
		[cell(score.left, score.right), Ui.text(":", label), cell(score.right, score.left)],
	)
}

banner : GameState, Score -> List(Element)
banner = |state, score| match state {
	Running => []
	Paused => banner_box("Paused", white_text, "Space to resume")
	EndGame => {
		winner = if score.left > score.right "Left" else "Right"
		banner_box("${winner} wins", green_text, "Space to play again")
	}
}

# Percent sizes the banner against the window. Grow stretches each row across
# the banner, so the text centres and the hint wraps inside it.
banner_box : Str, Rgba, Str -> List(Element)
banner_box = |title, color, hint| {
	row = |child| Ui.box({ ..centred, width: Grow({ min: 0.0, max: 0.0 }) }, [child])
	Ui.box(
		{ ..panel(CenterCenter, { x: 0.0, y: 0.0 }), width: Percent(0.3), direction: Col, gap: 8.0, pad: Ui.pad_all(16.0) },
		[row(Ui.text(title, { ..label, size: 40.0, color })), row(Ui.text(hint, label))],
	)
}

# The engine adds the offset at the same corner of the window and the box, so
# a bottom or right corner needs a negative offset.
hints : List(Element)
hints = Ui.box(panel(LeftBottom, { x: 16.0, y: -16.0 }), [Ui.text("W / S", label)])
	.concat(Ui.box(panel(RightBottom, { x: -16.0, y: -16.0 }), [Ui.text("Up / Down", label)]))
```
<!-- endregion -->

## The ui package

You don't write the list of Elements by hand. The [ui package][Ui] builds
it from nested code:

- [`Ui.box(config, children)`][Ui.box] gives a Box with its children. Each
  child is a list of Elements, so Boxes and Text mix in one list.
- [`Ui.text(str, style)`][Ui.text] gives one Text.
- [`Ui.default_box`][Ui.default_box] is the BoxConfig to start from.
- [`Ui.float_at(attach, offset)`][Ui.float_at] gives a Box that floats
  over the window.
- [`Ui.pad_all(n)`][Ui.pad_all] gives the same padding on all four sides.

## Elements, Boxes and Text

Under the ui package, the UI is a flat list with three kinds of Element:

- `Open` starts a Box. A Box is a rectangle that holds other Elements.
- `Text` draws one string.
- `Close` ends the last Box that is open.

The Elements between an `Open` and its `Close` are the children of the
Box. The list stays flat, and an Element's place in the list is its
identity. The type of a Box is [BoxConfig], because Roc's builtin `Box`
already has the name.

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

A mistake in the UI does not stop the game. The host repairs each of these
errors, and logs each one once:

- a `Close` with no open Box: the host ignores it.
- a Box that is still open at the end of the list: the host closes it.
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
[Ui.box]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.box
[Ui.text]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.text
[Ui.default_box]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_box
[Ui.float_at]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.float_at
[Ui.pad_all]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.pad_all
