#+test
package engine

import "core:bytes"
import "core:encoding/json"
import "core:net"
import "core:strings"
import "core:testing"

driver_dial :: proc(t: ^testing.T, port: int) -> net.TCP_Socket {
	socket, err := net.dial_tcp(net.Endpoint{net.IP4_Loopback, port})
	testing.expect_value(t, err, nil)
	return socket
}

driver_send :: proc(t: ^testing.T, socket: net.TCP_Socket, text: string) {
	_, err := net.send_tcp(socket, transmute([]u8)text)
	testing.expect_value(t, err, nil)
}

// Reads until count newlines arrive.
driver_read_lines :: proc(t: ^testing.T, socket: net.TCP_Socket, count: int) -> string {
	got := make([dynamic]u8, context.temp_allocator)
	buf: [512]u8
	for bytes.count(got[:], {'\n'}) < count {
		n, err := net.recv_tcp(socket, buf[:])
		if err != nil || n == 0 {
			testing.fail_now(t, "the host closed before it replied")
		}
		append(&got, ..buf[:n])
	}
	return string(got[:])
}

// Reads one reply line. The Driver sends the next request only after it has
// read a reply, so a read never takes part of the next one.
driver_read_reply :: proc(t: ^testing.T, socket: net.TCP_Socket) -> json.Object {
	line := driver_read_lines(t, socket, 1)
	testing.expect_value(t, strings.index_byte(line, '\n'), len(line) - 1)
	return driver_parse(t, line[:len(line) - 1])
}

// The Scene's numbers are f32, so a test of them leaves parse_integers off.
driver_parse :: proc(t: ^testing.T, reply: string, parse_integers := true) -> json.Object {
	value, err := json.parse_string(reply, parse_integers = parse_integers, allocator = context.temp_allocator)
	testing.expectf(t, err == nil, "the reply %q is not JSON: %v", reply, err)
	object, _ := value.(json.Object)
	return object
}

// Answers line as the transport would, and parses the reply.
driver_answer :: proc(t: ^testing.T, s: ^State, line: string, parse_integers := true) -> (reply: json.Object, next: Bridge_Next) {
	b := strings.builder_make(context.temp_allocator)
	next = bridge_handle(s, line, &b)
	reply = driver_parse(t, strings.to_string(b), parse_integers)
	return
}
