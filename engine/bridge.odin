package engine

import sapp "../sokol-odin/sokol/app"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"

BRIDGE_ENV :: "ROCCO_BRIDGE"

// A Bridge run is Lockstep that pauses: a Frame takes one fixed step while
// the Driver is owed steps, and none otherwise.
Bridge :: struct {
	on:         bool,
	transport:  Bridge_Transport,
	owed_steps: int,
	// Set by the quit op, or by a Quit from the game. The host ends the run
	// after the Frame.
	quit:       bool,
	// The step op's Input. held is for every step. tap and mouse are for the
	// first step only.
	held:       #sparse[sapp.Keycode]bool,
	tap:        #sparse[sapp.Keycode]bool,
	mouse:      [2]f32,
	// The held keys of the step before. Pressed is held minus these.
	prev_held:  #sparse[sapp.Keycode]bool,
	// The step op's Commands so far, as JSON array elements. They must
	// outlive the Frame arena, because the reply waits for the last step.
	commands:   strings.Builder,
}

// Returns 0 when the Bridge is off. Exits the process on a bad value, so a
// typo cannot produce a normal run.
bridge_port_from_env :: proc() -> int {
	value := os.get_env(BRIDGE_ENV, context.temp_allocator)
	port, ok := bridge_port_parse(value)
	if !ok {
		fmt.eprintfln("%v must be a port from 1 to 65535, got %q", BRIDGE_ENV, value)
		os.exit(1)
	}
	return port
}

// Treat an empty value as unset.
bridge_port_parse :: proc(value: string) -> (port: int, ok: bool) {
	if value == "" {
		return 0, true
	}
	n := strconv.parse_int(value, 10) or_return
	if n < 1 || n > 65535 || value != fmt.tprint(n) {
		return 0, false
	}
	return n, true
}

// Port 0 asks the OS for a free port. Only tests use it.
bridge_open :: proc(b: ^Bridge, port: int, allocator: mem.Allocator) -> net.Network_Error {
	bridge_transport_open(&b.transport, port, allocator) or_return
	b.commands = strings.builder_make(allocator)
	b.on = true
	return nil
}

// A port in use must not start a normal run, so it exits the process.
bridge_open_or_exit :: proc(b: ^Bridge, port: int, allocator: mem.Allocator) {
	if err := bridge_open(b, port, allocator); err != nil {
		fmt.eprintfln("%v=%v: the host cannot listen on 127.0.0.1:%v: %v", BRIDGE_ENV, port, port, err)
		os.exit(1)
	}
}

bridge_close :: proc(b: ^Bridge) {
	if !b.on {
		return
	}
	bridge_transport_close(&b.transport)
	strings.builder_destroy(&b.commands)
	b.on = false
}

// Answers the Driver's requests. With wait, it blocks until it has answered
// one.
bridge_poll :: proc(s: ^State, wait: bool) {
	if s.bridge.on && !s.bridge.quit {
		bridge_transport_poll(&s.bridge.transport, wait, bridge_handle, s)
	}
}

// Headless has no Frames to pace it, so it blocks on the socket until the
// Driver is owed a step or asks to quit.
bridge_wait_for_steps :: proc(s: ^State) {
	for s.bridge.on && s.bridge.owed_steps == 0 && !s.bridge.quit {
		bridge_poll(s, wait = true)
	}
}

// The time the clock gets this Frame. Under the Bridge, a Frame with no
// owed step adds no time, so it runs zero fixed steps.
bridge_clock_time :: proc(b: ^Bridge, frame_time: f64) -> f64 {
	if !b.on {
		return frame_time
	}
	if b.owed_steps == 0 {
		return 0
	}
	b.owed_steps -= 1
	return frame_time
}

// The Input for one step under the Bridge, in place of the real devices. It
// derives Pressed from the held keys of the step before, as the real latch
// does from key-down events.
bridge_input_take :: proc(b: ^Bridge, buf: ^Key_Buffers) -> Step_Keys {
	latch := Input_Latch {
		held  = b.held,
		mouse = b.mouse,
	}
	for k in sapp.Keycode {
		latch.pressed[k] = (b.held[k] && !b.prev_held[k]) || b.tap[k]
	}
	b.prev_held = b.held
	b.tap = {}
	b.mouse = {}
	return input_take(&latch, buf)
}

// Called after each step under the Bridge. After the step op's last step, or
// a Quit from the game, it sends the step op's reply.
bridge_step_taken :: proc(s: ^State, alloc: Alloc_Report, quit: bool) {
	b := &s.bridge
	if quit {
		b.owed_steps = 0
		b.quit = true
	}
	if b.owed_steps > 0 {
		return
	}
	reply := strings.builder_make(context.temp_allocator)
	strings.write_string(&reply, `{"ok":true`)
	bridge_reply_field(&reply, "steps", s.steps)
	strings.write_string(&reply, `,"commands":[`)
	strings.write_string(&reply, strings.to_string(b.commands))
	// The times have the alloc line's precision, not json.marshal's 16 digits.
	fmt.sbprintf(
		&reply,
		`],"alloc":{{"step":%v,"allocs":%v,"deallocs":%v,"reallocs":%v,"live":%v,"step_us":%.1f,"view_us":%.1f}}}}`,
		alloc.step,
		alloc.allocs,
		alloc.deallocs,
		alloc.reallocs,
		alloc.live,
		alloc.step_us,
		alloc.view_us,
	)
	strings.builder_reset(&b.commands)
	bridge_transport_send_held(&b.transport, strings.to_string(reply))
}
