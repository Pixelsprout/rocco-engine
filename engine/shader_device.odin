package engine

import sg "../sokol-odin/sokol/gfx"
import "core:encoding/json"

when ODIN_OS == .Linux {
 foreign import shader_gl "system:GL"
 foreign shader_gl { @(link_name = "glGetIntegerv") shader_gl_integer :: proc "system" (name: u32, value: ^i32) --- }
}

shader_device_check :: proc(p: json.Object) -> string {
	limits := sg.query_limits()
	if len(shader_array(p["attrs"])) > int(limits.max_vertex_attrs) { return "device vertex attribute capacity exceeded" }
	components, textures: [2]int
	storage := 0
	for block in shader_array(p["uniform_blocks"]) { b := shader_object(block); i := 0 if shader_text(b["stage"]) == "vertex" else 1; components[i] += shader_int(b["size"]) / 4 }
	for view in shader_array(p["views"]) { o := shader_object(view); if t, has := o["texture"]; has { i := 0 if shader_text(shader_object(t)["stage"]) == "vertex" else 1; textures[i] += 1 }; if "storage_buffer" in o { storage += 1 } }
	if max(textures[0], textures[1]) > int(limits.max_texture_bindings_per_stage) || storage > int(limits.max_storage_buffer_bindings_per_stage) { return "device sampled texture or storage capacity exceeded" }
	when ODIN_OS == .Linux {
		names := [7]u32{0x8B49, 0x8B4C, 0x8872, 0x8B4D, 0x90DD, 0x90DA, 0x8B4A}
		values: [7]i32
		for name, i in names { shader_gl_integer(name, &values[i]) }
		if components[0] > int(values[6]) || components[1] > int(values[0]) || textures[0] > int(values[1]) || textures[1] > int(values[2]) || textures[0] + textures[1] > int(values[3]) || storage > int(values[4]) || storage > int(values[5]) { return "GL reflected uniform, texture, or compact storage capacity exceeded" }
	}
	return ""
}
