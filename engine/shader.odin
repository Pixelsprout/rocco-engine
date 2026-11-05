package engine

import sg "../sokol-odin/sokol/gfx"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"

SHADER_ASSET_LIMIT :: 32
SHADER_PIPELINE_LIMIT :: 63
SHADER_TEXTURE_LIMIT :: 4

#assert(size_of(Surface_Vertex_Params) == 256)
#assert(size_of(Surface_Instance) == 116)
#assert(align_of(Surface_Instance) == 4)
#assert(offset_of(Surface_Instance, model) == 0 && offset_of(Surface_Instance, normal) == 64 && offset_of(Surface_Instance, tint) == 100)
#assert(size_of(Fs_Params) == 96 && size_of(Fs_Lights) == 512)

Shader_Asset :: Roc_VocabularyNode_Draw_Material_Surface_Surface_Shader
Shader_Values :: Roc_VocabularyNode_Draw_Material_Surface_Surface
Shader_Scope :: Roc_VocabularyNode_Draw_Material_Surface_Surface_Scope
Shader_Value :: Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters_Value
Material_Override :: Roc_VocabularyNode_Draw_Material
Material_Slot :: Roc_VocabularyNode_Draw_Materials_Slot

Surface_Pass :: enum { Colour, Shadow, Selection }
Shader_Layout :: enum { Rigid, Skinned, Instanced }
Shader_Pipeline_Key :: struct { pass: Surface_Pass, layout: Shader_Layout, alpha: Alpha_Mode, cull: sg.Cull_Mode }
Shader_Program :: struct { reflection: json.Object, handle: sg.Shader }
Shader :: struct {
	name: string,
	live, staged, ready, failed, retiring, declared: bool,
	retire_after: u64,
	generation: u16,
	package_data: Shader_Package,
	programs: [9]Shader_Program,
	pipelines: map[Shader_Pipeline_Key]sg.Pipeline,
	post_pipelines: [2]sg.Pipeline,
	samplers: [4]sg.Sampler,
	constants: [4]Mesh_Texture,
}
Shader_Table :: struct {
	assets: [SHADER_ASSET_LIMIT+1]Shader,
	refs: [SHADER_ASSET_LIMIT+1]int,
	uploaded: bool,
	sample_count: i32,
	frame: u64,
	allocator: mem.Allocator,
}
Surface_Material :: struct {
	shader: ^Shader,
	imported: [4]int,
	vertex, fragment: [64]f32,
	textures: [4]Mesh_Texture,
	draw_info: [4]f32,
	time: f32,
}
Surface_Vertex_Params :: struct {
	mvp, model, normal_model: Mat4,
	render_time, draw_info, camera, reserved_vertex: [4]f32,
}
// Vertex streams use scalar columns because matrix alignment can add trailing padding.
Surface_Instance :: struct { model: [4][4]f32, normal: [3][3]f32, tint: [4]f32 }

shader_table_init :: proc(t: ^Shader_Table, allocator: mem.Allocator) { t.allocator = allocator }
shader_table_full :: proc(t: ^Shader_Table) -> bool { return shader_free_slot(t) == 0 }
shader_free_slot :: proc(t: ^Shader_Table) -> int { for s, i in t.assets { if i > 0 && !s.live && !s.staged && !s.retiring && s.generation != max(u16) { return i } }; return 0 }
shader_id :: proc(t: ^Shader_Table, slot: int) -> u32 { return u32(t.assets[slot].generation) << MESH_SLOT_BITS | u32(slot) }
shader_lookup :: proc(t: ^Shader_Table, id: u32) -> (^Shader, bool) { slot := mesh_slot(id); if slot > 0 && slot < len(t.assets) && t.assets[slot].live && shader_id(t, slot) == id { return &t.assets[slot], true }; return nil, false }
shader_table_find :: proc(t: ^Shader_Table, name: string) -> (u32, bool) { for s, i in t.assets { if s.live && s.name == name { return shader_id(t, i), true } }; return 0, false }

shader_names_on_disk :: proc(dir: string, allocator: mem.Allocator) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
	if err != nil { return nil }
	names := make([dynamic]string, 0, len(entries), allocator)
	for e in entries { if e.type != .Directory && os.ext(e.name) == ".shaderpack" && shader_identifier(os.stem(e.name)) { append(&names, strings.concatenate({SHADER_PREFIX, os.stem(e.name)}, allocator)) } }
	slice.sort(names[:]); return names[:]
}

