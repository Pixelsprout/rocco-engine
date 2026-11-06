#+test
package engine

import "core:encoding/endian"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_surface_instance_keeps_two_records_in_the_116_byte_vertex_contract :: proc(t: ^testing.T) {
	instances: [2]Surface_Instance
	for &instance, i in instances {
		for column in 0 ..< 4 {
			for row in 0 ..< 4 { instance.model[column][row] = f32(i*100 + column*4 + row) }
		}
		for column in 0 ..< 3 {
			for row in 0 ..< 3 { instance.normal[column][row] = f32(i*100 + 16 + column*3 + row) }
		}
		for &component, j in instance.tint { component = f32(i*100 + 25 + j) }
	}
	testing.expect_value(t, size_of(instances), 232)
	testing.expect_value(t, offset_of(Surface_Instance, model), 0)
	testing.expect_value(t, offset_of(Surface_Instance, normal), 64)
	testing.expect_value(t, offset_of(Surface_Instance, tint), 100)
	stream := transmute([2][29]f32)instances
	for record, i in stream {
		for component, j in record { testing.expect_value(t, component, f32(i*100 + j)) }
	}
}

shader_test_manifest :: proc() -> string {
	programs := strings.builder_make(context.temp_allocator)
	for name, i in SHADER_PROGRAM_NAMES[:3] {
		if i > 0 { strings.write_byte(&programs, ',') }
		fmt.sbprintf(&programs, `{{"fragment_func":{{"d3d11_target":"ps_5_0","entry_point":"main","is_binary":false,"offset":0,"size":1}},"name":"%v","vertex_func":{{"d3d11_target":"vs_5_0","entry_point":"main","is_binary":false,"offset":0,"size":1}}}}`, name)
	}
	backends := strings.builder_make(context.temp_allocator)
	for name, i in SHADER_BACKENDS { if i > 0 { strings.write_byte(&backends, ',') }; fmt.sbprintf(&backends, `{{"programs":[%v],"slang":"%v"}}`, strings.to_string(programs), name) }
	return fmt.tprintf(`{{"backend_transform":"gl_ssbo_compact_v1","compiler":{{"commit":"11d0cf678105d614d675e6d9bd2aaf3eeff12f8c","repository":"floooh/sokol-tools-bin"}},"interface":{{"contract":1,"post":{{"inputs":[],"locations":[],"parameters":[],"textures":[]}},"surface":{{"instancing":false,"max_displacement":0.25,"parameters":[],"skinning":false,"textures":[]}}}},"shaders":[%v]}}`, strings.to_string(backends))
}
shader_test_pack :: proc(metadata: string, payload := "x", allocator := context.temp_allocator) -> []byte {
	bytes := make([]byte, 96+len(metadata)+len(payload), allocator)
	copy(bytes, "RCSHADER"); endian.put_u16(bytes[8:], .Little, 1); endian.put_u16(bytes[10:], .Little, 1); endian.put_u32(bytes[12:], .Little, 96); endian.put_u32(bytes[16:], .Little, u32(len(metadata))); endian.put_u32(bytes[20:], .Little, u32(len(payload))); endian.put_u32(bytes[28:], .Little, 7)
	copy(bytes[96:], metadata); copy(bytes[96+len(metadata):], payload)
	c := Shader_Canonical{source=metadata, valid=true}; shader_canonical_value(&c)
	hash := shader_hash(transmute([]byte)strings.concatenate({`{"interface":`, c.interface, `,"layout":`, c.layout, `}`}, context.temp_allocator)); copy(bytes[32:64], hash[:]); hash = shader_hash(bytes[96:]); copy(bytes[64:96], hash[:]); return bytes
}

@(test)
test_shader_package_accepts_all_required_backends_and_variants :: proc(t: ^testing.T) {
	pkg, reason, ok := shader_package_parse(shader_test_pack(shader_test_manifest()), context.allocator)
	testing.expectf(t, ok, "%v", reason)
	if ok { defer json.destroy_value(pkg.manifest); testing.expect_value(t, pkg.max_displacement, f32(0.25)); testing.expect(t, !pkg.post) }
}

@(test)
test_shader_package_rejects_header_checksum_and_payload_corruption :: proc(t: ^testing.T) {
	valid := shader_test_pack(shader_test_manifest())
	for i in ([]int{0,8,10,12,16,20,24,28,32,64,len(valid)-1}) {
		bytes := make([]byte,len(valid),context.temp_allocator); copy(bytes,valid); bytes[i] ~= 255
		_,reason,ok := shader_package_parse(bytes,context.allocator)
		testing.expectf(t,!ok && reason != "","corrupt byte %v",i)
	}
	for n in ([]int{0,7,95,len(valid)-1}) { _,_,ok := shader_package_parse(valid[:n],context.allocator); testing.expect(t,!ok) }
}

