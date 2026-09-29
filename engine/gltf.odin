package engine

import "core:encoding/endian"
import "core:encoding/json"
import "core:math/linalg"
import "core:mem"
import "core:slice"

GLB_MAGIC :: 0x46546C67 // "glTF"
GLB_CHUNK_JSON :: 0x4E4F534A // "JSON"
GLB_CHUNK_BIN :: 0x004E4942 // "BIN\0"
GLB_MAX_VERTICES :: 65_535

GLTF_MODE_TRIANGLES :: 4
GLTF_U8 :: 5121
GLTF_U16 :: 5123
GLTF_U32 :: 5125
GLTF_F32 :: 5126

Glb_Error :: enum {
	None,
	Too_Short,
	Bad_Magic,
	Bad_Version,
	Bad_Chunks,
	Bad_Json,
	No_Mesh,
	Bad_Node,
	Bad_Material,
	Not_Triangles,
	No_Positions,
	No_Normals,
	Bad_Accessor,
	Bad_Index,
	Too_Many_Vertices,
}

GLB_ERROR_REASONS := [Glb_Error]string {
	.None              = "no error",
	.Too_Short         = "the file is too short to be a .glb",
	.Bad_Magic         = "the file is not a .glb",
	.Bad_Version       = "the file is not glTF 2.0",
	.Bad_Chunks        = "the JSON or BIN chunk is missing or truncated",
	.Bad_Json          = "the JSON chunk does not parse",
	.No_Mesh           = "no node in the scene has a mesh",
	.Bad_Node          = "a node index is out of range or the nodes form a cycle",
	.Bad_Material      = "a material index is out of range",
	.Not_Triangles     = "a primitive is not triangles",
	.No_Positions      = "a primitive has no POSITION",
	.No_Normals        = "a primitive has no NORMAL",
	.Bad_Accessor      = "an accessor has the wrong type, is sparse or reads past its buffer",
	.Bad_Index         = "an index is out of range or the index count is not a multiple of 3",
	.Too_Many_Vertices = "the mesh has more than 65,535 vertices",
}

// Only the fields the engine reads. json.unmarshal skips the rest.
Gltf :: struct {
	scene:        Maybe(int),
	scenes:       []struct {
		nodes: []int,
	},
	nodes:        []Gltf_Node,
	meshes:       []struct {
		primitives: []Gltf_Primitive,
	},
	materials:    []struct {
		pbr: struct {
			base_color_factor: Maybe([4]f32) `json:"baseColorFactor"`,
		} `json:"pbrMetallicRoughness"`,
	},
	accessors:    []Gltf_Accessor,
	buffer_views: []Gltf_Buffer_View `json:"bufferViews"`,
}

Gltf_Node :: struct {
	mesh:        Maybe(int),
	children:    []int,
	mat:         Maybe([16]f32) `json:"matrix"`,
	translation: Maybe([3]f32),
	rotation:    Maybe([4]f32),
	scale:       Maybe([3]f32),
}

Gltf_Primitive :: struct {
	attributes: map[string]int,
	indices:    Maybe(int),
	material:   Maybe(int),
	mode:       Maybe(int),
}

Gltf_Accessor :: struct {
	buffer_view:    Maybe(int) `json:"bufferView"`,
	byte_offset:    int `json:"byteOffset"`,
	component_type: int `json:"componentType"`,
	count:          int,
	type:           string,
	sparse:         json.Value,
}

Gltf_Buffer_View :: struct {
	buffer:      int,
	byte_offset: int `json:"byteOffset"`,
	byte_length: int `json:"byteLength"`,
	byte_stride: int `json:"byteStride"`,
}

Glb_Loader :: struct {
	gltf:     Gltf,
	bin:      []byte,
	vertices: [dynamic]Vertex,
	indices:  [dynamic]u16,
}

// Merges every triangle primitive of every mesh node in the glTF scene into
// one mesh. Scratch is frame memory, so a rejected file leaves nothing in
// allocator.
glb_parse :: proc(bytes: []byte, allocator: mem.Allocator) -> (data: Mesh_Data, err: Glb_Error) {
	json_chunk, bin := glb_chunks(bytes) or_return

	l := Glb_Loader {
		bin      = bin,
		vertices = make([dynamic]Vertex, context.temp_allocator),
		indices  = make([dynamic]u16, context.temp_allocator),
	}
	if json.unmarshal(json_chunk, &l.gltf, allocator = context.temp_allocator) != nil {
		return {}, .Bad_Json
	}

	for root in glb_roots(&l.gltf) {
		glb_visit(&l, root, mat4_identity(), 0) or_return
	}
	if len(l.vertices) == 0 {
		return {}, .No_Mesh
	}
	return {vertices = slice.clone(l.vertices[:], allocator), indices = slice.clone(l.indices[:], allocator)}, .None
}

