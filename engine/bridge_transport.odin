package engine

import "core:bytes"
import "core:encoding/json"
import "core:mem"
import vmem "core:mem/virtual"
import "core:net"
import "core:strings"

// A longer request gets an error reply, so a Driver bug cannot fill memory.
BRIDGE_MAX_LINE :: 1 * mem.Megabyte
BRIDGE_READ_SIZE :: 16 * mem.Kilobyte

// What the transport does after a reply.
Bridge_Next :: enum {
	Read,
	Stop,
}

Json_Line_Status :: enum {
	None,
	Line,
	Too_Long,
}

// Splits the bytes from the socket into lines. A line is valid until the
// next push.
Json_Lines :: struct {
	buf:      [dynamic]u8,
	start:    int,
	too_long: bool,
}

// Answers one request line. The transport knows no op. It frees the
// context.temp_allocator after each request, and sends reply with a newline.
Bridge_Handler :: #type proc(ctx: rawptr, line: string, reply: ^strings.Builder) -> Bridge_Next

// One listening socket and at most one Driver. Both sockets are
// non-blocking, except while poll waits and while a reply is sent.
Bridge_Transport :: struct {
	listener:          net.TCP_Socket,
	driver:            net.TCP_Socket,
	connected:         bool,
	listener_blocking: bool,
	driver_blocking:   bool,
	lines:             Json_Lines,
	read_buf:          []u8,
	reply:             strings.Builder,
	scratch:           vmem.Arena,
	allocator:         mem.Allocator,
}

json_lines_init :: proc(f: ^Json_Lines, allocator: mem.Allocator) {
	f.buf = make([dynamic]u8, allocator)
}

json_lines_destroy :: proc(f: ^Json_Lines) {
	delete(f.buf)
}

json_lines_push :: proc(f: ^Json_Lines, data: []u8) {
	remove_range(&f.buf, 0, f.start)
	f.start = 0
	append(&f.buf, ..data)
}

// A blank line is skipped. A trailing carriage return is dropped, so a
// Driver on Windows can send CRLF.
json_lines_next :: proc(f: ^Json_Lines) -> (line: string, status: Json_Line_Status) {
	for {
		end := bytes.index_byte(f.buf[f.start:], '\n')
		if end < 0 {
			if len(f.buf) - f.start > BRIDGE_MAX_LINE {
				f.too_long = true
				clear(&f.buf)
				f.start = 0
			}
			return "", .None
		}
		line = string(f.buf[f.start:][:end])
		f.start += end + 1
		if f.too_long {
			f.too_long = false
			return "", .Too_Long
		}
		line = strings.trim_suffix(line, "\r")
		if strings.trim_space(line) != "" {
			return line, .Line
		}
	}
}

// Every reply is one object with ok. A failed one also has error.
bridge_reply_error :: proc(reply: ^strings.Builder, message: string) {
	strings.builder_reset(reply)
	strings.write_string(reply, `{"ok":false`)
	bridge_reply_field(reply, "error", message)
	strings.write_byte(reply, '}')
}

// Writes ,"key":value. value is any type that json.marshal takes.
bridge_reply_field :: proc(reply: ^strings.Builder, key: string, value: any) {
	strings.write_byte(reply, ',')
	_ = json.marshal_to_builder(reply, key, &{})
	strings.write_byte(reply, ':')
	_ = json.marshal_to_builder(reply, value, &{})
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
	vmem.arena_destroy(&t.scratch)
}

bridge_transport_port :: proc(t: ^Bridge_Transport) -> int {
	endpoint, err := net.bound_endpoint(t.listener)
	return endpoint.port if err == nil else 0
}

// Answers each request the socket holds, then returns. With wait, it first
// blocks until it has answered one request, and after a disconnect it waits
// for the next Driver. A handler that returns .Stop ends the poll, and the
// next poll answers the lines that are left first.
bridge_transport_poll :: proc(t: ^Bridge_Transport, wait: bool, handle: Bridge_Handler, ctx: rawptr) {
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
			if next == .Stop {
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
	// Linux does not pass the listener's mode to the accepted socket, and
	// macOS does, so set it.
	t.driver_blocking = !block
	clear(&t.lines.buf)
	t.lines.start = 0
	t.lines.too_long = false
	return true
}

// A failed send drops the Driver.
@(private = "file")
bridge_transport_answer :: proc(t: ^Bridge_Transport, line: string, status: Json_Line_Status, handle: Bridge_Handler, ctx: rawptr) -> (next: Bridge_Next) {
	strings.builder_reset(&t.reply)
	{
		context.temp_allocator = vmem.arena_allocator(&t.scratch)
		defer vmem.arena_free_all(&t.scratch)
		if status == .Too_Long {
			bridge_reply_error(&t.reply, "the request is longer than 1 MiB")
		} else {
			next = handle(ctx, line, &t.reply)
		}
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
	return
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
