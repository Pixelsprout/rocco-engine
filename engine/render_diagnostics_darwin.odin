#+build darwin
package engine

import sg "../sokol-odin/sokol/gfx"

when sg.DEBUG {
	foreign import render_diagnostics_native "../sokol-odin/sokol/gfx/sokol_gfx_macos_arm64_metal_debug.a"
} else {
	foreign import render_diagnostics_native "../sokol-odin/sokol/gfx/sokol_gfx_macos_arm64_metal_release.a"
}

g_render_diagnostics_enabled: bool
g_render_diagnostics_active: bool

foreign render_diagnostics_native {
	rocco_render_diagnostics_open :: proc "c" () -> bool ---
	rocco_render_diagnostics_close :: proc "c" () ---
	rocco_render_diagnostics_begin :: proc "c" (step: u64, placed: u32, camera_values: ^[11]u32) -> bool ---
	rocco_render_diagnostics_visible :: proc "c" (visible: u32) ---
	rocco_render_diagnostics_buffer :: proc "c" (role: cstring, buffer_id: u32) ---
}

render_diagnostics_begin :: proc(fr: ^Frame_Render, view: Frame_View) {
	if !g_render_diagnostics_enabled { return }
	c := view.camera
	camera_values := transmute([11]u32)([11]f32{c.eye.x, c.eye.y, c.eye.z, c.target.x, c.target.y, c.target.z, c.up.x, c.up.y, c.up.z, c.fov_y, view.aspect})
	g_render_diagnostics_active = rocco_render_diagnostics_begin(g_state.steps, u32(len(fr.placed)), &camera_values)
	if !g_render_diagnostics_active { return }
	r := &g_state.renderer
	rocco_render_diagnostics_buffer("instance", r.instance_buffer.id)
	for buffer in r.cluster_buffers { rocco_render_diagnostics_buffer("cluster", buffer.id) }
	if len(fr.placed) > 0 {
		mesh := fr.placed[0].mesh
		rocco_render_diagnostics_buffer("first-mesh-vertex", mesh.vertices.id)
		rocco_render_diagnostics_buffer("first-mesh-surface", mesh.surface_vertices.id)
		rocco_render_diagnostics_buffer("first-mesh-index", mesh.indices.id)
	}
}

render_diagnostics_visible :: proc(params: []Draw_Params) {
	if !g_render_diagnostics_active { return }
	visible: u32
	for p in params { if p.p.camera_visible { visible += 1 } }
	rocco_render_diagnostics_visible(visible)
}
