# Shader loader handoff

Read [the authoring guide](GAME-SHADERS.md) and [package contract](SHADER-CONTRACT.md).
Use `platform/shader-tools/contract-v1/` as the published production wrapper.
The reference proof is a separate binding fixture.
The production compiler does not depend on the proof parser or engine source.

`platform/Shader.roc` defines public `Asset`, `Values`, `Slot`, and `SlotAssignment` records.
Expose these shapes through the Scene, Material, Draw, and Post APIs.
A `Values` record names a Pack asset and one scope.
Its parameter tags preserve numeric type information.
Its texture tags preserve dimension information.
An omitted parameter uses the declaration default.
An omitted texture uses the declaration default source.
Reject unknown names, duplicate assignments, wrong types, wrong scopes, and nonfinite components before encoding.

Scan `assets/shaders/*.shaderpack` under the `shader/NAME` asset namespace.
Read package headers and manifest metadata before creating GPU resources.
The JSON manifest retains the version 1 `interface.surface`, `interface.post`, and backend `shaders` shape.
Only one interface kind contains active declarations in each asset.
Surface records also contain explicit `skinning` and `instancing` booleans.
Reject missing required programs for the enabled layouts.
Post records list their compiled locations and input dependencies.
`build.json` is development output, not the authoritative runtime package.

The package preserves compiler resource names, logical slots, physical backend mappings, stages, types, sizes, and flattened GL uniforms.
Source functions contain payload offsets and sizes instead of filesystem paths.
The checksum and interface fingerprint follow the package contract's canonical encoding.
The GL storage transform updates source declarations and reflected bindings together.
Use reflected physical mappings for Metal and D3D.
Do not derive physical texture registers from logical slots.

| Uniform slot | Production block | Bytes |
| --- | --- | --- |
| 0 | `engine_vertex`: MVP, model, inverse-transpose model, render_time, draw_info, camera, reserved_vertex | 256 |
| 1 Surface | `fs_params`: tint, material, emissive, glow, maps | 80 |
| 1 Post | `engine_post`: viewport, frame, reserved_post[6] | 128 |
| 2 | `fs_lights`: seven vectors, four cascade matrices, four Directional positions, four Directional colours, cluster_grid | 512 |
| 3 | `engine_skin`: joints[64] | 4096 |
| 4 | `game_vertex`: vertex_values[16] | 256 |
| 5 | `game_fragment`: fragment_values[16] | 256 |

`render_time.x` carries simulation-derived seconds.
`draw_info` is an engine-supplied stable Draw vector.
The wrapper exposes it unchanged to vertex hooks.
All related passes must use the same vector.
The initial loader can reserve unused components as zero.
`camera` and `reserved_vertex` are reserved engine vertex data.
`Vertex.world_position` snapshots the posed world position before the authored vertex hook.
`Vertex.world_origin` holds the resolved model's world origin.
The wrapper derives both values from the instance model or the rigid/skinned uniform model without adding GPU resources.
All three related passes share these inputs and the same vertex program.

`tint` contains resolved imported base RGBA multiplied by the Draw tint.
For instancing, upload the imported base RGBA here and the Draw tint in the instance stream.
The vertex attribute must contain raw `Mesh.vertex_colors`, not the factored `Vertex.color` stream.
Use `Mesh.vertex_materials` to resolve imported base factors when unnamed source materials share a part.
Do not apply the imported factor twice.
Do not replace unspecified imported properties or textures.
`material` is roughness, metallic, unlit flag, and alpha cutoff.
`emissive` and `glow` preserve the existing engine conventions.
`maps.xy` is normal scale and occlusion strength.
`maps.z` selects alpha policy: 0 Opaque, 1 Mask, 2 Blend.
`maps.w` is reserved.
Colour Blend premultiplies diffuse coverage while retaining specular and emission.
Shadow and selection discard only Mask fragments.
Blend selection retains full-shape coverage.

