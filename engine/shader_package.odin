package engine

import sg "../sokol-odin/sokol/gfx"
import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem"
import vmem "core:mem/virtual"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

SHADER_PREFIX :: "shader/"
SHADER_HEADER_SIZE :: 96
SHADER_METADATA_LIMIT :: 1024 * 1024
SHADER_PAYLOAD_LIMIT :: 16 * 1024 * 1024
@(rodata)
SHADER_UNIFORM_SIZES := [6]int{256, 96, 512, 4096, 256, 256}
@(rodata)
SHADER_BACKENDS := [3]string{"glsl430", "hlsl5", "metal_macos"}
@(rodata)
SHADER_PROGRAM_NAMES := [9]string{"surface_colour", "surface_shadow", "surface_selection", "skinned_colour", "skinned_shadow", "skinned_selection", "instanced_colour", "instanced_shadow", "instanced_selection"}
@(rodata)
SHADER_PARAMETER_TYPES := [7]string{"Bool", "Colour", "Mat4", "F32", "Vec2", "Vec3", "Vec4"}
@(rodata)
SHADER_PARAMETER_COMPONENTS := [7]int{1, 4, 16, 1, 2, 3, 4}

@(rodata)
SHADER_SHA256_K := [64]u32{
0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

Shader_Package :: struct {
	manifest: json.Value,
	bytes: []byte,
	payload: []byte,
	fingerprint: [32]byte,
	post: bool,
	max_displacement: f32,
}

Shader_Requirements :: struct { components: [2]int, textures: [2]int, attributes, storage, samplers, pairs, uniform_bytes: int }

Shader_Validation :: struct { reason: string }
Shader_Canonical :: struct {
	source: string,
	at, depth: int,
	valid: bool,
	interface, layout: string,
}

shader_rotate :: #force_inline proc(x: u32, n: uint) -> u32 { return x >> n | x << (32-n) }

shader_hash :: proc(bytes: []byte) -> (digest: [32]byte) {
 h := [8]u32{0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
 count := (len(bytes) + 9 + 63) / 64
 for block in 0 ..< count {
  buffer: [64]byte
  for i in 0 ..< 64 {
   at := block*64+i
   if at < len(bytes) { buffer[i] = bytes[at] } else if at == len(bytes) { buffer[i] = 0x80 }
  }
  if block == count-1 { endian.put_u64(buffer[56:], .Big, u64(len(bytes))*8) }
  w: [64]u32
  for i in 0 ..< 16 { w[i], _ = endian.get_u32(buffer[i*4:], .Big) }
  for i in 16 ..< 64 {
   x,y := w[i-15],w[i-2]
   s0 := shader_rotate(x,7) ~ shader_rotate(x,18) ~ (x >> 3)
   s1 := shader_rotate(y,17) ~ shader_rotate(y,19) ~ (y >> 10)
   w[i] = w[i-16]+s0+w[i-7]+s1
  }
  a,b,c,d,e,f,g,z := h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7]
  for i in 0 ..< 64 {
   s1 := shader_rotate(e,6) ~ shader_rotate(e,11) ~ shader_rotate(e,25)
   choose := (e & f) ~ (~e & g)
   t1 := z+s1+choose+SHADER_SHA256_K[i]+w[i]
   s0 := shader_rotate(a,2) ~ shader_rotate(a,13) ~ shader_rotate(a,22)
   majority := (a & b) ~ (a & c) ~ (b & c)
   t2 := s0+majority
   z,g,f,e,d,c,b,a = g,f,e,d+t1,c,b,a,t1+t2
  }
  h += [8]u32{a,b,c,d,e,f,g,z}
 }
 for value,i in h { endian.put_u32(digest[i*4:], .Big, value) }
 return
}

shader_object :: proc(value: json.Value) -> json.Object { v, _ := value.(json.Object); return v }
shader_array :: proc(value: json.Value) -> []json.Value { v, _ := value.(json.Array); return v[:] }
shader_text :: proc(value: json.Value) -> string { v, _ := value.(json.String); return v }
shader_int :: proc(value: json.Value) -> int { v, ok := value.(json.Integer); return int(v) if ok else -1 }
shader_bool :: proc(value: json.Value) -> bool { v, _ := value.(json.Boolean); return v }
shader_number :: proc(value: json.Value) -> (f32, bool) {
	n: f64
	#partial switch v in value {
	case json.Integer:
		n = f64(v)
	case json.Float:
		n = v
	case:
		return 0, false
	}
	return f32(n), !math.is_nan(n) && !math.is_inf(n) && abs(n) <= f64(max(f32))
}
shader_fail :: proc(v: ^Shader_Validation, reason: string) -> bool { if v.reason == "" { v.reason = reason }; return false }
shader_require :: proc(v: ^Shader_Validation, condition: bool, reason: string) -> bool { return condition || shader_fail(v, reason) }
shader_fields :: proc(v: ^Shader_Validation, value: json.Value, required: []string, optional: []string = nil) -> bool {
	o, ok := value.(json.Object)
	if !shader_require(v, ok, "expected a manifest object") { return false }
	for key in required { if _, has := o[key]; !has { return shader_fail(v, fmt.tprintf("missing manifest field %q", key[:min(len(key),128)])) } }
	for key in o { if !slice.contains(required, key) && !slice.contains(optional, key) { return shader_fail(v, fmt.tprintf("unknown manifest field %q", key[:min(len(key),128)])) } }
	return true
}
shader_list :: proc(v: ^Shader_Validation, value: json.Value, limit: int) -> bool {
	a, ok := value.(json.Array)
	return shader_require(v, ok && len(a) <= limit, "invalid manifest list or resource capacity")
}
shader_identifier :: proc(name: string, lowercase := false) -> bool {
	if len(name) == 0 { return false }
	for c, i in name {
		letter := c >= 'a' && c <= 'z' || !lowercase && c >= 'A' && c <= 'Z'
		if !letter && !(c == '_' && (!lowercase || i > 0)) && !(i > 0 && c >= '0' && c <= '9') { return false }
	}
	return true
}
shader_stage :: proc(value: json.Value) -> sg.Shader_Stage {
	return .VERTEX if shader_text(value) == "vertex" else .FRAGMENT
}

