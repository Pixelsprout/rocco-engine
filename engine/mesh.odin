package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

MESH_SLOT_BITS :: 16
// A mesh or sky id packs its slot in MESH_SLOT_BITS, so a table holds at most this many slots.
SLOT_LIMIT :: 1 << MESH_SLOT_BITS
SPHERE_RINGS :: 32
SPHERE_SEGMENTS :: 64
// A posed mesh can reach past its bind-pose box, so the box of a skinned
// mesh grows by this share of its largest side on every side.
SKINNED_BOX_PAD :: 0.25
// The texture pools reserve this many textures for each mesh slot. A file
// with more keeps the first ones, and its other parts draw white for them.
MESH_TEXTURE_LIMIT :: 16

#assert(size_of(Vertex) == 64)

// A file stem cannot contain "/", so a loaded file never takes a primitive's name.
PRIMITIVE_NAMES := [Primitive]string {
	.Fallback = "primitive/fallback",
	.Cube     = "primitive/cube",
	.Sphere   = "primitive/sphere",
	.Plane    = "primitive/plane",
}

GREY :: [4]f32{0.8, 0.8, 0.8, 1}
// A primitive, or a glTF primitive with no material, is not metal.
MATERIAL_MATTE :: Material {
	roughness = 1,
}
MAGENTA :: [4]f32{1, 0, 1, 1}

// A 1 x 1 quad in x-z, facing +y. One-sided: back-face culling hides it from below.
@(rodata)
PLANE_VERTICES := [4]Vertex {
	{pos = {-0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}, uv = {0, 0}, tangent = {1, 0, 0, 1}},
	{pos = {-0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}, uv = {0, 1}, tangent = {1, 0, 0, 1}},
	{pos = {0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}, uv = {1, 1}, tangent = {1, 0, 0, 1}},
	{pos = {0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}, uv = {1, 0}, tangent = {1, 0, 0, 1}},
}

@(rodata)
PLANE_INDICES := [6]u16{0, 1, 2, 0, 2, 3}

// Positions and normals of a unit cube. cube_build sets the colour and uvs.
@(rodata)
CUBE_VERTICES := [24]Vertex{
	// -z face
	{pos = {-0.5, -0.5, -0.5}, normal = {0, 0, -1}},
	{pos = {-0.5, 0.5, -0.5}, normal = {0, 0, -1}},
	{pos = {0.5, -0.5, -0.5}, normal = {0, 0, -1}},
	{pos = {0.5, 0.5, -0.5}, normal = {0, 0, -1}},

	// +z face
	{pos = {-0.5, -0.5, 0.5}, normal = {0, 0, 1}},
	{pos = {0.5, -0.5, 0.5}, normal = {0, 0, 1}},
	{pos = {-0.5, 0.5, 0.5}, normal = {0, 0, 1}},
	{pos = {0.5, 0.5, 0.5}, normal = {0, 0, 1}},

	// -y face
	{pos = {-0.5, -0.5, -0.5}, normal = {0, -1, 0}},
	{pos = {0.5, -0.5, -0.5}, normal = {0, -1, 0}},
	{pos = {0.5, -0.5, 0.5}, normal = {0, -1, 0}},
	{pos = {-0.5, -0.5, 0.5}, normal = {0, -1, 0}},

	// +y face
	{pos = {-0.5, 0.5, -0.5}, normal = {0, 1, 0}},
	{pos = {-0.5, 0.5, 0.5}, normal = {0, 1, 0}},
	{pos = {0.5, 0.5, 0.5}, normal = {0, 1, 0}},
	{pos = {0.5, 0.5, -0.5}, normal = {0, 1, 0}},

	// +x face
	{pos = {0.5, -0.5, -0.5}, normal = {1, 0, 0}},
	{pos = {0.5, 0.5, -0.5}, normal = {1, 0, 0}},
	{pos = {0.5, 0.5, 0.5}, normal = {1, 0, 0}},
	{pos = {0.5, -0.5, 0.5}, normal = {1, 0, 0}},

	// -x face
	{pos = {-0.5, -0.5, -0.5}, normal = {-1, 0, 0}},
	{pos = {-0.5, -0.5, 0.5}, normal = {-1, 0, 0}},
	{pos = {-0.5, 0.5, 0.5}, normal = {-1, 0, 0}},
	{pos = {-0.5, 0.5, -0.5}, normal = {-1, 0, 0}},
}

