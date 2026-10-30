import Vocabulary

## Gives an Input for tests. The host builds the real one.
Input := [].{

	## An Input with no keys, no mouse movement, no gamepads, the 960 by 540
	## window of `Launch.default`, and a pointer outside the window at (0, 0)
	## with no buttons down. Give it to `step` in a test.
	empty : Vocabulary.Input
	empty = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [], window: { width: 960.0, height: 540.0 }, pointer: { x: 0.0, y: 0.0, inside: Bool.False, held: [], pressed: [], released: [], wheel: { dx: 0.0, dy: 0.0 } } }

	## A Gamepad in slot 0 with no button down and the sticks and triggers at
	## rest. Change the fields that a test needs:
	## `{ ..Input.idle_gamepad, held: [Button.code(South)] }`.
	idle_gamepad : Vocabulary.Gamepad
	idle_gamepad = { slot: 0, held: [], pressed: [], left_stick: { x: 0.0, y: 0.0 }, right_stick: { x: 0.0, y: 0.0 }, left_trigger: 0.0, right_trigger: 0.0 }
}

expect Input.empty == { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [], window: { width: 960.0, height: 540.0 }, pointer: { x: 0.0, y: 0.0, inside: Bool.False, held: [], pressed: [], released: [], wheel: { dx: 0.0, dy: 0.0 } } }