glb_chunks :: proc(bytes: []byte) -> (json_chunk, bin: []byte, err: Glb_Error) {
	if len(bytes) < 12 {
		return nil, nil, .Too_Short
	}
	if magic, _ := endian.get_u32(bytes[0:], .Little); magic != GLB_MAGIC {
		return nil, nil, .Bad_Magic
	}
	if version, _ := endian.get_u32(bytes[4:], .Little); version != 2 {
		return nil, nil, .Bad_Version
	}
	total, _ := endian.get_u32(bytes[8:], .Little)
	if total < 12 || int(total) > len(bytes) {
		return nil, nil, .Bad_Chunks
	}

	rest := bytes[12:total]
	for len(rest) >= 8 {
		length, _ := endian.get_u32(rest[0:], .Little)
		kind, _ := endian.get_u32(rest[4:], .Little)
		if int(length) > len(rest) - 8 {
			return nil, nil, .Bad_Chunks
		}
		chunk := rest[8:][:length]
		switch {
		case kind == GLB_CHUNK_JSON && json_chunk == nil:
			json_chunk = chunk
		case kind == GLB_CHUNK_BIN && bin == nil:
			bin = chunk
		}
		rest = rest[8 + length:]
	}
	if json_chunk == nil || bin == nil {
		return nil, nil, .Bad_Chunks
	}
	return json_chunk, bin, .None
}

// Without a scene, every node that is no other node's child is a root.
glb_roots :: proc(g: ^Gltf) -> []int {
	scene := g.scene.? or_else 0
	if scene >= 0 && scene < len(g.scenes) {
		return g.scenes[scene].nodes
	}
	is_child := make([]bool, len(g.nodes), context.temp_allocator)
	for n in g.nodes {
		for c in n.children {
			if c >= 0 && c < len(is_child) {
				is_child[c] = true
			}
		}
	}
	roots := make([dynamic]int, context.temp_allocator)
	for child, i in is_child {
		if !child {
			append(&roots, i)
		}
	}
	return roots[:]
}

// depth stops a cycle: a tree of n nodes is at most n deep.
glb_visit :: proc(l: ^Glb_Loader, index: int, parent: Mat4, depth: int) -> Glb_Error {
	if index < 0 || index >= len(l.gltf.nodes) || depth >= len(l.gltf.nodes) {
		return .Bad_Node
	}
	node := &l.gltf.nodes[index]
	world := parent * glb_node_local(node)

	if mesh, ok := node.mesh.?; ok {
		if mesh < 0 || mesh >= len(l.gltf.meshes) {
			return .Bad_Node
		}
		for &p in l.gltf.meshes[mesh].primitives {
			glb_add_primitive(l, &p, world) or_return
		}
	}
	for child in node.children {
		glb_visit(l, child, world, depth + 1) or_return
	}
	return .None
}

// glTF stores matrix column-major, and a node without one is T * R * S.
glb_node_local :: proc(node: ^Gltf_Node) -> Mat4 {
	if m, ok := node.mat.?; ok {
		out: Mat4
		for col in 0 ..< 4 {
			for row in 0 ..< 4 {
				out[row, col] = m[col * 4 + row]
			}
		}
		return out
	}
	t := node.translation.? or_else {0, 0, 0}
	r := node.rotation.? or_else {0, 0, 0, 1}
	s := node.scale.? or_else {1, 1, 1}
	q := quaternion(w = r[3], x = r[0], y = r[1], z = r[2])
	return linalg.matrix4_translate_f32(t) * linalg.matrix4_from_quaternion_f32(q) * linalg.matrix4_scale_f32(s)
}