@(rodata)
CUBE_INDICES := [36]u16{
	0, 1, 2, 2, 1, 3, // -z
	4, 5, 6, 5, 7, 6, // +z
	8, 9, 10, 8, 10, 11, // -y
	12, 13, 14, 12, 14, 15, // +y
	16, 17, 18, 16, 18, 19, // +x
	20, 21, 22, 20, 22, 23, // -x
}

// The primitives are the first slots of the mesh table and never go on the free list, so each value is its mesh id.
Primitive :: enum u32 {
	Fallback,
	Cube,
	Sphere,
	Plane,
}

// glTF puts uv 0, 0 at the top left of the image. tangent points along
// increasing u. Its w is 1 when cross(normal, tangent) points up the image,
// towards decreasing v, and -1 where the uvs are mirrored.
Vertex :: struct {
	pos:     [3]f32,
	color:   [4]f32,
	normal:  [3]f32,
	uv:      [2]f32,
	tangent: [4]f32,
}

// glTF's alphaMode. A mesh's parts go in this order in its index buffer, so
// the Opaque and Mask parts are one range from index 0.
Alpha_Mode :: enum u8 {
	Opaque,
	Mask,
	Blend,
}

// unlit draws the base colour plus the emissive, with no lights and no tone
// map. emissive is linear and can exceed 1. normal_scale and
// occlusion_strength are 0 for a part without that map, so the flat normal
// image gives the vertex normal exactly. alpha_cutoff is 0 outside Mask, and
// double_sided is false for Opaque.
Material :: struct {
	roughness:          f32,
	metallic:           f32,
	unlit:              bool,
	emissive:           [3]f32,
	normal_scale:       f32,
	occlusion_strength: f32,
	alpha_mode:         Alpha_Mode,
	alpha_cutoff:       f32,
	double_sided:       bool,
}

// A zero id means the part has no texture and binds the white image, or the
// flat normal image for a normal map.
Mesh_Texture :: struct {
	image:   sg.Image,
	view:    sg.View,
	sampler: sg.Sampler,
}

// A range of the mesh's index buffer that draws with its own material and
// textures. Parts can share a texture, which Mesh.textures owns.
Mesh_Part :: struct {
	slot:               Maybe(int),
	first:              int,
	count:              int,
	material:           Material,
	texture:            Mesh_Texture,
	metallic_roughness: Mesh_Texture,
	emissive:           Mesh_Texture,
	normal:             Mesh_Texture,
	occlusion:          Mesh_Texture,
}

// The textures a part binds, with each missing one filled in.
Mesh_Part_Textures :: struct {
	base, metallic_roughness, emissive, normal, occlusion: Mesh_Texture,
}

// An axis-aligned box in the mesh's own space, around every vertex.
Box :: struct {
	min, max: [3]f32,
}

Mesh :: struct {
	name:             string,
	data:             Mesh_Data, // Loaded files only, until the upload. Primitives build theirs at upload.
	live:             bool,
	vertices:         sg.Buffer,
	indices:          sg.Buffer,
	index_count:      int,
	parts:            []Mesh_Part,
	material_slots:   []Mesh_Material_Slot,
	vertex_colors:    [][4]f32,
	vertex_materials: []int,
	textures:         []Mesh_Texture,
	box:              Box,
	skin:             Skin,
	first_clip:       u32,
	generation:       u16,
}

// After mesh_table_upload, a new mesh uploads when it is added. The table
// owns each mesh's parts and each loaded mesh's name and data. The slots
// never grow.
Mesh_Table :: struct {
	meshes:       []Mesh,
	count:        int,
	free:         []int,
	free_count:   int,
	logged:       map[u32]struct {},
	// The Clip ids that skin_matrices found on another mesh.
	clips_logged: map[u32]struct {},
	// Clip ids are never reused, so a stale Clip id names no Clip.
	next_clip:    u32,
	uploaded:     bool,
	allocator:    mem.Allocator,
	perm:         mem.Allocator,
}

// vertex_colors retains raw COLOR_0 for Surface inputs after upload; Vertex.color includes the base factor.
// A skinned mesh has one Influence per vertex. Its skin moves to the Mesh
// at mesh_table_add, because the upload deletes the rest. Data with no parts
// draws as one matte part.
Mesh_Data :: struct {
	vertices:         []Vertex,
	influences:       []Influence,
	indices:          []u16,
	textures:         []Texture,
	parts:            []Mesh_Data_Part,
	material_slots:   []Mesh_Material_Slot,
	vertex_colors:    [][4]f32,
	vertex_materials: []int,
	skin:             Skin,
}

