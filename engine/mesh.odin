package engine

import sg "../sokol-odin/sokol/gfx"
import "core:fmt"
import "core:math"
import "core:mem"

MESH_CAPACITY :: 64
SPHERE_RINGS :: 16
SPHERE_SEGMENTS :: 32

// The primitives are the first slots of the mesh table, so each value is its mesh id.
Primitive :: enum u32 {
	Fallback,
	Cube,
	Sphere,
	Plane,
}

// A file stem cannot contain "/", so a loaded file never takes a primitive's name.
PRIMITIVE_NAMES := [Primitive]string {
	.Fallback = "primitive/fallback",
	.Cube     = "primitive/cube",
	.Sphere   = "primitive/sphere",
	.Plane    = "primitive/plane",
}

GREY :: [4]f32{0.8, 0.8, 0.8, 1}
MAGENTA :: [4]f32{1, 0, 1, 1}

Mesh :: struct {
	name:        string,
	data:        Mesh_Data, // Loaded files only. Primitives build theirs at upload.
	vertices:    sg.Buffer,
	indices:     sg.Buffer,
	index_count: int,
}

// The mesh id is the slot index. Slots past count are empty.
Mesh_Table :: struct {
	meshes: [MESH_CAPACITY]Mesh,
	count:  int,
	logged: map[u32]struct {},
}

Mesh_Data :: struct {
	vertices: []Vertex,
	indices:  []u16,
}

// Names every primitive. The GPU buffers come later, from mesh_table_upload.
mesh_table_init :: proc(t: ^Mesh_Table, allocator: mem.Allocator) {
	t.logged = make(map[u32]struct {}, allocator)
	for p in Primitive {
		t.meshes[p].name = PRIMITIVE_NAMES[p]
	}
	t.count = len(Primitive)
}

mesh_table_destroy :: proc(t: ^Mesh_Table) {
	delete(t.logged)
}

// Needs sokol set up. The primitive vertex data is scratch and dies with the frame.
mesh_table_upload :: proc(t: ^Mesh_Table) {
	for p in Primitive {
		mesh_upload(&t.meshes[p], primitive_build(p, context.temp_allocator))
	}
	for &m in t.meshes[len(Primitive):t.count] {
		mesh_upload(&m, m.data)
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
}

// Id 0 and any id past the table draw the fallback. Each such id is logged once per run.
mesh_resolve :: proc(t: ^Mesh_Table, mesh_id: u32, draw_id: u64) -> (mesh: ^Mesh, fallback: bool) {
	if mesh_id != 0 && int(mesh_id) < t.count {
		return &t.meshes[mesh_id], false
	}
	if mesh_id not_in t.logged {
		t.logged[mesh_id] = {}
		if mesh_id == 0 {
			fmt.eprintfln("mesh id 0 is the fallback; drawing the fallback (first seen on draw id %v)", draw_id)
		} else {
			fmt.eprintfln("mesh id %v is not in the table; drawing the fallback (first seen on draw id %v)", mesh_id, draw_id)
		}
	}
	return &t.meshes[Primitive.Fallback], true
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
		vertices[i] = {pos = v.pos, color = color, normal = v.normal}
	}
	return {vertices = vertices, indices = CUBE_INDICES[:]}
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
			vertices[r * (SPHERE_SEGMENTS + 1) + s] = {pos = n * 0.5, color = GREY, normal = n}
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

// A 1 x 1 quad in x-z, facing +y. One-sided: back-face culling hides it from below.
@(rodata)
PLANE_VERTICES := [4]Vertex {
	{pos = {-0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}},
	{pos = {-0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}},
	{pos = {0.5, 0, 0.5}, color = GREY, normal = {0, 1, 0}},
	{pos = {0.5, 0, -0.5}, color = GREY, normal = {0, 1, 0}},
}

@(rodata)
PLANE_INDICES := [6]u16{0, 1, 2, 0, 2, 3}

// Positions and normals of a unit cube. cube_build sets the colour.
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
