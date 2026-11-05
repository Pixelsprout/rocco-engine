#+test
package engine

import "core:os"
import "core:strings"
import "core:testing"

Surface_Fixture :: struct { frame: Frame_Fixture, packs: Packs, images: Image_Table, audio: Audio, mesh: u32 }
Surface_Observed :: struct { pass: Surface_Pass, first: int, time: f32, vertex, fragment: [64]f32, model: Mat4 }

surface_fixture_init :: proc(t: ^testing.T, f: ^Surface_Fixture) {
	frame_fixture_init(&f.frame)
	image_table_init(&f.images,SMALL_IMAGES,context.allocator,context.allocator)
	files:=make(map[string][]byte,context.temp_allocator)
	files["meshes/tree.glb"]=transmute([]byte)#load("../examples/surface/assets/meshes/tree.glb")
	manifest:=shader_test_manifest()
	parameters:=`"parameters":[{"default":[0.5],"name":"wind","offset":0,"scope":"Scene","stage":"vertex","type":"F32"},{"default":[1,1,1,1],"name":"tint","offset":0,"scope":"Material","stage":"fragment","type":"Colour"},{"default":[0],"name":"phase","offset":16,"scope":"Draw","stage":"vertex","type":"F32"}],"skinning"`
	manifest,_=strings.replace_all(manifest,`"parameters":[],"skinning"`,parameters,context.temp_allocator)
	files["shaders/Test.shaderpack"]=shader_test_pack(manifest)
	dir:=temp_assets_dir(t,files); defer os.remove_all(dir)
	packs_init(&f.packs,dir,context.allocator)
	packs_attach(&f.packs,&f.frame.meshes,&f.frame.skies,&f.images,&f.audio,context.allocator)
	lines,loaded:=pack_load(&f.packs,"trees",{"tree","shader/Test"},context.temp_allocator)
	testing.expect(t,loaded && lines[0].id != 0 && lines[1].id != 0)
	f.mesh=lines[0].id
	f.frame.fr.packs=&f.packs
	f.frame.fr.submits.submit_surface=surface_record
}
surface_fixture_destroy :: proc(f: ^Surface_Fixture) { packs_destroy(&f.packs); image_table_destroy(&f.images); frame_fixture_destroy(&f.frame) }
surface_record :: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs: Vs_Params, fs: Fs_Params, skin: ^Skin_Params) {
	r:=(^Recorder)(ctx)
	append(&r.surfaces,Surface_Observed{pass,part.first,part.surface.time,part.surface.vertex,part.surface.fragment,vs.model})
	if pass==.Colour { record_submit(ctx,mesh,part,pipeline,vs,fs,skin) }
	if pass==.Shadow { record_shadow(ctx,mesh,part,pipeline,{light_mvp=vs.mvp,shadow_material={fs.material.w,0,0,0}},skin) }
}
surface_test_values :: proc(scope:=Shader_Scope.Material) -> Shader_Values { return {shader={pack=roc_str_from_slice("trees"),asset=roc_str_from_slice("shader/Test")},scope=scope} }
surface_test_draw :: proc(f: ^Surface_Fixture) -> Draw { return {id=10,mesh=f.mesh,scale={1,1,1},rot=IDENTITY,scale_rot=IDENTITY,tint={1,1,1},casts_shadow=true} }
surface_test_slot :: proc(material: u32) -> Material_Slot { return {mesh={pack=roc_str_from_slice("trees"),asset=roc_str_from_slice("tree")},source_material=material} }

@(test)
test_surface_named_slots_retain_imported_materials_and_raw_colours :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	d:=surface_test_draw(&f)
	assignments:=[]Roc_VocabularyNode_Draw_Materials{{slot=surface_test_slot(1),values=surface_test_values()}}
	d.materials=roc_list_view(assignments)
	mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh)
	parts:=surface_resolve_parts(&f.packs,&d,mesh,nil,2.5)
	testing.expect_value(t,len(parts),2)
	testing.expect(t,parts[0].surface==nil && parts[1].surface!=nil)
	testing.expect_value(t,parts[0].material,mesh.parts[0].material)
	testing.expect_value(t,parts[1].material,mesh.parts[1].material)
	testing.expect_value(t,parts[1].base_colour,mesh.material_slots[1].base_color_factor)
	testing.expect_value(t,parts[1].surface.time,f32(2.5))
	testing.expect(t,mesh.vertex_colors[0] != mesh.data.vertices[0].color)
}