glb_add_primitive :: proc(l: ^Glb_Loader, p: ^Gltf_Primitive, world: Mat4) -> Glb_Error {
	if (p.mode.? or_else GLTF_MODE_TRIANGLES) != GLTF_MODE_TRIANGLES {
		return .Not_Triangles
	}
	pos_index, has_pos := p.attributes["POSITION"]
	if !has_pos {
		return .No_Positions
	}
	nrm_index, has_nrm := p.attributes["NORMAL"]
	if !has_nrm {
		return .No_Normals
	}
	positions := glb_vec3_accessor(l, pos_index) or_return
	normals := glb_vec3_accessor(l, nrm_index) or_return
	count := positions.count
	if normals.count != count {
		return .Bad_Accessor
	}
	base := len(l.vertices)
	if base + count > GLB_MAX_VERTICES {
		return .Too_Many_Vertices
	}

	color := GREY
	if m, ok := p.material.?; ok {
		if m < 0 || m >= len(l.gltf.materials) {
			return .Bad_Material
		}
		color = l.gltf.materials[m].pbr.base_color_factor.? or_else {1, 1, 1, 1}
	}

	basis := linalg.matrix3_from_matrix4_f32(world)
	normal_matrix := linalg.matrix3_inverse_transpose_f32(basis)
	// glTF reverses the winding under a mirroring transform.
	mirrored := linalg.determinant(basis) < 0
	for i in 0 ..< count {
		pos := glb_read_vec3(positions, i)
		nrm := glb_read_vec3(normals, i)
		append(
			&l.vertices,
			Vertex {
				pos = (world * [4]f32{pos.x, pos.y, pos.z, 1}).xyz,
				color = color,
				normal = linalg.normalize0(normal_matrix * nrm),
			},
		)
	}

	index_count := count
	indices: Glb_View
	index_accessor, indexed := p.indices.?
	if indexed {
		indices = glb_index_accessor(l, index_accessor) or_return
		index_count = indices.count
	}
	if index_count % 3 != 0 {
		return .Bad_Index
	}
	for i in 0 ..< index_count {
		// A mirrored triangle swaps its last two corners.
		corner := i
		if mirrored && i % 3 != 0 {
			corner = i + 1 if i % 3 == 1 else i - 1
		}
		index := corner
		if indexed {
			index = glb_read_index(indices, corner)
		}
		if index < 0 || index >= count {
			return .Bad_Index
		}
		append(&l.indices, u16(base + index))
	}
	return .None
}

// One accessor's elements in the BIN chunk. data starts at element 0.
Glb_View :: struct {
	data:           []byte,
	count:          int,
	stride:         int,
	component_type: int,
}

glb_vec3_accessor :: proc(l: ^Glb_Loader, index: int) -> (view: Glb_View, err: Glb_Error) {
	view = glb_accessor(l, index, "VEC3") or_return
	return view, .None if view.component_type == GLTF_F32 else .Bad_Accessor
}

glb_index_accessor :: proc(l: ^Glb_Loader, index: int) -> (view: Glb_View, err: Glb_Error) {
	view = glb_accessor(l, index, "SCALAR") or_return
	return view, .None if view.component_type != GLTF_F32 else .Bad_Accessor
}

// Every bounds check is written so a hostile int in the JSON cannot overflow it.
glb_accessor :: proc(l: ^Glb_Loader, index: int, type: string) -> (view: Glb_View, err: Glb_Error) {
	if index < 0 || index >= len(l.gltf.accessors) {
		return {}, .Bad_Accessor
	}
	a := &l.gltf.accessors[index]
	if a.type != type || a.sparse != nil {
		return {}, .Bad_Accessor
	}
	size: int
	switch a.component_type {
	case GLTF_U8:
		size = 1
	case GLTF_U16:
		size = 2
	case GLTF_U32, GLTF_F32:
		size = 4
	case:
		return {}, .Bad_Accessor
	}
	if type == "VEC3" {
		size *= 3
	}

	// An accessor without a buffer view is all zeros. Exporters do not write one for meshes.
	view_index, ok := a.buffer_view.?
	if !ok || view_index < 0 || view_index >= len(l.gltf.buffer_views) {
		return {}, .Bad_Accessor
	}
	bv := &l.gltf.buffer_views[view_index]
	if bv.buffer != 0 || bv.byte_offset < 0 || bv.byte_offset > len(l.bin) || bv.byte_length < 0 || bv.byte_length > len(l.bin) - bv.byte_offset {
		return {}, .Bad_Accessor
	}
	stride := bv.byte_stride if bv.byte_stride != 0 else size
	if a.count < 0 || stride < size || a.byte_offset < 0 || a.byte_offset > bv.byte_length {
		return {}, .Bad_Accessor
	}
	room := bv.byte_length - a.byte_offset
	if a.count > 0 && (room < size || a.count - 1 > (room - size) / stride) {
		return {}, .Bad_Accessor
	}
	data := l.bin[bv.byte_offset:][:bv.byte_length][a.byte_offset:]
	return {data = data, count = a.count, stride = stride, component_type = a.component_type}, .None
}

glb_read_vec3 :: proc(v: Glb_View, i: int) -> [3]f32 {
	b := v.data[i * v.stride:]
	x, _ := endian.get_f32(b[0:], .Little)
	y, _ := endian.get_f32(b[4:], .Little)
	z, _ := endian.get_f32(b[8:], .Little)
	return {x, y, z}
}

glb_read_index :: proc(v: Glb_View, i: int) -> int {
	b := v.data[i * v.stride:]
	switch v.component_type {
	case GLTF_U8:
		return int(b[0])
	case GLTF_U16:
		n, _ := endian.get_u16(b, .Little)
		return int(n)
	case:
		n, _ := endian.get_u32(b, .Little)
		return int(n)
	}
}
