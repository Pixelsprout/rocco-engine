#+test
package engine

import "core:net"
import "core:testing"

@(test)
test_bridge_devices_are_on_only_for_the_driver_that_said_hello :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	testing.expect(t, bridge_devices_on(&r.s.bridge))
	step_run_request(t, &r, `{"op":"hello"}`)
	testing.expect(t, !bridge_devices_on(&r.s.bridge))
	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	testing.expect(t, bridge_devices_on(&r.s.bridge))
}

@(test)
test_bridge_devices_end_when_the_driver_disconnects :: proc(t: ^testing.T) {
	roc_heap_test_begin()
	defer roc_heap_test_end()
	defer free_all(context.temp_allocator)
	r: Step_Run
	step_run_open(t, &r)
	defer step_run_close(&r)

	step_run_request(t, &r, `{"op":"hello","devices":true}`)
	net.close(r.driver)
	r.driver = driver_dial(t, bridge_transport_port(&r.s.bridge.transport))
	step_run_request(t, &r, `{"op":"scene"}`)

	testing.expect(t, !bridge_devices_on(&r.s.bridge))
	testing.expect_value(t, r.s.bridge.transport.drivers, 2)
}