// Keep numeric spellings from the canonical pkg when removing private reflection fields.
shader_canonical_value :: proc(c: ^Shader_Canonical) -> string {
	if !c.valid || c.at >= len(c.source) || c.depth > 32 { c.valid = false; return "" }
	start := c.at
	switch c.source[c.at] {
	case '{', '[':
		object := c.source[c.at] == '{'
		end := byte('}') if object else ']'
		b := strings.builder_make(context.temp_allocator)
		strings.write_byte(&b, c.source[c.at]); c.at += 1; c.depth += 1
		previous := ""
		seen_key := false
		first := true
		for c.at < len(c.source) && c.source[c.at] != end {
			key, raw_key: string
			if object {
				if c.source[c.at] != '"' { c.valid = false; return "" }
				raw_key = shader_canonical_value(c)
				value, err := json.parse_string(raw_key, spec = .JSON, allocator = context.temp_allocator)
				key = shader_text(value)
				if err != nil || len(key) == 0 || (seen_key && key <= previous) || c.at >= len(c.source) || c.source[c.at] != ':' { c.valid = false; return "" }
				previous = key; seen_key = true; c.at += 1
			}
			value := shader_canonical_value(c)
			if c.depth == 1 && key == "interface" { c.interface = value }
			if c.depth == 1 && key == "shaders" { c.layout = value }
			if key != "vertex_func" && key != "fragment_func" && key != "inst_name" {
				if !first { strings.write_byte(&b, ',') }
				if object { strings.write_string(&b, raw_key); strings.write_byte(&b, ':') }
				strings.write_string(&b, value)
				first = false
			}
			if !c.valid || c.at >= len(c.source) { c.valid = false; return "" }
			if c.source[c.at] == end { break }
			if c.source[c.at] != ',' { c.valid = false; return "" }; c.at += 1
			if c.at >= len(c.source) || c.source[c.at] == end { c.valid = false; return "" }
		}
		if c.at >= len(c.source) { c.valid = false; return "" }
		c.at += 1; c.depth -= 1; strings.write_byte(&b, end)
		return strings.to_string(b)
	case '"':
		c.at += 1
		for c.at < len(c.source) {
			ch := c.source[c.at]; c.at += 1
			if ch == '"' { raw := c.source[start:c.at]; if !shader_canonical_string(raw) { c.valid = false }; return raw }
			if ch == '\\' { c.at += 1 }
		}
		c.valid = false; return ""
	case:
		for c.at < len(c.source) && c.source[c.at] != ',' && c.source[c.at] != ']' && c.source[c.at] != '}' {
			if c.source[c.at] <= ' ' { c.valid = false; return "" }; c.at += 1
		}
		if c.at == start || !shader_canonical_number(c.source[start:c.at]) { c.valid = false }
		return c.source[start:c.at]
	}
}

// The caller owns bytes. Failure creates no GPU objects and leaves no retained JSON.
shader_package_parse :: proc(bytes: []byte, allocator: mem.Allocator) -> (pkg: Shader_Package, reason: string, ok: bool) {
 caller_temp := context.temp_allocator
 scratch: vmem.Arena
 defer vmem.arena_destroy(&scratch)
 context.temp_allocator = vmem.arena_allocator(&scratch)
 pkg, reason, ok = shader_package_parse_scoped(bytes, allocator)
 if !ok && reason != "" { reason = strings.clone(reason, caller_temp) }
 return
}

shader_package_parse_scoped :: proc(bytes: []byte, allocator: mem.Allocator) -> (pkg: Shader_Package, reason: string, ok: bool) {
	if len(bytes) < SHADER_HEADER_SIZE || string(bytes[:8]) != "RCSHADER" { return {}, "invalid shader header", false }
	format, _ := endian.get_u16(bytes[8:], .Little); contract, _ := endian.get_u16(bytes[10:], .Little)
	header, _ := endian.get_u32(bytes[12:], .Little); metadata_size, _ := endian.get_u32(bytes[16:], .Little)
	payload_size, _ := endian.get_u32(bytes[20:], .Little); flags, _ := endian.get_u32(bytes[24:], .Little); mask, _ := endian.get_u32(bytes[28:], .Little)
	if format != 1 || contract != 1 || header != SHADER_HEADER_SIZE || flags != 0 || mask != 7 { return {}, "incompatible shader contract version or backend mask", false }
	if metadata_size == 0 || metadata_size > SHADER_METADATA_LIMIT || payload_size == 0 || payload_size > SHADER_PAYLOAD_LIMIT || u64(len(bytes)) != u64(header) + u64(metadata_size) + u64(payload_size) { return {}, "invalid shader package size", false }
	body := bytes[header:]
	checksum := shader_hash(body)
	if !slice.equal(checksum[:], bytes[64:96]) { return {}, "shader package checksum mismatch", false }
	metadata := string(body[:metadata_size])
	if !utf8.valid_string(metadata) { return {}, "shader manifest is not UTF-8", false }
	canonical := Shader_Canonical{source = metadata, valid = true}
	shader_canonical_value(&canonical)
	if !canonical.valid || canonical.at != len(metadata) || canonical.interface == "" || canonical.layout == "" { return {}, "shader manifest is not canonical JSON", false }
	fingerprint := shader_hash(transmute([]byte)strings.concatenate({`{"interface":`, canonical.interface, `,"layout":`, canonical.layout, `}`}, context.temp_allocator))
	if !slice.equal(fingerprint[:], bytes[32:64]) { return {}, "shader interface fingerprint mismatch", false }
	manifest, err := json.parse_string(shader_json_numbers(metadata), spec = .JSON, parse_integers = true, allocator = allocator)
	if err != nil { return {}, "invalid shader JSON manifest", false }

	pkg = {manifest = manifest, bytes = bytes, payload = body[metadata_size:], fingerprint = fingerprint}
	validation: Shader_Validation
	if !shader_manifest_validate(&validation, &pkg) { json.destroy_value(manifest, allocator); return {}, validation.reason, false }
	return pkg, "", true
}

