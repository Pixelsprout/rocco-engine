package engine

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"

BRIDGE_ENV :: "ROCCO_BRIDGE"

// A Bridge run is Lockstep that pauses: a Frame takes one fixed step while
// the Driver is owed steps, and none otherwise.
Bridge :: struct {
	on:         bool,
	transport:  Bridge_Transport,
	owed_steps: int,
	// Set by the quit op. The host ends the run after the Frame.
	quit:       bool,
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

// A port in use must not start a normal run, so it exits the process.
bridge_open_or_exit :: proc(b: ^Bridge, port: int, allocator: mem.Allocator) {
	if err := bridge_transport_open(&b.transport, port, allocator); err != nil {
		fmt.eprintfln("%v=%v: the host cannot listen on 127.0.0.1:%v: %v", BRIDGE_ENV, port, port, err)
		os.exit(1)
	}
	b.on = true
}

bridge_close :: proc(b: ^Bridge) {
	if !b.on {
		return
	}
	bridge_transport_close(&b.transport)
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
