#+build freestanding
package engine

import "arenas"
import "core:mem"
import "core:strings"

import "base:runtime"

// scripts/web/rocco_web.c defines these, and emcc resolves the rest
// against emscripten's libraries.
foreign import env "env.o"

BRIDGE_RETRY_MS :: 250
// The Relay closes a page with this code when a newer page replaces it.
BRIDGE_REPLACED_CODE :: 4000

// A page cannot listen on a socket, so it connects out to a Relay that the
// Driver also connects to. See ADR 0037.
Bridge_Open_Error :: enum {
	None,
	Unsupported,
}

Bridge_Socket_Event :: enum i32 {
	Open,
	Message,
	Closed,
}

// One WebSocket to the Relay. Each message is one request, and each reply
// goes back as one message. socket is 0 while there is none, and the
// transport dials again after BRIDGE_RETRY_MS.
Bridge_Transport :: struct {
	port:      int,
	socket:    i32,
	connected: bool,
	// The count of connections opened. The Relay hides each Driver's
	// connection, so devices last until the page connects again.
	drivers:   u64,
	holding:   bool,
	// Set when a newer page took the Relay. The page stops dialling.
	replaced:  bool,
	last_dial: f64,
	// The requests that arrived since the last poll, oldest first.
	requests:  [dynamic]string,
	reply:     strings.Builder,
	scratch:   arenas.Arena,
	allocator: mem.Allocator,
	// The callbacks run outside a Frame, from the browser's event loop.
	ctx:       runtime.Context,
}

Bridge_Socket_Callback :: #type proc "c" (user: rawptr, socket: i32, kind: Bridge_Socket_Event, data: [^]u8, size: u32)

@(default_calling_convention = "c")
foreign env {
	emscripten_get_now :: proc() -> f64 ---
	rocco_web_location :: proc(host: [^]u8, host_size: i32, bridge: [^]u8, bridge_size: i32) ---
	rocco_web_socket_supported :: proc() -> bool ---
	rocco_web_socket_open :: proc(port: i32, user: rawptr, on_event: Bridge_Socket_Callback) -> i32 ---
	rocco_web_socket_send :: proc(socket: i32, text: cstring) -> bool ---
	rocco_web_socket_close :: proc(socket: i32) ---
}

bridge_port_text :: proc() -> (value, name: string) {
	host, bridge: [256]u8
	rocco_web_location(&host[0], len(host), &bridge[0], len(bridge))
	hostname := strings.clone_from_cstring(cstring(&host[0]), context.temp_allocator)
	value = strings.clone_from_cstring(cstring(&bridge[0]), context.temp_allocator)
	return bridge_web_port_text(hostname, value), "?bridge"
}

bridge_transport_open :: proc(t: ^Bridge_Transport, port: int, allocator: mem.Allocator) -> Bridge_Open_Error {
	if !rocco_web_socket_supported() {
		return .Unsupported
	}
	t.port = port
	t.allocator = allocator
	t.ctx = context
	t.requests = make([dynamic]string, allocator)
	t.reply = strings.builder_make(allocator)
	bridge_transport_dial(t)
	return nil
}

bridge_transport_close :: proc(t: ^Bridge_Transport) {
	if t.socket != 0 {
		socket := t.socket
		// The close event that follows names a socket the transport no longer has.
		t.socket = 0
		t.connected = false
		rocco_web_socket_close(socket)
	}
	bridge_transport_clear_requests(t)
	delete(t.requests)
	strings.builder_destroy(&t.reply)
	arenas.destroy(&t.scratch)
}

// A handler that returns .Stop or .Hold ends the poll, and the next poll
// answers the requests that are left first. wait is for Headless only.
bridge_transport_poll :: proc(t: ^Bridge_Transport, wait: bool, handle: Bridge_Handler, ctx: rawptr) {
	if t.holding {
		return
	}
	if t.socket == 0 {
		bridge_transport_dial(t)
		return
	}
	for len(t.requests) > 0 {
		line := pop_front(&t.requests)
		next := bridge_transport_answer(t, line, handle, ctx)
		delete(line, t.allocator)
		if next != .Read {
			return
		}
	}
}

// Sends the reply that a .Hold kept back, and lets the poll read again. A
// page that has lost its socket sends nothing.
bridge_transport_send_held :: proc(t: ^Bridge_Transport, reply: string) {
	t.holding = false
	strings.builder_reset(&t.reply)
	strings.write_string(&t.reply, reply)
	bridge_transport_send(t)
}

@(private = "file")
bridge_transport_dial :: proc(t: ^Bridge_Transport) {
	if t.replaced {
		return
	}
	now := emscripten_get_now()
	if t.last_dial != 0 && now - t.last_dial < BRIDGE_RETRY_MS {
		return
	}
	t.last_dial = now
	t.socket = rocco_web_socket_open(i32(t.port), t, bridge_transport_on_event)
}

@(private = "file")
bridge_transport_on_event :: proc "c" (user: rawptr, socket: i32, kind: Bridge_Socket_Event, data: [^]u8, size: u32) {
	t := (^Bridge_Transport)(user)
	context = t.ctx
	if socket != t.socket {
		return
	}
	switch kind {
	case .Open:
		t.connected = true
		t.drivers += 1
	case .Message:
		append(&t.requests, strings.clone(string(data[:size]), t.allocator))
	case .Closed:
		// size is the close code. A reply held for this socket goes nowhere, and the run goes on.
		t.connected = false
		t.socket = 0
		t.replaced = size == BRIDGE_REPLACED_CODE
		bridge_transport_clear_requests(t)
	}
}

@(private = "file")
bridge_transport_answer :: proc(t: ^Bridge_Transport, line: string, handle: Bridge_Handler, ctx: rawptr) -> (next: Bridge_Next) {
	strings.builder_reset(&t.reply)
	{
		context.temp_allocator = arenas.allocator(&t.scratch)
		defer arenas.free_all(&t.scratch)
		if len(line) > BRIDGE_MAX_LINE {
			bridge_reply_error(&t.reply, "the request is longer than 1 MiB")
		} else {
			next = handle(ctx, line, &t.reply)
		}
	}
	if next == .Hold {
		t.holding = true
		return
	}
	bridge_transport_send(t)
	return
}

@(private = "file")
bridge_transport_send :: proc(t: ^Bridge_Transport) {
	if !t.connected {
		return
	}
	strings.write_byte(&t.reply, 0)
	rocco_web_socket_send(t.socket, cstring(raw_data(t.reply.buf)))
}

@(private = "file")
bridge_transport_clear_requests :: proc(t: ^Bridge_Transport) {
	for line in t.requests {
		delete(line, t.allocator)
	}
	clear(&t.requests)
}