shader_manifest_validate :: proc(v: ^Shader_Validation, pkg: ^Shader_Package) -> bool {
	if !shader_fields(v, pkg.manifest, {"compiler", "backend_transform", "interface", "shaders"}) { return false }
	root := shader_object(pkg.manifest)
	if shader_text(root["backend_transform"]) != "gl_ssbo_compact_v1" { return shader_fail(v, "unsupported backend transform") }
	if !shader_fields(v, root["compiler"], {"repository", "commit"}) { return false }
	compiler := shader_object(root["compiler"])
	if shader_text(compiler["repository"]) != "floooh/sokol-tools-bin" || shader_text(compiler["commit"]) != "11d0cf678105d614d675e6d9bd2aaf3eeff12f8c" { return shader_fail(v, "unsupported shader compiler") }
	if !shader_fields(v, root["interface"], {"contract", "surface", "post"}) { return false }
	interface := shader_object(root["interface"])
	if shader_int(interface["contract"]) != 1 { return shader_fail(v, "incompatible manifest contract") }
	surface, post := shader_object(interface["surface"]), shader_object(interface["post"])
	_, has_skinning := surface["skinning"]
	_, has_instancing := surface["instancing"]
	if has_skinning != has_instancing { return shader_fail(v, "incomplete Surface layout declarations") }
	pkg.post = !has_skinning
	if !shader_fields(v, interface["surface"], {"max_displacement", "parameters", "textures"}, {"skinning", "instancing"}) || !shader_fields(v, interface["post"], {"parameters", "textures", "inputs", "locations"}) { return false }
	displacement, finite := shader_number(surface["max_displacement"])
	if !finite || displacement < 0 { return shader_fail(v, "invalid maximum displacement") }; pkg.max_displacement = displacement
	if !shader_list(v, post["inputs"], 4) || !shader_list(v, post["locations"], 2) { return false }
	if !pkg.post {
		_, skin_ok := surface["skinning"].(json.Boolean); _, instance_ok := surface["instancing"].(json.Boolean)
		if !skin_ok || !instance_ok || len(shader_array(post["inputs"])) != 0 || len(shader_array(post["locations"])) != 0 || len(shader_array(post["parameters"])) != 0 || len(shader_array(post["textures"])) != 0 { return shader_fail(v, "mixed or invalid shader interfaces") }
	} else if displacement != 0 || len(shader_array(surface["parameters"])) != 0 || len(shader_array(surface["textures"])) != 0 { return shader_fail(v, "mixed shader interfaces") }
	for kind in ([]string{"surface", "post"}) { if !shader_declarations_validate(v, shader_object(interface[kind]), kind == "post") { return false } }
	if !shader_list(v, root["shaders"], 3) || len(shader_array(root["shaders"])) != 3 { return shader_fail(v, "missing shader backend") }
	expected := make([dynamic]string, context.temp_allocator)
	if pkg.post {
		if !shader_list(v, post["locations"], 2) || !shader_list(v, post["inputs"], 4) { return false }
		for loc in shader_array(post["locations"]) {
			name := shader_text(loc)
			if name != "before_bloom" && name != "after_tone_map" { return shader_fail(v, "invalid Post location") }
			program := "post_hdr" if name == "before_bloom" else "post_ldr"
			if slice.contains(expected[:], program) { return shader_fail(v, "duplicate Post location") }; append(&expected, program)
		}
		inputs := make(map[string]bool, context.temp_allocator)
		for input in shader_array(post["inputs"]) { name := shader_text(input); if !slice.contains([]string{"scene_colour", "scene_depth", "selection_coverage", "selection_depth"}, name) || inputs[name] { return shader_fail(v, "invalid Post input") }; inputs[name] = true }
		if len(expected) == 0 || len(inputs) == 0 { return shader_fail(v, "Post requires a location and an input") }
	} else {
		for name, i in SHADER_PROGRAM_NAMES { if i >= 3 && i < 6 && !shader_bool(surface["skinning"]) || i >= 6 && !shader_bool(surface["instancing"]) { continue }; append(&expected, name) }
	}
	reference := make(map[string]Shader_Requirements, context.temp_allocator)
	for backend, i in shader_array(root["shaders"]) {
		if !shader_fields(v, backend, {"slang", "programs"}) { return false }
		b := shader_object(backend)
		if shader_text(b["slang"]) != SHADER_BACKENDS[i] || !shader_list(v, b["programs"], 9) || len(shader_array(b["programs"])) != len(expected) { return shader_fail(v, "incomplete shader variants") }
		used := make(map[string]bool, context.temp_allocator)
		for program in shader_array(b["programs"]) {
			name := shader_text(shader_object(program)["name"])
			if !slice.contains(expected[:], name) || used[name] { return shader_fail(v, "unexpected or duplicate shader variant") }; used[name] = true
			if !shader_program_validate(v, program, SHADER_BACKENDS[i], pkg) { return false }
			budget := shader_requirements(shader_object(program))
			if i == 0 { reference[name] = budget } else if reference[name] != budget { return shader_fail(v, "backend resource budgets differ") }
		}
	}
	return true
}

