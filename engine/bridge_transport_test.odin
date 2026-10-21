#+test
package engine

import "core:bytes"
import "core:net"
import "core:slice"
import "core:strings"
import "core:testing"

Bridge_Echo :: struct {
	answered: int,
}

// Replies with the line, so a test sees what the transport passed on. A
// "stop" line returns .Stop, and a "hold" line returns .Hold.
@(private = "file")
echo_handler :: proc(ctx: rawptr, line: string, reply: ^strings.Builder) -> Bridge_Next {
	echo := (^Bridge_Echo)(ctx)
	echo.answered += 1
	strings.write_string(reply, `{"ok":true`)
	bridge_reply_field(reply, "line", line)
	strings.write_byte(reply, '}')
	switch line {
	case "stop":
		return .Stop
	case "hold":
		return .Hold
	}
	return .Read
}

@(private = "file")
open_transport :: proc(t: ^testing.T, transport: ^Bridge_Transport) -> int {
	err := bridge_transport_open(transport, 0, context.allocator)
	testing.expect_value(t, err, nil)
	return bridge_transport_port(transport)
}

@(private = "file")
dial :: proc(t: ^testing.T, port: int) -> net.TCP_Socket {
	socket, err := net.dial_tcp(net.Endpoint{net.IP4_Loopback, port})
	testing.expect_value(t, err, nil)
	return socket
}

@(private = "file")
send :: proc(t: ^testing.T, socket: net.TCP_Socket, text: string) {
	_, err := net.send_tcp(socket, transmute([]u8)text)
	testing.expect_value(t, err, nil)
}

// Reads until count newlines arrive.
@(private = "file")
read_lines :: proc(t: ^testing.T, socket: net.TCP_Socket, count: int) -> string {
	got := make([dynamic]u8, context.temp_allocator)
	buf: [256]u8
	for bytes.count(got[:], {'\n'}) < count {
		n, err := net.recv_tcp(socket, buf[:])
		if err != nil || n == 0 {
			testing.fail_now(t, "the transport closed before it replied")
		}
		append(&got, ..buf[:n])
	}
	return string(got[:])
}

@(test)
test_json_lines_holds_a_partial_line_until_its_newline :: proc(t: ^testing.T) {
	f: Json_Lines
	json_lines_init(&f, context.allocator)
	defer json_lines_destroy(&f)

	json_lines_push(&f, transmute([]u8)string(`{"op":"he`))
	_, status := json_lines_next(&f)
	testing.expect_value(t, status, Json_Line_Status.None)

	json_lines_push(&f, transmute([]u8)string("llo\"}\n"))
	line, next := json_lines_next(&f)
	testing.expect_value(t, next, Json_Line_Status.Line)
	testing.expect_value(t, line, `{"op":"hello"}`)
	_, status = json_lines_next(&f)
	testing.expect_value(t, status, Json_Line_Status.None)
}

@(test)
test_json_lines_splits_two_requests_in_one_read :: proc(t: ^testing.T) {
	f: Json_Lines
	json_lines_init(&f, context.allocator)
	defer json_lines_destroy(&f)

	json_lines_push(&f, transmute([]u8)string("{\"op\":\"hello\"}\r\n\n{\"op\":\"quit\"}\n{\"op\""))

	first, s1 := json_lines_next(&f)
	second, s2 := json_lines_next(&f)
	_, s3 := json_lines_next(&f)
	testing.expect_value(t, s1, Json_Line_Status.Line)
	testing.expect_value(t, first, `{"op":"hello"}`)
	testing.expect_value(t, s2, Json_Line_Status.Line)
	testing.expect_value(t, second, `{"op":"quit"}`)
	testing.expect_value(t, s3, Json_Line_Status.None)

	json_lines_push(&f, transmute([]u8)string(":\"ask\"}\n"))
	third, _ := json_lines_next(&f)
	testing.expect_value(t, third, `{"op":"ask"}`)
}

@(test)
test_json_lines_drops_an_overlong_line_and_reports_it_at_its_newline :: proc(t: ^testing.T) {
	f: Json_Lines
	json_lines_init(&f, context.allocator)
	defer json_lines_destroy(&f)
	long := make([]u8, BRIDGE_MAX_LINE + 1)
	defer delete(long)
	slice.fill(long, 'x')

	json_lines_push(&f, long)
	_, status := json_lines_next(&f)
	testing.expect_value(t, status, Json_Line_Status.None)
	json_lines_push(&f, transmute([]u8)string("xx\n{\"op\":\"hello\"}\n"))

	_, s1 := json_lines_next(&f)
	line, s2 := json_lines_next(&f)
	testing.expect_value(t, s1, Json_Line_Status.Too_Long)
	testing.expect_value(t, s2, Json_Line_Status.Line)
	testing.expect_value(t, line, `{"op":"hello"}`)
	testing.expect(t, len(f.buf) < 64)
}

