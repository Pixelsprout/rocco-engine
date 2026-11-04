#+test
package engine

import sg "../sokol-odin/sokol/gfx"
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

@(test)
test_mesh_pipeline_desc_gives_each_alpha_mode_its_shader_cull_depth_write_and_blend :: proc(t: ^testing.T) {
	opaque := sg.Pipeline_Desc {
		shader = {id = 1},
		depth = {write_enabled = true},
		cull_mode = .BACK,
	}
	shaders := Mesh_Shaders {
		mask  = {id = 2},
		blend = {id = 3},
	}
	premultiplied := sg.Blend_State {
		enabled          = true,
		src_factor_rgb   = .ONE,
		dst_factor_rgb   = .ONE_MINUS_SRC_ALPHA,
		src_factor_alpha = .ONE,
		dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
	}
	want := [Mesh_Pipeline]struct {
		shader:      sg.Shader,
		cull:        sg.Cull_Mode,
		depth_write: bool,
		blend:       sg.Blend_State,
	} {
		.Opaque            = {opaque.shader, .BACK, true, {}},
		.Mask              = {shaders.mask, .BACK, true, {}},
		.Mask_Double_Sided = {shaders.mask, .NONE, true, {}},
		.Blend             = {shaders.blend, .BACK, false, premultiplied},
		.Blend_Back_Faces  = {shaders.blend, .FRONT, false, premultiplied},
	}
	for w, pipeline in want {
		d := mesh_pipeline_desc(opaque, shaders, pipeline)
		testing.expectf(t, d.shader == w.shader, "%v: shader %v", pipeline, d.shader)
		testing.expectf(t, d.cull_mode == w.cull, "%v: cull %v", pipeline, d.cull_mode)
		testing.expectf(t, d.depth.write_enabled == w.depth_write, "%v: depth write %v", pipeline, d.depth.write_enabled)
		testing.expectf(t, d.colors[0].blend == w.blend, "%v: blend %v", pipeline, d.colors[0].blend)
	}
}