@(test)
test_surface_scalar_slot_override_inherits_the_whole_draw_shader :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	d:=surface_test_draw(&f); d.material.surface={tag=.Surface,payload={surface=surface_test_values()}}
	properties:=[]Roc_VocabularyNode_Draw_Material_Properties{{tag=.Roughness,payload={roughness=0.25}}}
	slots:=[]Roc_VocabularyNode_Draw_SlotMaterials{{slot=surface_test_slot(1),material={properties=roc_list_view(properties)}}}
	d.slot_materials=roc_list_view(slots)
	mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh)
	parts:=surface_resolve_parts(&f.packs,&d,mesh,nil,0)
	testing.expect_value(t,len(parts),2)
	testing.expect(t,parts[0].surface!=nil && parts[1].surface!=nil)
	testing.expect_value(t,parts[1].material.roughness,f32(0.25))
	testing.expect_value(t,parts[0].material.roughness,mesh.parts[0].material.roughness)
	testing.expect_value(t,parts[1].base_colour,mesh.material_slots[1].base_color_factor)
}

@(test)
test_surface_resolved_alpha_groups_share_time_and_exclude_noncasters :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	d:=surface_test_draw(&f); d.material.surface={tag=.Surface,payload={surface=surface_test_values()}}
	mask:=[]Roc_VocabularyNode_Draw_Material_Properties{{tag=.Alpha,payload={alpha={tag=.Mask,payload={mask=0.4}}}}}
	opaque:=[]Roc_VocabularyNode_Draw_Material_Properties{{tag=.Alpha,payload={alpha={tag=.Opaque}}}}
	d.material.properties=roc_list_view(mask)
	slots:=[]Roc_VocabularyNode_Draw_SlotMaterials{{slot=surface_test_slot(1),material={properties=roc_list_view(opaque)}}};d.slot_materials=roc_list_view(slots)
	f.frame.fr.render_time=3.5
	scene:=scene_lit({d},{light_sun({x=0,y=-1,z=0},{r=1,g=1,b=1})})
	frame_fixture_draw(&f.frame,scene,scene,0)
	testing.expect_value(t,len(f.frame.rec.shadows),2)
	testing.expect_value(t,f.frame.rec.shadows[0].first,36)
	testing.expect_value(t,f.frame.rec.shadows[1].first,0)
	testing.expect_value(t,len(f.frame.rec.submits),2)
	for observed in f.frame.rec.surfaces { testing.expect_value(t,observed.time,f32(3.5)); testing.expect_value(t,observed.model,f.frame.fr.placed[0].model) }
	mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh)
	testing.expect_value(t,placed_box(&f.frame.fr.placed[0]).min,mesh.box.min-f32(0.25))
	clear(&f.frame.rec.surfaces);d.casts_shadow=false
	scene=scene_lit({d},{light_sun({x=0,y=-1,z=0},{r=1,g=1,b=1})},default_casting=false);frame_fixture_draw(&f.frame,scene,scene,0)
	testing.expect_value(t,len(f.frame.rec.shadows),0)
	testing.expect_value(t,len(f.frame.rec.submits),2)
	testing.expect_value(t,len(f.frame.rec.surfaces),2)
}

@(test)
test_surface_whole_draw_keeps_different_factors_in_unnamed_merged_parts :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	allocator:=context.allocator
	data:=Mesh_Data{vertices=make([]Vertex,6,allocator),indices=make([]u16,6,allocator),parts=make([]Mesh_Data_Part,1,allocator),material_slots=make([]Mesh_Material_Slot,2,allocator),vertex_colors=make([][4]f32,6,allocator),vertex_materials=make([]int,6,allocator)}
	red,blue:=[4]f32{0.7,0.1,0.2,0.8},[4]f32{0.1,0.2,0.9,0.4}
	data.material_slots[0]={source_material=0,base_color_factor=red};data.material_slots[1]={source_material=1,base_color_factor=blue}
	data.parts[0]={count=6,material=MATERIAL_MATTE}
	for i in 0 ..< 6 { data.vertices[i]={pos={f32(i),0,0},color=red if i<3 else blue};data.indices[i]=u16(i);data.vertex_colors[i]={1,1,1,1};data.vertex_materials[i]=0 if i<3 else 1 }
	slot,added:=mesh_table_add(&f.frame.meshes,strings.clone("unnamed",allocator),data);testing.expect(t,added)
	d:=surface_test_draw(&f);d.mesh=mesh_id(&f.frame.meshes,slot);d.material.surface={tag=.Surface,payload={surface=surface_test_values()}}
	mesh,_:=mesh_lookup(&f.frame.meshes,d.mesh)
	testing.expect_value(t,len(mesh.parts),1)
	parts:=surface_resolve_parts(&f.packs,&d,mesh,nil,0)
	testing.expect_value(t,len(parts),2)
	testing.expect_value(t,parts[0].base_colour,red);testing.expect_value(t,parts[1].base_colour,blue)
	testing.expect_value(t,parts[0].first,0);testing.expect_value(t,parts[1].first,3)
	testing.expect_value(t,mesh.vertex_colors[4],[4]f32{1,1,1,1})
	f.frame.fr.draw_capacity=1
	scene:=scene_of({d});frame_fixture_draw(&f.frame,scene,scene,0)
	testing.expect_value(t,len(f.frame.rec.submits),1)
	testing.expect_value(t,f.frame.rec.submits[0].tint,red)
}

