import Vocabulary

## Gives an Input for tests. The host builds the real one.
Input := [].{

	## An Input with no keys, no mouse movement and no gamepads. Give it to
	## `step` in a test.
	empty : Vocabulary.Input
	empty = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [] }

	## A Gamepad in slot 0 with no button down and the sticks and triggers at
	## rest. Change the fields that a test needs:
	## `{ ..Input.idle_gamepad, held: [Button.code(South)] }`.
	idle_gamepad : Vocabulary.Gamepad
	idle_gamepad = { slot: 0, held: [], pressed: [], left_stick: { x: 0.0, y: 0.0 }, right_stick: { x: 0.0, y: 0.0 }, left_trigger: 0.0, right_trigger: 0.0 }
}

expect Input.empty == { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [] }
