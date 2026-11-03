#+test
package engine

import "core:testing"

@(test)
test_main_pass_action_clears_to_the_linear_colour :: proc(t: ^testing.T) {
	action := main_pass_action({r = 0.5, g = 0, b = 1})

	colour := action.colors[0]
	testing.expect(t, colour.load_action == .CLEAR)
	expect_v4_near(t, {colour.clear_value.r, colour.clear_value.g, colour.clear_value.b, colour.clear_value.a}, {0.5, 0, 1, 1})
	testing.expect(t, action.depth.load_action == .CLEAR)
	testing.expect_value(t, action.depth.clear_value, 0)
}

// The tone map rolls a channel above 1 off, so only a negative channel clamps.
@(test)
test_main_pass_action_keeps_a_channel_above_1_and_clamps_a_negative_one_to_0 :: proc(t: ^testing.T) {
	c := main_pass_action({r = 2, g = -1, b = 0.002}).colors[0].clear_value

	expect_v4_near(t, {c.r, c.g, c.b, c.a}, {2, 0, 0.002, 1})
}