shader_load_file :: proc(t: ^Shader_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
 caller_temp := context.temp_allocator
 scratch: vmem.Arena
 defer vmem.arena_destroy(&scratch)
 context.temp_allocator = vmem.arena_allocator(&scratch)
 id, reason, ok = shader_load_file_scoped(t, dir, name)
 if !ok && reason != "" { reason = strings.clone(reason, caller_temp) }
 return
}

shader_load_file_scoped :: proc(t: ^Shader_Table, dir, name: string) -> (id: u32, reason: string, ok: bool) {
	if shader_table_full(t) { return 0, "Shader asset capacity exhausted", false }
	file, err := os.open(fmt.tprintf("%v/%v.shaderpack", dir, strings.trim_prefix(name, SHADER_PREFIX)))
 if err != nil { return 0, "cannot open Shader asset", false }
 defer os.close(file)
 size, size_error := os.file_size(file)
 if size_error != nil || size < SHADER_HEADER_SIZE || size > SHADER_HEADER_SIZE + SHADER_METADATA_LIMIT + SHADER_PAYLOAD_LIMIT { return 0, "invalid Shader asset file size", false }
 bytes := make([]byte, int(size), t.allocator)
 read := 0
 for read < len(bytes) {
  n, error := os.read(file, bytes[read:])
  read += n
  if n == 0 || error != nil { delete(bytes, t.allocator); return 0, "truncated Shader asset", false }
 }
 extra: [1]byte
 if n, _ := os.read(file, extra[:]); n != 0 { delete(bytes, t.allocator); return 0, "Shader asset changed while reading", false }
	pkg, error, parsed := shader_package_parse(bytes, t.allocator)
	if !parsed { delete(bytes, t.allocator); return 0, error, false }
	for &s, slot in t.assets {
		if slot == 0 || s.live || s.staged || s.retiring || s.generation == max(u16) { continue }
		s = {name = strings.clone(name, t.allocator), live = true, generation = s.generation, package_data = pkg, pipelines = make(map[Shader_Pipeline_Key]sg.Pipeline, t.allocator)}
		if t.uploaded && !shader_upload(t, &s) { shader_table_remove(t, slot); return 0, "Shader GPU generation failed", false }
		return shader_id(t, slot), "", true
	}
	json.destroy_value(pkg.manifest, t.allocator)
	delete(bytes,t.allocator)
	return 0, "Shader asset capacity exhausted", false
}

shader_gpu_destroy :: proc(s: ^Shader) {
	if sg.isvalid() {
		for _, pip in s.pipelines { sg.destroy_pipeline(pip) }
		for pip in s.post_pipelines { sg.destroy_pipeline(pip) }
		for program in s.programs { if program.handle.id != 0 { sg.destroy_shader(program.handle) } }
		for sampler in s.samplers { if sampler.id != 0 { sg.destroy_sampler(sampler) } }
		for tex in s.constants { if tex.image.id != 0 { sg.destroy_view(tex.view); sg.destroy_image(tex.image) } }
	}
	clear(&s.pipelines); s.post_pipelines = {}; s.programs = {}; s.samplers = {}; s.constants = {}; s.ready = false
}
shader_table_remove :: proc(t: ^Shader_Table, slot: int) {
 s := &t.assets[slot]
 json.destroy_value(s.package_data.manifest, t.allocator)
 delete(s.package_data.bytes, t.allocator); delete(s.name, t.allocator)
 s.package_data = {}; s.name = ""; s.live = false; s.generation += 1
 if t.uploaded && s.ready {
  s.retiring = true; s.retire_after = t.frame + sg.NUM_INFLIGHT_FRAMES + 1
  for &program in s.programs { program.reflection = nil }
 } else { shader_retire_destroy(s) }
}
shader_retire_destroy :: proc(s: ^Shader) {
 shader_gpu_destroy(s); delete(s.pipelines)
 s^ = {generation = s.generation}
}
shader_table_frame :: proc(t: ^Shader_Table) {
 t.frame += 1
 for &s in t.assets { if s.retiring && t.frame >= s.retire_after { shader_retire_destroy(&s) } }
}
shader_table_destroy :: proc(t: ^Shader_Table) {
 for &s, i in t.assets {
  if s.staged { shader_candidate_destroy(t, i) }
  if s.live { shader_table_remove(t, i) }
  if s.retiring { shader_retire_destroy(&s) }
 }
}
shader_table_upload :: proc(t: ^Shader_Table, sample_count: i32) {
	t.sample_count = sample_count; t.uploaded = true
	for &s in t.assets { if s.live { shader_upload(t, &s) } }
}
shader_interface :: proc(s: ^Shader) -> json.Object { return shader_object(shader_object(shader_object(s.package_data.manifest)["interface"])["post" if s.package_data.post else "surface"]) }
shader_program_index :: proc(name: string) -> int { for n, i in SHADER_PROGRAM_NAMES { if n == name { return i } }; if name == "post_hdr" { return 0 }; if name == "post_ldr" { return 1 }; return -1 }