shader_declarations_validate :: proc(v: ^Shader_Validation, declarations: json.Object, post: bool) -> bool {
	if !shader_list(v, declarations["parameters"], 32) || !shader_list(v, declarations["textures"], 4) { return false }
	names := make(map[string]bool, context.temp_allocator)
	occupied: [2][16]bool
	next_offset: [2]int
	for parameter in shader_array(declarations["parameters"]) {
		if !shader_fields(v, parameter, {"name", "type", "scope", "stage", "default", "offset"}) { return false }
		p := shader_object(parameter); name := shader_text(p["name"])
		if !shader_identifier(name, true) || names[name] { return shader_fail(v, "invalid or duplicate parameter name") }; names[name] = true
		kind := shader_text(p["type"]); index := -1
		for t, i in SHADER_PARAMETER_TYPES { if t == kind { index = i } }
		stage, scope := shader_text(p["stage"]), shader_text(p["scope"])
		if index < 0 || !slice.contains([]string{"vertex", "fragment"}, stage) || !slice.contains([]string{"Scene", "Material", "Draw"}, scope) || post && (stage != "fragment" || scope == "Material") { return shader_fail(v, "invalid parameter type, scope, or stage") }
		components := SHADER_PARAMETER_COMPONENTS[index]
		if !shader_list(v, p["default"], components) || len(shader_array(p["default"])) != components { return shader_fail(v, "invalid parameter default size") }
		for value in shader_array(p["default"]) {
			if kind == "Bool" { if _, ok := value.(json.Boolean); !ok { return shader_fail(v, "Bool default must be boolean") } } else if _, ok := shader_number(value); !ok { return shader_fail(v, "parameter default requires finite F32 values") }
		}
		offset := shader_int(p["offset"]); size := 64 if kind == "Mat4" else 16; s := 0 if stage == "vertex" else 1
		if offset < 0 || offset % 16 != 0 || offset > 256 - size || offset != next_offset[s] { return shader_fail(v, "parameter exceeds aligned game uniform block") }
		next_offset[s] += size
		for lane in offset / 16 ..< (offset + size) / 16 { if occupied[s][lane] { return shader_fail(v, "overlapping parameters") }; occupied[s][lane] = true }
	}
	clear(&names); slots: [4]bool
	for texture in shader_array(declarations["textures"]) {
		if !shader_fields(v, texture, {"name", "scope", "stage", "type", "sample_type", "colour_space", "sampler_policy", "view", "sampler", "default"}, {"optional"}) { return false }
		t := shader_object(texture); name := shader_text(t["name"]); slot := shader_int(t["view"])
		if !shader_identifier(name, true) || names[name] || slot < 8 || slot > 11 || shader_int(t["sampler"]) != slot { return shader_fail(v, "invalid texture name or slot") }; names[name] = true
		if slots[slot-8] { return shader_fail(v, "duplicate texture slot") }; slots[slot-8] = true
		stage, scope := shader_text(t["stage"]), shader_text(t["scope"])
		if !slice.contains([]string{"vertex", "fragment"}, stage) || !slice.contains([]string{"Scene", "Material", "Draw"}, scope) || post && (stage != "fragment" || scope == "Material") || !slice.contains([]string{"2d", "cube"}, shader_text(t["type"])) || shader_text(t["sample_type"]) != "float" || !slice.contains([]string{"linear", "srgb"}, shader_text(t["colour_space"])) { return shader_fail(v, "invalid texture type, scope, stage, or colour space") }
		if !shader_fields(v, t["sampler_policy"], {"min", "mag", "wrap"}) { return false }; policy := shader_object(t["sampler_policy"])
		if !slice.contains([]string{"nearest", "linear"}, shader_text(policy["min"])) || !slice.contains([]string{"nearest", "linear"}, shader_text(policy["mag"])) || !slice.contains([]string{"clamp", "repeat", "mirror"}, shader_text(policy["wrap"])) { return shader_fail(v, "invalid sampler policy") }
		if optional, exists := t["optional"]; exists { if _, ok := optional.(json.Boolean); !ok { return shader_fail(v, "invalid texture optional flag") } }
		default := t["default"]
		if _, null := default.(json.Null); null { return shader_fail(v, "texture default source is required") }
		d := shader_object(default)
		switch {
		case len(d) == 1 && "constant" in d:
			if !shader_bool(t["optional"]) || !shader_list(v, d["constant"], 4) || len(shader_array(d["constant"])) != 4 { return shader_fail(v, "invalid constant texture default") }
			for n in shader_array(d["constant"]) { if _, ok := shader_number(n); !ok { return shader_fail(v, "nonfinite constant texture default") } }
		case len(d) == 1 && "imported" in d:
			if scope != "Material" || shader_text(t["type"]) != "2d" || !slice.contains([]string{"base_colour", "metallic_roughness", "emissive", "normal", "occlusion"}, shader_text(d["imported"])) { return shader_fail(v, "invalid imported texture default") }
			expected_space := "srgb" if shader_text(d["imported"]) == "base_colour" || shader_text(d["imported"]) == "emissive" else "linear"
			if shader_text(t["colour_space"]) != expected_space { return shader_fail(v, "imported texture colour space mismatch") }
		case len(d) == 2 && "pack" in d && "asset" in d:
			if shader_text(d["pack"]) == "" || shader_text(d["asset"]) == "" { return shader_fail(v, "invalid Pack texture default") }
		case: return shader_fail(v, "invalid texture default source")
		}
	}
	return true
}

