import Vocabulary
import Input

## A mouse button. The pointer carries the code. Your game decides what a
## button means.
MouseButton := [Left, Right, Middle].{

	## The code of a button, as the pointer carries it.
	code : MouseButton -> U8
	code = |button| match button {
		Left => 0
		Right => 1
		Middle => 2
	}

	## True while the button is down.
	held : Vocabulary.Input, MouseButton -> Bool
	held = |input, button| List.contains(input.pointer.held, code(button))

	## True in the first step after the button went down. A button clicked
	## between two steps is pressed and released but not held.
	pressed : Vocabulary.Input, MouseButton -> Bool
	pressed = |input, button| List.contains(input.pointer.pressed, code(button))

	## True in the first step after the button went up.
	released : Vocabulary.Input, MouseButton -> Bool
	released = |input, button| List.contains(input.pointer.released, code(button))
}

expect MouseButton.code(Left) == 0 and MouseButton.code(Right) == 1 and MouseButton.code(Middle) == 2

pointer = Input.empty.pointer

expect MouseButton.held({ ..Input.empty, pointer: { ..pointer, held: [0] } }, Left)
expect MouseButton.pressed({ ..Input.empty, pointer: { ..pointer, pressed: [1] } }, Right) and !MouseButton.held({ ..Input.empty, pointer: { ..pointer, pressed: [1] } }, Right)
expect MouseButton.released({ ..Input.empty, pointer: { ..pointer, released: [2] } }, Middle)
expect !MouseButton.held(Input.empty, Left) and !MouseButton.pressed(Input.empty, Left) and !MouseButton.released(Input.empty, Left)