// Each texture is an index into Mesh_Data.textures. nil binds white, or the
// flat normal image for normal.
Mesh_Data_Part :: struct {
	slot:               Maybe(int),
	first:              int,
	count:              int,
	material:           Material,
	texture:            Maybe(int),
	metallic_roughness: Maybe(int),
	emissive:           Maybe(int),
	normal:             Maybe(int),
	occlusion:          Maybe(int),
}

// Source indices survive part sorting. Empty names have no named override.
Mesh_Material_Slot :: struct {
	name:              string,
	source_material:   int,
	base_color_factor: [4]f32,
}

Mesh_Material_Slot_Error :: enum {
	None,
	Unnamed,
	Unknown_Name,
	Duplicate_Name,
}

// Names every primitive. The GPU buffers come later, from mesh_table_upload.
// The slots come from perm; the names, data, parts and log from allocator,
// which must free.
mesh_table_init :: proc(t: ^Mesh_Table, capacity: int, perm, allocator: mem.Allocator) {
	fmt.assertf(capacity >= len(Primitive) && capacity <= SLOT_LIMIT, "a mesh table of %v slots cannot hold the primitives or give each slot an id", capacity)
	t.allocator = allocator
	t.perm = perm
	t.meshes = make([]Mesh, capacity, perm)
	t.free = make([]int, capacity, perm)
	t.logged = make(map[u32]struct {}, allocator)
	t.clips_logged = make(map[u32]struct {}, allocator)
	t.next_clip = 1
	for p in Primitive {
		data := primitive_build(p, context.temp_allocator)
		t.meshes[p] = {
			name        = PRIMITIVE_NAMES[p],
			live        = true,
			index_count = len(data.indices),
			parts       = mesh_one_part(len(data.indices), MATERIAL_MATTE, allocator),
			box         = mesh_box(data.vertices),
		}
	}
	t.count = len(Primitive)
}

// sg.shutdown destroys the GPU buffers and textures.
mesh_table_destroy :: proc(t: ^Mesh_Table) {
	for &m in t.meshes[:len(Primitive)] {
		delete(m.parts, t.allocator)
	}
	for &m in t.meshes[len(Primitive):t.count] {
		if m.live {
			mesh_loaded_delete(t, &m)
		}
	}
	delete(t.logged)
	delete(t.clips_logged)
	delete(t.meshes, t.perm)
	delete(t.free, t.perm)
}

mesh_id :: proc(t: ^Mesh_Table, slot: int) -> u32 {
	return u32(t.meshes[slot].generation) << MESH_SLOT_BITS | u32(slot)
}

mesh_slot :: proc(id: u32) -> int {
	return int(id & (1 << MESH_SLOT_BITS - 1))
}

mesh_table_full :: proc(t: ^Mesh_Table) -> bool {
	return t.free_count == 0 && t.count == len(t.meshes)
}

mesh_table_full_reason :: proc(t: ^Mesh_Table) -> string {
	return fmt.tprintf("the mesh table is full at %v meshes", len(t.meshes))
}

mesh_table_find :: proc(t: ^Mesh_Table, name: string) -> (id: u32, found: bool) {
	for m, slot in t.meshes[:t.count] {
		if m.live && m.name == name {
			return mesh_id(t, slot), true
		}
	}
	return 0, false
}

// Keeps the slot's generation, so a mesh in a reused slot gets a new id.
// name and data must come from t.allocator.
mesh_table_add :: proc(t: ^Mesh_Table, name: string, data: Mesh_Data) -> (slot: int, ok: bool) {
	if mesh_table_full(t) {
		return 0, false
	}
	if t.free_count > 0 {
		t.free_count -= 1
		slot = t.free[t.free_count]
	} else {
		slot = t.count
		t.count += 1
	}
	box := mesh_box(data.vertices)
	if len(data.influences) > 0 {
		box = box_pad(box, SKINNED_BOX_PAD)
	}
	t.meshes[slot] = {
		name        = name,
		data        = data,
		live        = true,
		index_count = len(data.indices),
		parts       = mesh_parts(data, t.allocator),
		material_slots = data.material_slots,
		vertex_colors = data.vertex_colors,
		vertex_materials = data.vertex_materials,
		box         = box,
		skin        = data.skin,
		first_clip  = t.next_clip,
		generation  = t.meshes[slot].generation,
	}
	t.meshes[slot].data.skin = {}
	t.meshes[slot].data.material_slots = nil
	t.meshes[slot].data.vertex_colors = nil
	t.meshes[slot].data.vertex_materials = nil
	t.next_clip += u32(len(data.skin.clips))
	if t.uploaded {
		mesh_upload_loaded(t, &t.meshes[slot])
	}
	return slot, true
}

