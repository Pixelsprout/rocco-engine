# The key and mouse button codes that the widgets read, and an empty Input and
# QueryResults for their tests. A package cannot import the platform, so the
# codes copy pf.Key and pf.MouseButton, which carry sokol's codes. The
# expects in examples/widgets drive Focus with pf.Key codes.
Seam := [].{

	Key : [Space, Enter, Tab, PageUp, PageDown, Home, End, LeftShift, RightShift]

	MouseButton : [Left, Right, Middle]

	key_code : Key -> U16
	key_code = |key| match key {
		Space => 32
		Enter => 257
		Tab => 258
		PageUp => 266
		PageDown => 267
		Home => 268
		End => 269
		LeftShift => 340
		RightShift => 344
	}

	button_code : MouseButton -> U8
	button_code = |button| match button {
		Left => 0
		Right => 1
		Middle => 2
	}

	is_key_held : { held : List(U16), ..input }, Key -> Bool
	is_key_held = |input, key| input.held.contains(key_code(key))

	is_key_pressed : { pressed : List(U16), ..input }, Key -> Bool
	is_key_pressed = |input, key| input.pressed.contains(key_code(key))

	is_button_held : { pointer : { held : List(U8), ..pointer }, ..input }, MouseButton -> Bool
	is_button_held = |input, button| input.pointer.held.contains(button_code(button))

	is_button_pressed : { pointer : { pressed : List(U8), ..pointer }, ..input }, MouseButton -> Bool
	is_button_pressed = |input, button| input.pointer.pressed.contains(button_code(button))

	is_button_released : { pointer : { released : List(U8), ..pointer }, ..input }, MouseButton -> Bool
	is_button_released = |input, button| input.pointer.released.contains(button_code(button))

	TestInput : { held : List(U16), pressed : List(U16), pointer : { x : F32, y : F32, held : List(U8), pressed : List(U8), released : List(U8), wheel : { dx : F32, dy : F32 } } }

	TestResults : { ui : { over : List(U64), scroll : List({ id : U64, view : { width : F32, height : F32 }, content : { width : F32, height : F32 } }) } }

	input : TestInput
	input = { held: [], pressed: [], pointer: { x: 0.0, y: 0.0, held: [], pressed: [], released: [], wheel: { dx: 0.0, dy: 0.0 } } }

	results : TestResults
	results = { ui: { over: [], scroll: [] } }
}
