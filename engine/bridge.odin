package engine

import sapp "../sokol-odin/sokol/app"
import "core:fmt"
import "core:mem"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

BRIDGE_ENV :: "ROCCO_BRIDGE"
// A Bridge run has vsync off, so a paused window waits this long each Frame
// instead of drawing as fast as it can.
BRIDGE_PAUSE_WAIT :: 16 * time.Millisecond

// A Bridge run is Lockstep that pauses: a Frame takes one fixed step while
// the Driver is owed steps, and none otherwise.
Bridge :: struct {
	on:           bool,
	transport:    Bridge_Transport,
	owed_steps:   int,
	// Set by the quit op, a Quit from the game or the Frame limit. The host
	// ends the run after the Frame.
	quit:         bool,
	// The step op's Input. held is for every step. tap and mouse are for the
	// first step only.
	held:         #sparse[sapp.Keycode]bool,
	tap:          #sparse[sapp.Keycode]bool,
	mouse:        [2]f32,
	// The held keys of the step before. Pressed is held minus these.
	prev_held:    #sparse[sapp.Keycode]bool,
	// The step op's pads by slot, with the same rules as the keys. They
	// replace the real pads.
	gamepads:     [GAMEPAD_SLOTS]Bridge_Gamepad,
	// The held buttons of the step before, by slot.
	prev_buttons: [GAMEPAD_SLOTS]Gamepad_Buttons,
	// The step op's pointer, with the same rules as the keys. It replaces the
	// real pointer.
	pointer:      Bridge_Pointer,
	// The held mouse buttons of the step before.
	prev_pointer_held: Mouse_Buttons,
	// The step op's Commands so far, as JSON array elements. They must
	// outlive the Frame arena, because the reply waits for the last step.
	commands:     strings.Builder,
	// The alloc line fields of the last step, for the step op's reply.
	alloc:        Alloc_Report,
	// The tell op's messages for the next step.
	ports:        Bridge_Ports,
}

// One pad of a step op. A slot that the request does not name has no pad.
// The axes are for every step, and skip the dead zones.
Bridge_Gamepad :: struct {
	connected: bool,
	held:      Gamepad_Buttons,
	tap:       Gamepad_Buttons,
	axes:      Gamepad_Axes,
}

// The pointer of a step op, in logical pixels. A request with no pointer
// gives one that is not inside, at (0, 0), with no button held. pos, inside
// and held are for every step. tap and wheel are for the first step only.
Bridge_Pointer :: struct {
	given:  bool,
	pos:    [2]f32,
	inside: bool,
	held:   Mouse_Buttons,
	tap:    Mouse_Buttons,
	wheel:  [2]f32,
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

bridge_open :: proc(b: ^Bridge, port: int, allocator: mem.Allocator) -> net.Network_Error {
	bridge_transport_open(&b.transport, port, allocator) or_return
	b.commands = strings.builder_make(allocator)
	bridge_ports_init(&b.ports, allocator)
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
	bridge_ports_destroy(&b.ports)
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

// A paused Frame runs no step, and draws the Scene that the scene op returns.
bridge_paused :: proc(b: ^Bridge) -> bool {
	return b.on && b.owed_steps == 0
}

// The Input for one step under the Bridge, in place of the real devices. It
// derives Pressed from the held keys of the step before, as the real latch
// does from key-down events.
bridge_input_take :: proc(b: ^Bridge, buf: ^Input_Buffers) -> Step_Input {
	latch := Input_Latch {
		held  = b.held,
		mouse = b.mouse,
	}
	for k in sapp.Keycode {
		latch.pressed[k] = (b.held[k] && !b.prev_held[k]) || b.tap[k]
	}
	for &pad, i in b.gamepads {
		if pad.connected {
			latch.gamepads.slots[i] = {
				connected = true,
				held      = pad.held,
				pressed   = (pad.held - b.prev_buttons[i]) + pad.tap,
				axes      = pad.axes,
			}
		}
		b.prev_buttons[i] = pad.held
		pad.tap = {}
	}
	b.prev_held = b.held
	b.tap = {}
	b.mouse = {}
	step_input := input_take(&latch, buf)

	p := &b.pointer
	step_input.pointer = {
		pos      = p.pos,
		inside   = p.given && p.inside,
		held     = pointer_buttons(p.held, &buf.pointer.held),
		pressed  = pointer_buttons((p.held - b.prev_pointer_held) + p.tap, &buf.pointer.pressed),
		released = pointer_buttons((b.prev_pointer_held - p.held) + p.tap, &buf.pointer.released),
		wheel    = p.wheel,
	}
	b.prev_pointer_held = p.held
	p.tap = {}
	p.wheel = {}
	return step_input
}

// Called after each step under the Bridge. After the step op's last step, or
// a Quit from the game, it sends the step op's reply.
bridge_step_taken :: proc(s: ^State, alloc: Alloc_Report, quit: bool) {
	b := &s.bridge
	b.alloc = alloc
	if quit {
		b.owed_steps = 0
		b.quit = true
	}
	if b.owed_steps == 0 {
		bridge_send_step_reply(s)
	}
}

// The Frame limit ends the run. A step op that it cuts short still gets its
// reply, with the steps run so far.
bridge_frame_limit_reached :: proc(s: ^State) {
	b := &s.bridge
	if !b.on {
		return
	}
	if b.transport.holding {
		b.owed_steps = 0
		bridge_send_step_reply(s)
	}
	b.quit = true
}

@(private = "file")
bridge_send_step_reply :: proc(s: ^State) {
	reply := strings.builder_make(context.temp_allocator)
	bridge_reply_op(s, nil, &reply, bridge_step_reply)
	strings.builder_reset(&s.bridge.commands)
	bridge_transport_send_held(&s.bridge.transport, strings.to_string(reply))
}
