package engine

import sg "../sokol-odin/sokol/gfx"
import "arenas"
import "core:encoding/endian"
import "core:encoding/json"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:strings"

GLB_MAGIC :: 0x46546C67 // "glTF"
GLB_CHUNK_JSON :: 0x4E4F534A // "JSON"
GLB_CHUNK_BIN :: 0x004E4942 // "BIN\0"
GLB_MAX_VERTICES :: 65_535
GLB_PLACEHOLDER_TANGENT :: [4]f32{1, 0, 0, 1}

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

#assert(MESH_TEXTURE_LIMIT == 16, "the Too_Many_Textures reason states the limit")
GLB_NOTE_REASONS := [Glb_Note]string {
	.Jpeg_Skipped         = "a texture is a JPEG, so it draws without that texture; export PNG",
	.Bad_Png              = "a texture PNG does not decode or has a side over 32768, so it draws without that texture",
	.Unsupported_Image    = "a texture is not an embedded PNG, so it draws without that texture",
	.Too_Many_Textures    = "it has more than 16 textures, so the textures past the first 16 do not draw",
	.Channel_Skipped      = "a Clip moves morph weights, a node that is not a Joint, or no node, so the Clip skips that channel",
	.Generated_Tangents   = "a normal-mapped primitive has no TANGENT, so the host makes tangents that may not match the baker; export tangents",
	.Second_Uv_Ignored    = "a texture names a texCoord other than 0, so it draws with the first UV set",
	.Transmission_Ignored = "a material has KHR_materials_transmission, so it draws by alphaMode; use Alpha in Blender for glass",
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
	Too_Many_Textures,
	Channel_Skipped,
	Generated_Tangents,
	Second_Uv_Ignored,
	Transmission_Ignored,
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
		name: string,
		pbr:        struct {
			base_color_factor:          Maybe([4]f32) `json:"baseColorFactor"`,
			base_color_texture:         Maybe(Gltf_Texture_Ref) `json:"baseColorTexture"`,
			metallic_factor:            Maybe(f32) `json:"metallicFactor"`,
			roughness_factor:           Maybe(f32) `json:"roughnessFactor"`,
			metallic_roughness_texture: Maybe(Gltf_Texture_Ref) `json:"metallicRoughnessTexture"`,
		} `json:"pbrMetallicRoughness"`,
		normal_texture:    Maybe(Gltf_Texture_Ref) `json:"normalTexture"`,
		occlusion_texture: Maybe(Gltf_Texture_Ref) `json:"occlusionTexture"`,
		emissive_factor:   Maybe([3]f32) `json:"emissiveFactor"`,
		emissive_texture:  Maybe(Gltf_Texture_Ref) `json:"emissiveTexture"`,
		alpha_mode:        string `json:"alphaMode"`,
		alpha_cutoff:      Maybe(f32) `json:"alphaCutoff"`,
		double_sided:      bool `json:"doubleSided"`,
		extensions:        struct {
			unlit:             Maybe(struct {}) `json:"KHR_materials_unlit"`,
			transmission:      Maybe(struct {
					factor: Maybe(f32) `json:"transmissionFactor"`,
				}) `json:"KHR_materials_transmission"`,
			emissive_strength: Maybe(struct {
					strength: Maybe(f32) `json:"emissiveStrength"`,
				}) `json:"KHR_materials_emissive_strength"`,
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

// Only normalTexture has scale and only occlusionTexture has strength.
Gltf_Texture_Ref :: struct {
	index:     int,
	tex_coord: int `json:"texCoord"`,
	scale:     Maybe(f32),
	strength:  Maybe(f32),
}

Gltf_Node :: struct {
	name:        string,
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
	normalized:     bool,
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
	gltf:             Gltf,
	bin:              []byte,
	vertices:         [dynamic]Vertex,
	vertex_colors:    [dynamic][4]f32,
	vertex_materials: [dynamic]int,
	// One per vertex when the mesh nodes are skinned.
	influences:       [dynamic]Glb_Influence,
	// One per distinct material, in the order the walk first meets it.
	runs:             [dynamic]Glb_Material_Run,
	// Texture pixels use the caller's retained allocator.
	textures:         [dynamic]Texture,
	texture_keys:     [dynamic]Glb_Texture_Key,
	notes:            Glb_Notes,
	skinned:          bool,
	rigid:            bool,
}

// Named source materials cannot merge, even when their values match.
Glb_Material_Run :: struct {
	slot:     Maybe(int),
	material: Glb_Material,
	indices:  [dynamic]u16,
	part:     Mesh_Data_Part,
}

// Texture variants separate colour space and effective MASK cutoff.
// Missing or excess textures have no slot.
Glb_Texture_Key :: struct {
	index:        int,
	srgb:         bool,
	alpha_cutoff: f32,
	slot:         Maybe(int),
}

// Each texture is the first glTF texture with the same image and sampler,
// so two materials that use the same textures compare equal.
Glb_Material :: struct {
	values:             Material,
	texture:            Maybe(int),
	metallic_roughness: Maybe(int),
	emissive:           Maybe(int),
	normal:             Maybe(int),
	occlusion:          Maybe(int),
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

// Returned data must outlive parse scratch. Failed parses leave no retained allocations.
// Skinned mesh nodes merge in bind-pose space with their Skin and Clips.
glb_parse :: proc(bytes: []byte, allocator: mem.Allocator) -> (data: Mesh_Data, notes: Glb_Notes, err: Glb_Error) {
	// Keep allocator unchanged when the caller passes context.temp_allocator.
	scratch: arenas.Arena
	defer arenas.destroy(&scratch)
	context.temp_allocator = arenas.allocator(&scratch)
	json_chunk, bin := glb_chunks(bytes) or_return

	l := Glb_Loader {
		bin          = bin,
		vertices     = make([dynamic]Vertex, context.temp_allocator),
		vertex_colors = make([dynamic][4]f32, context.temp_allocator),
		vertex_materials = make([dynamic]int, context.temp_allocator),
		influences   = make([dynamic]Glb_Influence, context.temp_allocator),
		runs         = make([dynamic]Glb_Material_Run, context.temp_allocator),
		textures     = make([dynamic]Texture, context.temp_allocator),
		texture_keys = make([dynamic]Glb_Texture_Key, context.temp_allocator),
	}
	if json.unmarshal(json_chunk, &l.gltf, allocator = context.temp_allocator) != nil {
		return {}, {}, .Bad_Json
	}
	if len(l.gltf.skins) > 1 {
		return {}, {}, .Two_Skins
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
	indices, parts, parts_err := glb_parts(&l, allocator)
	if parts_err != .None {
		for tex in l.textures {
			texture_delete(tex, allocator)
		}
		return {}, {}, parts_err
	}
	data = {
		vertices   = slice.clone(l.vertices[:], allocator),
		influences = slice.clone(influences, allocator),
		indices    = slice.clone(indices, allocator),
		textures   = slice.clone(l.textures[:], allocator),
		parts      = slice.clone(parts, allocator),
		skin       = skin_clone(skin, allocator),
		material_slots = glb_material_slots(&l, allocator),
		vertex_colors = slice.clone(l.vertex_colors[:], allocator),
		vertex_materials = slice.clone(l.vertex_materials[:], allocator),
	}
	return data, l.notes, .None
}

// Lays the runs out by alpha mode, each mode in walk order, so each part is
// one range of the index buffer. Indices and parts use parse scratch;
// textures use the retained allocator.
glb_parts :: proc(l: ^Glb_Loader, allocator: mem.Allocator) -> (indices: []u16, parts: []Mesh_Data_Part, err: Glb_Error) {
	// Textures take their slots in walk order, so the texture limit drops the
	// last textures the walk meets, whatever their part's alpha mode.
	for &run in l.runs {
		run.part = glb_part(l, &run, allocator) or_return
		run.part.slot = run.slot
	}
	slice.stable_sort_by(l.runs[:], proc(a, b: Glb_Material_Run) -> bool {
		return a.material.values.alpha_mode < b.material.values.alpha_mode
	})
	all := make([dynamic]u16, 0, len(l.vertices), context.temp_allocator)
	parts = make([]Mesh_Data_Part, len(l.runs), context.temp_allocator)
	for run, i in l.runs {
		parts[i] = run.part
		parts[i].first = len(all)
		parts[i].count = len(run.indices)
		append(&all, ..run.indices[:])
	}
	return all[:], parts, .None
}

// The part's material and texture slots, without its range.
glb_part :: proc(l: ^Glb_Loader, run: ^Glb_Material_Run, allocator: mem.Allocator) -> (part: Mesh_Data_Part, err: Glb_Error) {
	material := run.material
	part = {
		material           = material.values,
		texture            = glb_texture_slot(l, material.texture, srgb = true, allocator = allocator, alpha_cutoff = glb_mask_texture_cutoff(l, run)) or_return,
		metallic_roughness = glb_texture_slot(l, material.metallic_roughness, srgb = false, allocator = allocator) or_return,
		emissive           = glb_texture_slot(l, material.emissive, srgb = true, allocator = allocator) or_return,
		normal             = glb_texture_slot(l, material.normal, srgb = false, allocator = allocator) or_return,
		occlusion          = glb_texture_slot(l, material.occlusion, srgb = false, allocator = allocator) or_return,
	}
	if part.normal == nil {
		part.material.normal_scale = 0
	}
	if part.occlusion == nil {
		part.material.occlusion_strength = 0
	}
	return part, .None
}

// A varying vertex alpha has no single texture threshold to preserve.
glb_mask_texture_cutoff :: proc(l: ^Glb_Loader, run: ^Glb_Material_Run) -> f32 {
	cutoff := run.material.values.alpha_cutoff
	if run.material.values.alpha_mode != .Mask || cutoff <= 0 || len(run.indices) == 0 {
		return 0
	}
	alpha := l.vertices[run.indices[0]].color.w
	if alpha <= 0 || cutoff > alpha { return 0 }
	for index in run.indices {
		if l.vertices[index].color.w != alpha { return 0 }
	}
	return cutoff / alpha
}

// A primitive with no material is matte. glTF gives a material without
// factors a roughness and a metallic of 1. An unknown alphaMode is opaque.
glb_material :: proc(l: ^Glb_Loader, index: Maybe(int)) -> Glb_Material {
	m, ok := index.?
	if !ok {
		return {values = MATERIAL_MATTE}
	}
	gltf_material := &l.gltf.materials[m]
	if gltf_material.extensions.transmission != nil {
		l.notes += {.Transmission_Ignored}
	}
	pbr := &gltf_material.pbr
	material := Glb_Material {
		values = {
			roughness = clamp(pbr.roughness_factor.? or_else 1, 0, 1),
			metallic = clamp(pbr.metallic_factor.? or_else 1, 0, 1),
			unlit = gltf_material.extensions.unlit != nil,
		},
	}
	switch gltf_material.alpha_mode {
	case "MASK":
		material.values.alpha_mode = .Mask
		material.values.alpha_cutoff = gltf_material.alpha_cutoff.? or_else 0.5
	case "BLEND":
		material.values.alpha_mode = .Blend
	}
	// Blender writes doubleSided true by default, so an Opaque part always culls back faces.
	material.values.double_sided = gltf_material.double_sided && material.values.alpha_mode != .Opaque
	if ref, textured := pbr.base_color_texture.?; textured {
		material.texture = glb_texture_ref(l, ref)
	}
	if ref, textured := pbr.metallic_roughness_texture.?; textured {
		material.metallic_roughness = glb_texture_ref(l, ref)
	}
	if ref, textured := gltf_material.normal_texture.?; textured {
		material.normal = glb_texture_ref(l, ref)
		material.values.normal_scale = ref.scale.? or_else 1
	}
	if ref, textured := gltf_material.occlusion_texture.?; textured {
		material.occlusion = glb_texture_ref(l, ref)
		material.values.occlusion_strength = clamp(ref.strength.? or_else 1, 0, 1)
	}
	factor := gltf_material.emissive_factor.? or_else {}
	strength: f32 = 1
	if ext, has_strength := gltf_material.extensions.emissive_strength.?; has_strength {
		strength = ext.strength.? or_else 1
	}
	for &c in factor {
		c = clamp(c, 0, 1) * max(strength, 0)
	}
	material.values.emissive = factor
	if ref, textured := gltf_material.emissive_texture.?; textured {
		material.emissive = glb_texture_ref(l, ref)
	}
	return material
}

// Every texture samples the first UV set.
glb_texture_ref :: proc(l: ^Glb_Loader, ref: Gltf_Texture_Ref) -> int {
	if ref.tex_coord != 0 {
		l.notes += {.Second_Uv_Ignored}
	}
	return glb_first_texture(l, ref.index)
}

// Blender writes one glTF texture for each material that uses an image, so
// textures that name the same image and sampler decode as one.
glb_first_texture :: proc(l: ^Glb_Loader, index: int) -> int {
	if index < 0 || index >= len(l.gltf.textures) {
		return index
	}
	t := l.gltf.textures[index]
	if t.source == nil {
		return index
	}
	for other, i in l.gltf.textures[:index] {
		if other.source == t.source && other.sampler == t.sampler {
			return i
		}
	}
	return index
}

// The slot in l.textures of the glTF texture in this colour space, decoding
// it the first time a part names it. A texture that cannot draw takes no
// slot. Past MESH_TEXTURE_LIMIT, a texture still decodes, so it gets the
// same checks and notes, and then the part gets none.
glb_texture_slot :: proc(l: ^Glb_Loader, index: Maybe(int), srgb: bool, allocator: mem.Allocator, alpha_cutoff: f32 = 0) -> (slot: Maybe(int), err: Glb_Error) {
	i, named := index.?
	if !named {
		return nil, .None
	}
	for key in l.texture_keys {
		if key.index == i && key.srgb == srgb && key.alpha_cutoff == alpha_cutoff {
			return key.slot, .None
		}
	}
	if tex, ok := (glb_texture(l, i, srgb, allocator, alpha_cutoff) or_return).?; ok {
		if len(l.textures) == MESH_TEXTURE_LIMIT {
			texture_delete(tex, allocator)
			l.notes += {.Too_Many_Textures}
		} else {
			slot = len(l.textures)
			append(&l.textures, tex)
		}
	}
	append(&l.texture_keys, Glb_Texture_Key{index = i, srgb = srgb, alpha_cutoff = alpha_cutoff, slot = slot})
	return slot, .None
}

// The primitives with this material so far, or a new empty run.
glb_material_run :: proc(l: ^Glb_Loader, material: Glb_Material, source: Maybe(int)) -> ^Glb_Material_Run {
	slot: Maybe(int)
	if index, ok := source.?; ok && l.gltf.materials[index].name != "" {
		slot = index
	}
	for &run in l.runs {
		if run.material == material && run.slot == slot {
			return &run
		}
	}
	append(&l.runs, Glb_Material_Run{slot = slot, material = material, indices = make([dynamic]u16, context.temp_allocator)})
	return &l.runs[len(l.runs) - 1]
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
	return linalg.matrix4_translate_f32(t) * linalg.matrix4_from_quaternion_f32(key_rotation(r)) * linalg.matrix4_scale_f32(s)
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
	tangents: Glb_View
	tangent_index, has_tangent := p.attributes["TANGENT"]
	if has_tangent {
		tangents = glb_accessor(l, tangent_index, "VEC4") or_return
		if tangents.component_type != GLTF_F32 || tangents.count != count {
			return .Bad_Accessor
		}
	}
	colors: Glb_View
	color_index, has_color := p.attributes["COLOR_0"]
	if has_color {
		colors = glb_color_accessor(l, color_index) or_return
		if colors.count != count { return .Bad_Accessor }
	}
	if skinned {
		glb_add_influences(l, p, count) or_return
	}

	color := GREY
	normal_mapped := false
	if m, ok := p.material.?; ok {
		if m < 0 || m >= len(l.gltf.materials) {
			return .Bad_Material
		}
		color = l.gltf.materials[m].pbr.base_color_factor.? or_else {1, 1, 1, 1}
		normal_mapped = l.gltf.materials[m].normal_texture != nil
	}
	run := glb_material_run(l, glb_material(l, p.material), p.material)

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
		tangent := GLB_PLACEHOLDER_TANGENT
		if has_tangent {
			tangent = glb_read_vec4(tangents, i)
			tangent.xyz = linalg.normalize0(basis * tangent.xyz)
			// A mirroring transform flips the handedness.
			if mirrored {
				tangent.w = -tangent.w
			}
		}
		vertex_color := [4]f32{1, 1, 1, 1}
		if has_color { vertex_color = glb_read_color(l, color_index, colors, i) }
		append(&l.vertex_colors, vertex_color)
		append(&l.vertex_materials, p.material.? or_else -1)
		append(
			&l.vertices,
			Vertex {
				pos = (world * [4]f32{pos.x, pos.y, pos.z, 1}).xyz,
				color = color * vertex_color,
				normal = linalg.normalize0(normal_matrix * nrm),
				uv = uv,
				tangent = tangent,
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
	first_index := len(run.indices)
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
		append(&run.indices, u16(base + index))
	}
	if normal_mapped && !has_tangent {
		glb_lengyel_tangents(l.vertices[base:], run.indices[first_index:], base)
		l.notes += {.Generated_Tangents}
	}
	return .None
}

// Works from the placed positions, so a mirroring node needs no w flip. Each
// index in triangles is base more than its vertex's place in vertices.
glb_lengyel_tangents :: proc(vertices: []Vertex, triangles: []u16, base: int) {
	// Per vertex: the sum of dP/du, and the sum of -dP/dv, which points up the
	// image as glTF's bitangent does.
	sums := make([][2][3]f32, len(vertices), context.temp_allocator)
	for i := 0; i < len(triangles); i += 3 {
		corners := [3]int{int(triangles[i]) - base, int(triangles[i + 1]) - base, int(triangles[i + 2]) - base}
		a, b, c := vertices[corners[0]], vertices[corners[1]], vertices[corners[2]]
		e1, e2 := b.pos - a.pos, c.pos - a.pos
		d1, d2 := b.uv - a.uv, c.uv - a.uv
		det := d1.x * d2.y - d2.x * d1.y
		if abs(det) < 1e-12 {
			continue
		}
		du := (e1 * d2.y - e2 * d1.y) / det
		dv := (e2 * d1.x - e1 * d2.x) / det
		for corner in corners {
			sums[corner][0] += du
			sums[corner][1] -= dv
		}
	}
	for &v, i in vertices {
		n := v.normal
		sum, up := sums[i][0], sums[i][1]
		t := sum - n * linalg.dot(n, sum)
		length := linalg.length(t)
		if length <= 1e-4 * linalg.length(sum) {
			v.tangent = glb_any_tangent(n)
			continue
		}
		t /= length
		w: f32 = 1 if linalg.dot(linalg.cross(n, t), up) >= 0 else -1
		v.tangent = {t.x, t.y, t.z, w}
	}
}

// For a vertex whose UVs give no direction.
glb_any_tangent :: proc(n: [3]f32) -> [4]f32 {
	axis := [3]f32{1, 0, 0} if abs(n.x) < 0.9 else [3]f32{0, 1, 0}
	t := linalg.normalize(axis - n * linalg.dot(n, axis))
	return {t.x, t.y, t.z, 1}
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
glb_texture :: proc(l: ^Glb_Loader, index: int, srgb: bool, allocator: mem.Allocator, alpha_cutoff: f32 = 0) -> (tex: Maybe(Texture), err: Glb_Error) {
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
		// Each PNG releases its decoder scratch after retained pixels are copied.
		scratch: arenas.Arena
		defer arenas.destroy(&scratch)
		context.temp_allocator = arenas.allocator(&scratch)
		width, height, rgba, ok := png_decode(bytes)
		if !ok {
			l.notes += {.Bad_Png}
			return nil, .None
		}
		return texture_build(width, height, rgba, sampler, srgb, allocator, alpha_cutoff), .None
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

// Source indices identify slots independently of walk order and alpha sorting.
glb_material_slots :: proc(l: ^Glb_Loader, allocator: mem.Allocator) -> []Mesh_Material_Slot {
	slots := make([]Mesh_Material_Slot, len(l.gltf.materials), allocator)
	for material, i in l.gltf.materials {
		slots[i] = {name = strings.clone(material.name, allocator), source_material = i,
			base_color_factor = material.pbr.base_color_factor.? or_else {1, 1, 1, 1}}
	}
	return slots
}

glb_color_accessor :: proc(l: ^Glb_Loader, index: int) -> (view: Glb_View, err: Glb_Error) {
	if index < 0 || index >= len(l.gltf.accessors) { return {}, .Bad_Accessor }
	a := &l.gltf.accessors[index]
	if a.type != "VEC3" && a.type != "VEC4" { return {}, .Bad_Accessor }
	view = glb_accessor(l, index, a.type) or_return
	switch view.component_type {
	case GLTF_F32:
		if a.normalized { return {}, .Bad_Accessor }
	case GLTF_U8, GLTF_U16:
		if !a.normalized { return {}, .Bad_Accessor }
	case:
		return {}, .Bad_Accessor
	}
	return view, .None
}

glb_read_color :: proc(l: ^Glb_Loader, index: int, view: Glb_View, vertex: int) -> [4]f32 {
	color := [4]f32{1, 1, 1, 1}
	components := 3 if l.gltf.accessors[index].type == "VEC3" else 4
	bytes := view.data[vertex * view.stride:]
	for i in 0 ..< components {
		switch view.component_type {
		case GLTF_F32:
			color[i], _ = endian.get_f32(bytes[i * 4:], .Little)
		case GLTF_U8:
			color[i] = f32(bytes[i]) / 255
		case GLTF_U16:
			value, _ := endian.get_u16(bytes[i * 2:], .Little)
			color[i] = f32(value) / 65535
		}
	}
	return color
}
