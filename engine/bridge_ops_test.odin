#+test
package engine

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(private = "file")
expect_error :: proc(t: ^testing.T, reply: json.Object, error: string, loc := #caller_location) {
	expect_field(t, reply, "ok", false, loc)
	expect_field(t, reply, "error", error, loc)
}

@(private = "file")
expect_field :: proc(t: ^testing.T, reply: json.Object, key: string, want: $T, loc := #caller_location) {
	got, ok := reply[key].(T)
	testing.expectf(t, ok, "the reply has no %v %q", typeid_of(T), key, loc = loc)
	testing.expect_value(t, got, want, loc)
}

@(test)
test_bridge_hello_reports_the_protocol_the_step_rate_the_steps_and_the_mode :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	s.launch.step_hz = 60
	s.steps = 7
	s.mode = .Headless

	reply, next := driver_answer(t, &s, `{"op":"hello"}`)

	testing.expect_value(t, next, Bridge_Next.Read)
	expect_field(t, reply, "ok", true)
	expect_field(t, reply, "protocol", i64(BRIDGE_PROTOCOL))
	expect_field(t, reply, "step_hz", i64(60))
	expect_field(t, reply, "steps", i64(7))
	expect_field(t, reply, "headless", true)
	testing.expect(t, !("error" in reply))
}

@(test)
test_bridge_hello_in_a_window_is_not_headless :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	s.mode = .Lockstep

	reply, _ := driver_answer(t, &s, `{"op":"hello"}`)

	expect_field(t, reply, "headless", false)
}

@(test)
test_bridge_quit_replies_ok_and_stops_the_poll :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State

	reply, next := driver_answer(t, &s, `{"op":"quit"}`)

	expect_field(t, reply, "ok", true)
	testing.expect_value(t, next, Bridge_Next.Stop)
	testing.expect(t, s.bridge.quit)
}

@(test)
test_bridge_reserved_ops_reply_not_yet :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	for op in ([]string{"ask", "listen"}) {
		reply, next := driver_answer(t, &s, strings.concatenate({`{"op":"`, op, `"}`}, context.temp_allocator))
		expect_error(t, reply, "not yet")
		testing.expect_value(t, next, Bridge_Next.Read)
	}
	testing.expect(t, !s.bridge.quit)
}

@(test)
test_bridge_unknown_op_replies_an_error_that_names_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State

	reply, next := driver_answer(t, &s, `{"op":"jump"}`)

	expect_error(t, reply, `unknown op "jump"`)
	testing.expect_value(t, next, Bridge_Next.Read)
}

@(test)
test_bridge_bad_requests_reply_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	cases := []struct {
		line:  string,
		error: string,
	} {
		{`{"op":`, "the request is not JSON: Unexpected_Token"},
		{`["hello"]`, "the request is not a JSON object"},
		{`{"n":1}`, `the request has no "op" string`},
		{`{"op":1}`, `the request has no "op" string`},
	}
	for c in cases {
		reply, next := driver_answer(t, &s, c.line)
		expect_error(t, reply, c.error)
		testing.expect_value(t, next, Bridge_Next.Read)
	}
}

@(test)
test_bridge_step_owes_n_steps_and_holds_the_reply :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	b := strings.builder_make(context.temp_allocator)

	next := bridge_handle(&s, `{"op":"step","n":5,"held":["W"]}`, &b)

	testing.expect_value(t, next, Bridge_Next.Hold)
	testing.expect_value(t, s.bridge.owed_steps, 5)
	testing.expect(t, s.bridge.held[.W])
}

@(test)
test_bridge_step_without_n_owes_one_step :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	b := strings.builder_make(context.temp_allocator)

	bridge_handle(&s, `{"op":"step"}`, &b)

	testing.expect_value(t, s.bridge.owed_steps, 1)
}

