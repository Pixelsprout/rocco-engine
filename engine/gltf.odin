package engine

import sg "../sokol-odin/sokol/gfx"
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
GLTF_I8 :: 5120
GLTF_U8 :: 5121
GLTF_I16 :: 5122
GLTF_U16 :: 5123
GLTF_U32 :: 5125
GLTF_F32 :: 5126
GLTF_NEAREST :: 9728
GLTF_LINEAR :: 9729
GLTF_NEAREST_MIPMAP_NEAREST :: 9984
GLTF_LINEAR_MIPMAP_NEAREST :: 9985
GLTF_NEAREST_MIPMAP_LINEAR :: 9986
GLTF_LINEAR_MIPMAP_LINEAR :: 9987
GLTF_CLAMP_TO_EDGE :: 33071
GLTF_MIRRORED_REPEAT :: 33648
GLTF_REPEAT :: 10497

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
	.Bad_Texture       = "a texture, image, sampler or image buffer view index is out of range",
	.Not_Triangles     = "a primitive is not triangles",
	.No_Positions      = "a primitive has no POSITION",
	.No_Normals        = "a primitive has no NORMAL",
	.Bad_Accessor      = "an accessor has the wrong type, is sparse or reads past its buffer",
	.Bad_Index         = "an index is out of range or the index count is not a multiple of 3",
	.Too_Many_Vertices = "the mesh has more than 65,535 vertices",
	.Two_Skins         = "the file has more than one Skin",
	.Mixed_Skinning    = "the file mixes skinned and unskinned mesh nodes",
	.Too_Many_Joints   = "the Skin has more than 64 Joints",
	.Cubic_Spline      = "a Clip has CUBICSPLINE keys; export LINEAR or STEP keys",
	.No_Influences     = "a skinned primitive has no JOINTS_0 or WEIGHTS_0",
	.Bad_Skin          = "a Skin has no Joints, names a node twice or out of range, or a vertex names a Joint past the Skin",
	.Bad_Clip          = "a Clip names a sampler or node out of range, or its key times do not rise or do not match its values",
}

GLB_NOTE_REASONS := [Glb_Note]string {
	.Jpeg_Skipped      = "a texture is a JPEG, so it draws without that texture; export PNG",
	.Bad_Png           = "a texture PNG does not decode or has a side over 32768, so it draws without that texture",
	.Unsupported_Image = "a texture is not an embedded PNG, so it draws without that texture",
	.Mixed_Textures    = "its primitives do not share one base colour texture, so they all draw the first",
	.Mixed_Materials   = "its primitives do not share one roughness, metallic, unlit flag and metallic-roughness texture, so they all draw the first",
	.Channel_Skipped   = "a Clip moves morph weights, a node that is not a Joint, or no node, so the Clip skips that channel",
}

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
	Bad_Texture,
	Not_Triangles,
	No_Positions,
	No_Normals,
	Bad_Accessor,
	Bad_Index,
	Too_Many_Vertices,
	Two_Skins,
	Mixed_Skinning,
	Too_Many_Joints,
	Cubic_Spline,
	No_Influences,
	Bad_Skin,
	Bad_Clip,
}

// A problem that does not stop the mesh loading.
Glb_Note :: enum {
	Jpeg_Skipped,
	Bad_Png,
	Unsupported_Image,
	Mixed_Textures,
	Mixed_Materials,
	Channel_Skipped,
}

Glb_Notes :: bit_set[Glb_Note]

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
		pbr:        struct {
			base_color_factor:          Maybe([4]f32) `json:"baseColorFactor"`,
			base_color_texture:         Maybe(Gltf_Texture_Ref) `json:"baseColorTexture"`,
			metallic_factor:            Maybe(f32) `json:"metallicFactor"`,
			roughness_factor:           Maybe(f32) `json:"roughnessFactor"`,
			metallic_roughness_texture: Maybe(Gltf_Texture_Ref) `json:"metallicRoughnessTexture"`,
		} `json:"pbrMetallicRoughness"`,
		extensions: struct {
			unlit: Maybe(struct {}) `json:"KHR_materials_unlit"`,
		},
	},
	textures:     []struct {
		source:  Maybe(int),
		sampler: Maybe(int),
	},
	images:       []struct {
		buffer_view: Maybe(int) `json:"bufferView"`,
		mime_type:   string `json:"mimeType"`,
	},
	samplers:     []struct {
		mag_filter: Maybe(int) `json:"magFilter"`,
		min_filter: Maybe(int) `json:"minFilter"`,
		wrap_s:     Maybe(int) `json:"wrapS"`,
		wrap_t:     Maybe(int) `json:"wrapT"`,
	},
	accessors:    []Gltf_Accessor,
	buffer_views: []Gltf_Buffer_View `json:"bufferViews"`,
	skins:        []Gltf_Skin,
	animations:   []Gltf_Animation,
}