@(test)
test_surface_scope_values_validate_types_defaults_and_finiteness :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh);part:=mesh.surface_parts[1]
	values:=surface_test_values()
	scene:=[]Shader_Values{surface_test_values(.Scene)};draw:=[]Shader_Values{surface_test_values(.Draw)}
	wind:=[]Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name=roc_str_from_slice("wind"),value={tag=.Scalar,payload={scalar=0.2}}}}
	phase:=[]Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{{name=roc_str_from_slice("phase"),value={tag=.Scalar,payload={scalar=0.75}}}}
	scene[0].parameters=roc_list_view(wind);draw[0].parameters=roc_list_view(phase)
	resolved,reason:=surface_values_resolve(&f.packs,&part,&values,scene,draw,1.25,false)
	testing.expect_value(t,reason,"")
	testing.expect_value(t,resolved.vertex[0],f32(0.2));testing.expect_value(t,resolved.vertex[4],f32(0.75))
	testing.expect_value(t,resolved.fragment[0],f32(1));testing.expect_value(t,resolved.time,f32(1.25))
	wind[0].value={tag=.Boolean,payload={boolean=true}}
	_,reason=surface_values_resolve(&f.packs,&part,&values,scene,draw,0,false);testing.expect(t,reason!="")
	wind[0].value={tag=.Scalar,payload={scalar=transmute(f32)u32(0x7fc00000)}}
	_,reason=surface_values_resolve(&f.packs,&part,&values,scene,draw,0,false);testing.expect(t,reason!="")
	wind[0].value={tag=.Scalar,payload={scalar=0.2}};wind[0].name=roc_str_from_slice("unknown")
	_,reason=surface_values_resolve(&f.packs,&part,&values,scene,draw,0,false);testing.expect(t,reason!="")
	wind[0].name=roc_str_from_slice("wind");scene[0].scope=.Draw
	_,reason=surface_values_resolve(&f.packs,&part,&values,scene,draw,0,false);testing.expect(t,reason!="")
	scene[0].scope=.Scene
	duplicates:=[]Roc_VocabularyNode_Draw_Material_Surface_Surface_Parameters{wind[0],wind[0]};scene[0].parameters=roc_list_view(duplicates)
	_,reason=surface_values_resolve(&f.packs,&part,&values,scene,draw,0,false);testing.expect(t,reason!="")
}

@(test)
test_surface_failures_omit_only_the_affected_named_part_and_reject_conflicts :: proc(t: ^testing.T) {
	f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
	d:=surface_test_draw(&f);values:=surface_test_values();values.shader.asset=roc_str_from_slice("shader/Missing")
	assignments:=[]Roc_VocabularyNode_Draw_Materials{{slot=surface_test_slot(1),values=values}};d.materials=roc_list_view(assignments)
	mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh)
	parts:=surface_resolve_parts(&f.packs,&d,mesh,nil,0)
	testing.expect_value(t,len(parts),1);testing.expect_value(t,parts[0].source_material,0)
	assignments[0].values=surface_test_values()
	duplicate:=[]Roc_VocabularyNode_Draw_Materials{assignments[0],assignments[0]};d.materials=roc_list_view(duplicate)
	testing.expect_value(t,len(surface_resolve_parts(&f.packs,&d,mesh,nil,0)),0)
	d.materials=roc_list_view(assignments)
	conflicts:=[]Roc_VocabularyNode_Draw_SlotMaterials{{slot=surface_test_slot(1),material={surface={tag=.Surface,payload={surface=surface_test_values()}}}}};d.slot_materials=roc_list_view(conflicts)
	testing.expect_value(t,len(surface_resolve_parts(&f.packs,&d,mesh,nil,0)),0)
}

