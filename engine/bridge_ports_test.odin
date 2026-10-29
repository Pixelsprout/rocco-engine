#+test
package engine

import "core:strings"
import "core:testing"

@(private = "file")
listen_town :: proc() -> Query {
	return Query{tag = .Listen, payload = {listen = roc_str_from_slice("town")}}
}

@(private = "file")
expect_row :: proc(t: ^testing.T, row: ^Port_Message, port, msg: string, loc := #caller_location) {
	testing.expect_value(t, roc_str_string(&row.port), port, loc = loc)
	testing.expect_value(t, roc_str_string(&row.msg), msg, loc = loc)
}

@(test)
test_bridge_ports_deliver_gives_the_messages_of_a_listened_port_in_order :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	p: Bridge_Ports
	bridge_ports_init(&p, context.allocator)
	defer bridge_ports_destroy(&p)
	query := listen_town()
	defer roc_decref(query)

	bridge_ports_push(&p, "town", "1")
	bridge_ports_push(&p, "town", "")
	bridge_ports_push(&p, "other", "x")
	list := bridge_ports_deliver(&p, {query})
	defer roc_list_decref(list)

	testing.expect_value(t, list.length, 2)
	if list.length == 2 {
		expect_row(t, &list.elements[0], "town", "1")
		expect_row(t, &list.elements[1], "town", "")
	}
	testing.expect_value(t, p.bytes, 0)
	testing.expect_value(t, len(p.queue), 0)
}

@(test)
test_bridge_ports_deliver_drops_a_port_nobody_listens_to_and_logs_once :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	p: Bridge_Ports
	bridge_ports_init(&p, context.allocator)
	defer bridge_ports_destroy(&p)

	bridge_ports_push(&p, "ghost", "a")
	list := bridge_ports_deliver(&p, nil)
	testing.expect_value(t, list.length, 0)
	testing.expect(t, p.dropped["ghost"])

	bridge_ports_push(&p, "ghost", "b")
	list = bridge_ports_deliver(&p, nil)
	testing.expect_value(t, list.length, 0)
	testing.expect_value(t, len(p.dropped), 1)
}

@(test)
test_bridge_ports_deliver_with_an_empty_queue_allocates_nothing :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	p: Bridge_Ports
	bridge_ports_init(&p, context.allocator)
	defer bridge_ports_destroy(&p)
	query := listen_town()
	defer roc_decref(query)

	before := roc_heap_counters()
	list := bridge_ports_deliver(&p, {query})
	testing.expect_value(t, roc_heap_counters(), before)
	testing.expect_value(t, list.length, 0)
}

@(test)
test_bridge_ports_push_refuses_a_full_queue_and_keeps_what_it_has :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	p: Bridge_Ports
	bridge_ports_init(&p, context.allocator)
	defer bridge_ports_destroy(&p)
	query := listen_town()
	defer roc_decref(query)
	big := strings.repeat("x", BRIDGE_PORTS_MAX_BYTES - 4)
	defer delete(big)

	queued, error := bridge_ports_push(&p, "town", big)
	testing.expect_value(t, error, "")
	testing.expect_value(t, queued, 1)

	queued, error = bridge_ports_push(&p, "town", "12345")
	testing.expect_value(t, error, "the port queue is full")
	testing.expect_value(t, queued, 0)
	testing.expect_value(t, len(p.queue), 1)

	list := bridge_ports_deliver(&p, {query})
	testing.expect_value(t, list.length, 1)
	roc_list_decref(list)
	queued, error = bridge_ports_push(&p, "town", "12345")
	testing.expect_value(t, error, "")
	testing.expect_value(t, queued, 1)
}

@(test)
test_bridge_ports_push_counts_the_messages_on_the_port :: proc(t: ^testing.T) {
	p: Bridge_Ports
	bridge_ports_init(&p, context.allocator)
	defer bridge_ports_destroy(&p)

	first, _ := bridge_ports_push(&p, "a", "1")
	second, _ := bridge_ports_push(&p, "a", "2")
	other, _ := bridge_ports_push(&p, "b", "3")
	testing.expect_value(t, first, 1)
	testing.expect_value(t, second, 2)
	testing.expect_value(t, other, 1)
}
