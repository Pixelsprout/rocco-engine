package engine

import sapp "../sokol-odin/sokol/app"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

// A Driver reads this from hello. Raise it when a reply changes shape.
// 2: results gained ports, for the tell op.
// 4: step takes a pointer, results gained ui, and Box configs gained id and overflow.
BRIDGE_PROTOCOL :: 4
BRIDGE_NOT_YET :: "not yet"

// ask and listen are kept for Ports (ADR 0009).
@(rodata)
BRIDGE_OPS := [?]Bridge_Op_Entry {
	{"hello", bridge_op_hello},
	{"quit", bridge_op_quit},
	{"step", bridge_op_step},
	{"scene", bridge_op_scene},
	{"screenshot", bridge_op_screenshot},
	{"tell", bridge_op_tell},
	{"ask", bridge_op_not_yet},
	{"listen", bridge_op_not_yet},
}

// Writes its reply fields with bridge_reply_field, or returns an error.
// bridge_reply_op writes the ok and closes the object.
Bridge_Op :: #type proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string)

Bridge_Op_Entry :: struct {
	name: string,
	op:   Bridge_Op,
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
		return bridge_reply_op(s, request, reply, entry.op)
	}
	bridge_reply_error(reply, fmt.tprintf("unknown op %q", name))
	return .Read
}

// Every op's reply is ok and its fields, or the error that it returns.
bridge_reply_op :: proc(s: ^State, request: json.Object, reply: ^strings.Builder, op: Bridge_Op) -> Bridge_Next {
	strings.write_string(reply, `{"ok":true`)
	next, error := op(s, request, reply)
	if error != "" {
		bridge_reply_error(reply, error)
	} else {
		strings.write_byte(reply, '}')
	}
	return next
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
	gamepads: [GAMEPAD_SLOTS]Bridge_Gamepad
	pointer: Bridge_Pointer
	held, error = bridge_read_keys(request, "held")
	if error == "" {
		tap, error = bridge_read_keys(request, "tap")
	}
	if error == "" {
		mouse, error = bridge_read_mouse(request)
	}
	if error == "" {
		gamepads, error = bridge_read_gamepads(request)
	}
	if error == "" {
		pointer, error = bridge_read_pointer(request)
	}
	if error != "" {
		return .Read, error
	}

	s.bridge.held = held
	s.bridge.tap = tap
	s.bridge.mouse = mouse
	s.bridge.gamepads = gamepads
	s.bridge.pointer = pointer
	s.bridge.owed_steps = int(n)
	return .Hold, ""
}

// The step op's held reply, which bridge_step_taken sends after the last
// step. alloc has the fields of the last step's alloc line.
bridge_step_reply :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	bridge_reply_field(reply, "steps", s.steps)
	strings.write_string(reply, `,"commands":[`)
	strings.write_string(reply, strings.to_string(s.bridge.commands))
	strings.write_string(reply, `],"alloc":{`)
	alloc_report_write(reply, s.bridge.alloc, `"%v":%v`, ",")
	strings.write_byte(reply, '}')
	return .Read, ""
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

// Saves the target that the last Frame drew. A bad path fails the request,
// and the run goes on.
bridge_op_screenshot :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	path, has_path := request["path"].(json.String)
	if !has_path || path == "" {
		return .Read, `"path" must be a file path`
	}
	if s.mode == .Headless {
		return .Read, "a Headless run draws no image to screenshot"
	}
	size: [2]i32
	size, error = screenshot_save(&s.renderer, path)
	if error != "" {
		return .Read, error
	}
	bridge_reply_field(reply, "path", path)
	bridge_reply_field(reply, "physical", size)
	bridge_reply_field(reply, "logical", screenshot_logical_size(size, sapp.dpi_scale()))
	return .Read, ""
}

// Queues msg for the next step whose Scene Listens on port. queued is the
// count on that port.
bridge_op_tell :: proc(s: ^State, request: json.Object, reply: ^strings.Builder) -> (next: Bridge_Next, error: string) {
	port, has_port := request["port"].(json.String)
	if !has_port || port == "" {
		return .Read, `"port" must be a non-empty string`
	}
	msg, has_msg := request["msg"].(json.String)
	if !has_msg {
		return .Read, `"msg" must be a string`
	}
	queued: int
	queued, error = bridge_ports_push(&s.bridge.ports, port, msg)
	if error != "" {
		return .Read, error
	}
	bridge_reply_field(reply, "queued", queued)
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
	return bridge_read_pair(value, `"mouse" must be [dx, dy]`)
}

// x and y are required. inside defaults to true.
@(private = "file")
bridge_read_pointer :: proc(request: json.Object) -> (pointer: Bridge_Pointer, error: string) {
	value, has_pointer := request["pointer"]
	if !has_pointer {
		return
	}
	fields, is_object := value.(json.Object)
	if !is_object {
		return pointer, `"pointer" must be an object`
	}
	x, has_x := bridge_number(fields["x"])
	y, has_y := bridge_number(fields["y"])
	if !has_x || !has_y {
		return pointer, `"pointer" needs "x" and "y" as numbers`
	}
	pointer = {given = true, pos = {x, y}, inside = true}
	if inside_value, has_inside := fields["inside"]; has_inside {
		inside, is_bool := inside_value.(json.Boolean)
		if !is_bool {
			return pointer, `"inside" must be true or false`
		}
		pointer.inside = inside
	}
	pointer.held, error = bridge_read_mouse_buttons(fields, "held")
	if error == "" {
		pointer.tap, error = bridge_read_mouse_buttons(fields, "tap")
	}
	if error == "" {
		if wheel_value, has_wheel := fields["wheel"]; has_wheel {
			pointer.wheel, error = bridge_read_pair(wheel_value, `"wheel" must be [dx, dy]`)
		}
	}
	return
}