// Empties the slot and adds 1 to its generation, so an id kept from it
// resolves to the fallback.
mesh_table_remove :: proc(t: ^Mesh_Table, slot: int) {
	fmt.assertf(slot >= len(Primitive) && slot < t.count && t.meshes[slot].live, "mesh slot %v holds no loaded mesh", slot)
	m := &t.meshes[slot]
	if m.vertices.id != 0 {
		sg.destroy_buffer(m.vertices)
		sg.destroy_buffer(m.indices)
	}
	for tex in m.textures {
		mesh_texture_destroy(tex)
	}
	mesh_loaded_delete(t, m)
	m^ = {generation = m.generation + 1}
	t.free[t.free_count] = slot
	t.free_count += 1
}

// Needs sokol set up. The primitive vertex data is scratch and dies with the frame.
mesh_table_upload :: proc(t: ^Mesh_Table) {
	for p in Primitive {
		mesh_upload(&t.meshes[p], primitive_build(p, context.temp_allocator))
	}
	for &m in t.meshes[len(Primitive):t.count] {
		if m.live {
			mesh_upload_loaded(t, &m)
		}
	}
	t.uploaded = true
}

// The vertex data is scratch once the GPU has it.
@(private = "file")
mesh_upload_loaded :: proc(t: ^Mesh_Table, m: ^Mesh) {
	mesh_upload(m, m.data)
	m.textures = make([]Mesh_Texture, len(m.data.textures), t.allocator)
	for tex, i in m.data.textures {
		m.textures[i] = texture_upload(tex)
	}
	for data_part, i in m.data.parts {
		part := &m.parts[i]
		part.texture = mesh_texture_at(m.textures, data_part.texture)
		part.metallic_roughness = mesh_texture_at(m.textures, data_part.metallic_roughness)
		part.emissive = mesh_texture_at(m.textures, data_part.emissive)
		part.normal = mesh_texture_at(m.textures, data_part.normal)
		part.occlusion = mesh_texture_at(m.textures, data_part.occlusion)
	}
	mesh_data_delete(t, m.data)
	m.data = {}
}

@(private = "file")
mesh_texture_at :: proc(textures: []Mesh_Texture, index: Maybe(int)) -> Mesh_Texture {
	if i, ok := index.?; ok {
		return textures[i]
	}
	return {}
}

@(private = "file")
mesh_data_delete :: proc(t: ^Mesh_Table, data: Mesh_Data) {
	delete(data.vertices, t.allocator)
	delete(data.influences, t.allocator)
	delete(data.indices, t.allocator)
	for tex in data.textures {
		texture_delete(tex, t.allocator)
	}
	delete(data.textures, t.allocator)
	delete(data.parts, t.allocator)
	mesh_material_slots_delete(data.material_slots, t.allocator)
	delete(data.vertex_colors, t.allocator)
	delete(data.vertex_materials, t.allocator)
}

@(private = "file")
mesh_loaded_delete :: proc(t: ^Mesh_Table, m: ^Mesh) {
	delete(m.name, t.allocator)
	mesh_material_slots_delete(m.material_slots, t.allocator)
	delete(m.vertex_colors, t.allocator)
	delete(m.vertex_materials, t.allocator)
	mesh_data_delete(t, m.data)
	delete(m.parts, t.allocator)
	delete(m.textures, t.allocator)
	skin_delete(m.skin, t.allocator)
}

// The textures upload later, so each part starts with none.
@(private = "file")
mesh_parts :: proc(data: Mesh_Data, allocator: mem.Allocator) -> []Mesh_Part {
	if len(data.parts) == 0 {
		return mesh_one_part(len(data.indices), MATERIAL_MATTE, allocator)
	}
	parts := make([]Mesh_Part, len(data.parts), allocator)
	for p, i in data.parts {
		parts[i] = {slot = p.slot, first = p.first, count = p.count, material = p.material}
	}
	return parts
}

