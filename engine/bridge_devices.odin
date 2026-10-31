package engine

// The real devices reach the step only for the Driver that turned them on in
// hello. A Driver that reconnects, or says hello without devices, gets none.
bridge_devices_on :: proc(b: ^Bridge) -> bool {
	return b.on && b.devices && b.transport.connected && b.devices_driver == b.transport.drivers
}