shader_sampler_desc :: proc(declaration: json.Object) -> sg.Sampler_Desc {
	policy := shader_object(declaration["sampler_policy"])
	wrap := sg.Wrap.CLAMP_TO_EDGE
	switch shader_text(policy["wrap"]) {
	case "repeat":
		wrap = .REPEAT
	case "mirror":
		wrap = .MIRRORED_REPEAT
	}
	return {min_filter = .LINEAR if shader_text(policy["min"]) == "linear" else .NEAREST, mag_filter = .LINEAR if shader_text(policy["mag"]) == "linear" else .NEAREST, wrap_u = wrap, wrap_v = wrap, wrap_w = wrap}
}
shader_upload :: proc(t: ^Shader_Table, s: ^Shader) -> bool {
 scratch: vmem.Arena
 defer vmem.arena_destroy(&scratch)
 context.temp_allocator = vmem.arena_allocator(&scratch)

	if s.ready { return true }; if s.failed { return false }
	backend := "metal_macos"
	#partial switch sg.query_backend() {
	case .GLCORE:
		backend = "glsl430"
	case .D3D11:
		backend = "hlsl5"
	case .METAL_MACOS:
	case:
		s.failed = true; return false
	}
	defer if !s.ready {
		s.failed = true; shader_gpu_destroy(s)
		if s.staged { fmt.eprintfln("Shader %q candidate failed GPU validation", s.name) }
		else { fmt.eprintfln("Shader %q failed GPU validation; affected parts are omitted", s.name) }
	}
 for declaration in shader_array(shader_interface(s)["textures"]) {
  d := shader_object(declaration)
  if "constant" in shader_object(d["default"]) {
   caps := sg.query_pixelformat(.RGBA32F)
   policy := shader_object(d["sampler_policy"])
   filtering := shader_text(policy["min"]) == "linear" || shader_text(policy["mag"]) == "linear"
   if !caps.sample || filtering && !caps.filter { fmt.eprintfln("Shader %q needs unsupported RGBA32F constant sampling",s.name);return false }
  }
 }
	root := shader_object(s.package_data.manifest)
	for b in shader_array(root["shaders"]) {
		obj := shader_object(b); if shader_text(obj["slang"]) != backend { continue }
		for program in shader_array(obj["programs"]) { p := shader_object(program); if reason := shader_device_check(p); reason != "" { fmt.eprintfln("Shader %q %v: %v", s.name, shader_text(p["name"]), reason); return false } }
		for program in shader_array(obj["programs"]) {
			p := shader_object(program); index := shader_program_index(shader_text(p["name"]))
			handle := shader_make_program(&s.package_data, p); s.programs[index] = {p, handle}
			if sg.query_shader_state(handle) != .VALID { return false }
		}
	}
	for declaration in shader_array(shader_interface(s)["textures"]) {
		d := shader_object(declaration); index := shader_int(d["view"]) - 8
		s.samplers[index] = sg.make_sampler(shader_sampler_desc(d))
		if sg.query_sampler_state(s.samplers[index]) != .VALID { return false }
		default := shader_object(d["default"])
		if constant, exists := default["constant"]; exists {
			pixels := shader_constant_texels(constant)
			cube := shader_text(d["type"]) == "cube"
			image := sg.make_image({type = .CUBE if cube else ._2D, width = 1, height = 1, num_slices = 6 if cube else 1, pixel_format = .RGBA32F, data = {mip_levels = {0 = {ptr = &pixels[0], size = 96 if cube else 16}}}})
			s.constants[index] = {image = image, view = sg.make_view({texture = {image = image}})}
			if sg.query_image_state(image) != .VALID || sg.query_view_state(s.constants[index].view) != .VALID { return false }
		}
	}
	s.ready = true; return true
}