@(test)
test_bridge_step_bad_fields_reply_an_error_and_owe_no_step :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	cases := []struct {
		line:  string,
		error: string,
	} {
		{`{"op":"step","n":0}`, `"n" must be a whole number of 1 or more`},
		{`{"op":"step","n":1.5}`, `"n" must be a whole number of 1 or more`},
		{`{"op":"step","held":"W"}`, `"held" must be a list of Key names`},
		{`{"op":"step","tap":[87]}`, `"tap" must be a list of Key names`},
		{`{"op":"step","tap":["w"]}`, `unknown Key "w" in "tap"`},
		{`{"op":"step","mouse":[1]}`, `"mouse" must be [dx, dy]`},
		{`{"op":"step","mouse":[1,"2"]}`, `"mouse" must be [dx, dy]`},
	}
	for c in cases {
		reply, next := driver_answer(t, &s, c.line)
		expect_error(t, reply, c.error)
		testing.expect_value(t, next, Bridge_Next.Read)
		testing.expect_value(t, s.bridge.owed_steps, 0)
	}
}

@(test)
test_bridge_reply_error_escapes_the_message :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	defer free_all(context.temp_allocator)

	bridge_reply_error(&b, "a \"quoted\"\nline")

	testing.expect_value(t, strings.to_string(b), `{"ok":false,"error":"a \"quoted\"\nline"}`)
}

@(test)
test_bridge_screenshot_bad_requests_reply_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	cases := []struct {
		line:  string,
		mode:  Run_Mode,
		error: string,
	} {
		{`{"op":"screenshot"}`, .Lockstep, `"path" must be a file path`},
		{`{"op":"screenshot","path":""}`, .Lockstep, `"path" must be a file path`},
		{`{"op":"screenshot","path":7}`, .Lockstep, `"path" must be a file path`},
		{`{"op":"screenshot","path":"out.png"}`, .Headless, "a Headless run draws no image to screenshot"},
		{`{"op":"screenshot","path":"out.png"}`, .Lockstep, "no Frame has been drawn yet"},
	}
	for c in cases {
		s.mode = c.mode
		reply, next := driver_answer(t, &s, c.line)
		expect_error(t, reply, c.error)
		testing.expect_value(t, next, Bridge_Next.Read)
	}
}

@(test)
test_bridge_tell_queues_the_message_and_replies_the_count_on_the_port :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	defer bridge_ports_destroy(&s.bridge.ports)

	reply, next := driver_answer(t, &s, `{"op":"tell","port":"town","msg":"hi"}`)
	expect_field(t, reply, "ok", true)
	expect_field(t, reply, "queued", i64(1))
	testing.expect_value(t, next, Bridge_Next.Read)

	reply, _ = driver_answer(t, &s, `{"op":"tell","port":"town","msg":"hi"}`)
	expect_field(t, reply, "queued", i64(2))
	testing.expect_value(t, len(s.bridge.ports.queue), 2)
}

@(test)
test_bridge_tell_bad_requests_reply_an_error_and_queue_nothing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	defer bridge_ports_destroy(&s.bridge.ports)

	cases := []struct {
		request, error: string,
	} {
		{`{"op":"tell","msg":"hi"}`, `"port" must be a non-empty string`},
		{`{"op":"tell","port":"","msg":"hi"}`, `"port" must be a non-empty string`},
		{`{"op":"tell","port":7,"msg":"hi"}`, `"port" must be a non-empty string`},
		{`{"op":"tell","port":"town"}`, `"msg" must be a string`},
		{`{"op":"tell","port":"town","msg":7}`, `"msg" must be a string`},
	}
	for c in cases {
		reply, next := driver_answer(t, &s, c.request)
		expect_error(t, reply, c.error)
		testing.expect_value(t, next, Bridge_Next.Read)
	}
	testing.expect_value(t, len(s.bridge.ports.queue), 0)
}

@(test)
test_bridge_tell_on_a_full_queue_replies_an_error :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	defer bridge_ports_destroy(&s.bridge.ports)
	big := strings.repeat("x", BRIDGE_PORTS_MAX_BYTES - len("town"), context.temp_allocator)
	_, push_error := bridge_ports_push(&s.bridge.ports, "town", big)
	testing.expect_value(t, push_error, "")

	reply, _ := driver_answer(t, &s, `{"op":"tell","port":"town","msg":"hi"}`)

	expect_error(t, reply, "the port queue is full")
	testing.expect_value(t, len(s.bridge.ports.queue), 1)
}
