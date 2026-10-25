package engine

// A stub until this OS has a backend. It reports no pads.
Gamepad_Backend :: struct {}

gamepad_backend_init :: proc(backend: ^Gamepad_Backend) {}

// Writes each connected pad to out and returns the count. See Gamepad_Raw.
gamepad_backend_poll :: proc(backend: ^Gamepad_Backend, out: []Gamepad_Raw) -> int {
	return 0
}

gamepad_backend_shutdown :: proc(backend: ^Gamepad_Backend) {}