@(private = "file")
mesh_one_part :: proc(index_count: int, material: Material, allocator: mem.Allocator) -> []Mesh_Part {
	parts := make([]Mesh_Part, 1, allocator)
	parts[0] = {count = index_count, material = material}
	return parts
}

@(private = "file")
mesh_texture_destroy :: proc(tex: Mesh_Texture) {
	if tex.image.id != 0 {
		sg.destroy_view(tex.view)
		sg.destroy_image(tex.image)
		sg.destroy_sampler(tex.sampler)
	}
}

// A skinned mesh uploads Skinned_Vertex, for the skinned pipelines. sokol
// copies the data, so the skinned vertices are scratch.
mesh_upload :: proc(m: ^Mesh, data: Mesh_Data) {
	vertices := sg.Range{raw_data(data.vertices), uint(len(data.vertices) * size_of(Vertex))}
	if len(data.influences) > 0 {
		skinned := skinned_vertices(data.vertices, data.influences, context.temp_allocator)
		vertices = {raw_data(skinned), uint(len(skinned) * size_of(Skinned_Vertex))}
	}
	m.vertices = sg.make_buffer({label = "mesh-vertices", data = vertices})
	m.indices = sg.make_buffer(
		{
			label = "mesh-indices",
			data = {ptr = raw_data(data.indices), size = uint(len(data.indices) * size_of(u16))},
			usage = {index_buffer = true},
		},
	)
}

// White leaves the base colour as it is, the material factors at their
// values and the ambient without occlusion.
mesh_part_textures :: proc(part: ^Mesh_Part, white, flat_normal: Mesh_Texture) -> Mesh_Part_Textures {
	pick :: proc(tex, missing: Mesh_Texture) -> Mesh_Texture {
		return tex if tex.image.id != 0 else missing
	}
	return {
		base = pick(part.texture, white),
		metallic_roughness = pick(part.metallic_roughness, white),
		emissive = pick(part.emissive, white),
		normal = pick(part.normal, flat_normal),
		occlusion = pick(part.occlusion, white),
	}
}

// A mesh with no lit part needs no lights.
mesh_unlit :: proc(m: ^Mesh) -> bool {
	for part in m.parts {
		if !part.material.unlit {
			return false
		}
	}
	return true
}

parts_opaque_count :: proc(parts: []Mesh_Part) -> (count: int) {
	for part in parts {
		if part.material.alpha_mode != .Opaque { break }
		count += part.count
	}
	return
}

parts_shadow_count :: proc(parts: []Mesh_Part) -> (count: int) {
	for part in parts {
		if part.material.alpha_mode == .Blend { break }
		count += part.count
	}
	return
}

// Id 0, an id past the table and a stale id draw the fallback. Each such id is logged once per run.
mesh_resolve :: proc(t: ^Mesh_Table, id: u32, draw_id: u64) -> (mesh: ^Mesh, fallback: bool) {
	if found, ok := mesh_lookup(t, id); ok {
		return found, false
	}
	slot := mesh_slot(id)
	generation := id >> MESH_SLOT_BITS
	stale := slot >= len(Primitive) && slot < len(t.meshes) && generation != u32(t.meshes[slot].generation)
	if id not_in t.logged {
		t.logged[id] = {}
		if id == 0 {
			fmt.eprintfln("mesh id 0 is the fallback; drawing the fallback (first seen on draw id %v)", draw_id)
		} else if stale {
			fmt.eprintfln("mesh id %v is from an unloaded pack; drawing the fallback (first seen on draw id %v)", id, draw_id)
		} else {
			fmt.eprintfln("mesh id %v is not in the table; drawing the fallback (first seen on draw id %v)", id, draw_id)
		}
	}
	return &t.meshes[Primitive.Fallback], true
}

// Id 0, an id past the table and a stale id find no mesh. Nothing logs.
mesh_lookup :: proc(t: ^Mesh_Table, id: u32) -> (mesh: ^Mesh, ok: bool) {
	slot := mesh_slot(id)
	if id != 0 && slot < t.count && t.meshes[slot].live && mesh_id(t, slot) == id {
		return &t.meshes[slot], true
	}
	return nil, false
}

mesh_box :: proc(vertices: []Vertex) -> Box {
	if len(vertices) == 0 {
		return {}
	}
	box := Box{vertices[0].pos, vertices[0].pos}
	for v in vertices[1:] {
		box.min = linalg.min(box.min, v.pos)
		box.max = linalg.max(box.max, v.pos)
	}
	return box
}

