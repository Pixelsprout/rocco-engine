#+build freestanding
package engine

import "core:mem"

// A page cannot listen on a socket. The web Bridge waits for a WebSocket
// that the page opens to the Driver.
Bridge_Open_Error :: enum {
	None,
	Unsupported,
}

Bridge_Transport :: struct {
	connected: bool,
	drivers:   u64,
	holding:   bool,
}

bridge_transport_open :: proc(t: ^Bridge_Transport, port: int, allocator: mem.Allocator) -> Bridge_Open_Error {
	return .Unsupported
}

bridge_transport_close :: proc(t: ^Bridge_Transport) {}

bridge_transport_poll :: proc(t: ^Bridge_Transport, wait: bool, handle: Bridge_Handler, ctx: rawptr) {}

bridge_transport_send_held :: proc(t: ^Bridge_Transport, reply: string) {}
