---
title: Input
summary: Held keys for things that last and pressed keys for things that happen once, the mouse movement, the mouse lock, the window size, and how to test input.
order: 6
---

# Input

A game asks two different questions about a key. "Is W down right now?"
makes the player walk for as long as the key is down. "Did Space just go
down?" makes the player jump once. If you answer the second question with
the first, the player jumps at every step while Space is down.

So the host gives `step` an [Input] at each fixed step with both answers:
the keys that are held, the keys that were pressed, the mouse movement, the
gamepads and the window size. The host never decides what a key means, and
it removes no key from the Input. What each key does is up to your game.

This page covers the keyboard and the mouse. [Gamepads](gamepad.md) covers
the pads.

## Read the keys

Use the [Key] module to read the Input:

- [`Key.held`][Key.held] tells if a key is down, such as `W` or `Space`.
- [`Key.pressed`][Key.pressed] tells if a key went down since the last
  step.
- [`Key.axis`][Key.axis] turns two held keys into -1, 0 or 1.

The entity game binds W, A, S and D to a direction, and Escape to `Quit`:

<!-- region: examples/entity-game/main.roc#keys -->
```roc
# The game, not the engine, decides what each key means.
move_dir : Vocabulary.Input -> Vec3
move_dir = |input| { x: Key.axis(input, A, D), y: 0.0, z: Key.axis(input, W, S) }

# Reads the raw input, so ESC quits during the celebration too.
quit_on_escape : Vocabulary.Input -> List(Command)
quit_on_escape = |input|
	if Key.pressed(input, Escape) {
		[Quit]
	} else {
		[]
	}
```
<!-- endregion -->

The host binds no key to `Quit`, so a game that should quit on Escape has
to do it like this.

Space makes the player jump once for each press, not once for each step
while it is held:

<!-- region: examples/entity-game/main.roc#jump -->
```roc
jump : Model, Vocabulary.Input -> Model
jump = |m, input|
	if Key.pressed(input, Space) {
		map_entities(
			m,
			|e| match e.kind {
				Player(p) if p.grounded => { ..e, kind: Player({ grounded: Bool.False }), vel: { ..e.vel, y: jump_speed } }
				_ => e
			},
		)
	} else {
		m
	}
```
<!-- endregion -->

## Held and pressed

A key is held while it is down. A key is pressed only in the first step
after it went down. In other words:

- Held is a state. If you ask in two steps while the key stays down, you
  get the same answer.
- Pressed is an edge. It is true in exactly one step for each key press.
- A key that the player taps between two steps is pressed but not held.
- A key that repeats while the player holds it is not pressed again.

The host keeps a press until a step takes it. The first step of a frame
gets the presses since the last step, and the later steps of that frame get
none. If a frame runs no step, the next step gets the presses.

When the window loses focus, the host releases each held key.

## The mouse

`Input.mouse` holds `dx` and `dy`: how far the mouse moved since the last
step. +`dx` is to the right and +`dy` is down. The unit changes with the OS
and with the mouse lock, so tune your game's mouse speed on each OS. As
with presses, the first step of a frame gets the movement, and the later
steps of that frame get zero.

The Input has no mouse buttons yet.

## The window size

`Input.window` holds the `width` and `height` of the window in logical
pixels, the unit of the UI. The host reads it once per frame, so it
follows a resize. A Headless run gets the Launch width and height. Pass it
to `Camera.project` to put a label over a point in the world.

## The mouse lock

The [Cursor] field of the Scene locks or frees the mouse:

- `Free` shows the pointer. This is the value in `Scene.empty`.
- `Locked` hides the pointer and keeps it in the window. The mouse still
  gives `dx` and `dy`.

The Cursor is a field of the [Scene], not a [Command], because it is a
state that should stay true at each step. Once in each frame, the host
compares the Cursor of the current Scene with the mouse lock, and locks or
frees the mouse if they differ.

With `ROCCO_DEBUG_CAMERA=1`, the host locks the mouse and ignores the
Cursor. See [Running and debugging](running.md).

## Test the input

The Input holds key codes, not key names, so in a test you make the codes
with [`Key.code`][Key.code]. This pong test holds W for one long step and
checks the paddles:

<!-- region: examples/pong/main.roc#input-test -->
```roc
# Holding W for a long step drives the left paddle to its limit, the right stays put.
expect {
	stepped = step(init(Config.empty).model, { ..Input.empty, held: [Key.code(W)] }, QueryResults.empty, 10.0)
	m = stepped.model
	stepped.commands == [] and m.left == -paddle_limit and m.right == 0.0
}
```
<!-- endregion -->

[Input]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Input
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Cursor]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Cursor
[Key]: https://pixelsprout.dev/projects/rocco/api/platform/Key/
[Key.held]: https://pixelsprout.dev/projects/rocco/api/platform/Key/#Key.held
[Key.pressed]: https://pixelsprout.dev/projects/rocco/api/platform/Key/#Key.pressed
[Key.axis]: https://pixelsprout.dev/projects/rocco/api/platform/Key/#Key.axis
[Key.code]: https://pixelsprout.dev/projects/rocco/api/platform/Key/#Key.code
