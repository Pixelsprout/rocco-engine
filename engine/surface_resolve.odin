package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:math"
import "core:strings"

surface_log :: proc(p: ^Packs, draw: u64, reason: string) {
	key := fmt.tprintf("surface:%v:%v", draw, reason)
	if key not_in p.logged_assets { p.logged_assets[strings.clone(key, p.allocator)] = {}; fmt.eprintfln("Draw %v Surface: %v; affected parts are omitted", draw, reason) }
}
surface_asset :: proc(p: ^Packs, reference: ^Shader_Asset) -> (Held_Asset, bool) { return pack_asset_lookup(p, roc_str_string(&reference.pack), roc_str_string(&reference.asset)) }
surface_slot_valid :: proc(p: ^Packs, slot: ^Material_Slot, d: ^Draw, m: ^Mesh) -> bool {
	asset, ok := surface_asset(p, &slot.mesh)
	return ok && asset.kind == .Mesh && asset.id == d.mesh && int(slot.source_material) < len(m.material_slots) && m.material_slots[slot.source_material].name != ""
}
surface_has_overrides :: proc(d: ^Draw) -> bool { return d.material.surface.tag != .Imported || d.material.properties.length > 0 || d.material.textures.length > 0 || d.materials.length > 0 || d.slot_materials.length > 0 }

surface_resolve_parts :: proc(p: ^Packs, d: ^Draw, m: ^Mesh, scene_values: []Shader_Values, time: f32) -> []Mesh_Part {
	if !surface_has_overrides(d) { return m.parts }
	if p == nil { return nil }
	if p.shaders.uploaded && (sg.query_buffer_state(m.surface_vertices) != .VALID || sg.query_buffer_state(m.indices) != .VALID) { surface_log(p,d.id,"Surface mesh buffers failed to load"); return nil }
	shader_slots := make(map[u32]bool, context.temp_allocator)
	property_slots := make(map[u32]bool, context.temp_allocator)
	for &assignment in d.materials.elements[:d.materials.length] {
		if !surface_slot_valid(p, &assignment.slot, d, m) || shader_slots[assignment.slot.source_material] { surface_log(p, d.id, "invalid or duplicate named Surface slot"); return nil }
		shader_slots[assignment.slot.source_material] = true
	}
	for &assignment in d.slot_materials.elements[:d.slot_materials.length] {
		if !surface_slot_valid(p, &assignment.slot, d, m) || property_slots[assignment.slot.source_material] || assignment.material.surface.tag == .Surface && shader_slots[assignment.slot.source_material] { surface_log(p, d.id, "invalid, duplicate, or conflicting named material slot"); return nil }
		property_slots[assignment.slot.source_material] = true
	}
	result := make([dynamic]Mesh_Part, 0, len(m.surface_parts), context.temp_allocator)
	for source in m.surface_parts {
		part := source
		values: ^Shader_Values
		if d.material.surface.tag == .Surface { values = &d.material.surface.payload.surface }
		if reason := surface_material_override(p, &part, &d.material); reason != "" { surface_log(p, d.id, reason); continue }
		for &assignment in d.materials.elements[:d.materials.length] { if slot, named := part.slot.?; named && u32(slot) == assignment.slot.source_material { values = &assignment.values } }
		valid := true
		for &assignment in d.slot_materials.elements[:d.slot_materials.length] {
			if slot, named := part.slot.?; named && u32(slot) == assignment.slot.source_material {
				if assignment.material.surface.tag == .Surface { values = &assignment.material.surface.payload.surface }
				if reason := surface_material_override(p, &part, &assignment.material); reason != "" { surface_log(p, d.id, reason); valid = false }
			}
		}
		if !valid { continue }
  if part.material.alpha_mode != source.material.alpha_mode || part.material.alpha_cutoff != source.material.alpha_cutoff || part.base_colour.a != source.base_colour.a {
   if part.texture.ordinary != nil { part.texture = part.texture.ordinary^ }
  }
		if values != nil {
			resolved, reason := surface_values_resolve(p, &part, values, scene_values, d.shader_values.elements[:d.shader_values.length], time, mesh_skinned(m))
			if reason != "" { surface_log(p, d.id, reason); continue }
			part.surface = new_clone(resolved, context.temp_allocator)
		}
  if p.shaders.uploaded {
   ready := true
   for tex in ([5]Mesh_Texture{part.texture,part.metallic_roughness,part.emissive,part.normal,part.occlusion}) { if tex.image.id != 0 && !surface_texture_ready(p,tex) { ready = false } }
   if !ready { surface_log(p,d.id,"Surface imported textures failed to load"); continue }
  }
		append(&result, part)
	}
	return result[:]
}