@(private = "file")
bridge_read_mouse_buttons :: proc(fields: json.Object, field: string) -> (buttons: Mouse_Buttons, error: string) {
	value, has_field := fields[field]
	if !has_field {
		return
	}
	names, is_array := value.(json.Array)
	if !is_array {
		return buttons, fmt.tprintf("%q must be a list of MouseButton names", field)
	}
	for item in names {
		name, is_string := item.(json.String)
		if !is_string {
			return buttons, fmt.tprintf("%q must be a list of MouseButton names", field)
		}
		button, known := mouse_button_from_tag(name)
		if !known {
			return buttons, fmt.tprintf("unknown MouseButton %q in %q", name, field)
		}
		buttons += {button}
	}
	return
}

@(private = "file")
bridge_read_pair :: proc(value: json.Value, message: string) -> (pair: [2]f32, error: string) {
	items, is_array := value.(json.Array)
	if !is_array || len(items) != 2 {
		return pair, message
	}
	for item, i in items {
		number, is_number := bridge_number(item)
		if !is_number {
			return {}, message
		}
		pair[i] = number
	}
	return
}

// An absent gamepads means no pad is connected. A missing field of a pad is
// zero, so a pad with no slot is in slot 0.
@(private = "file")
bridge_read_gamepads :: proc(request: json.Object) -> (pads: [GAMEPAD_SLOTS]Bridge_Gamepad, error: string) {
	value, has_field := request["gamepads"]
	if !has_field {
		return
	}
	list, is_array := value.(json.Array)
	if !is_array {
		return pads, `"gamepads" must be a list of objects`
	}
	for item in list {
		fields, is_object := item.(json.Object)
		if !is_object {
			return pads, `"gamepads" must be a list of objects`
		}
		slot := i64(0)
		if slot_value, has_slot := fields["slot"]; has_slot {
			number, is_integer := slot_value.(json.Integer)
			if !is_integer || number < 0 || number >= GAMEPAD_SLOTS {
				return pads, fmt.tprintf(`"slot" must be a whole number from 0 to %v`, GAMEPAD_SLOTS - 1)
			}
			slot = number
		}
		pad := &pads[slot]
		if pad.connected {
			return pads, fmt.tprintf(`two gamepads have slot %v`, slot)
		}
		pad.connected = true
		if error = bridge_read_gamepad(fields, pad); error != "" {
			return
		}
	}
	return
}

@(private = "file")
bridge_read_gamepad :: proc(fields: json.Object, pad: ^Bridge_Gamepad) -> (error: string) {
	pad.held, error = bridge_read_buttons(fields, "held")
	if error == "" {
		pad.tap, error = bridge_read_buttons(fields, "tap")
	}
	if error == "" {
		pad.axes.left_stick, error = bridge_read_stick(fields, "left_stick")
	}
	if error == "" {
		pad.axes.right_stick, error = bridge_read_stick(fields, "right_stick")
	}
	if error == "" {
		pad.axes.left_trigger, error = bridge_read_trigger(fields, "left_trigger")
	}
	if error == "" {
		pad.axes.right_trigger, error = bridge_read_trigger(fields, "right_trigger")
	}
	return
}

@(private = "file")
bridge_read_buttons :: proc(fields: json.Object, field: string) -> (buttons: Gamepad_Buttons, error: string) {
	value, has_field := fields[field]
	if !has_field {
		return
	}
	names, is_array := value.(json.Array)
	if !is_array {
		return buttons, fmt.tprintf("%q must be a list of Button names", field)
	}
	for item in names {
		name, is_string := item.(json.String)
		if !is_string {
			return buttons, fmt.tprintf("%q must be a list of Button names", field)
		}
		button, known := button_from_tag(name)
		if !known {
			return buttons, fmt.tprintf("unknown Button %q in %q", name, field)
		}
		buttons += {button}
	}
	return
}

// The Bridge gives the stick as step gets it, so it must be inside the unit
// disc.
@(private = "file")
bridge_read_stick :: proc(fields: json.Object, field: string) -> (stick: [2]f32, error: string) {
	value, has_field := fields[field]
	if !has_field {
		return
	}
	message := fmt.tprintf("%q must be [x, y] inside the unit disc", field)
	pair, is_array := value.(json.Array)
	if !is_array || len(pair) != 2 {
		return stick, message
	}
	for item, i in pair {
		number, is_number := bridge_number(item)
		if !is_number {
			return stick, message
		}
		stick[i] = number
	}
	if stick.x * stick.x + stick.y * stick.y > 1 + 1e-6 {
		return {}, message
	}
	return
}

@(private = "file")
bridge_read_trigger :: proc(fields: json.Object, field: string) -> (trigger: f32, error: string) {
	value, has_field := fields[field]
	if !has_field {
		return
	}
	number, is_number := bridge_number(value)
	if !is_number || !(number >= 0 && number <= 1) {
		return 0, fmt.tprintf("%q must be a number from 0 to 1", field)
	}
	return number, ""
}

@(private = "file")
bridge_number :: proc(value: json.Value) -> (number: f32, ok: bool) {
	#partial switch n in value {
	case json.Integer:
		return f32(n), true
	case json.Float:
		return f32(n), true
	}
	return 0, false
}
