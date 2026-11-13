#+build freestanding
package engine

// The web host reads no gamepads yet. Every poll reports no connected pad.
Gamepad_Reader :: struct {}

gamepad_reader_init :: proc(reader: ^Gamepad_Reader) {}

gamepad_reader_poll :: proc(reader: ^Gamepad_Reader, out: []Gamepad_Raw) -> int {
	return 0
}

gamepad_reader_shutdown :: proc(reader: ^Gamepad_Reader) {}
