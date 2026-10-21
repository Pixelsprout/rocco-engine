package engine

import sapp "../sokol-odin/sokol/app"
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
	{"step", bridge_op_step},
	{"scene", bridge_op_scene},
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

// Owes the steps and holds the reply. bridge_step_taken sends it after the
// last step. A bad field fails the request before any step runs.
bridge_op_step :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	n := i64(1)
	if value, has_n := request["n"]; has_n {
		count, is_integer := value.(json.Integer)
		if !is_integer || count < 1 {
			return .Read, `"n" must be a whole number of 1 or more`
		}
		n = count
	}
	held, tap: #sparse[sapp.Keycode]bool
	mouse: [2]f32
	held, error = bridge_read_keys(request, "held")
	if error == "" {
		tap, error = bridge_read_keys(request, "tap")
	}
	if error == "" {
		mouse, error = bridge_read_mouse(request)
	}
	if error != "" {
		return .Read, error
	}

	s.bridge.held = held
	s.bridge.tap = tap
	s.bridge.mouse = mouse
	s.bridge.owed_steps = int(n)
	return .Hold, ""
}

// The Scene that a paused window shows, and the QueryResults that the next
// step gets.
bridge_op_scene :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	bridge_reply_field(reply, "steps", s.steps)
	strings.write_string(reply, `,"scene":`)
	json_write_scene(reply, &s.seam.curr)
	strings.write_string(reply, `,"results":`)
	json_write_query_results(reply, &s.seam.results)
	return .Read, ""
}

bridge_op_not_yet :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	return .Read, BRIDGE_NOT_YET
}

// An absent field means no key.
@(private = "file")
bridge_read_keys :: proc(request: json.Object, field: string) -> (keys: #sparse[sapp.Keycode]bool, error: string) {
	value, has_field := request[field]
	if !has_field {
		return
	}
	names, is_array := value.(json.Array)
	if !is_array {
		return keys, fmt.tprintf("%q must be a list of Key names", field)
	}
	for item in names {
		name, is_string := item.(json.String)
		if !is_string {
			return keys, fmt.tprintf("%q must be a list of Key names", field)
		}
		key, known := key_from_tag(name)
		if !known {
			return keys, fmt.tprintf("unknown Key %q in %q", name, field)
		}
		keys[key] = true
	}
	return
}

// An absent mouse means no movement.
@(private = "file")
bridge_read_mouse :: proc(request: json.Object) -> (mouse: [2]f32, error: string) {
	value, has_mouse := request["mouse"]
	if !has_mouse {
		return
	}
	pair, is_array := value.(json.Array)
	if !is_array || len(pair) != 2 {
		return mouse, `"mouse" must be [dx, dy]`
	}
	for item, i in pair {
		#partial switch number in item {
		case json.Integer:
			mouse[i] = f32(number)
		case json.Float:
			mouse[i] = f32(number)
		case:
			return mouse, `"mouse" must be [dx, dy]`
		}
	}
	return
}
