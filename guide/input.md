---
title: Input
summary: The keys that are held and pressed at each step, the mouse movement, and the mouse lock.
order: 5
---

# Input

The host gives `step` an [Input] at each fixed step. The Input tells what
the player did: the keys that are down, the keys that went down, and the
mouse movement. The host does not decide what a key means. Your game decides
what each key means.

## Keys held and pressed

A key is held while it is down. A key is pressed in the first step after it
went down. So:

- Held is a state. Ask in two steps, and you get the same answer while the
  key stays down.
- Pressed is an edge. It is true in exactly one step for each key press.
- A key that the player taps between two steps is pressed but not held.
- A key that repeats while the player holds it is not pressed again.

Use the [Key] module to read the Input. [`Key.held`][Key.held] and
[`Key.pressed`][Key.pressed] take a key name, such as `W` or `Space`.
[`Key.axis`][Key.axis] turns two held keys into -1, 0 or 1.

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

Space makes the player jump once for each press, not for each step while
it is held:

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

The host holds a press until a step takes it. The first step of a frame
gets the presses since the last step. The later steps of that frame get no
presses. If a frame runs no step, the next step gets the presses.

The host removes no key from the Input. It gives no key a meaning. When the
window loses focus, the host releases each held key.

## The mouse

`Input.mouse` holds `dx` and `dy`: the mouse movement since the last step.
+`dx` is to the right and +`dy` is down. The unit changes with the OS and
with the mouse lock, so tune the mouse speed of your game on each OS. The first step of a frame gets the movement, and the later steps of
that frame get zero, as for presses.

The Input has no mouse buttons and no gamepad.

## The mouse lock

The [Cursor] field of the Scene locks the mouse or frees it:

- `Free` shows the pointer. This is the value in `Scene.empty`.
- `Locked` hides the pointer and keeps it in the window. The mouse still
  gives `dx` and `dy`.

The Cursor is a state, so it is a field of the [Scene] and not a [Command]. Once
in each frame, the host compares the Cursor of the current Scene with the
mouse lock. If they differ, the host locks or frees the mouse.

With `ROCCO_DEBUG_CAMERA=1`, the host locks the mouse and ignores the
Cursor. See [Running and debugging](running.md).

## Test the input

The Input holds key codes, not key names. In a test, make the codes with
[`Key.code`][Key.code]. Pong holds W for one long step and checks the
paddles:

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