The seven lighting vectors are ambient, camera_pos, shadow, cascade_far, view_dir, fog_color, and fog_ramp.
`ambient.w` stores the Directional count.
The first Directional is the Sun.
`view_dir.xyz` stores unit camera forward.
The remaining lighting layout matches `engine/shaders/basic.glsl` from the clustered-light implementation.
`cluster_grid` stores `(16/width, 9/height, 24/ln(far/near), near)`.
Use the production storage records and slots:

| Logical slot | Block | Record |
| --- | --- | --- |
| 12 | `engine_points` | `Point { vec4 pos; vec4 color; }`, 32 bytes |
| 13 | `engine_clusters` | `Cluster { uvec4 range; }`, 16 bytes |
| 14 | `engine_indices` | `LightIndices { uvec4 ids; }`, 16 bytes |

Cluster range xy stores a scalar index offset and count.
Scalar index n is `indices[n/4].ids[n%4]`.
Point colour w stores range.
GL storage bindings are compact 0, 1, and 2.
The buffers remain readonly fragment resources.
The Sun comparison sample runs before the variable cluster loop and hook-controlled unlit branch for D3D derivative safety.

Post `viewport` stores width, height, reciprocal width, and reciprocal height.
Post `frame.x` stores the same simulation render time.
Other Post frame components and reserved vectors are zero.
Post views 0 through 3 match the declared scene colour, scene depth, selection coverage, and selection depth semantics.
All Post input samplers use regular float sampling.
Surface shadow slot 2 uses an array depth texture and a comparison sampler.
Other reserved Surface sampled slots retain the package contract's imported material and environment meanings.

| Layout | Vertex inputs |
| --- | --- |
| Rigid | Slots 0–4: FLOAT3 position, FLOAT4 raw colour, FLOAT3 normal, FLOAT2 UV, FLOAT4 tangent |
| Skinned | Rigid inputs, slot 5 UBYTE4 joint ids, slot 6 FLOAT4 normalized joint weights |
| Instanced | Rigid inputs, slots 5–8 FLOAT4 model columns, slots 9–11 FLOAT3 inverse-transpose normal columns, slot 12 FLOAT4 linear tint |

The instance stream uses per-instance stepping.
One natural packed record has 116 bytes: 64 model bytes, 36 normal bytes, and 16 tint bytes.
The shader accepts other strides when the descriptor supplies correct offsets.
The instanced MVP uniform stores view-projection without an instance model.
The instance model supplies the full local-to-world transform.
Instance normal columns supply its inverse-transpose linear transform.
Rigid and skinned MVP uniforms retain the existing model-inclusive convention.

Batch keys must include game numeric values, texture references, material state, and `draw_info`.
Model, normal, and tint are the only values that vary within a batch.
Different arbitrary Draw parameters require separate batches.
A skin pose cannot join this rigid instanced layout.
Culling and selection identity remain host responsibilities.
Batch only instances eligible for that pass.
All nine programs share the same authored deformation and opacity hooks.

The package records actual active resources for each program.
Upload only reflected blocks and bind only reflected resources.
Reserve each applied block at 256-byte alignment.
Account for all reflected GL components, including the complete skin palette.
A thirteen-attribute instance layout stays below GL's sixteen-attribute minimum.
Do not increase the three fragment storage slots for instancing.
Retain all related pass variants atomically during reload.
A missing or incompatible Surface omits affected parts in every related pass.
Do not substitute the built-in shader after a load failure.

`native.py` compiles and decodes production packages independently of the runtime loader.
Its C descriptors use each backend's reflected resource mappings.
Its native harness creates pipelines, binds resources, and draws all eleven variants for three frames.
The instance programs draw two instance records.
GPU selection readback verifies resolved world inputs for rigid, skinned, and both instance records.
The native fixture adds the check to a copy of the authored vertex hook.
GPU readback tests outline edges over nonzero floor and wall depths.
It checks both visible-only and through-wall policies.
CI uploads `build/shader-assets-native/native-evidence.json` with per-package hashes and backend logs.
Production Metal execution passed locally on 2026-11-05.
Production GL and D3D execution remains pending CI.
The previous eight-program reference proof passed all three backends in CI run 41955851562.