shader_program_validate :: proc(v: ^Shader_Validation, value: json.Value, backend: string, pkg: ^Shader_Package) -> bool {
	if !shader_fields(v, value, {"name", "vertex_func", "fragment_func"}, {"attrs", "uniform_blocks", "views", "samplers", "texture_sampler_pairs"}) { return false }
	p := shader_object(value); name := shader_text(p["name"])
	for stage in ([]string{"vertex_func", "fragment_func"}) {
		if !shader_fields(v, p[stage], {"offset", "size", "entry_point", "is_binary"}, {"d3d11_target"}) { return false }
		f := shader_object(p[stage]); offset, size := shader_int(f["offset"]), shader_int(f["size"])
		binary, boolean := f["is_binary"].(json.Boolean)
		if offset < 0 || size <= 0 || offset > len(pkg.payload) || size > len(pkg.payload) - offset || !boolean || binary || !shader_identifier(shader_text(f["entry_point"])) { return shader_fail(v, "invalid shader source range or entry point") }
		source := string(pkg.payload[offset:][:size])
		if !utf8.valid_string(source) || strings.contains(source, "\x00") { return shader_fail(v, "shader source requires UTF-8 without NUL") }
		if backend == "hlsl5" && shader_text(f["d3d11_target"]) != ("vs_5_0" if stage == "vertex_func" else "ps_5_0") { return shader_fail(v, "invalid D3D shader target") }
	}
	for key in ([]string{"attrs", "uniform_blocks", "views", "samplers", "texture_sampler_pairs"}) {
		if a, exists := p[key]; exists { if !shader_list(v, a, 16) { return false } }
	}
	attrs: [13]bool
	ceiling := 0 if pkg.post else 13 if strings.has_prefix(name, "instanced") else 7 if strings.has_prefix(name, "skinned") else 5
	for attr in shader_array(p["attrs"]) {
		if !shader_fields(v, attr, {"slot", "type", "base_type"}, {"glsl_name", "hlsl_sem_name", "hlsl_sem_index"}) { return false }
		a := shader_object(attr); slot := shader_int(a["slot"])
		if slot < 0 || slot >= ceiling || attrs[slot] { return shader_fail(v, "invalid or duplicate vertex attribute") }; attrs[slot] = true
		type := "vec4"
		if slot == 0 || slot == 2 || ceiling == 13 && slot >= 9 && slot <= 11 { type = "vec3" }
		if slot == 3 { type = "vec2" }; if ceiling == 7 && slot == 5 { type = "uvec4" }
		if shader_text(a["type"]) != type || shader_text(a["base_type"]) != ("UInt" if type == "uvec4" else "Float") { return shader_fail(v, "vertex attribute differs from engine layout") }
		for key in ([]string{"glsl_name", "hlsl_sem_name"}) { if x, has := a[key]; has && !shader_identifier(shader_text(x)) { return shader_fail(v, "invalid attribute identifier") } }
		if x, has := a["hlsl_sem_index"]; has && (shader_int(x) < 0 || shader_int(x) > 15) { return shader_fail(v, "invalid attribute semantic index") }
	}
	blocks: [6]bool
	for block in shader_array(p["uniform_blocks"]) {
		if !shader_fields(v, block, {"slot", "stage", "size", "struct_name", "inst_name"}, {"glsl_uniforms", "hlsl_register_b_n", "msl_buffer_n"}) { return false }
		b := shader_object(block); slot := shader_int(b["slot"])
		if slot < 0 || slot >= 6 || blocks[slot] { return shader_fail(v, "invalid uniform block slot") }; blocks[slot] = true
		if slot == 2 && !strings.has_suffix(name,"_colour") { return shader_fail(v,"lighting uniforms are unavailable in coverage passes") }
		size := SHADER_UNIFORM_SIZES[slot]
		if pkg.post { if slot != 1 && slot != 5 { return shader_fail(v, "invalid Post uniform block") }; if slot == 1 { size = 128 } }
		if shader_int(b["size"]) != size || shader_text(b["stage"]) != ("vertex" if slot == 0 || slot == 3 || slot == 4 else "fragment") || slot == 3 && ceiling != 7 { return shader_fail(v, "uniform block differs from engine contract") }
		for key in ([]string{"struct_name", "inst_name"}) { if !shader_identifier(shader_text(b[key])) { return shader_fail(v, "invalid uniform identifier") } }
		for key in ([]string{"hlsl_register_b_n", "msl_buffer_n"}) { if x, has := b[key]; has && shader_int(x) != slot { return shader_fail(v, "invalid physical uniform mapping") } }
		if backend == "glsl430" {
			if !shader_list(v, b["glsl_uniforms"], 1) || len(shader_array(b["glsl_uniforms"])) != 1 { return shader_fail(v, "unsupported GL uniform flattening") }
			u := shader_array(b["glsl_uniforms"])[0]
			if !shader_fields(v, u, {"type", "array_count", "offset", "glsl_name"}) { return false }; o := shader_object(u)
			if shader_text(o["type"]) != "vec4" || shader_int(o["array_count"]) != size / 16 || shader_int(o["offset"]) != 0 || !shader_identifier(shader_text(o["glsl_name"])) { return shader_fail(v, "invalid flattened GL uniform size") }
		}
	}
	interface := shader_object(shader_object(pkg.manifest)["interface"])
	d := shader_object(interface["post" if pkg.post else "surface"])
	textures, samplers: [12]json.Object
	storage: [3]bool
	physical_views: [2][128]bool
	for view in shader_array(p["views"]) {
		o, object := view.(json.Object)
		if !object || len(o) != 1 { return shader_fail(v, "invalid reflected view") }
		if resource, has := o["texture"]; has {
			if !shader_fields(v, resource, {"slot", "stage", "name", "multisampled", "type", "sample_type"}, {"hlsl_register_t_n", "msl_texture_n"}) { return false }
			t := shader_object(resource); slot := shader_int(t["slot"]); stage := shader_text(t["stage"])
			ms, boolean := t["multisampled"].(json.Boolean)
			if slot < 0 || slot >= 12 || textures[slot] != nil || !boolean || ms || !slice.contains([]string{"vertex", "fragment"}, stage) || !shader_identifier(shader_text(t["name"])) { return shader_fail(v, "invalid texture reflection") }
			textures[slot] = t
			if slot >= 8 {
				found := false
				for declaration in shader_array(d["textures"]) { td := shader_object(declaration); if shader_int(td["view"]) == slot && shader_text(td["stage"]) == stage && shader_text(td["type"]) == shader_text(t["type"]) && shader_text(t["sample_type"]) == "float" { found = true } }
				if !found { return shader_fail(v, "texture reflection differs from declarations") }
			} else {
				names := []string{"base_tex", "metallic_roughness_tex", "shadow_tex", "emissive_tex", "normal_tex", "occlusion_tex", "env_diffuse_tex", "env_specular_tex"}
				type, sample := "2d", "float"
				if slot == 2 { type, sample = "array", "depth" }; if slot == 6 || slot == 7 { type = "cube" }
				if pkg.post {
					names = []string{"scene_colour", "scene_depth", "selection_coverage", "selection_depth"}; type, sample = "2d", "float"
					if slot >= 4 { return shader_fail(v, "invalid reserved Post texture") }
					found := false; for input in shader_array(d["inputs"]) { if shader_text(input) == names[slot] { found = true } }; if !found { return shader_fail(v, "undeclared Post input") }
				}
				if stage != "fragment" || shader_text(t["name"]) != names[slot] || shader_text(t["type"]) != type || shader_text(t["sample_type"]) != sample { return shader_fail(v, "texture differs from reserved engine semantic") }
			}
			key := "msl_texture_n" if backend == "metal_macos" else "hlsl_register_t_n"
			if backend != "glsl430" { n := shader_int(t[key]); s := 0 if stage == "vertex" else 1; if n < 0 || n >= 128 || physical_views[s][n] { return shader_fail(v, "invalid or overlapping physical texture binding") }; physical_views[s][n] = true }
		} else if storage_resource, has_storage := o["storage_buffer"]; has_storage {
			if !shader_fields(v, storage_resource, {"slot", "stage", "size", "align", "struct_name", "inst_name", "inner_struct_name", "readonly"}, {"glsl_binding_n", "hlsl_register_t_n", "msl_buffer_n"}) { return false }
			b := shader_object(storage_resource); slot := shader_int(b["slot"])
			if slot < 12 || slot > 14 || storage[slot-12] || pkg.post || !strings.has_suffix(name,"_colour") || shader_text(b["stage"]) != "fragment" || !shader_bool(b["readonly"]) || shader_int(b["size"]) != (32 if slot == 12 else 16) || shader_int(b["align"]) != 16 { return shader_fail(v, "invalid clustered storage reflection") }; storage[slot-12] = true
			for key in ([]string{"struct_name", "inst_name", "inner_struct_name"}) { if !shader_identifier(shader_text(b[key])) { return shader_fail(v, "invalid storage identifier") } }
			key := "glsl_binding_n" if backend == "glsl430" else "msl_buffer_n" if backend == "metal_macos" else "hlsl_register_t_n"
			n := shader_int(b[key]); expected := slot - 12 if backend == "glsl430" else slot - 4 if backend == "metal_macos" else n
			if n < 0 || n >= 128 || n != expected { return shader_fail(v, "invalid compact or physical storage binding") }
			if backend == "hlsl5" { if physical_views[1][n] { return shader_fail(v, "overlapping D3D storage binding") }; physical_views[1][n] = true }
		} else { return shader_fail(v, "unknown reflected view kind") }
	}
	physical_samplers: [2][16]bool
	for sampler in shader_array(p["samplers"]) {
		if !shader_fields(v, sampler, {"slot", "stage", "name", "sampler_type"}, {"hlsl_register_s_n", "msl_sampler_n"}) { return false }
		s := shader_object(sampler); slot := shader_int(s["slot"])
		if slot < 0 || slot >= 12 || samplers[slot] != nil || textures[slot] == nil || shader_text(s["stage"]) != shader_text(textures[slot]["stage"]) || !shader_identifier(shader_text(s["name"])) || shader_text(s["sampler_type"]) != ("comparison" if !pkg.post && slot == 2 else "filtering") { return shader_fail(v, "invalid sampler reflection") }; samplers[slot] = s
		if backend != "glsl430" { key := "msl_sampler_n" if backend == "metal_macos" else "hlsl_register_s_n"; n := shader_int(s[key]); stage := 0 if shader_text(s["stage"]) == "vertex" else 1; if n < 0 || n >= 16 || physical_samplers[stage][n] { return shader_fail(v, "invalid physical sampler binding") }; physical_samplers[stage][n] = true }
	}
	pairs, paired: [12]bool
	for pair in shader_array(p["texture_sampler_pairs"]) {
		if !shader_fields(v, pair, {"slot", "stage", "name", "view_name", "sampler_name", "view_slot", "sampler_slot"}, {"glsl_name"}) { return false }
		pair_obj := shader_object(pair); slot, view, sampler := shader_int(pair_obj["slot"]), shader_int(pair_obj["view_slot"]), shader_int(pair_obj["sampler_slot"])
		if slot < 0 || slot >= 12 || pairs[slot] || view < 0 || view >= 12 || view != sampler || textures[view] == nil || samplers[sampler] == nil || paired[view] { return shader_fail(v, "invalid texture sampler pair") }; pairs[slot] = true; paired[view] = true
		if shader_text(pair_obj["stage"]) != shader_text(textures[view]["stage"]) || shader_text(pair_obj["view_name"]) != shader_text(textures[view]["name"]) || shader_text(pair_obj["sampler_name"]) != shader_text(samplers[sampler]["name"]) || !shader_identifier(shader_text(pair_obj["name"])) { return shader_fail(v, "texture sampler pair differs from reflection") }
		if backend == "glsl430" && !shader_identifier(shader_text(pair_obj["glsl_name"])) { return shader_fail(v, "invalid GL sampler pair name") }
	}
	for texture, i in textures { if texture != nil && (!paired[i] || samplers[i] == nil) { return shader_fail(v, "unpaired reflected texture") } }
 budget := shader_requirements(p)
 maximum := 512 if pkg.post else 1536 if strings.has_suffix(name,"_colour") else 1024
 if strings.has_prefix(name,"skinned") { maximum += 4096 }
 if budget.uniform_bytes > maximum { return shader_fail(v,"reflected uniforms exceed the per-pass arena budget") }
	return true
}