box_pad :: proc(box: Box, share: f32) -> Box {
	size := box.max - box.min
	pad := share * max(size.x, size.y, size.z)
	return {box.min - pad, box.max + pad}
}

primitive_build :: proc(p: Primitive, allocator: mem.Allocator) -> Mesh_Data {
	switch p {
	case .Fallback:
		return cube_build(MAGENTA, allocator)
	case .Cube:
		return cube_build(GREY, allocator)
	case .Sphere:
		return sphere_build(allocator)
	case .Plane:
		return {vertices = PLANE_VERTICES[:], indices = PLANE_INDICES[:]}
	}
	unreachable()
}

cube_build :: proc(color: [4]f32, allocator: mem.Allocator) -> Mesh_Data {
	vertices := make([]Vertex, len(CUBE_VERTICES), allocator)
	for v, i in CUBE_VERTICES {
		vertices[i] = {pos = v.pos, color = color, normal = v.normal, uv = cube_uv(v.pos, v.normal), tangent = cube_tangent(v.normal)}
	}
	return {vertices = vertices, indices = CUBE_INDICES[:]}
}

// Each side face shows the whole texture upright from outside. The top face
// puts the top of the image towards -z.
cube_uv :: proc(pos, normal: [3]f32) -> [2]f32 {
	u, v: f32
	switch {
	case normal.x != 0:
		u, v = -pos.z * normal.x, -pos.y
	case normal.y != 0:
		u, v = pos.x, pos.z * normal.y
	case:
		u, v = pos.x * normal.z, -pos.y
	}
	return {u + 0.5, v + 0.5}
}

// The direction of increasing u in cube_uv. No face is mirrored.
cube_tangent :: proc(normal: [3]f32) -> [4]f32 {
	switch {
	case normal.x != 0:
		return {0, 0, -normal.x, 1}
	case normal.y != 0:
		return {1, 0, 0, 1}
	case:
		return {normal.z, 0, 0, 1}
	}
}

// A UV sphere of diameter 1. Ring 0 is the +y pole. Each ring repeats its
// first vertex at the seam so the last segment closes without a wrap index.
sphere_build :: proc(allocator: mem.Allocator) -> Mesh_Data {
	vertices := make([]Vertex, (SPHERE_RINGS + 1) * (SPHERE_SEGMENTS + 1), allocator)
	for r in 0 ..= SPHERE_RINGS {
		theta := math.PI * f32(r) / SPHERE_RINGS
		for s in 0 ..= SPHERE_SEGMENTS {
			phi := 2 * math.PI * f32(s) / SPHERE_SEGMENTS
			n := [3]f32{math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi)}
			uv := [2]f32{f32(s) / SPHERE_SEGMENTS, f32(r) / SPHERE_RINGS}
			// u grows with phi, which mirrors the texture seen from outside.
			tangent := [4]f32{-math.sin(phi), 0, math.cos(phi), -1}
			vertices[r * (SPHERE_SEGMENTS + 1) + s] = {pos = n * 0.5, color = GREY, normal = n, uv = uv, tangent = tangent}
		}
	}

	// The pole rings skip the triangle that would collapse to a point.
	indices := make([dynamic]u16, 0, 3 * SPHERE_SEGMENTS * (2 * SPHERE_RINGS - 2), allocator)
	for r in 0 ..< SPHERE_RINGS {
		for s in 0 ..< SPHERE_SEGMENTS {
			a := u16(r * (SPHERE_SEGMENTS + 1) + s)
			b := a + SPHERE_SEGMENTS + 1
			if r != 0 {
				append(&indices, a, a + 1, b)
			}
			if r != SPHERE_RINGS - 1 {
				append(&indices, a + 1, b + 1, b)
			}
		}
	}
	return {vertices = vertices, indices = indices[:]}
}

mesh_material_slots_delete :: proc(slots: []Mesh_Material_Slot, allocator: mem.Allocator) {
	for slot in slots {
		delete(slot.name, allocator)
	}
	delete(slots, allocator)
}

// Duplicate names are ambiguous; generated helpers must reject them.
mesh_material_slot :: proc(slots: []Mesh_Material_Slot, name: string) -> (index: int, err: Mesh_Material_Slot_Error) {
	if name == "" {
		return 0, .Unnamed
	}
	found := false
	for slot in slots {
		if slot.name == name {
			if found {
				return 0, .Duplicate_Name
			}
			index, found = slot.source_material, true
		}
	}
	return index, .None if found else .Unknown_Name
}