@(test)
test_shader_package_rejects_rehashed_manifest_and_range_errors :: proc(t: ^testing.T) {
	base := shader_test_manifest()
	for c in ([][2]string{
		{`"max_displacement":0.25`,`"max_displacement":-1`},
		{`"contract":1`,`"contract":2`},
		{`"offset":0`,`"offset":9223372036854775807`},
		{`"size":1`,`"size":9223372036854775807`},
		{`"surface_selection"`,`"unknown_selection"`},
		{`"skinning":false`,`"skinning":true`},
		{`"parameters":[],"skinning"`,`"parameters":[{"default":[0],"name":"wind","offset":9223372036854775792,"scope":"Scene","stage":"vertex","type":"F32"}],"skinning"`},
		{`"max_displacement":0.25`,`"max_displacement":1e39`},
		{`"backend_transform":"gl_ssbo_compact_v1"`,`"backend_transform":"unknown"`},
		{`"compiler":{`,`"compiler":{"bad":0,`},
	}) {
		metadata, _ := strings.replace_all(base,c[0],c[1],context.temp_allocator)
		_,reason,ok := shader_package_parse(shader_test_pack(metadata),context.allocator)
		testing.expectf(t,!ok && reason != "","accepted %v",c)
	}
	for payload in ([]string{"\x00","\xff"}) { _,_,ok := shader_package_parse(shader_test_pack(base,payload),context.allocator); testing.expect(t,!ok) }
}

@(test)
test_shader_runtime_reads_production_compiler_packages :: proc(t: ^testing.T) {
	path := os.get_env("ROCCO_SHADER_FIXTURE",context.temp_allocator)
	if path == "" { return }
	bytes,err := os.read_entire_file(path,context.temp_allocator); testing.expect_value(t,err,nil)
	pkg,reason,ok := shader_package_parse(bytes,context.allocator)
	testing.expectf(t,ok,"production package: %v",reason)
	if ok { json.destroy_value(pkg.manifest) }
}

@(test)
test_shader_packs_share_assets_and_invalidate_unloaded_ids :: proc(t: ^testing.T) {
	files := make(map[string][]byte,context.temp_allocator)
	files["shaders/Test.shaderpack"] = shader_test_pack(shader_test_manifest())
	dir := temp_assets_dir(t,files); defer os.remove_all(dir)
	packs: Packs
	packs_init(&packs,dir,context.allocator); defer packs_destroy(&packs)
	a,a_ok := pack_load(&packs,"A",{"shader/Test"},context.temp_allocator)
	b,b_ok := pack_load(&packs,"B",{"shader/Test"},context.temp_allocator)
	testing.expect(t,a_ok && b_ok && a[0].id != 0)
	testing.expect_value(t,a[0].id,b[0].id)
	id:=a[0].id
	testing.expect_value(t,packs.shaders.refs[mesh_slot(id)],2)
	testing.expect(t,pack_unload(&packs,"A"))
	_,live:=shader_lookup(&packs.shaders,id); testing.expect(t,live)
	_,owned:=pack_asset_lookup(&packs,"A","shader/Test"); testing.expect(t,!owned)
	_,owned=pack_asset_lookup(&packs,"B","shader/Test"); testing.expect(t,owned)
	testing.expect(t,pack_unload(&packs,"B"))
	_,live=shader_lookup(&packs.shaders,id); testing.expect(t,!live)
	c,_:=pack_load(&packs,"C",{"shader/Test"},context.temp_allocator)
	testing.expect(t,c[0].id != id && c[0].id != 0)
	_,live=shader_lookup(&packs.shaders,id); testing.expect(t,!live)
}

@(test)
test_shader_asset_capacity_and_failed_loads_create_no_replacements :: proc(t: ^testing.T) {
	files:=make(map[string][]byte,context.temp_allocator)
	bytes:=shader_test_pack(shader_test_manifest())
	for i in 0 ..= SHADER_ASSET_LIMIT { files[fmt.tprintf("shaders/Test%v.shaderpack",i)]=bytes }
	files["shaders/Bad.shaderpack"]=bytes[:95]
	dir:=temp_assets_dir(t,files); defer os.remove_all(dir)
	packs:Packs; packs_init(&packs,dir,context.allocator); defer packs_destroy(&packs)
	bad,_:=pack_load(&packs,"bad",{"shader/Bad"},context.temp_allocator); testing.expect_value(t,bad[0].id,u32(0))
	for i in 0 ..< SHADER_ASSET_LIMIT {
		manifest,_:=pack_load(&packs,fmt.tprintf("p%v",i),{fmt.tprintf("shader/Test%v",i)},context.temp_allocator)
		testing.expectf(t,manifest[0].id != 0,"capacity rejected asset %v",i)
	}
	over,_:=pack_load(&packs,"over",{fmt.tprintf("shader/Test%v",SHADER_ASSET_LIMIT)},context.temp_allocator)
	testing.expect_value(t,over[0].id,u32(0))
	testing.expect(t,pack_unload(&packs,"p0"))
	again,_:=pack_load(&packs,"retry",{fmt.tprintf("shader/Test%v",SHADER_ASSET_LIMIT)},context.temp_allocator)
	testing.expect(t,again[0].id != 0)
}