@(test)
test_surface_texture_references_follow_the_named_pack_across_unload_and_reload :: proc(t: ^testing.T) {
 f:Surface_Fixture; surface_fixture_init(t,&f); defer surface_fixture_destroy(&f)
 slot,_:=image_table_add(&f.images,strings.clone("image/detail",context.allocator),1,1,make([]byte,4,context.allocator))
 old:=image_id(&f.images,slot)
 held:=make([]Held_Asset,1,context.allocator);held[0]={.Image,old}
 f.packs.loaded[strings.clone("textures",context.allocator)]=held;f.packs.image_refs[slot]=1
 _,ok:=surface_texture_lookup(&f.packs,"textures","image/detail",false,true);testing.expect(t,ok)
 _,ok=surface_texture_lookup(&f.packs,"trees","image/detail",false,true);testing.expect(t,!ok)
 _,ok=surface_texture_lookup(&f.packs,"textures","image/detail",true,true);testing.expect(t,!ok)
 mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh);part:=mesh.surface_parts[1]
 textures:=[]Roc_VocabularyNode_Draw_Material_Textures{{semantic=.BaseColour,image={pack=roc_str_from_slice("textures"),asset=roc_str_from_slice("image/detail")}}}
 override:=Material_Override{textures=roc_list_view(textures)}
 testing.expect_value(t,surface_material_override(&f.packs,&part,&override),"")
 testing.expect(t,pack_unload(&f.packs,"textures"))
 _,ok=surface_texture_lookup(&f.packs,"textures","image/detail",false,true);testing.expect(t,!ok)
 testing.expect(t,surface_material_override(&f.packs,&part,&override)!="")
 slot,_=image_table_add(&f.images,strings.clone("image/detail",context.allocator),1,1,make([]byte,4,context.allocator))
 fresh:=image_id(&f.images,slot);testing.expect(t,fresh!=old)
 held=make([]Held_Asset,1,context.allocator);held[0]={.Image,fresh}
 f.packs.loaded[strings.clone("textures",context.allocator)]=held;f.packs.image_refs[slot]=1
 testing.expect_value(t,surface_material_override(&f.packs,&part,&override),"")
 _,ok=image_lookup(&f.images,old);testing.expect(t,!ok)
}

@(test)
test_surface_shader_retirement_reserves_slots_until_gpu_frames_complete :: proc(t: ^testing.T) {
 files:=make(map[string][]byte,context.temp_allocator);files["Test.shaderpack"]=shader_test_pack(shader_test_manifest())
 dir:=temp_assets_dir(t,files);defer os.remove_all(dir)
 table:Shader_Table;shader_table_init(&table,context.allocator);defer shader_table_destroy(&table)
 id,_,ok:=shader_load_file(&table,dir,"shader/Test");testing.expect(t,ok)
 slot:=mesh_slot(id);table.uploaded=true;table.assets[slot].ready=true
 shader_table_remove(&table,slot)
 _,ok=shader_lookup(&table,id);testing.expect(t,!ok)
 testing.expect(t,table.assets[slot].retiring)
 for _ in 0 ..< 2 { shader_table_frame(&table);testing.expect(t,table.assets[slot].retiring) }
 shader_table_frame(&table);testing.expect(t,!table.assets[slot].retiring)
}

@(test)
test_surface_alpha_changes_select_ordinary_mips_without_changing_imported_parts :: proc(t: ^testing.T) {
 f:Surface_Fixture;surface_fixture_init(t,&f);defer surface_fixture_destroy(&f)
 mesh,_:=mesh_lookup(&f.frame.meshes,f.mesh)
 ordinary:=Mesh_Texture{image={id=20}}
 mesh.surface_parts[1].texture={image={id=10},ordinary=&ordinary}
 d:=surface_test_draw(&f);d.material.surface={tag=.Surface,payload={surface=surface_test_values()}}
 parts:=surface_resolve_parts(&f.packs,&d,mesh,nil,0);testing.expect_value(t,parts[1].texture.image.id,u32(10))
 properties:=[]Roc_VocabularyNode_Draw_Material_Properties{{tag=.Alpha,payload={alpha={tag=.Mask,payload={mask=0.75}}}}}
 d.material.properties=roc_list_view(properties)
 parts=surface_resolve_parts(&f.packs,&d,mesh,nil,0);testing.expect_value(t,parts[1].texture.image.id,u32(20))
 testing.expect_value(t,mesh.surface_parts[1].texture.image.id,u32(10))
}
