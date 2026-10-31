package engine

// The real devices reach the step only for the Driver that turned them on in
// hello. A Driver that reconnects, or says hello without devices, gets none.
bridge_devices_on :: proc(b: ^Bridge) -> bool {
	return b.on && b.devices && b.transport.connected && b.devices_driver == b.transport.drivers
}

// Merges the request's mouse buttons with the real ones, as the keys merge.
// A real click between two steps has no held button left to show it, so the
// real pressed and released count too.
bridge_merge_buttons :: proc(request_held, request_tap, real_held, real_pressed, real_released, prev: Mouse_Buttons) -> (held, pressed, released: Mouse_Buttons) {
	held = request_held + real_held
	pressed = (held - prev) + request_tap + (real_pressed - prev)
	released = (prev - held) + request_tap + (real_released - held)
	return
}
