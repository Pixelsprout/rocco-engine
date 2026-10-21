package engine

import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A Driver reads this from hello. Raise it when a reply changes shape.
BRIDGE_PROTOCOL :: 1
BRIDGE_NOT_YET :: "not yet"

// Writes its reply fields with bridge_reply_field, or returns an error. The
// dispatch writes the ok and closes the object.
Bridge_Op :: #type proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string)

Bridge_Op_Entry :: struct {
	name: string,
	op:   Bridge_Op,
}

// tell, ask and listen are kept for Ports (ADR 0009).
@(rodata)
BRIDGE_OPS := [?]Bridge_Op_Entry {
	{"hello", bridge_op_hello},
	{"quit", bridge_op_quit},
	{"tell", bridge_op_not_yet},
	{"ask", bridge_op_not_yet},
	{"listen", bridge_op_not_yet},
}

// The Bridge_Handler for the transport. ctx is the ^State.
bridge_handle :: proc(ctx: rawptr, line: string, reply: ^strings.Builder) -> Bridge_Next {
	s := (^State)(ctx)
	value, parse_err := json.parse_string(line, spec = .JSON, parse_integers = true, allocator = context.temp_allocator)
	if parse_err != nil {
		bridge_reply_error(reply, fmt.tprintf("the request is not JSON: %v", parse_err))
		return .Read
	}
	request, is_object := value.(json.Object)
	if !is_object {
		bridge_reply_error(reply, "the request is not a JSON object")
		return .Read
	}
	name, has_op := request["op"].(json.String)
	if !has_op {
		bridge_reply_error(reply, `the request has no "op" string`)
		return .Read
	}
	for entry in BRIDGE_OPS {
		if entry.name != name {
			continue
		}
		strings.write_string(reply, `{"ok":true`)
		next, error := entry.op(s, request, reply)
		if error != "" {
			bridge_reply_error(reply, error)
		} else {
			strings.write_byte(reply, '}')
		}
		return next
	}
	bridge_reply_error(reply, fmt.tprintf("unknown op %q", name))
	return .Read
}

bridge_op_hello :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	bridge_reply_field(reply, "protocol", BRIDGE_PROTOCOL)
	bridge_reply_field(reply, "step_hz", s.launch.step_hz)
	bridge_reply_field(reply, "steps", s.steps)
	bridge_reply_field(reply, "headless", s.mode == .Headless)
	return .Read, ""
}

// The host ends the run after the reply, as Quit does. Lines after quit are
// not answered.
bridge_op_quit :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	s.bridge.quit = true
	return .Stop, ""
}

bridge_op_not_yet :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	return .Read, BRIDGE_NOT_YET
}
