# Shader asset contract, version 1

Date: 2026-11-05.
Status: executable package reference and public compiler; engine integration follows.
[ADR 0028](adr/0028-game-shaders-are-pack-assets.md) owns the authoring decisions.
[The immersive scope](IMMERSIVE-SCENE.md) owns the village requirements.

The compiler, Surface integration, Post integration, and reload work must use this contract.
The reference code lives in `scripts/shader_contract/`.
The public compiler lives in `platform/shader-tools/`.
[The authoring guide](GAME-SHADERS.md) defines its supported declarations and hooks.
[The loader handoff](SHADER-LOADER-HANDOFF.md) records its production layouts.
It does not add a Shader loader to the engine.

## Reproduce the proof

Run these commands from the repository root:

```sh
python3 scripts/shader_contract/install.py
python3 scripts/shader_contract/contract.py --shdc build/shader-tools/sokol-shdc --check --run
python3 -m unittest scripts/test_shader_contract.py
```

On Windows, use `python` and `build/shader-tools/sokol-shdc.exe`.
On Linux, use Xvfb with `LIBGL_ALWAYS_SOFTWARE=1` when no display exists.
The native proof requires the initialized `sokol-odin` submodule and a C compiler.
Use `--sokol PATH` to select another checkout of the pinned submodule.
Use `--shdc PATH` to select an existing compiler.

The installer uses `floooh/sokol-tools-bin` commit `11d0cf678105d614d675e6d9bd2aaf3eeff12f8c`.
`compiler.json` records each distributed binary's SHA-256 checksum.
The proof rejects other binaries.
The command uses `bare_yaml` with `metal_macos:glsl430:hlsl5`.
It does not request native bytecode.

The build writes these files under `build/shader-contract/`:

| File | Purpose |
| --- | --- |
| `proof_*` sources | Exact compiler output for eight programs and three backends |
| `proof_reflection.yaml` | Exact compiler reflection |
| `manifest.json` | Normalized package metadata |
| `proof.shaderpack` | Versioned package with all backend sources |
| `proof_bindings.h` | Native descriptors generated from the decoded package |
| `evidence.json` | Output checksums and resource budgets |
| `invalid-source.log` | Source filename, line, and compiler error |
| `native.log` | Device limits and native binding result |
| `native-evidence.json` | Native result and package checksum |

`expected.json` records output checksums and budgets for comparison.
It excludes host-specific device results.
Proof checksums normalize CRLF to LF for `.yaml`, `.glsl`, `.hlsl`, `.metal`, and `.h` evidence.
This normalization changes hashes only; the build keeps raw compiler output bytes.
The generated `proof_bindings.h` uses LF on every host.
Use `--check` to compare every expected checksum.
Use the default output path for exact reproduction.
Changing `--out` changes raw reflection paths and its checksum.

The fixture has rigid and skinned colour, shadow, and selection programs.
It also has HDR and LDR Post programs.
The Surface programs share deformation and alpha functions.
The Post programs can compare selection depth with scene depth or ignore that comparison.
The native harness creates eight shaders and pipelines from decoded package metadata.
It binds uniforms, sampled images, samplers, and three clustered-light buffers.
It submits each program for three frames and rejects graphics validation errors.
The harness tests HDR and LDR attachments and separate selection coverage and depth attachments.
It does not test visual parity, the game loader, reload, or published platform bundles.

## Execution evidence

The local Metal proof passed on 2026-11-05.
Sokol exposed 16 attributes, 32 texture bindings per stage, and 15 storage bindings per stage.
Metal does not report a GL uniform component limit.
The package tests passed.
All eight programs cross-compiled for each of the three targets.

