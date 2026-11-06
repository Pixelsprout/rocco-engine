package engine

SURFACE_REUSE_LIMIT :: 128
SURFACE_REUSE_BUCKET_LIMIT :: 8
SURFACE_REUSE_HASH_OFFSET :: u64(14695981039346656037)
SURFACE_REUSE_HASH_PRIME :: u64(1099511628211)

Surface_Reuse_Entry :: struct {
	mesh_id: u32,
	mesh: ^Mesh,
	material: Material_Override,
	parts: []Mesh_Part,
}

Surface_Reuse_Bucket :: struct {
	entries: [SURFACE_REUSE_BUCKET_LIMIT]int,
	count: int,
}

// Borrowed Roc values never survive frame_render_draw.
Surface_Reuse :: struct {
	buckets: map[u64]Surface_Reuse_Bucket,
	entries: [dynamic]Surface_Reuse_Entry,
}

surface_reuse_init :: proc(cache: ^Surface_Reuse) {
	cache.buckets = make(map[u64]Surface_Reuse_Bucket, context.temp_allocator)
	cache.entries = make([dynamic]Surface_Reuse_Entry, 0, SURFACE_REUSE_LIMIT, context.temp_allocator)
}

surface_reuse_word :: #force_inline proc(hash: ^u64, value: u64) {
	hash^ = (hash^ ~ value) * SURFACE_REUSE_HASH_PRIME
}

surface_reuse_text :: proc(hash: ^u64, value: string) {
	surface_reuse_word(hash, u64(len(value)))
	for byte in transmute([]u8)value { surface_reuse_word(hash, u64(byte)) }
}

surface_reuse_float_bits :: #force_inline proc(value: f32) -> u32 {
	return transmute(u32)value
}

surface_reuse_property :: proc(property: Roc_VocabularyNode_Draw_Material_Properties) -> (key: [5]u32) {
	key[0] = u32(property.tag)
	v := property.payload
	switch property.tag {
	case .BaseColour:
		key[1], key[2], key[3], key[4] = surface_reuse_float_bits(v.base_colour.r), surface_reuse_float_bits(v.base_colour.g), surface_reuse_float_bits(v.base_colour.b), surface_reuse_float_bits(v.base_colour.a)
	case .Roughness: key[1] = surface_reuse_float_bits(v.roughness)
	case .Metallic: key[1] = surface_reuse_float_bits(v.metallic)
	case .Emission:
		key[1], key[2], key[3] = surface_reuse_float_bits(v.emission.x), surface_reuse_float_bits(v.emission.y), surface_reuse_float_bits(v.emission.z)
	case .Unlit: key[1] = u32(v.unlit)
	case .NormalScale: key[1] = surface_reuse_float_bits(v.normal_scale)
	case .OcclusionStrength: key[1] = surface_reuse_float_bits(v.occlusion_strength)
	case .DoubleSided: key[1] = u32(v.double_sided)
	case .Alpha:
		key[1] = u32(v.alpha.tag)
		if v.alpha.tag == .Mask { key[2] = surface_reuse_float_bits(v.alpha.payload.mask) }
	}
	return
}

surface_reuse_value :: proc(value: Shader_Value) -> ([16]f32, bool) {
	kind: string
	switch value.tag {
	case .Boolean: kind = "Bool"
	case .LinearColour: kind = "Colour"
	case .Matrix4: kind = "Mat4"
	case .Scalar: kind = "F32"
	case .Vector2: kind = "Vec2"
	case .Vector3: kind = "Vec3"
	case .Vector4: kind = "Vec4"
	}
	encoded, _, valid := surface_value_encode(value, kind)
	return encoded, valid
}

surface_reuse_hash :: proc(d: ^Draw) -> (hash: u64, eligible: bool) {
	if d.material.surface.tag != .Surface || d.material.textures.length != 0 || d.materials.length != 0 || d.slot_materials.length != 0 || d.shader_values.length != 0 { return }
	values := &d.material.surface.payload.surface
	if values.textures.length != 0 { return }
	hash = SURFACE_REUSE_HASH_OFFSET
	surface_reuse_word(&hash, u64(d.mesh))
	surface_reuse_text(&hash, roc_str_string(&values.shader.pack))
	surface_reuse_text(&hash, roc_str_string(&values.shader.asset))
	surface_reuse_word(&hash, u64(values.scope))
	surface_reuse_word(&hash, u64(values.parameters.length))
	for &parameter in values.parameters.elements[:values.parameters.length] {
		surface_reuse_text(&hash, roc_str_string(&parameter.name))
		surface_reuse_word(&hash, u64(parameter.value.tag))
		encoded, valid := surface_reuse_value(parameter.value)
		if !valid { return 0, false }
		for value in encoded { surface_reuse_word(&hash, u64(surface_reuse_float_bits(value))) }
	}
	surface_reuse_word(&hash, u64(d.material.properties.length))
	for property in d.material.properties.elements[:d.material.properties.length] {
		for value in surface_reuse_property(property) { surface_reuse_word(&hash, u64(value)) }
	}
	return hash, true
}

surface_reuse_equal :: proc(a, b: ^Material_Override) -> bool {
	av, bv := &a.surface.payload.surface, &b.surface.payload.surface
	if av.scope != bv.scope || !surface_same_asset(&av.shader, &bv.shader) || av.parameters.length != bv.parameters.length || a.properties.length != b.properties.length { return false }
	for &parameter, i in av.parameters.elements[:av.parameters.length] {
		other := &bv.parameters.elements[i]
		if roc_str_string(&parameter.name) != roc_str_string(&other.name) || parameter.value.tag != other.value.tag { return false }
		ae, a_valid := surface_reuse_value(parameter.value)
		be, b_valid := surface_reuse_value(other.value)
		if !a_valid || !b_valid || transmute([16]u32)ae != transmute([16]u32)be { return false }
	}
	for property, i in a.properties.elements[:a.properties.length] {
		if surface_reuse_property(property) != surface_reuse_property(b.properties.elements[i]) { return false }
	}
	return true
}

surface_reuse_find :: proc(cache: ^Surface_Reuse, hash: u64, d: ^Draw, mesh: ^Mesh) -> ([]Mesh_Part, bool) {
	bucket := cache.buckets[hash]
	for index in bucket.entries[:bucket.count] {
		entry := &cache.entries[index]
		if entry.mesh_id == d.mesh && entry.mesh == mesh && surface_reuse_equal(&entry.material, &d.material) { return entry.parts, true }
	}
	return nil, false
}

surface_reuse_parts :: proc(cache: ^Surface_Reuse, p: ^Packs, d: ^Draw, mesh: ^Mesh, scene_values: []Shader_Values, time: f32) -> []Mesh_Part {
	hash, eligible := surface_reuse_hash(d)
	if !eligible { return surface_resolve_parts(p, d, mesh, scene_values, time) }
	if cache.buckets == nil { surface_reuse_init(cache) }
	if parts, found := surface_reuse_find(cache, hash, d, mesh); found { return parts }
	complete := false
	parts := surface_resolve_parts(p, d, mesh, scene_values, time, &complete)
	bucket := cache.buckets[hash]
	if complete && len(cache.entries) < SURFACE_REUSE_LIMIT && bucket.count < SURFACE_REUSE_BUCKET_LIMIT {
		bucket.entries[bucket.count] = len(cache.entries)
		bucket.count += 1
		append(&cache.entries, Surface_Reuse_Entry{d.mesh, mesh, d.material, parts})
		cache.buckets[hash] = bucket
	}
	return parts
}
