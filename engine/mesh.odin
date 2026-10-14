package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

MESH_CAPACITY :: 64
MESH_SLOT_BITS :: 16
SPHERE_RINGS :: 16
SPHERE_SEGMENTS :: 32

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
	{pos = {-0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}, uv = {0, 0}},
	{pos = {-0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}, uv = {0, 1}},
	{pos = {0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}, uv = {1, 1}},
	{pos = {0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}, uv = {1, 0}},
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

// glTF puts uv 0, 0 at the top left of the image.
Vertex :: struct {
	pos:    [3]f32,
	color:  [4]f32,
	normal: [3]f32,
	uv:     [2]f32,
}

// unlit draws the base colour as it is, with no lights and no tone map.
Material :: struct {
	roughness: f32,
	metallic:  f32,
	unlit:     bool,
}

// A zero id means the mesh has no texture and binds the white image.
Mesh_Texture :: struct {
	image:   sg.Image,
	view:    sg.View,
	sampler: sg.Sampler,
}

// An axis-aligned box in the mesh's own space, around every vertex.
Box :: struct {
	min, max: [3]f32,
}

Mesh :: struct {
	name:               string,
	data:               Mesh_Data, // Loaded files only, until the upload. Primitives build theirs at upload.
	live:               bool,
	vertices:           sg.Buffer,
	indices:            sg.Buffer,
	index_count:        int,
	texture:            Mesh_Texture,
	metallic_roughness: Mesh_Texture,
	material:           Material,
	box:                Box,
	generation:         u16,
}

// After mesh_table_upload, a new mesh uploads when it is added. The table
// owns each loaded mesh's name and data.
Mesh_Table :: struct {
	meshes:     [MESH_CAPACITY]Mesh,
	count:      int,
	free:       [MESH_CAPACITY]int,
	free_count: int,
	logged:     map[u32]struct {},
	uploaded:   bool,
	allocator:  mem.Allocator,
}

Mesh_Data :: struct {
	vertices:           []Vertex,
	indices:            []u16,
	texture:            Maybe(Texture),
	metallic_roughness: Maybe(Texture),
	material:           Material,
}

// Names every primitive. The GPU buffers come later, from mesh_table_upload.
mesh_table_init :: proc(t: ^Mesh_Table, allocator: mem.Allocator) {
	t.allocator = allocator
	t.logged = make(map[u32]struct {}, allocator)
	for p in Primitive {
		box := mesh_box(primitive_build(p, context.temp_allocator).vertices)
		t.meshes[p] = {name = PRIMITIVE_NAMES[p], live = true, material = MATERIAL_MATTE, box = box}
	}
	t.count = len(Primitive)
}

// Frees the names and data of the loaded meshes. sg.shutdown destroys their buffers.
mesh_table_destroy :: proc(t: ^Mesh_Table) {
	for &m in t.meshes[len(Primitive):t.count] {
		if m.live {
			delete(m.name, t.allocator)
			mesh_data_delete(t, m.data)
		}
	}
	delete(t.logged)
}

mesh_id :: proc(t: ^Mesh_Table, slot: int) -> u32 {
	return u32(t.meshes[slot].generation) << MESH_SLOT_BITS | u32(slot)
}

mesh_slot :: proc(id: u32) -> int {
	return int(id & (1 << MESH_SLOT_BITS - 1))
}

mesh_table_full :: proc(t: ^Mesh_Table) -> bool {
	return t.free_count == 0 && t.count == MESH_CAPACITY
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
	t.meshes[slot] = {name = name, data = data, live = true, material = data.material, box = mesh_box(data.vertices), generation = t.meshes[slot].generation}
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
	mesh_texture_destroy(m.texture)
	mesh_texture_destroy(m.metallic_roughness)
	delete(m.name, t.allocator)
	mesh_data_delete(t, m.data)
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
	mesh_data_delete(t, m.data)
	m.data = {}
}

@(private = "file")
mesh_data_delete :: proc(t: ^Mesh_Table, data: Mesh_Data) {
	delete(data.vertices, t.allocator)
	delete(data.indices, t.allocator)
	if tex, ok := data.texture.?; ok {
		texture_delete(tex, t.allocator)
	}
	if tex, ok := data.metallic_roughness.?; ok {
		texture_delete(tex, t.allocator)
	}
}

@(private = "file")
mesh_texture_destroy :: proc(tex: Mesh_Texture) {
	if tex.image.id != 0 {
		sg.destroy_view(tex.view)
		sg.destroy_image(tex.image)
		sg.destroy_sampler(tex.sampler)
	}
}

mesh_upload :: proc(m: ^Mesh, data: Mesh_Data) {
	m.vertices = sg.make_buffer(
		{label = "mesh-vertices", data = {ptr = raw_data(data.vertices), size = uint(len(data.vertices) * size_of(Vertex))}},
	)
	m.indices = sg.make_buffer(
		{
			label = "mesh-indices",
			data = {ptr = raw_data(data.indices), size = uint(len(data.indices) * size_of(u16))},
			usage = {index_buffer = true},
		},
	)
	m.index_count = len(data.indices)
	if tex, ok := data.texture.?; ok {
		m.texture = texture_upload(tex)
	}
	if tex, ok := data.metallic_roughness.?; ok {
		m.metallic_roughness = texture_upload(tex)
	}
}

// White leaves the base colour as it is and the material factors at their values.
mesh_textures :: proc(m: ^Mesh, white: Mesh_Texture) -> (base, metallic_roughness: Mesh_Texture) {
	base = m.texture if m.texture.image.id != 0 else white
	metallic_roughness = m.metallic_roughness if m.metallic_roughness.image.id != 0 else white
	return
}

// Id 0, an id past the table and a stale id draw the fallback. Each such id is logged once per run.
mesh_resolve :: proc(t: ^Mesh_Table, id: u32, draw_id: u64) -> (mesh: ^Mesh, fallback: bool) {
	slot := mesh_slot(id)
	generation := id >> MESH_SLOT_BITS
	if id != 0 && slot < t.count && t.meshes[slot].live && mesh_id(t, slot) == id {
		return &t.meshes[slot], false
	}
	stale := slot >= len(Primitive) && slot < MESH_CAPACITY && generation != u32(t.meshes[slot].generation)
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
		vertices[i] = {pos = v.pos, color = color, normal = v.normal, uv = cube_uv(v.pos, v.normal)}
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
			vertices[r * (SPHERE_SEGMENTS + 1) + s] = {pos = n * 0.5, color = GREY, normal = n, uv = uv}
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