shader_program_desc :: proc(pkg: ^Shader_Package, p: json.Object) -> (d: sg.Shader_Desc) {
	cstring_value :: proc(v: json.Value) -> cstring { return strings.clone_to_cstring(shader_text(v), context.temp_allocator) }
	for stage in 0 ..< 2 {
		f := shader_object(p["vertex_func" if stage == 0 else "fragment_func"])
		dst := &d.vertex_func if stage == 0 else &d.fragment_func
		dst.source = strings.clone_to_cstring(string(pkg.payload[shader_int(f["offset"]):][:shader_int(f["size"])]), context.temp_allocator)
		dst.entry = cstring_value(f["entry_point"])
		if target, has := f["d3d11_target"]; has { dst.d3d11_target = cstring_value(target) }
	}
	for attr in shader_array(p["attrs"]) { a := shader_object(attr); dst := &d.attrs[shader_int(a["slot"])]; dst.base_type = .UINT if shader_text(a["base_type"]) == "UInt" else .FLOAT; dst.glsl_name = cstring_value(a["glsl_name"]); dst.hlsl_sem_name = cstring_value(a["hlsl_sem_name"]); if n, has := a["hlsl_sem_index"]; has { dst.hlsl_sem_index = u8(shader_int(n)) } }
	for block in shader_array(p["uniform_blocks"]) {
		b := shader_object(block); dst := &d.uniform_blocks[shader_int(b["slot"])]; dst.stage = shader_stage(b["stage"]); dst.size = u32(shader_int(b["size"])); dst.layout = .STD140
		if n, mapped := b["hlsl_register_b_n"]; mapped { dst.hlsl_register_b_n = u8(shader_int(n)) }; if n, mapped := b["msl_buffer_n"]; mapped { dst.msl_buffer_n = u8(shader_int(n)) }
		for uniform, i in shader_array(b["glsl_uniforms"]) { u := shader_object(uniform); dst.glsl_uniforms[i] = {type = .FLOAT4, array_count = u16(shader_int(u["array_count"])), glsl_name = cstring_value(u["glsl_name"])} }
	}
	for view in shader_array(p["views"]) {
		o := shader_object(view)
		if resource, has := o["texture"]; has { t := shader_object(resource); dst := &d.views[shader_int(t["slot"])].texture; dst.stage = shader_stage(t["stage"]); dst.image_type = .CUBE if shader_text(t["type"]) == "cube" else .ARRAY if shader_text(t["type"]) == "array" else ._2D; dst.sample_type = .DEPTH if shader_text(t["sample_type"]) == "depth" else .FLOAT; if n, mapped := t["msl_texture_n"]; mapped { dst.msl_texture_n = u8(shader_int(n)) }; if n, mapped := t["hlsl_register_t_n"]; mapped { dst.hlsl_register_t_n = u8(shader_int(n)) } }
		if resource, has := o["storage_buffer"]; has { b := shader_object(resource); dst := &d.views[shader_int(b["slot"])].storage_buffer; dst.stage = .FRAGMENT; dst.readonly = true; if n, mapped := b["msl_buffer_n"]; mapped { dst.msl_buffer_n = u8(shader_int(n)) }; if n, mapped := b["hlsl_register_t_n"]; mapped { dst.hlsl_register_t_n = u8(shader_int(n)) }; if n, mapped := b["glsl_binding_n"]; mapped { dst.glsl_binding_n = u8(shader_int(n)) } }
	}
	for sampler in shader_array(p["samplers"]) { s := shader_object(sampler); dst := &d.samplers[shader_int(s["slot"])]; dst.stage = shader_stage(s["stage"]); dst.sampler_type = .COMPARISON if shader_text(s["sampler_type"]) == "comparison" else .FILTERING; if n, mapped := s["msl_sampler_n"]; mapped { dst.msl_sampler_n = u8(shader_int(n)) }; if n, mapped := s["hlsl_register_s_n"]; mapped { dst.hlsl_register_s_n = u8(shader_int(n)) } }
	for pair in shader_array(p["texture_sampler_pairs"]) { pair_obj := shader_object(pair); dst := &d.texture_sampler_pairs[shader_int(pair_obj["slot"])]; dst.stage = shader_stage(pair_obj["stage"]); dst.view_slot = u8(shader_int(pair_obj["view_slot"])); dst.sampler_slot = u8(shader_int(pair_obj["sampler_slot"])); dst.glsl_name = cstring_value(pair_obj["glsl_name"]) }
	return
}

