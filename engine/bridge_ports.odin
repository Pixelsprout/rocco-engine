package engine

import "core:fmt"
import "core:mem"
import "core:strings"

// Counts the port names and the messages. A tell past it queues nothing.
BRIDGE_PORTS_MAX_BYTES :: 4 * 1024 * 1024

// Copies in the Bridge_Ports allocator.
Port_Queued :: struct {
	port, msg: string,
}

// The tell op's messages, waiting for the next step. They live in the Bridge,
// not the transport, so a Driver that disconnects loses none of them.
Bridge_Ports :: struct {
	queue:     [dynamic]Port_Queued,
	bytes:     int,
	// The ports already logged as dropped. Each key is its own clone, because
	// the queued message that named it is freed.
	dropped:   map[string]bool,
	allocator: mem.Allocator,
}

bridge_ports_init :: proc(p: ^Bridge_Ports, allocator: mem.Allocator) {
	p.allocator = allocator
	p.queue = make([dynamic]Port_Queued, allocator)
	p.dropped = make(map[string]bool, allocator)
}

bridge_ports_destroy :: proc(p: ^Bridge_Ports) {
	if p.allocator.procedure == nil {
		return
	}
	for m in p.queue {
		bridge_ports_free(p, m)
	}
	delete(p.queue)
	for port in p.dropped {
		delete(port, p.allocator)
	}
	delete(p.dropped)
	p^ = {}
}

// queued is the count on port after the push. A full queue changes nothing.
// A zero Bridge_Ports starts in the context allocator.
bridge_ports_push :: proc(p: ^Bridge_Ports, port, msg: string) -> (queued: int, error: string) {
	if p.allocator.procedure == nil {
		bridge_ports_init(p, context.allocator)
	}
	size := len(port) + len(msg)
	if p.bytes + size > BRIDGE_PORTS_MAX_BYTES {
		return 0, "the port queue is full"
	}
	append(&p.queue, Port_Queued{port = strings.clone(port, p.allocator), msg = strings.clone(msg, p.allocator)})
	p.bytes += size
	for m in p.queue {
		if m.port == port {
			queued += 1
		}
	}
	return queued, ""
}

// Empties the queue. The messages of a port that a Query in queries Listens
// to go to the list, in queue order, and the game owns them. The rest are
// dropped, so a stale queue cannot grow.
bridge_ports_deliver :: proc(p: ^Bridge_Ports, queries: []Query) -> Roc_List(Port_Message) {
	if len(p.queue) == 0 {
		return {}
	}
	rows := make([dynamic]Port_Message, 0, len(p.queue), context.temp_allocator)
	for m in p.queue {
		if bridge_ports_listened(queries, m.port) {
			append(&rows, Port_Message{port = roc_str_from_slice(m.port), msg = roc_str_from_slice(m.msg)})
		} else if m.port not_in p.dropped {
			fmt.eprintfln("the port %q has no Listen, so its messages are dropped", m.port)
			p.dropped[strings.clone(m.port, p.allocator)] = true
		}
		bridge_ports_free(p, m)
	}
	clear(&p.queue)
	p.bytes = 0
	return roc_list_from_slice(rows[:])
}

@(private = "file")
bridge_ports_listened :: proc(queries: []Query, port: string) -> bool {
	for &query in queries {
		if query.tag == .Listen && roc_str_string(&query.payload.listen) == port {
			return true
		}
	}
	return false
}

@(private = "file")
bridge_ports_free :: proc(p: ^Bridge_Ports, m: Port_Queued) {
	delete(m.port, p.allocator)
	delete(m.msg, p.allocator)
}