@(test)
test_shader_sha256_matches_known_vectors :: proc(t: ^testing.T) {
	testing.expect_value(t,shader_hash(transmute([]byte)string("abc")),[32]byte{0xba,0x78,0x16,0xbf,0x8f,0x01,0xcf,0xea,0x41,0x41,0x40,0xde,0x5d,0xae,0x22,0x23,0xb0,0x03,0x61,0xa3,0x96,0x17,0x7a,0x9c,0xb4,0x10,0xff,0x61,0xf2,0x00,0x15,0xad})
}

@(test)
test_shader_constant_defaults_keep_linear_hdr_and_negative_components :: proc(t: ^testing.T) {
 value,err:=json.parse_string(`[2.5,-0.25,0.5,0.75]`,spec=.JSON,allocator=context.temp_allocator)
 testing.expect_value(t,err,nil)
 pixels:=shader_constant_texels(value)
 for face in 0 ..< 6 { testing.expect_value(t,pixels[face*4+0],f32(2.5));testing.expect_value(t,pixels[face*4+1],f32(-0.25));testing.expect_value(t,pixels[face*4+2],f32(0.5));testing.expect_value(t,pixels[face*4+3],f32(0.75)) }
}

@(test)
test_shader_reflection_rejects_overflowing_flattened_uniform_counts :: proc(t: ^testing.T) {
 block:=`"name":"surface_colour","uniform_blocks":[{"glsl_uniforms":[{"array_count":1152921504606846992,"glsl_name":"engine_vertex","offset":0,"type":"vec4"}],"inst_name":"engine_vertex","size":256,"slot":0,"stage":"vertex","struct_name":"engine_vertex"}],"vertex_func"`
 metadata,_:=strings.replace_all(shader_test_manifest(),`"name":"surface_colour","vertex_func"`,block,context.temp_allocator)
 _,reason,ok:=shader_package_parse(shader_test_pack(metadata),context.allocator)
 testing.expect(t,!ok);testing.expect_value(t,reason,"invalid flattened GL uniform size")
}

@(test)
test_shader_canonical_strings_and_numeric_spellings_match_the_compiler :: proc(t: ^testing.T) {
 for text in ([]string{"0","1","-1","0.25","1.0","-0.0","1e-05","1e+16","3.4028234663852886e+38"}) { testing.expectf(t,shader_canonical_number(text),"valid %v",text) }
 for text in ([]string{"-0","01","1e0","1E+16","1.00","0.00001","1e+016"}) { testing.expectf(t,!shader_canonical_number(text),"invalid %v",text) }
 for text in ([]string{`"hello"`,`"\u007f"`,`"\ud83d\ude00"`,`"\n"`}) { testing.expectf(t,shader_canonical_string(text),"valid %v",text) }
 for text in ([]string{`"\u0061"`,`"\/"`,`"\u00AF"`}) { testing.expectf(t,!shader_canonical_string(text),"invalid %v",text) }
}

@(test)
test_shader_post_interfaces_accept_declared_inputs_without_scene_colour :: proc(t: ^testing.T) {
 root_value,err:=json.parse_string(shader_test_manifest(),spec=.JSON,parse_integers=true,allocator=context.temp_allocator);testing.expect_value(t,err,nil)
 root:=shader_object(root_value);interface:=shader_object(root["interface"]);surface:=shader_object(interface["surface"]);post:=shader_object(interface["post"])
 delete_key(&surface,"skinning");delete_key(&surface,"instancing");surface["max_displacement"]=json.Integer(0)
 inputs:=make(json.Array,1,context.temp_allocator);inputs[0]=json.String("selection_coverage");post["inputs"]=inputs
 locations:=make(json.Array,1,context.temp_allocator);locations[0]=json.String("before_bloom");post["locations"]=locations
 for backend in shader_array(root["shaders"]) {
  b:=shader_object(backend);first:=shader_array(b["programs"])[0];program:=shader_object(first);program["name"]=json.String("post_hdr")
  programs:=make(json.Array,1,context.temp_allocator);programs[0]=first;b["programs"]=programs
 }
 metadata,encode_error:=json.unparse(root_value,{spec=.JSON,sort_maps_by_key=true},allocator=context.temp_allocator);testing.expect_value(t,encode_error,nil)
 pkg,reason,ok:=shader_package_parse(shader_test_pack(metadata),context.allocator);testing.expectf(t,ok,"%v",reason)
 if ok { testing.expect(t,pkg.post);json.destroy_value(pkg.manifest) }
}
