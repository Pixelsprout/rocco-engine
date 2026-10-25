import Vocabulary

## Gives an Input for tests. The host builds the real one.
Input := [].{

	## An Input with no keys, no mouse movement and no gamepads. Give it to
	## `step` in a test.
	empty : Vocabulary.Input
	empty = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [] }
}

expect Input.empty == { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 }, gamepads: [] }
