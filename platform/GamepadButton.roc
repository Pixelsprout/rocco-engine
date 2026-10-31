import Vocabulary exposing [Gamepad]
import Input

## A gamepad button, named by its place on the pad, not by its label. `South`
## is the bottom face button: A on an Xbox pad, Cross on a PlayStation pad and
## B on a Switch pad. A Gamepad carries the code. Your game decides what a
## button means.
##
## The triggers are not buttons. Read `left_trigger` and `right_trigger`.
GamepadButton := [
	South,
	East,
	West,
	North,
	LeftShoulder,
	RightShoulder,
	LeftStick,
	RightStick,
	Start,
	Back,
	DpadUp,
	DpadDown,
	DpadLeft,
	DpadRight,
].{

	## The code of a button, as a Gamepad carries it.
	code : GamepadButton -> U8
	code = |button| match button {
		South => 0
		East => 1
		West => 2
		North => 3
		LeftShoulder => 4
		RightShoulder => 5
		LeftStick => 6
		RightStick => 7
		Start => 8
		Back => 9
		DpadUp => 10
		DpadDown => 11
		DpadLeft => 12
		DpadRight => 13
	}

	## True while the button is down on this pad.
	held : Gamepad, GamepadButton -> Bool
	held = |gamepad, button| List.contains(gamepad.held, code(button))

	## True in the first step after the button went down on this pad. A button
	## tapped between two steps is pressed but not held.
	pressed : Gamepad, GamepadButton -> Bool
	pressed = |gamepad, button| List.contains(gamepad.pressed, code(button))

	## True while the button is down on any pad. For a game with one player.
	held_any : Vocabulary.Input, GamepadButton -> Bool
	held_any = |input, button| List.any(input.gamepads, |gamepad| held(gamepad, button))

	## True when the button went down on any pad since the previous step.
	pressed_any : Vocabulary.Input, GamepadButton -> Bool
	pressed_any = |input, button| List.any(input.gamepads, |gamepad| pressed(gamepad, button))
}

expect GamepadButton.code(South) == 0
expect GamepadButton.code(Start) == 8
expect GamepadButton.code(DpadRight) == 13

idle = Input.idle_gamepad

expect GamepadButton.held({ ..idle, held: [0] }, South) and !GamepadButton.held({ ..idle, pressed: [0] }, South)
expect GamepadButton.pressed({ ..idle, pressed: [8] }, Start) and !GamepadButton.pressed({ ..idle, held: [8] }, Start)
expect !GamepadButton.held(idle, South) and !GamepadButton.pressed(idle, South)
expect !GamepadButton.held_any(Input.empty, South) and !GamepadButton.pressed_any(Input.empty, South)
expect GamepadButton.held_any({ ..Input.empty, gamepads: [idle, { ..idle, slot: 2, held: [10] }] }, DpadUp)
expect GamepadButton.pressed_any({ ..Input.empty, gamepads: [{ ..idle, slot: 1, pressed: [1] }] }, East)
expect !GamepadButton.held_any({ ..Input.empty, gamepads: [{ ..idle, pressed: [1] }] }, East)