Gltf_Texture_Ref :: struct {
	index: int,
}

Gltf_Node :: struct {
	mesh:        Maybe(int),
	skin:        Maybe(int),
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

Gltf_Skin :: struct {
	joints:                []int,
	inverse_bind_matrices: Maybe(int) `json:"inverseBindMatrices"`,
}

Gltf_Animation :: struct {
	name:     string,
	channels: []struct {
		sampler: int,
		target:  struct {
			node: Maybe(int),
			path: string,
		},
	},
	samplers: []struct {
		input:         int,
		output:        int,
		interpolation: string,
	},
}

Gltf_Buffer_View :: struct {
	buffer:      int,
	byte_offset: int `json:"byteOffset"`,
	byte_length: int `json:"byteLength"`,
	byte_stride: int `json:"byteStride"`,
}

Glb_Loader :: struct {
	gltf:       Gltf,
	bin:        []byte,
	vertices:   [dynamic]Vertex,
	// One per vertex when the mesh nodes are skinned.
	influences: [dynamic]Glb_Influence,
	indices:    [dynamic]u16,
	texture:    Maybe(int),
	// The primitives so far name one texture, or none, between them.
	first:      Maybe(Maybe(int)),
	mixed:      bool,
	// The first primitive's, which the whole mesh draws with.
	material:   Maybe(Glb_Material),
	notes:      Glb_Notes,
	skinned:    bool,
	rigid:      bool,
}

Glb_Material :: struct {
	values:             Material,
	metallic_roughness: Maybe(int),
}

// joints index the glTF skin's joints, which the Skin puts in another order.
Glb_Influence :: struct {
	joints:  [4]u16,
	weights: [4]u8,
}

// One accessor's elements in the BIN chunk. data starts at element 0.
Glb_View :: struct {
	data:           []byte,
	count:          int,
	stride:         int,
	component_type: int,
}

// Merges every triangle primitive of every mesh node in the glTF scene into
// one mesh with one base colour texture and one material. Scratch is frame memory, so a
// rejected file leaves nothing in allocator. Skinned mesh nodes merge in
// bind-pose space with their Skin and Clips.
glb_parse :: proc(bytes: []byte, allocator: mem.Allocator) -> (data: Mesh_Data, notes: Glb_Notes, err: Glb_Error) {
	json_chunk, bin := glb_chunks(bytes) or_return

	l := Glb_Loader {
		bin      = bin,
		vertices   = make([dynamic]Vertex, context.temp_allocator),
		influences = make([dynamic]Glb_Influence, context.temp_allocator),
		indices    = make([dynamic]u16, context.temp_allocator),
	}
	if json.unmarshal(json_chunk, &l.gltf, allocator = context.temp_allocator) != nil {
		return {}, {}, .Bad_Json
	}

	for root in glb_roots(&l.gltf) {
		glb_visit(&l, root, mat4_identity(), 0) or_return
	}
	if len(l.vertices) == 0 {
		return {}, {}, .No_Mesh
	}
	skin: Skin
	influences: []Influence
	if l.skinned {
		skin, influences = glb_skin(&l) or_return
	}
	texture: Maybe(Texture)
	if index, ok := l.texture.?; ok {
		texture = glb_texture(&l, index, srgb = true, allocator = allocator) or_return
	}
	if l.mixed && texture != nil {
		l.notes += {.Mixed_Textures}
	}
	material := l.material.? or_else {}
	metallic_roughness: Maybe(Texture)
	if index, ok := material.metallic_roughness.?; ok {
		metallic_roughness = glb_texture(&l, index, srgb = false, allocator = allocator) or_return
	}
	data = {
		vertices           = slice.clone(l.vertices[:], allocator),
		influences         = slice.clone(influences, allocator),
		indices            = slice.clone(l.indices[:], allocator),
		texture            = texture,
		material           = material.values,
		metallic_roughness = metallic_roughness,
		skin               = skin_clone(skin, allocator),
	}
	return data, l.notes, .None
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
		skin, skinned := node.skin.?
		if skinned && (skin < 0 || skin >= len(l.gltf.skins)) {
			return .Bad_Skin
		}
		l.skinned ||= skinned
		l.rigid ||= !skinned
		if l.skinned && l.rigid {
			return .Mixed_Skinning
		}
		// glTF ignores the transform of a skinned mesh node.
		place := mat4_identity() if skinned else world
		for &p in l.gltf.meshes[mesh].primitives {
			glb_add_primitive(l, &p, place, skinned) or_return
		}
	}
	for child in node.children {
		glb_visit(l, child, world, depth + 1) or_return
	}
	return .None
}