The native proof passed on all three backends in [CI run 41955851562](https://github.com/Pixelsprout/rocco-engine/actions/runs/41955851562).
Each backend created, bound, and drew all eight variants for three frames.
The uploaded `native-evidence.json` files report the same package SHA-256:

```text
55b625ac3d9eb04a2269125136afe1a51ea3bc7675057a1dc199c0db93d8f4ce
```

| Backend | Attributes | Texture bindings per stage | Storage bindings per stage |
| --- | --- | --- | --- |
| Metal | 16 | 32 | 15 |
| GL | 16 | 32 | 32 |
| D3D11 | 16 | 32 | 32 |

The GL host reported 16,384 vertex and fragment uniform components and 80 storage binding points.
It reported 16 fragment storage blocks, 32 vertex textures, and 192 combined texture units.
These measured host limits do not replace the contract's portable limits.
The Linux job uses Mesa software rendering.
The Windows job can use WARP through Sokol's existing device fallback.
Later build-script expectation failures made that CI run fail after the native proofs passed.
The village checks on the reference machines remain separate.

## Package header

All integers use little-endian encoding.
The fixed header contains 96 bytes.
The manifest immediately follows the header.
The source payload immediately follows the manifest.
Format 2 has no compression, trailing data, native pointers, or host enum numbers.

| Offset | Size | Field | Required value |
| --- | --- | --- | --- |
| 0 | 8 | Magic | ASCII `RCSHADER` |
| 8 | 2 | Format version | `2` |
| 10 | 2 | Platform contract version | `1` |
| 12 | 4 | Header bytes | `96` |
| 16 | 4 | Manifest bytes | At most 1,048,576 |
| 20 | 4 | Source payload bytes | At most 16,777,216 |
| 24 | 4 | Flags | `0` |
| 28 | 4 | Backend mask | `15`: GL bit 0, D3D bit 1, Metal bit 2, WGSL bit 3 |
| 32 | 32 | Interface fingerprint | SHA-256 described below |
| 64 | 32 | Content checksum | SHA-256 of manifest followed by source payload |

The manifest uses UTF-8 JSON without whitespace.
Object keys use sorted order.
Numbers must be finite.
The format uses the reference `canonical()` encoding for hashes.
Future encoders must reproduce those bytes.

The manifest records the compiler commit, backend transform, declarations, and each backend's reflected programs.
Each stage records `offset`, `size`, `entry_point`, and `is_binary=false`.
HLSL stages also record `d3d11_target`, such as `vs_5_0`.
Offsets address the source payload.
Sources use UTF-8 without embedded NUL bytes.
The loader adds a NUL terminator when an API requires one.
The package does not store compiler output paths.
The manifest lists the backends in the order `glsl430`, `hlsl5`, `metal_macos`, `wgsl`.
WGSL binds each uniform block in group 0 at its slot.
WGSL binds each texture and storage buffer in group 1 at its slot, and each sampler in group 1 at 32 plus its slot.

The fingerprint covers declarations and each backend's program names, attributes, blocks, views, samplers, and texture/sampler pairs.
It includes parameter types, scopes, offsets, defaults, texture roles, Post inputs, Post locations, and displacement bounds.
It excludes source bytes, source offsets, and compiler-generated `inst_name` identifiers.
A source edit can therefore preserve the fingerprint.
A declaration or binding change requires a game rebuild and restart.

Reject an unknown version, backend mask, flag, checksum, fingerprint, or resource requirement before creating GPU objects.
Format 1 packages hold no WGSL backend.
The runtime rejects them with a message to rebuild them with the current shader tools.
Check lengths with overflow-safe arithmetic before allocating or reading sections.
Reject truncated packages and trailing bytes.
Validate every source range and UTF-8 string.
Validate reflected slots, stages, types, sizes, and backend mappings against the published platform contract.
The reference parser reads only the pinned compiler's restricted YAML syntax.
The production packer must reject unsupported reflection rather than guess.

## Parameter values and scopes

A declaration gives each parameter a unique name, type, scope, stage, offset, and default.
Names use `[a-z][a-z0-9_]*`.
A name is unique within its Surface or Post declaration.

| Type | Input components | Encoded bytes | Encoding |
| --- | --- | --- | --- |
| `F32` | 1 | 16 | One float, then three zero floats |
| `Vec2` | 2 | 16 | Two floats, then two zero floats |
| `Vec3` | 3 | 16 | Three floats, then one zero float |
| `Vec4` | 4 | 16 | Four floats |
| `Colour` | 4 | 16 | Linear RGBA floats |
| `Bool` | 1 | 16 | `false` becomes 0; `true` becomes 1; remaining floats are zero |
| `Mat4` | 16 | 64 | Four column-major float vectors |

Version 1 does not expose integer, string, array, or nested-record parameters.
Texture references use separate declarations.
Numeric components use IEEE-754 binary32.
Each parameter starts at a 16-byte boundary.
Parameters cannot overlap or exceed their stage's 256-byte game block.
A matrix consumes four of the 16 available vector lanes.
Other types consume one lane.
The build assigns offsets in declaration order.
The manifest stores the resulting offsets explicitly.

Reject NaN, infinity, overflow, wrong component counts, unknown names, duplicate assignments, and wrong types.
Reject invalid defaults during the asset build.
Reject invalid runtime assignments before encoding the value.
Do not clamp, reinterpret, or substitute an invalid assignment.
Omitted assignments use the declared default.

| Scope | Surface source | Post source |
| --- | --- | --- |
| Scene | Scene values for this Shader | Scene values for this Shader |
| Material | Resolved Material for this named Mesh slot | Not available |
| Draw | Values on this Draw | Values on this Post effect instance |

Each parameter has one scope.
A Draw assignment cannot silently override a Scene parameter.
A declaration can expose separate parameters when both controls are needed.
All three scopes can coexist in one stage block.
The host merges their resolved values before each submit.
Scope does not create another GPU block.
A parameter used in both stages has separate reflected fields and consumes capacity in both blocks.
Post parameters use the fragment stage.

## Reserved bindings

These are logical Sokol slots across the whole program.
A slot has one resource kind and one stage within a program.
Sharing an image between stages requires separate view and sampler declarations.
Unused slots have no reflected binding and require no dummy upload.
Authors cannot declare resources in engine slots.

| Uniform slot | Owner | Size ceiling | Purpose |
| --- | --- | --- | --- |
| 0 | Engine | 256 | Vertex transforms, simulation render time, Draw and camera data |
| 1 | Engine | 128 | Resolved Material values; frame data for Post programs |
| 2 | Engine | 512 | Lighting, shadow transforms, and environment data |
| 3 | Engine | 4,096 | Existing 64-joint skin palette |
| 4 | Game | 256 | Merged vertex parameters |
| 5 | Game | 256 | Merged fragment parameters |
| 6–7 | Engine | Unavailable in version 1 | Future engine blocks |

Uniform slot 0 starts with MVP, model, and inverse-transpose model matrices, followed by four vectors.
The first vector carries simulation-derived render time in seconds in `x`.
Every related pass receives the same render time and Draw data.
The budgets include the current renderer's light and cascade values.
They also reserve room for clustered-light grid and environment metadata.
The Surface integration must publish member names and semantic helpers within these budgets.
`Vertex.world_to_local_direction` exposes `transpose(mat3(world_normal))` from the resolved inverse-transpose normal basis.
It converts world vectors into posed mesh-local vectors without another uniform or binding.
Rigid and skinned Draws use the uniform basis; instanced Draws use the instance basis.
The conversion excludes translation and does not undo skinning.
A zero-scale transform has no exact inverse.
`max_displacement` remains the maximum local offset length after conversion.
Authors must cover inverse scale in that bound or limit the converted local offset.
The fixture's lighting multiplication tests bindings; it does not implement the engine's final lighting response.

| View or sampler slot | Surface role | Post role |
| --- | --- | --- |
| 0 | Imported base colour | Scene colour |
| 1 | Imported metallic/roughness | Scene depth |
| 2 | Sun shadow array and comparison sampler | Selection coverage |
| 3 | Imported emissive | Selection depth |
| 4 | Imported normal | Reserved |
| 5 | Imported occlusion | Reserved |
| 6 | Diffuse cubemap environment | Reserved |
| 7 | GGX specular cubemap environment | Reserved |
| 8–11 | Four declared game textures and samplers | Four declared game textures and samplers |
| 12 | Clustered Point-light storage view | Reserved |
| 13 | Cluster range storage view | Reserved |
| 14 | Packed light-index storage view | Reserved |
| 15–31 | Reserved engine views | Reserved |

Storage views have no sampler.
Storage views 12–14 are readonly fragment inputs.
The pinned compiler requires exactly one flexible array of a struct in each storage block.
The fixture proves 32-byte Point records and 16-byte cluster and index records.
The clustered-light implementation can refine record contents within its engine contract.
It must preserve the reserved slots.

The clustered path supports 1,024 Points and 64 indices per cluster.
For a 16 × 9 × 24 grid, padded range records consume 55,296 bytes.
Packed 32-bit indices consume at most 884,736 bytes.
The fixture's Point layout consumes 32,768 bytes for 1,024 Points.
The three buffers therefore require 972,800 bytes before resource overhead.
The host must also count their buffers, views, upload copies, and frame lifetime.

Backend physical bindings come from reflection.
Never derive a texture register from its logical slot.
The proof maps logical texture 9 to a different HLSL or Metal texture number.
Uniform bindings and sampler numbers retain their explicit indices with this compiler.
Metal maps storage views 12–14 to buffer indices 8–10.
HLSL allocates readonly storage resources in the texture register namespace.

The package applies `gl_ssbo_compact_v1` to the compiler's GL storage declarations.
It maps logical views 12–14 to physical GL storage binding points 0–2.
The transform requires exactly one matching declaration for each reflected block name and original binding.
It updates source and reflected `glsl_binding_n` together.
It rejects a missing or ambiguous match.
It preserves sampled texture bindings, which use a separate GL namespace.
Raw compiler files remain unchanged for reproducibility.
The package fingerprint and checksum cover the transformed layout and code.

## Production clustered PBR layout

[ADR 0033](adr/0033-clustered-forward-lights.md) replaces the per-Draw Point list.
The built-in shader uses the following exact engine fragment blocks.
Every member starts at a 16-byte boundary.

| Slot | Block | Members in byte order | Bytes |
| --- | --- | --- | --- |
| 1 | `fs_params` | `tint`, `material`, `emissive`, `glow`, `maps`, `environment_params`, each `vec4` | 96 |
| 2 | `fs_lights` | Seven `vec4`: `ambient`, `camera_pos`, `shadow`, `cascade_far`, `view_dir`, `fog_color`, `fog_ramp`; `mat4 light_view_proj[4]`; `vec4 directional_pos[4]`; `vec4 directional_color[4]`; `vec4 cluster_grid` | 512 |

`ambient.w` holds the Directional count, from zero through four.
The Sun occupies Directional slot zero when present.
`view_dir.xyz` always holds the camera's unit forward vector.
`cluster_grid` holds `16 / physical_width`, `9 / physical_height`, `24 / ln(far / near)`, and `near`.
The near depth is 0.1 units.
The far depth includes every accepted Point sphere and is at least 100 units.

The fragment uses camera-forward world depth for the logarithmic slice.
It uses physical fragment coordinates for the tile.
GL tiles count upward; Metal and D3D convert their downward fragment coordinates before tile selection.
The cluster index is `(z * 9 + y) * 16 + x`.
Each axis clamps at the grid boundary.

Storage slot 12 contains `Point { vec4 pos; vec4 color; }` records.
`pos.xyz` is world position, and `pos.w` is one.
`color.xyz` is linear radiance, and `color.w` is range.
Slot 13 contains `Cluster { uvec4 range; }` records.
`range.xy` holds the scalar index offset and count; `range.zw` is zero.
Slot 14 contains `LightIndices { uvec4 ids; }` records.
Scalar index `n` reads `indices[n / 4].ids[n % 4]`.
The final vector uses zero padding.

The renderer owns three storage buffers and three storage views.
Their maximum logical allocation is 972,800 bytes.
Metal's stream buffers retain two backing copies, totaling 1,945,600 bytes before driver overhead.
Other backends can allocate additional driver storage.
The host uploads 55,296 range bytes, up to 32,768 Point bytes, and up to 884,736 index bytes each Frame.
Empty Point and index buffers receive one zero record.
The host compacts indices in place before upload.
The Frame arena also holds the full 884,736-byte index workspace and up to 12,288 bytes of camera-space positions.
Growing gathered light arrays can retain earlier allocations until the Frame ends.

Repeated bindings and equal Material values reuse the active pipeline state.
Pipeline changes invalidate both caches.
Sokol retains uploaded stream data until the corresponding in-flight Frame completes.
The renderer budgets three additional buffer handles and three view handles.
The default mesh buffer budget now includes every mesh slot, UI buffers, and these storage buffers.

## Portable limits and device checks

The pinned Sokol header defines 8 uniform slots, 32 view slots, 12 sampler slots, 32 texture/sampler pairs, and 16 attributes.
Version 1 limits authoring more tightly:

| Resource | Contract ceiling |
| --- | --- |
| Game uniform data | 256 bytes per stage |
| Game texture/sampler declarations | Four across both stages |
| Active sampled images | 12 across both stages |
| Texture/sampler pairs | One per declaration; at most 12 |
| Active storage views | Three, in fragment stage |
| Surface attributes | Five rigid; seven skinned; thirteen rigid instanced |
| Post attributes | Zero; fullscreen triangle uses vertex id |
| Cascades | Four |
| Joints | 64, subject to the GL uniform check below |

The Surface attribute order is position, vertex colour, normal, UV, tangent, joint ids, and joint weights.
The first five use FLOAT3, FLOAT4, FLOAT3, FLOAT2, and FLOAT4.
The rigid instanced layout adds four FLOAT4 model columns, three FLOAT3 inverse-transpose normal columns, and one FLOAT4 tint.
These eight additional attributes use per-instance stepping.
Instancing adds no storage views.
Batch keys retain identical arbitrary Draw parameters, textures, material state, and Draw data.
Only instance model, normal transform, and tint vary within a batch.
Skinned instancing is unavailable in version 1.
Joint ids use unsigned bytes.
Joint weights retain the imported normalized weights.
The fixture uses FLOAT4 weights to exercise the same seven attribute locations.

GL 4.3 guarantees at least 16 attributes, 16 sampled images per stage, and 1,024 default uniform components per stage.
The pinned compiler flattens uniform blocks into float-vector uniforms on GL.
Uniform block size limits therefore do not establish GL capacity.
Count every reflected stage block, including the complete skin array.

The rigid vertex program needs 128 components.
The skinned vertex program needs 1,152 components: `(256 + 256 + 4096) / 4`.
The current engine already exceeds the GL minimum with its 64-joint palette and transforms.
Version 1 preserves that palette size.
The additional game block increases the requirement.
A GL device with only 1,024 components cannot run this skinned variant.
The required village geometry uses the rigid path.

GL 4.3 guarantees eight global storage binding points and eight fragment storage blocks.
The compact GL mapping requires three of each.
The compiler's original binding numbers would require 15 global binding points.
Do not restore those original numbers in the package.

Query actual vertex and fragment uniform limits before creating GL programs.
Query vertex texture, fragment texture, combined texture, attribute, and storage limits.
Sokol's GL texture query alone does not establish every stage's limit.
Validate each variant against its reflected requirements.
Reject an unsupported variant with a clear development log.
Omit affected Mesh parts from related passes when no valid Surface exists.
Do not reduce the joint count, replace the Material, or substitute a shader.

D3D11 permits 14 constant buffers, 16 samplers, and 128 input resources per stage.
The pinned Sokol interface imposes the smaller slot ceilings above.
D3D11 constant buffers use 16-byte size multiples and a 64 KiB ceiling.
Every version 1 block fits those limits.
Metal uses separate buffer, texture, and sampler indices.
The native proof records the limits exposed by Sokol.
CI and reference-machine results establish actual backend support.

## Uniform and pipeline capacity

Reserve `align_up(block_bytes, 256)` for every applied block on every backend.
This covers macOS Metal's 256-byte uniform arena alignment.
Count an upload again when a pipeline change requires reapplication.
Do not count Scene or Material values only once because their values remain constant.

| Proof variant | Aligned bytes per submit | Vertex components | Fragment components | Attributes | Texture views | Storage views |
| --- | --- | --- | --- | --- | --- | --- |
| Rigid colour | 1,536 | 128 | 224 | 5 | 3 | 3 |
| Rigid shadow | 1,024 | 128 | 96 | 5 | 2 | 0 |
| Rigid selection | 1,024 | 128 | 96 | 5 | 2 | 0 |
| Skinned colour | 5,632 | 1,152 | 224 | 7 | 3 | 3 |
| Skinned shadow | 5,120 | 1,152 | 96 | 7 | 2 | 0 |
| Skinned selection | 5,120 | 1,152 | 96 | 7 | 2 | 0 |
| Either Post location | 512 | 0 | 96 | 0 | 4 | 0 |

For `D` rigid colour submits, `S` shadow submits, `Q` selection submits, and `P` Post effects, reserve:

```text
1536*D + 1024*S + 1024*Q + 512*P
```

Add 4,096 bytes for each skinned submit in any Surface pass.
Add built-in sky, bloom, tone map, and UI costs separately.
Count a shadow submit for each cascade.
Use checked arithmetic and reject budgets above the API's signed 32-bit arena size.
The proof reserves 1 MiB and applies 20,480 bytes per frame.

A Surface has nine compiled programs: three passes times rigid, skinned, or rigid instanced layout.
An asset can omit skinned or instanced variants when its declaration excludes that layout.
The original reference fixture retains its six Surface programs and two Post programs.
The production native fixture exercises all nine Surface programs and both Post locations.
A Post has one program for its declared location.
The proof includes both locations.

A pipeline key includes asset generation, pass, vertex layout, alpha policy, cull mode, formats, sample count, and blend state.
Colour supports Opaque, Mask, and Blend policies.
Shadow and selection use solid or cutout coverage policies.
Blend selection uses full-shape coverage, consistent with the existing selection policy.
The three cull states are back, front, and none.

A conservative cache ceiling is `3 * (3*3 + 2*3 + 2*3) = 63` pipelines per Surface generation.
This ceiling covers all three vertex layouts, one main sample count, and fixed pass formats.
Only allocate keys used by the game.
Multiply the ceiling when retaining multiple sample counts or target format sets.
A Post needs one pipeline per target format and sample count.
Count loaded assets, shaders, pipelines, retained generations, texture views, samplers, buffers, and render targets in platform capacity.
During reload, reserve both generations until the old GPU work finishes.
Reject capacity exhaustion before replacing the current generation.

## Surface semantics

The engine wrapper owns entry points, transforms, lighting resources, and pass variants.
Game hooks control local vertex movement, shading normals, surface properties, and lighting response.
The Surface integration must expose all four controls within this resource layout.
Default hooks preserve the built-in PBR result.
An empty hook must preserve imported Material values.

The vertex order is skinning, local game deformation, then world transformation.
The wrapper preserves a geometric normal separately from the game shading normal.
The geometric normal controls geometric operations such as shadow bias.
Normal and tangent transforms preserve inverse-transpose and handedness rules.
Vertex colour remains an independent mesh input.

The author declares a finite, nonnegative maximum displacement in mesh-local units.
The host expands local bounds before applying the Draw transform.
Colour, shadow, and selection call the same deformation and alpha functions.
They use the same skin pose, parameters, textures, seed, and simulation render time.
A shader must not derive animation time from wall-clock time.
A fixed Bridge step must reproduce the pose.

Surface output includes linear base colour, metallic, roughness, emission, opacity, and shading normal.
The lighting hook receives engine lighting inputs and can change the response, including foliage transmission.
The wrapper retains engine light selection, clusters, shadows, and environment access.
The hook cannot create render passes or access undeclared buffers.

A resolved Material begins with its imported textures and scalar properties.
An explicit game override replaces only the named property or texture.
Named Material slots remain stable through import, Material merging, and Mesh part sorting.
[The import contract](GLTF-MATERIAL-SLOTS.md) defines source identities, name errors, raw colours, and metadata lifetime.
A whole-Draw assignment supplies the Draw's Material override.
A named slot assignment takes precedence for that slot.
Unspecified slots keep their imported Materials.

## Texture references and lifetime

A texture declaration gives a name, scope, stage, dimension, sample type, colour space, sampler policy, and default source.
Version 1 permits 2D and cubemap float-sampled game textures.
Game storage resources and writable images are unavailable.
A default source is an explicit Pack asset reference or an imported Material semantic.
An optional declaration can use a declared constant texture default.
The default belongs in the interface fingerprint.
A required texture without a source is invalid.
Do not silently bind a white image after a failed texture load.

A texture reference identifies an asset within a Pack through its stable asset key.
It never contains a GPU handle or a pointer from Roc.
The engine resolves the reference to an owned image, view, and sampler.
The assignment must match dimension, colour space, sample type, and scope.
Colour images sample as linear values through their declared sRGB format.
Normal, roughness, metallic, occlusion, depth, and noise images use linear data formats.
The runtime resolves references through their named live Pack at each frame boundary.
Explicit Pack unload invalidates dependent resolved materials and omits affected parts from every related pass.
Shared assets remain valid for references through other live Packs.
Retired GPU resources remain protected until in-flight use ends.
A failed reload must retain the previous shader and its texture dependencies unless a dependency Pack was explicitly unloaded.
Constant defaults are linear shader values, independent of file colour decoding.
RGBA32F constant storage preserves finite negative values and HDR values.

## Post inputs, scheduling, and depth

Post effects run in declared Scene order at `before_bloom` or `after_tone_map`.
The first location reads and writes linear HDR colour in RGBA16F.
The second reads and writes encoded display colour in RGBA8 before UI.
UI remains outside these effects.
Each effect reads the previous effect's result and writes a separate target.
Never sample the current colour attachment.

| Input | Encoding and population |
| --- | --- |
| Scene colour | Resolved, single-sample HDR before bloom; encoded display colour after tone mapping |
| Scene depth | Single-sample R32F reversed device depth; clear 0; nearer values are greater |
| Selection coverage | Single-sample R8 normalized coverage; 0 outside selected geometry |
| Selection depth | Single-sample R32F nearest selected depth; clear 0; includes hidden selected geometry |

All Post images use physical output pixels.
The shader receives pixel size and simulation render time through engine Post data.
The wrapper supplies UVs that address the same physical pixel across all four inputs on each backend.
GL and Metal/D3D image origins require the generated wrapper's UV conversion.
Scene depth and selection depth reflect as `unfilterable_float` with `nonfiltering` samplers on every backend, because WebGPU cannot filter R32F.
The engine samples every Post input with a nearest sampler.
Depth stays in the engine's 0–1 reversed projection range.
Convert GL clip depth before producing that image.

Transparent Blend geometry does not write scene depth.
Selection uses the existing full-shape Blend policy.
Mask holes and vertex deformation apply to selected coverage and depth.
Selected Group Draws contribute to one union with the nearest selected depth.
The Post shader owns edge detection and visible-only or through-wall policy.
It can compare selected depth with scene depth or omit that comparison.

Produce depth and selection images only when an enabled effect declares them.
Do not sample a multisampled depth attachment as a portable single-sample texture.
The Post integration must produce separate single-sample depth with shared deformation and alpha rules.
For MSAA, document that path's coverage difference at polygon edges.
Normals, motion vectors, history, arbitrary passes, and custom sky shaders require later contract versions.

## Failures and reload

Invalid source stops the asset build with the original source filename and line.
The proof verifies this diagnostic with an undefined function in the shared deformation block.
A game-hook wrapper must preserve source locations through its own source map.

An incompatible asset logs the mismatch and creates no replacement GPU generation.
A Surface without a valid generation omits affected Mesh parts from colour, shadow, and selection.
A Post without a valid generation skips that effect.
No failure selects a fallback shader or Material.

A reload with the same fingerprint can create all related variants outside the active generation.
The host switches the complete generation at one frame boundary after validation succeeds.
It retains the previous generation when any source, texture, pipeline, or capacity check fails.
The host retires old resources only after their GPU use ends.
A different fingerprint requires a game rebuild and restart in the initial implementation.

## Sources

The resource ceilings and bindings use the pinned `sokol-odin` submodule at `b13d03cf534c36bb1afb766eef6e3445061d786a`.
The compiler evidence comes from the pinned binary.
The upstream [shader compiler documentation](https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md) explains raw output and binding metadata.
The [OpenGL 4.3 specification](https://registry.khronos.org/OpenGL/specs/gl/glspec43.core.pdf) defines guaranteed GL limits.
Microsoft documents [D3D11 limits](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-limits) and [constant buffer rules](https://learn.microsoft.com/en-us/windows/win32/direct3d11/overviews-direct3d-11-resources-buffers-constant-how-to).

Environment metadata uses `environment_params = (enabled, specular_max_lod, 0, 0)`.
Fragment slots 6 and 7 bind linear RGBA16F diffuse and GGX specular cubemaps.
The diffuse cubemap stores cosine-integrated radiance divided by pi.
The specular mip roughness is `mip / specular_max_lod`.
Bind black cubemaps and zero metadata when the Sky is absent or unloaded.
The `rocco_environment(direction, lod)` hook helper samples the specular cubemap at an explicit mip.

## Shadow appearance lanes

The runtime and production Surface wrapper use the same shadow comparisons.
The `fs_lights` block remains 512 bytes.
`camera_pos.w` contains comparison depth bias.
`fog_color.w` contains the comparison filter radius: 0, 1 or 2.
`view_dir.w` contains effective shadow distance, or 0 for legacy single-map fitting.
`shadow.z` contains world normal bias.
`shadow.w` contains the cascade blend fraction.
A blend band that rounds to zero width uses a hard step and avoids an undefined smoothstep.
Finite distance uses camera fitting with one or multiple cascades.
All layouts preserve these lanes across rigid, skinned and instanced colour variants.

## Selected Group production

`Group.selected` includes all descendant Draws in one coverage and nearest-depth union.
The current Scene supplies membership, including selected ancestors of nested Groups.
Selection shares admitted geometry, interpolated transforms, skin poses, Surface hooks, and render time with colour.
Its depth test stays independent of scene depth and shadow casting.
Mask fragments use shared alpha rules; Blend fragments cover their full shape even at zero alpha.
The host allocates and produces Selection only when a valid enabled Post effect requests either Selection input.
Removing the last consumer releases the targets.
The example Post shader implements visible-only and through-wall policies before bloom from the same four inputs.

Selection reuses the existing coverage shaders, pipelines, target credits, and per-part uniform reservation.
Its grouped individual submissions add no resource credits or instance bytes.
The instance stride remains 116 bytes.
`python3 scripts/post_check.py` runs selected-Group checks in each native backend CI job.
Local Metal results do not establish GL or D3D11 acceptance.
