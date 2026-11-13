#+build !freestanding
package engine

import "arenas"
import "core:mem"
import "core:net"
import "core:strings"

Bridge_Open_Error :: net.Network_Error

// One listening socket and at most one Driver. Both sockets are
// non-blocking, except while poll waits and while a reply is sent.
Bridge_Transport :: struct {
	listener:          net.TCP_Socket,
	driver:            net.TCP_Socket,
	connected:         bool,
	// The count of Drivers accepted, so a setting can belong to one Driver.
	drivers:           u64,
	holding:           bool,
	listener_blocking: bool,
	driver_blocking:   bool,
	lines:             Json_Lines,
	read_buf:          []u8,
	reply:             strings.Builder,
	scratch:           arenas.Arena,
	allocator:         mem.Allocator,
}

// Port 0 asks the OS for a free port. Only tests use it.
bridge_transport_open :: proc(t: ^Bridge_Transport, port: int, allocator: mem.Allocator) -> net.Network_Error {
	t.listener = net.listen_tcp({net.IP4_Loopback, port}, backlog = 1) or_return
	t.listener_blocking = true
	if err := bridge_transport_listener_blocking(t, false); err != nil {
		net.close(t.listener)
		return err
	}
	t.allocator = allocator
	json_lines_init(&t.lines, allocator)
	t.read_buf = make([]u8, BRIDGE_READ_SIZE, allocator)
	t.reply = strings.builder_make(allocator)
	return nil
}

bridge_transport_close :: proc(t: ^Bridge_Transport) {
	bridge_transport_disconnect(t)
	net.close(t.listener)
	json_lines_destroy(&t.lines)
	delete(t.read_buf, t.allocator)
	strings.builder_destroy(&t.reply)
	arenas.destroy(&t.scratch)
}

bridge_transport_port :: proc(t: ^Bridge_Transport) -> int {
	endpoint, err := net.bound_endpoint(t.listener)
	return endpoint.port if err == nil else 0
}

// Answers each request the socket holds, then returns. With wait, it first
// blocks until it has answered one request, and after a disconnect it waits
// for the next Driver. A handler that returns .Stop or .Hold ends the poll,
// and the next poll answers the lines that are left first. While a reply is
// held, the poll does nothing.
bridge_transport_poll :: proc(t: ^Bridge_Transport, wait: bool, handle: Bridge_Handler, ctx: rawptr) {
	if t.holding {
		return
	}
	answered := 0
	for {
		if !t.connected && !bridge_transport_accept(t, wait && answered == 0) {
			return
		}
		for t.connected {
			line, status := json_lines_next(&t.lines)
			if status == .None {
				break
			}
			next := bridge_transport_answer(t, line, status, handle, ctx)
			answered += 1
			if next != .Read {
				return
			}
		}
		if !t.connected {
			continue
		}
		block := wait && answered == 0
		if bridge_transport_driver_blocking(t, block) != nil {
			bridge_transport_disconnect(t)
			continue
		}
		n, err := net.recv_tcp(t.driver, t.read_buf)
		if err == .Would_Block || err == .Interrupted {
			if block {
				continue
			}
			return
		}
		if err != nil || n == 0 {
			bridge_transport_disconnect(t)
			continue
		}
		json_lines_push(&t.lines, t.read_buf[:n])
	}
}

@(private = "file")
bridge_transport_accept :: proc(t: ^Bridge_Transport, block: bool) -> bool {
	if bridge_transport_listener_blocking(t, block) != nil {
		return false
	}
	driver, _, err := net.accept_tcp(t.listener)
	if err != nil {
		return false
	}
	t.driver = driver
	t.connected = true
	t.drivers += 1
	// Linux does not pass the listener's mode to the accepted socket, and
	// macOS does, so set it.
	t.driver_blocking = !block
	clear(&t.lines.buf)
	t.lines.start = 0
	t.lines.too_long = false
	return true
}

// Sends the reply that a .Hold kept back, and lets the poll read again. A
// Driver that has gone gets nothing.
bridge_transport_send_held :: proc(t: ^Bridge_Transport, reply: string) {
	t.holding = false
	if !t.connected {
		return
	}
	strings.builder_reset(&t.reply)
	strings.write_string(&t.reply, reply)
	bridge_transport_send(t)
}

@(private = "file")
bridge_transport_answer :: proc(t: ^Bridge_Transport, line: string, status: Json_Line_Status, handle: Bridge_Handler, ctx: rawptr) -> (next: Bridge_Next) {
	strings.builder_reset(&t.reply)
	{
		context.temp_allocator = arenas.allocator(&t.scratch)
		defer arenas.free_all(&t.scratch)
		if status == .Too_Long {
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

// Sends the reply builder with a newline. A failed send drops the Driver.
@(private = "file")
bridge_transport_send :: proc(t: ^Bridge_Transport) {
	if !t.connected {
		return
	}
	strings.write_byte(&t.reply, '\n')
	// A reply can be larger than the socket buffer, so it is sent blocking.
	if bridge_transport_driver_blocking(t, true) != nil {
		bridge_transport_disconnect(t)
		return
	}
	if _, err := net.send_tcp(t.driver, t.reply.buf[:]); err != nil {
		bridge_transport_disconnect(t)
	}
}

@(private = "file")
bridge_transport_disconnect :: proc(t: ^Bridge_Transport) {
	if !t.connected {
		return
	}
	net.close(t.driver)
	t.connected = false
}

@(private = "file")
bridge_transport_listener_blocking :: proc(t: ^Bridge_Transport, block: bool) -> net.Network_Error {
	if t.listener_blocking == block {
		return nil
	}
	net.set_blocking(t.listener, block) or_return
	t.listener_blocking = block
	return nil
}

@(private = "file")
bridge_transport_driver_blocking :: proc(t: ^Bridge_Transport, block: bool) -> net.Network_Error {
	if t.driver_blocking == block {
		return nil
	}
	net.set_blocking(t.driver, block) or_return
	t.driver_blocking = block
	return nil
}