// A node without a matrix is T * R * S.
glb_node_local :: proc(node: ^Gltf_Node) -> Mat4 {
	if m, ok := node.mat.?; ok {
		return glb_mat4(m)
	}
	t := node.translation.? or_else {0, 0, 0}
	r := node.rotation.? or_else {0, 0, 0, 1}
	s := node.scale.? or_else {1, 1, 1}
	q := quaternion(w = r[3], x = r[0], y = r[1], z = r[2])
	return linalg.matrix4_translate_f32(t) * linalg.matrix4_from_quaternion_f32(q) * linalg.matrix4_scale_f32(s)
}

// glTF stores a matrix column-major.
glb_mat4 :: proc(m: [16]f32) -> Mat4 {
	out: Mat4
	for col in 0 ..< 4 {
		for row in 0 ..< 4 {
			out[row, col] = m[col * 4 + row]
		}
	}
	return out
}

glb_add_primitive :: proc(l: ^Glb_Loader, p: ^Gltf_Primitive, world: Mat4, skinned: bool) -> Glb_Error {
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

	uvs: Glb_View
	uv_index, has_uv := p.attributes["TEXCOORD_0"]
	if has_uv {
		uvs = glb_accessor(l, uv_index, "VEC2") or_return
		if uvs.component_type != GLTF_F32 || uvs.count != count {
			return .Bad_Accessor
		}
	}
	if skinned {
		glb_add_influences(l, p, count) or_return
	}

	color := GREY
	tex: Maybe(int)
	material := Glb_Material {
		values = MATERIAL_MATTE,
	}
	if m, ok := p.material.?; ok {
		if m < 0 || m >= len(l.gltf.materials) {
			return .Bad_Material
		}
		gltf_material := &l.gltf.materials[m]
		pbr := &gltf_material.pbr
		color = pbr.base_color_factor.? or_else {1, 1, 1, 1}
		if ref, textured := pbr.base_color_texture.?; textured {
			tex = ref.index
			if l.texture == nil {
				l.texture = ref.index
			}
		}
		material.values = {
			roughness = clamp(pbr.roughness_factor.? or_else 1, 0, 1),
			metallic  = clamp(pbr.metallic_factor.? or_else 1, 0, 1),
			unlit     = gltf_material.extensions.unlit != nil,
		}
		if ref, textured := pbr.metallic_roughness_texture.?; textured {
			material.metallic_roughness = ref.index
		}
	}
	if first, seen := l.first.?; !seen {
		l.first = tex
	} else if first != tex {
		l.mixed = true
	}
	if first, seen := l.material.?; !seen {
		l.material = material
	} else if first != material {
		l.notes += {.Mixed_Materials}
	}

	basis := linalg.matrix3_from_matrix4_f32(world)
	normal_matrix := linalg.matrix3_inverse_transpose_f32(basis)
	// glTF reverses the winding under a mirroring transform.
	mirrored := linalg.determinant(basis) < 0
	for i in 0 ..< count {
		pos := glb_read_vec3(positions, i)
		nrm := glb_read_vec3(normals, i)
		uv: [2]f32
		if has_uv {
			uv = glb_read_vec2(uvs, i)
		}
		append(
			&l.vertices,
			Vertex {
				pos = (world * [4]f32{pos.x, pos.y, pos.z, 1}).xyz,
				color = color,
				normal = linalg.normalize0(normal_matrix * nrm),
				uv = uv,
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

glb_vec3_accessor :: proc(l: ^Glb_Loader, index: int) -> (view: Glb_View, err: Glb_Error) {
	view = glb_accessor(l, index, "VEC3") or_return
	return view, .None if view.component_type == GLTF_F32 else .Bad_Accessor
}

glb_index_accessor :: proc(l: ^Glb_Loader, index: int) -> (view: Glb_View, err: Glb_Error) {
	view = glb_accessor(l, index, "SCALAR") or_return
	switch view.component_type {
	case GLTF_U8, GLTF_U16, GLTF_U32:
		return view, .None
	}
	return view, .Bad_Accessor
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
	case GLTF_I8, GLTF_U8:
		size = 1
	case GLTF_I16, GLTF_U16:
		size = 2
	case GLTF_U32, GLTF_F32:
		size = 4
	case:
		return {}, .Bad_Accessor
	}
	switch type {
	case "VEC2":
		size *= 2
	case "VEC3":
		size *= 3
	case "VEC4":
		size *= 4
	case "MAT4":
		size *= 16
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

// A texture that cannot draw gives a note and no texture. Only a bad index is an error.
glb_texture :: proc(l: ^Glb_Loader, index: int, srgb: bool, allocator: mem.Allocator) -> (tex: Maybe(Texture), err: Glb_Error) {
	if index < 0 || index >= len(l.gltf.textures) {
		return nil, .Bad_Texture
	}
	t := &l.gltf.textures[index]
	sampler := glb_sampler(nil, nil, nil, nil)
	if s, ok := t.sampler.?; ok {
		if s < 0 || s >= len(l.gltf.samplers) {
			return nil, .Bad_Texture
		}
		gs := &l.gltf.samplers[s]
		sampler = glb_sampler(gs.mag_filter, gs.min_filter, gs.wrap_s, gs.wrap_t)
	}

	source, has_source := t.source.?
	if !has_source {
		l.notes += {.Unsupported_Image}
		return nil, .None
	}
	if source < 0 || source >= len(l.gltf.images) {
		return nil, .Bad_Texture
	}
	img := &l.gltf.images[source]
	view_index, embedded := img.buffer_view.?
	if !embedded {
		l.notes += {.Unsupported_Image}
		return nil, .None
	}
	if view_index < 0 || view_index >= len(l.gltf.buffer_views) {
		return nil, .Bad_Texture
	}
	bv := &l.gltf.buffer_views[view_index]
	if bv.buffer != 0 || bv.byte_offset < 0 || bv.byte_offset > len(l.bin) || bv.byte_length < 0 || bv.byte_length > len(l.bin) - bv.byte_offset {
		return nil, .Bad_Texture
	}
	bytes := l.bin[bv.byte_offset:][:bv.byte_length]

	switch img.mime_type {
	case "image/png":
		width, height, rgba, ok := png_decode(bytes)
		if !ok {
			l.notes += {.Bad_Png}
			return nil, .None
		}
		return texture_build(width, height, rgba, sampler, srgb, allocator), .None
	case "image/jpeg":
		l.notes += {.Jpeg_Skipped}
	case:
		l.notes += {.Unsupported_Image}
	}
	return nil, .None
}

// glTF leaves a missing filter to the engine, which picks linear with no
// mipmaps. A missing wrap is repeat.
glb_sampler :: proc(mag_filter, min_filter, wrap_s, wrap_t: Maybe(int)) -> Texture_Sampler {
	s := Texture_Sampler {
		min_filter    = .LINEAR,
		mag_filter    = .NEAREST if mag_filter == GLTF_NEAREST else .LINEAR,
		mipmap_filter = .NEAREST,
	}
	switch min_filter.? or_else GLTF_LINEAR {
	case GLTF_NEAREST:
		s.min_filter = .NEAREST
	case GLTF_NEAREST_MIPMAP_NEAREST:
		s.min_filter, s.mipmaps = .NEAREST, true
	case GLTF_LINEAR_MIPMAP_NEAREST:
		s.min_filter, s.mipmaps = .LINEAR, true
	case GLTF_NEAREST_MIPMAP_LINEAR:
		s.min_filter, s.mipmap_filter, s.mipmaps = .NEAREST, .LINEAR, true
	case GLTF_LINEAR_MIPMAP_LINEAR:
		s.min_filter, s.mipmap_filter, s.mipmaps = .LINEAR, .LINEAR, true
	}
	s.wrap_u = glb_wrap(wrap_s)
	s.wrap_v = glb_wrap(wrap_t)
	return s
}

glb_wrap :: proc(wrap: Maybe(int)) -> sg.Wrap {
	switch wrap.? or_else GLTF_REPEAT {
	case GLTF_CLAMP_TO_EDGE:
		return .CLAMP_TO_EDGE
	case GLTF_MIRRORED_REPEAT:
		return .MIRRORED_REPEAT
	}
	return .REPEAT
}

glb_read_vec2 :: proc(v: Glb_View, i: int) -> [2]f32 {
	b := v.data[i * v.stride:]
	x, _ := endian.get_f32(b[0:], .Little)
	y, _ := endian.get_f32(b[4:], .Little)
	return {x, y}
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