surface_material_override :: proc(p: ^Packs, part: ^Mesh_Part, override: ^Material_Override) -> string {
	used: bit_set[Roc_VocabularyNode_Draw_Material_Properties_Tag]
	for property in override.properties.elements[:override.properties.length] {
		if property.tag in used { return "duplicate material property" }; used += {property.tag}
		m, v := &part.material, property.payload
		switch property.tag {
		case .BaseColour: part.base_colour = {v.base_colour.r, v.base_colour.g, v.base_colour.b, v.base_colour.a}
		case .Roughness: m.roughness = v.roughness
		case .Metallic: m.metallic = v.metallic
		case .Emission: m.emissive = {v.emission.x, v.emission.y, v.emission.z}
		case .Unlit: m.unlit = v.unlit
		case .NormalScale: m.normal_scale = v.normal_scale
		case .OcclusionStrength: m.occlusion_strength = v.occlusion_strength
		case .DoubleSided: m.double_sided = v.double_sided
		case .Alpha:
			m.alpha_cutoff = 0
			switch v.alpha.tag {
			case .Opaque:
				m.alpha_mode = .Opaque
			case .Blend:
				m.alpha_mode = .Blend
			case .Mask:
				m.alpha_mode = .Mask; m.alpha_cutoff = v.alpha.payload.mask
			}
		}
	}
	for n in part.base_colour { if math.is_nan(n) || math.is_inf(n) { return "nonfinite material base colour" } }
	for n in ([8]f32{part.material.roughness, part.material.metallic, part.material.normal_scale, part.material.occlusion_strength, part.material.alpha_cutoff, part.material.emissive.x, part.material.emissive.y, part.material.emissive.z}) { if math.is_nan(n) || math.is_inf(n) { return "nonfinite material property" } }
	if part.material.roughness < 0 || part.material.roughness > 1 || part.material.metallic < 0 || part.material.metallic > 1 || part.material.occlusion_strength < 0 || part.material.occlusion_strength > 1 || part.material.alpha_cutoff < 0 || part.material.alpha_cutoff > 1 { return "material property outside its range" }
	textures: bit_set[Roc_VocabularyNode_Draw_Material_Textures_Semantic]
	for &assignment in override.textures.elements[:override.textures.length] {
		if assignment.semantic in textures { return "duplicate material texture" }; textures += {assignment.semantic}
		asset, ok := surface_asset(p, &assignment.image)
		if !ok || asset.kind != .Image { return "material image is absent from its Pack" }
		image, live := image_lookup(p.images, asset.id); if !live { return "stale material image" }
		tex := Mesh_Texture{image = image.image, view = image.view, sampler = p.images.linear}
		if assignment.semantic == .MetallicRoughness || assignment.semantic == .Normal || assignment.semantic == .Occlusion { tex.image, tex.view = image.linear_image, image.linear_view }
		if !surface_texture_ready(p,tex) { return "material texture failed to load" }
		switch assignment.semantic {
		case .BaseColour:
			part.texture = tex
		case .MetallicRoughness:
			part.metallic_roughness = tex
		case .Emission:
			part.emissive = tex
		case .Normal:
			part.normal = tex
		case .Occlusion:
			part.occlusion = tex
		}
	}
	return ""
}

surface_same_asset :: proc(a, b: ^Shader_Asset) -> bool { return roc_str_string(&a.pack) == roc_str_string(&b.pack) && roc_str_string(&a.asset) == roc_str_string(&b.asset) }
surface_scope_name :: proc(scope: Shader_Scope) -> string {
	switch scope {
	case .Scene:
		return "Scene"
	case .Material:
		return "Material"
	case .Draw:
		return "Draw"
	}; return "" }

