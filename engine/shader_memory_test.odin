#+test
package engine

import "arenas"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_shader_load_scratch_does_not_accumulate_in_frame_memory :: proc(t: ^testing.T) {
 payload:=make([]byte,256*1024,context.temp_allocator);for &b in payload { b='x' }
 files:=make(map[string][]byte,context.temp_allocator)
 files["Test.shaderpack"]=shader_test_pack(shader_test_manifest(),string(payload))
 bad,_:=strings.replace_all(shader_test_manifest(),`"repository":"floooh/sokol-tools-bin"`,`"repository":"floooh/sokol-tools-bin","unexpected":0`,context.temp_allocator)
 files["Bad.shaderpack"]=shader_test_pack(bad)
 dir:=temp_assets_dir(t,files);defer os.remove_all(dir)
 frame:arenas.Arena;defer arenas.destroy(&frame)
 context.temp_allocator=arenas.allocator(&frame)
 assets:mem.Tracking_Allocator;mem.tracking_allocator_init(&assets,context.allocator);defer mem.tracking_allocator_destroy(&assets)
 allocator:=mem.tracking_allocator(&assets)
 table:Shader_Table;shader_table_init(&table,allocator)
 baseline:=assets.current_memory_allocated
 for _ in 0 ..< 4 {
  ids:[2]u32
  for &id in ids {
   before:=frame.total_used
   loaded,reason,ok:=shader_load_file(&table,dir,"shader/Test")
   testing.expectf(t,ok,"%v",reason);testing.expect_value(t,frame.total_used,before)
   id=loaded
   testing.expect_value(t,table.assets[mesh_slot(id)].package_data.max_displacement,f32(0.25))
  }
  for id in ids { shader_table_remove(&table,mesh_slot(id)) }
  testing.expect_value(t,assets.current_memory_allocated,baseline)
  before:=frame.total_used
  _,reason,ok:=shader_load_file(&table,dir,"shader/Bad")
  testing.expect(t,!ok);testing.expect(t,strings.contains(reason,"unexpected"))
  testing.expect(t,frame.total_used-before<512)
  testing.expect_value(t,assets.current_memory_allocated,baseline)
 }
 shader_table_destroy(&table)
 testing.expect_value(t,assets.current_memory_allocated,i64(0))
}

@(test)
test_shader_parse_preserves_caller_arena_results_and_long_names :: proc(t: ^testing.T) {
 name:=strings.repeat("wind",80,context.temp_allocator)
 parameter:=strings.concatenate({`"parameters":[{"default":[0.5],"name":"`,name,`","offset":0,"scope":"Scene","stage":"vertex","type":"F32"}],"skinning"`},context.temp_allocator)
 metadata,_:=strings.replace_all(shader_test_manifest(),`"parameters":[],"skinning"`,parameter,context.temp_allocator)
 bytes:=shader_test_pack(metadata)
 frame:arenas.Arena;defer arenas.destroy(&frame);context.temp_allocator=arenas.allocator(&frame)
 pkg,reason,ok:=shader_package_parse(bytes,context.temp_allocator)
 testing.expectf(t,ok,"%v",reason)
 if ok {
  interface:=shader_object(shader_object(pkg.manifest)["interface"])
  declaration:=shader_object(shader_array(shader_object(interface["surface"])["parameters"])[0])
  testing.expect_value(t,shader_text(declaration["name"]),name)
 }
 testing.expect(t,shader_identifier(strings.concatenate({"game_",name,"_tex_game_",name,"_smp"},context.temp_allocator)))
}