@(test)
test_bridge_transport_answers_each_line_and_keeps_the_driver_after_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	transport: Bridge_Transport
	port := open_transport(t, &transport)
	defer bridge_transport_close(&transport)
	driver := dial(t, port)
	defer net.close(driver)
	echo: Bridge_Echo

	send(t, driver, "one\ntwo\nth")
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	testing.expect_value(t, read_lines(t, driver, 2), "{\"ok\":true,\"line\":\"one\"}\n{\"ok\":true,\"line\":\"two\"}\n")

	send(t, driver, "ree\n")
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	testing.expect_value(t, read_lines(t, driver, 1), "{\"ok\":true,\"line\":\"three\"}\n")
	testing.expect_value(t, echo.answered, 3)
	testing.expect(t, transport.connected)
}

@(test)
test_bridge_transport_without_wait_returns_when_no_request_is_waiting :: proc(t: ^testing.T) {
	transport: Bridge_Transport
	open_transport(t, &transport)
	defer bridge_transport_close(&transport)
	echo: Bridge_Echo

	bridge_transport_poll(&transport, false, echo_handler, &echo)

	testing.expect_value(t, echo.answered, 0)
	testing.expect(t, !transport.connected)
}

@(test)
test_bridge_transport_stop_leaves_the_next_lines_for_the_next_poll :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	transport: Bridge_Transport
	port := open_transport(t, &transport)
	defer bridge_transport_close(&transport)
	driver := dial(t, port)
	defer net.close(driver)
	echo: Bridge_Echo

	send(t, driver, "stop\nafter\n")
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	testing.expect_value(t, echo.answered, 1)
	testing.expect_value(t, read_lines(t, driver, 1), "{\"ok\":true,\"line\":\"stop\"}\n")

	bridge_transport_poll(&transport, false, echo_handler, &echo)
	testing.expect_value(t, echo.answered, 2)
	testing.expect_value(t, read_lines(t, driver, 1), "{\"ok\":true,\"line\":\"after\"}\n")
}

// The first line the Driver reads is the held reply, so the transport sent
// nothing for hold and answered nothing while it held.
@(test)
test_bridge_transport_hold_sends_the_reply_later_and_reads_nothing_until_then :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	transport: Bridge_Transport
	port := open_transport(t, &transport)
	defer bridge_transport_close(&transport)
	driver := dial(t, port)
	defer net.close(driver)
	echo: Bridge_Echo

	send(t, driver, "hold\nafter\n")
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	testing.expect_value(t, echo.answered, 1)
	testing.expect(t, transport.holding)

	bridge_transport_send_held(&transport, `{"ok":true,"held":1}`)
	testing.expect(t, !transport.holding)
	bridge_transport_poll(&transport, false, echo_handler, &echo)

	testing.expect_value(t, echo.answered, 2)
	testing.expect_value(t, read_lines(t, driver, 2), "{\"ok\":true,\"held\":1}\n{\"ok\":true,\"line\":\"after\"}\n")
}

@(test)
test_bridge_transport_waits_for_the_next_driver_after_a_disconnect :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	transport: Bridge_Transport
	port := open_transport(t, &transport)
	defer bridge_transport_close(&transport)
	echo: Bridge_Echo

	first := dial(t, port)
	send(t, first, "first\n")
	bridge_transport_poll(&transport, true, echo_handler, &echo)
	read_lines(t, first, 1)
	net.close(first)

	second := dial(t, port)
	defer net.close(second)
	send(t, second, "second\n")
	bridge_transport_poll(&transport, true, echo_handler, &echo)

	testing.expect_value(t, read_lines(t, second, 1), "{\"ok\":true,\"line\":\"second\"}\n")
	testing.expect_value(t, echo.answered, 2)
}

@(test)
test_bridge_transport_on_a_port_in_use_fails :: proc(t: ^testing.T) {
	first: Bridge_Transport
	port := open_transport(t, &first)
	defer bridge_transport_close(&first)

	second: Bridge_Transport
	err := bridge_transport_open(&second, port, context.allocator)

	testing.expect(t, err != nil)
}