surface_value_encode :: proc(value: Shader_Value, kind: string) -> (out: [16]f32, count: int, ok: bool) {
	v := value.payload
	switch value.tag {
	case .Boolean: if kind != "Bool" { return }; out[0] = 1 if v.boolean else 0; count = 1
	case .LinearColour: if kind != "Colour" { return }; out[0],out[1],out[2],out[3] = v.linear_colour.r,v.linear_colour.g,v.linear_colour.b,v.linear_colour.a; count = 4
	case .Matrix4:
		if kind != "Mat4" { return }; m := v.matrix4
		out = {m.c0.x,m.c0.y,m.c0.z,m.c0.w,m.c1.x,m.c1.y,m.c1.z,m.c1.w,m.c2.x,m.c2.y,m.c2.z,m.c2.w,m.c3.x,m.c3.y,m.c3.z,m.c3.w}; count = 16
	case .Scalar: if kind != "F32" { return }; out[0] = v.scalar; count = 1
	case .Vector2: if kind != "Vec2" { return }; out[0], out[1] = v.vector2.x, v.vector2.y; count = 2
	case .Vector3: if kind != "Vec3" { return }; out[0],out[1],out[2] = v.vector3.x,v.vector3.y,v.vector3.z; count = 3
	case .Vector4: if kind != "Vec4" { return }; out[0],out[1],out[2],out[3] = v.vector4.x,v.vector4.y,v.vector4.z,v.vector4.w; count = 4
	}
	for n in out[:count] { if math.is_nan(n) || math.is_inf(n) { return {}, 0, false } }
	return out, count, true
}