shader_canonical_string :: proc(raw: string) -> bool {
 value, err := json.parse_string(raw, spec = .JSON, allocator = context.temp_allocator)
 if err != nil { return false }
 b := strings.builder_make(context.temp_allocator)
 strings.write_byte(&b, '"')
 for r in shader_text(value) {
  switch r {
  case '"': strings.write_string(&b, `\"`)
  case '\\': strings.write_string(&b, `\\`)
  case '\b': strings.write_string(&b, `\b`)
  case '\f': strings.write_string(&b, `\f`)
  case '\n': strings.write_string(&b, `\n`)
  case '\r': strings.write_string(&b, `\r`)
  case '\t': strings.write_string(&b, `\t`)
  case:
   if r < 32 || r >= 127 {
    if r > 0xffff { n := u32(r)-0x10000; fmt.sbprintf(&b, `\u%04x\u%04x`, 0xd800+(n>>10), 0xdc00+(n&1023)) }
    else { fmt.sbprintf(&b, `\u%04x`,u32(r)) }
   } else { strings.write_rune(&b,r) }
  }
 }
 strings.write_byte(&b,'"')
 return strings.to_string(b) == raw
}

shader_canonical_number :: proc(raw: string) -> bool {
 if raw == "true" || raw == "false" || raw == "null" { return true }
 if raw == "" { return false }
 if !strings.contains(raw,".") && !strings.contains(raw,"e") && !strings.contains(raw,"E") {
  start := 1 if raw[0] == '-' else 0
  if start >= len(raw) || raw == "-0" || len(raw)-start > 1 && raw[start] == '0' { return false }
  for c in raw[start:] { if c < '0' || c > '9' { return false } }
  return true
 }
 n, ok := strconv.parse_f64(raw)
 if !ok || math.is_inf(n) || math.is_nan(n) { return false }
 scientific := n != 0 && (abs(n) < 0.0001 || abs(n) >= 1e16)
 buffer: [64]byte
 text := strconv.write_float(buffer[:],n,'e' if scientific else 'f',-1,64)
 text = strings.trim_prefix(text,"+")
 if !scientific && !strings.contains(text,".") { return raw == strings.concatenate({text,".0"},context.temp_allocator) }
 return raw == text
}

