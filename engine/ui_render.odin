package engine

import sg "../sokol-odin/sokol/gfx"
import "core:mem"

// The GPU side of the UI: one pipeline, one atlas and one vertex buffer
// that renderer_ui refills each frame.
Ui_Gpu :: struct {
	pip:      sg.Pipeline,
	vertices: sg.Buffer,
	indices:  sg.Buffer,
	atlas:    Mesh_Texture,
	scratch:  []Ui_Vertex,
}

// Needs sokol set up. The buffers hold quad_capacity quads. sample_count is
// the swapchain's, so the pipeline matches it.
ui_gpu_init :: proc(g: ^Ui_Gpu, quad_capacity: int, sample_count: i32, allocator: mem.Allocator) -> mem.Allocator_Error {
	g.scratch = make([]Ui_Vertex, quad_capacity * 4, allocator) or_return
	indices := make([]u16, quad_capacity * len(UI_QUAD_INDICES), context.temp_allocator) or_return
	for i in 0 ..< quad_capacity {
		for index, j in UI_QUAD_INDICES {
			indices[i * len(UI_QUAD_INDICES) + j] = u16(i * 4) + index
		}
	}
	g.indices = sg.make_buffer({usage = {index_buffer = true}, data = {ptr = raw_data(indices), size = uint(len(indices) * size_of(u16))}, label = "ui-indices"})
	g.vertices = sg.make_buffer({usage = {vertex_buffer = true, stream_update = true}, size = uint(len(g.scratch) * size_of(Ui_Vertex)), label = "ui-vertices"})

	image := sg.make_image(
		{
			width = FONT_ATLAS_WIDTH,
			height = FONT_ATLAS_HEIGHT,
			pixel_format = .R8,
			data = {mip_levels = {0 = {ptr = &FONT_ATLAS, size = size_of(FONT_ATLAS)}}},
			label = "font-atlas",
		},
	)
	g.atlas = {
		image   = image,
		view    = sg.make_view({texture = {image = image}}),
		sampler = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE, label = "font-atlas"}),
	}

	// The UI draws over the scene, so it ignores depth and blends by alpha.
	g.pip = sg.make_pipeline(
		{
			shader = sg.make_shader(ui_shader_desc(sg.query_backend())),
			sample_count = sample_count,
			depth = {compare = .ALWAYS},
			colors = {
				0 = {
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
						src_factor_alpha = .ONE,
						dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
					},
				},
			},
			index_type = .UINT16,
			cull_mode = .NONE,
			layout = {
				attrs = {
					ATTR_ui_pos = {format = .FLOAT2},
					ATTR_ui_uv = {format = .FLOAT2},
					ATTR_ui_color = {format = .FLOAT4},
					ATTR_ui_shape = {format = .FLOAT4},
				},
			},
			label = "ui",
		},
	)
	return nil
}

// sokol allows one update_buffer per buffer per frame, so this runs at most once a frame.
renderer_ui :: proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {
	r := (^Renderer)(ctx)
	g := &r.ui
	assert(len(quads) * 4 <= len(g.scratch))
	for q, i in quads {
		corners := ui_quad_vertices(q)
		copy(g.scratch[i * 4:], corners[:])
	}
	sg.update_buffer(g.vertices, {ptr = raw_data(g.scratch), size = uint(len(quads) * 4 * size_of(Ui_Vertex))})
	sg.apply_pipeline(g.pip)
	sg.apply_bindings({vertex_buffers = {0 = g.vertices}, index_buffer = g.indices, views = {VIEW_font_tex = g.atlas.view}, samplers = {SMP_font_smp = g.atlas.sampler}})
	vs := Ui_Vs_Params{screen = {screen.x, screen.y, 0, 0}}
	sg.apply_uniforms(UB_ui_vs_params, {ptr = &vs, size = size_of(Ui_Vs_Params)})
	sg.draw(0, i32(len(quads) * len(UI_QUAD_INDICES)), 1)
}