surface_values_resolve :: proc(p: ^Packs, part: ^Mesh_Part, material: ^Shader_Values, scene, draw: []Shader_Values, time: f32, skinned: bool, post := false) -> (resolved: Surface_Material, reason: string) {
	asset, loaded := surface_asset(p, &material.shader)
	if !loaded || asset.kind != .Shader { return {}, "Surface Shader is absent from its Pack" }
	s, live := shader_lookup(&p.shaders, asset.id)
	if !live || s.package_data.post != post || s.failed || p.shaders.uploaded && !s.ready { return {}, "Surface Shader has no valid generation" }
	if skinned && !shader_bool(shader_interface(s)["skinning"]) { return {}, "Surface does not permit skinning" }
	resolved.shader, resolved.time = s, time
	d := shader_interface(s)
	for declaration in shader_array(d["parameters"]) {
		decl := shader_object(declaration); target := &resolved.vertex if shader_text(decl["stage"]) == "vertex" else &resolved.fragment
		at := shader_int(decl["offset"]) / 4
		for value, i in shader_array(decl["default"]) { n, _ := shader_number(value); if shader_text(decl["type"]) == "Bool" { n = 1 if shader_bool(value) else 0 }; target[at+i] = n }
	}
	parameters := make(map[string]bool, context.temp_allocator)
	textures := make(map[string]bool, context.temp_allocator)
	for scope in Shader_Scope {
		assignments := scene if scope == .Scene else draw if scope == .Draw else nil if post else []Shader_Values{material^}
		for &values in assignments {
			if !surface_same_asset(&values.shader, &material.shader) { continue }
			if values.scope != scope { return {}, "shader values have the wrong scope" }
			for &parameter in values.parameters.elements[:values.parameters.length] {
				name := roc_str_string(&parameter.name)
				if parameters[name] { return {}, "duplicate shader parameter assignment" }; parameters[name] = true
				found := false
				for declaration in shader_array(d["parameters"]) {
					decl := shader_object(declaration); if shader_text(decl["name"]) != name { continue }
					if shader_text(decl["scope"]) != surface_scope_name(scope) { return {}, "parameter assignment has the wrong scope" }
					encoded, count, valid := surface_value_encode(parameter.value, shader_text(decl["type"]))
					if !valid { return {}, "parameter assignment has the wrong type or nonfinite components" }
					target := &resolved.vertex if shader_text(decl["stage"]) == "vertex" else &resolved.fragment
					offset := shader_int(decl["offset"]) / 4; copy(target[offset:][:count], encoded[:count]); found = true
				}
				if !found { return {}, "unknown shader parameter name" }
			}
			for &texture in values.textures.elements[:values.textures.length] {
				name := roc_str_string(&texture.name)
				if textures[name] { return {}, "duplicate shader texture assignment" }; textures[name] = true
				found := false
				for declaration in shader_array(d["textures"]) {
					decl := shader_object(declaration); if shader_text(decl["name"]) != name { continue }
					if shader_text(decl["scope"]) != surface_scope_name(scope) { return {}, "texture assignment has the wrong scope" }
					cube := texture.texture.tag == .Cubemap
					if cube != (shader_text(decl["type"]) == "cube") { return {}, "texture assignment has the wrong dimension" }
					ref := &texture.texture.payload.cubemap if cube else &texture.texture.payload.image2d
					tex, valid := surface_texture_lookup(p, roc_str_string(&ref.pack), roc_str_string(&ref.asset), cube, shader_text(decl["colour_space"]) == "srgb")
					if !valid { return {}, "shader texture is absent, stale, or has the wrong dimension" }
					index := shader_int(decl["view"]) - 8; tex.sampler = s.samplers[index]; resolved.textures[index] = tex; found = true
				}
				if !found { return {}, "unknown shader texture name" }
			}
		}
	}
	for declaration in shader_array(d["textures"]) {
		decl := shader_object(declaration); index := shader_int(decl["view"]) - 8
		if textures[shader_text(decl["name"])] { continue }
		default := shader_object(decl["default"])
		if imported, has := default["imported"]; has {
			name := shader_text(imported)
			switch name {
			case "base_colour":
				resolved.imported[index] = 1
			case "metallic_roughness":
				resolved.imported[index] = 2
			case "emissive":
				resolved.imported[index] = 3
			case "normal":
				resolved.imported[index] = 4
			case "occlusion":
				resolved.imported[index] = 5
			}
		} else if "constant" in default { resolved.textures[index] = s.constants[index]
		} else if "pack" in default {
			tex, valid := surface_texture_lookup(p, shader_text(default["pack"]), shader_text(default["asset"]), shader_text(decl["type"]) == "cube", shader_text(decl["colour_space"]) == "srgb")
			if !valid { return {}, "default shader texture is absent, stale, or has the wrong dimension" }; resolved.textures[index] = tex
		} else { return {}, "required shader texture has no source" }
		resolved.textures[index].sampler = s.samplers[index]
	}
	if p.shaders.uploaded && !post {
		layout := Shader_Layout.Skinned if skinned else .Rigid
		for pass in Surface_Pass {
			cull := surface_cull(part.material, pass, .Blend if part.material.alpha_mode == .Blend else .Opaque)
			if _, ok := shader_pipeline(&p.shaders, s, {pass, layout, part.material.alpha_mode, cull}); !ok { return {}, "Surface pipeline creation or capacity failed" }
		}
		if part.material.alpha_mode == .Blend && part.material.double_sided { if _, ok := shader_pipeline(&p.shaders, s, {.Colour, layout, .Blend, .FRONT}); !ok { return {}, "Surface pipeline creation failed" } }
	}
	return resolved, ""
}

surface_texture_lookup :: proc(p: ^Packs, pack, name: string, cube, srgb: bool) -> (Mesh_Texture, bool) {
	asset, loaded := pack_asset_lookup(p, pack, name)
	if !loaded { return {}, false }
	if cube {
		if asset.kind != .Sky { return {}, false }; sky, live := sky_resolve(p.skies, asset.id); if !live { return {}, false }
		tex := sky.texture if srgb else sky.linear_texture
		return tex, surface_texture_ready(p, tex)
	}
	if asset.kind != .Image { return {}, false }; image, live := image_lookup(p.images, asset.id); if !live { return {}, false }
	tex := Mesh_Texture{image = image.image if srgb else image.linear_image, view = image.view if srgb else image.linear_view}
	return tex, surface_texture_ready(p, tex)
}

surface_texture_ready :: proc(p: ^Packs, tex: Mesh_Texture) -> bool { return !p.shaders.uploaded || sg.query_image_state(tex.image) == .VALID && sg.query_view_state(tex.view) == .VALID }