// JSON's integer parser uses i64. Large numeric defaults still require a finite F32 conversion.
shader_json_numbers :: proc(source: string) -> string {
 b := strings.builder_make(context.temp_allocator)
 quoted, escaped := false, false
 at := 0
 for at < len(source) {
  ch := source[at]
  if quoted {
   strings.write_byte(&b,ch); at += 1
   if escaped { escaped = false } else if ch == '\\' { escaped = true } else if ch == '"' { quoted = false }
  } else if ch == '"' { quoted = true; strings.write_byte(&b,ch); at += 1
  } else if ch == '-' || ch >= '0' && ch <= '9' {
   start := at
   for at < len(source) && (source[at] == '-' || source[at] == '+' || source[at] == '.' || source[at] == 'e' || source[at] == 'E' || source[at] >= '0' && source[at] <= '9') { at += 1 }
   raw := source[start:at]; strings.write_string(&b,raw)
   if len(raw) > 18 && !strings.contains(raw,".") && !strings.contains(raw,"e") && !strings.contains(raw,"E") { strings.write_string(&b,".0") }
  } else { strings.write_byte(&b,ch); at += 1 }
 }
 return strings.to_string(b)
}

shader_requirements :: proc(p: json.Object) -> (r: Shader_Requirements) {
 r.attributes = len(shader_array(p["attrs"])); r.samplers = len(shader_array(p["samplers"])); r.pairs = len(shader_array(p["texture_sampler_pairs"]))
 for block in shader_array(p["uniform_blocks"]) { b := shader_object(block); stage := 0 if shader_text(b["stage"]) == "vertex" else 1; size := shader_int(b["size"]); r.components[stage] += size / 4; r.uniform_bytes += (size+255)/256*256 }
 for view in shader_array(p["views"]) { o := shader_object(view); if t, has := o["texture"]; has { stage := 0 if shader_text(shader_object(t)["stage"]) == "vertex" else 1; r.textures[stage] += 1 }; if "storage_buffer" in o { r.storage += 1 } }
 return
}