shader_pipeline :: proc(t: ^Shader_Table, s: ^Shader, key: Shader_Pipeline_Key) -> (sg.Pipeline, bool) {
	key := key
	if key.pass != .Colour && key.alpha == .Blend { key.alpha = .Opaque }
	if pip, has := s.pipelines[key]; has { return pip, true }
	if !s.ready || len(s.pipelines) >= SHADER_PIPELINE_LIMIT { return {}, false }
	index := int(key.layout) * 3 + int(key.pass); program := s.programs[index]
	if program.handle.id == 0 { return {}, false }
	d := sg.Pipeline_Desc{shader = program.handle, index_type = .UINT16, face_winding = .CCW, cull_mode = key.cull, depth = {pixel_format = TARGET_DEPTH_FORMAT, compare = .GREATER_EQUAL, write_enabled = true}, colors = {0 = {pixel_format = HDR_COLOR_FORMAT}}, sample_count = t.sample_count}
	if key.pass == .Shadow { d.colors[0].pixel_format = .NONE; d.depth.pixel_format = .DEPTH; d.depth.bias = SHADOW_DEPTH_BIAS; d.depth.bias_slope_scale = SHADOW_SLOPE_BIAS; d.sample_count = 1 }
	if key.pass == .Selection { d.color_count = 2; d.colors[0].pixel_format = .R8; d.colors[1].pixel_format = .R32F; d.sample_count = 1; d.depth.pixel_format = .DEPTH }
	if key.pass == .Colour && key.alpha == .Blend { d.depth.write_enabled = false; d.colors[0].blend = {enabled = true, src_factor_rgb = .ONE, dst_factor_rgb = .ONE_MINUS_SRC_ALPHA, src_factor_alpha = .ONE, dst_factor_alpha = .ONE_MINUS_SRC_ALPHA} }
	stride := size_of(Skinned_Vertex) if key.layout == .Skinned else size_of(Vertex); d.layout.buffers[0].stride = i32(stride)
	formats := [5]sg.Vertex_Format{.FLOAT3, .FLOAT4, .FLOAT3, .FLOAT2, .FLOAT4}
	offsets := [5]uintptr{offset_of(Vertex, pos), offset_of(Vertex, color), offset_of(Vertex, normal), offset_of(Vertex, uv), offset_of(Vertex, tangent)}
	for format, i in formats { d.layout.attrs[i] = {format = format, offset = i32(offsets[i])} }
	if key.layout == .Skinned { d.layout.attrs[5] = {format = .UBYTE4, offset = i32(offset_of(Skinned_Vertex, joints))}; d.layout.attrs[6] = {format = .UBYTE4N, offset = i32(offset_of(Skinned_Vertex, weights))} }
	if key.layout == .Instanced {
		d.layout.buffers[1] = {stride = size_of(Surface_Instance), step_func = .PER_INSTANCE}
		for i in 0 ..< 4 { d.layout.attrs[5+i] = {format = .FLOAT4, buffer_index = 1, offset = i32(offset_of(Surface_Instance, model))+i32(i*16)} }
		for i in 0 ..< 3 { d.layout.attrs[9+i] = {format = .FLOAT3, buffer_index = 1, offset = i32(offset_of(Surface_Instance, normal))+i32(i*12)} }
		d.layout.attrs[12] = {format = .FLOAT4, buffer_index = 1, offset = i32(offset_of(Surface_Instance, tint))}
	}
	// Sokol rejects attributes absent from the compiled vertex stage.
	active: [16]bool; for a in shader_array(program.reflection["attrs"]) { active[shader_int(shader_object(a)["slot"])] = true }
	for &a, i in d.layout.attrs { if !active[i] { a = {} } }
	pip := sg.make_pipeline(d)
	if sg.query_pipeline_state(pip) != .VALID { sg.destroy_pipeline(pip); return {}, false }
	s.pipelines[key] = pip; return pip, true
}

shader_constant_texels :: proc(value: json.Value) -> (pixels: [24]f32) {
 for component,i in shader_array(value) { n,_:=shader_number(component); for face in 0 ..< 6 { pixels[face*4+i]=n } }
 return
}

shader_make_program :: proc(pkg: ^Shader_Package, reflection: json.Object) -> sg.Shader {
 scratch: vmem.Arena
 defer vmem.arena_destroy(&scratch)
 context.temp_allocator = vmem.arena_allocator(&scratch)
 // Sokol consumes source and reflected names during make_shader.
 return sg.make_shader(shader_program_desc(pkg, reflection))
}
