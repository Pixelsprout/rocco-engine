#+test
package engine

import "core:encoding/base64"
import "core:encoding/endian"
import "core:encoding/json"
import "core:net"
import "core:strings"
import "core:testing"

Screenshot_Hold :: struct {
	s:    ^State,
	path: string,
}

// Holds the reply as the web screenshot op does after it starts the read.
@(private = "file")
hold_handler :: proc(ctx: rawptr, line: string, reply: ^strings.Builder) -> Bridge_Next {
	h := (^Screenshot_Hold)(ctx)
	return bridge_screenshot_hold(h.s, h.path)
}

// The web transport holds the reply until the read-back ends, and runs on
// the native transport here.
@(private = "file")
open_held_screenshot :: proc(t: ^testing.T, s: ^State, path: string) -> net.TCP_Socket {
	testing.expect_value(t, bridge_open(&s.bridge, 0, context.allocator), nil)
	driver := driver_dial(t, bridge_transport_port(&s.bridge.transport))
	driver_send(t, driver, `{"op":"screenshot","path":"ignored"}` + "\n")
	hold := Screenshot_Hold{s, path}
	bridge_transport_poll(&s.bridge.transport, true, hold_handler, &hold)
	testing.expect(t, s.bridge.transport.holding)
	return driver
}

@(test)
test_bridge_screenshot_read_sends_the_held_reply_with_the_png_in_base64 :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	s.window.dpi = 2
	driver := open_held_screenshot(t, &s, "/tmp/out.png")
	defer net.close(driver)
	defer bridge_close(&s.bridge)

	rgba := []byte{255, 0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0, 9, 9, 9, 0}
	bridge_screenshot_read(&s, rgba, {4, 1}, "")

	testing.expect(t, !s.bridge.transport.holding)
	reply := driver_read_reply(t, driver)
	testing.expect_value(t, reply["ok"].(json.Boolean), true)
	testing.expect_value(t, reply["path"].(json.String), "/tmp/out.png")
	physical := reply["physical"].(json.Array)
	logical := reply["logical"].(json.Array)
	testing.expect_value(t, physical[0].(json.Integer), 4)
	testing.expect_value(t, physical[1].(json.Integer), 1)
	testing.expect_value(t, logical[0].(json.Integer), 2)
	testing.expect_value(t, logical[1].(json.Integer), 1)
	png, err := base64.decode(reply["png"].(json.String), allocator = context.temp_allocator)
	testing.expect_value(t, err, nil)
	signature := PNG_SIGNATURE
	testing.expect(t, strings.has_prefix(string(png), string(signature[:])))
	width, _ := endian.get_u32(png[16:20], .Big)
	height, _ := endian.get_u32(png[20:24], .Big)
	testing.expect_value(t, width, 4)
	testing.expect_value(t, height, 1)
}

@(test)
test_bridge_screenshot_read_that_failed_sends_an_error_and_reads_again :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s: State
	driver := open_held_screenshot(t, &s, "/tmp/out.png")
	defer net.close(driver)
	defer bridge_close(&s.bridge)

	bridge_screenshot_read(&s, nil, {4, 1}, "the target did not map")

	testing.expect(t, !s.bridge.transport.holding)
	reply := driver_read_reply(t, driver)
	testing.expect_value(t, reply["ok"].(json.Boolean), false)
	testing.expect_value(t, reply["error"].(json.String), "the target did not map")
}
