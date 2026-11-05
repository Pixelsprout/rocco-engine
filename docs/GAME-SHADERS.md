# Game shader assets

The platform bundle contains `shader-tools/build.py` and `shader-tools/contract-v1/`.
These files form the shader build tool for that platform version.
The tool needs Python 3 and the pinned sokol-shdc binary.
It needs no Odin compiler, engine source, or running game.
The Python code uses only the standard library.

Put `shaders.json` beside the game's `main.roc`.
Use [the authoring example](../scripts/shader_assets/example/shaders.json) as a starting point.
Source paths refer to the declaration folder.
Run the tool from the game folder:

```sh
python3 /path/to/platform/shader-tools/build.py --install
```

The first `--install` downloads the pinned compiler into the user's cache.
The tool verifies the binary checksum before each build.
Use `--shdc PATH` or `ROCCO_SHDC` to select an installed binary.
Use `--contract PATH` to select the contract folder from the pinned platform bundle.
Keep the build tool and contract folder from the same bundle.

`roc scripts/build.roc -- game NAME` runs this tool when the game has `shaders.json`.
The tool always compiles declared sources.
An invalid source stops the build, even when a previous package exists.
A failed build preserves previous output files.
The caller must honor the failed exit status.

The default output folder is `assets/shaders/`.
The default helper folder is the game folder.
Use `--out` and `--helpers` to change these paths.
Each shader produces a package, a JSON manifest, raw compiler sources, reflection, and a typed Roc module.
`build.json` records package hashes, interface fingerprints, pass budgets, and named material slots.
`dependencies.json` records source dependencies relative to the declaration folder.
Repeated builds preserve equivalent package bytes and unchanged output timestamps.
Raw reflection uses stable temporary filenames rather than game paths.

## Live shader development

Build the game once to regenerate packages and typed helpers.
Start the game.
Run this command from the game folder:

```sh
python3 /path/to/platform/shader-tools/build.py --watch --install
```

The command compiles outside the game.
It polls `shaders.json` and declared vertex, Surface, lighting, and Post hook files every 250 milliseconds.
It compares file contents, including missing files, rather than timestamps.
It follows changed hook paths even when another declaration field is invalid.
If JSON parsing fails, it retains the previous hook paths until the declaration recovers.
It does not watch Mesh sources, platform templates, GLSL includes, or macros.
Run a normal build after changing Mesh sources or platform templates.

The compiler checks the source snapshot again before publication.
If an input changes during compilation, the watcher retries without publishing that result.
The compiler writes `build.json` after all other outputs.
The game verifies every listed package hash before it accepts that completion record.
Each Shader swaps all its variants together.
Different Shader assets can accept or reject the same completed build independently.

The game polls at most four times per second while a loaded Pack requests Shaders.
Games without Shader requests do no reload file I/O.
An unchanged completion record costs one bounded file read and SHA-256 calculation.
Package reads and GPU creation occur only after the completion record changes or requested Pack membership changes.
Staging exhaustion retains the current generation and retries on later polls.

Compatible packages keep the same Shader ID and Pack references.
The candidate must create every active Surface pipeline and Post location before the frame boundary swap.
Existing pipelines remain lazy until a frame uses them.
Failed compilation, package validation, program creation, or pipeline creation keeps the previous valid generation.
Diagnostics appear in the development log.
Missing or invalid first packages recover through retained Pack requests after a complete build appears.

The first accepted package defines the running game's interface baseline.
Interface changes, declaration removal, and declaration renaming require rebuilding the game and restarting it.
The game logs that requirement and retains the current generation.
Standalone packages outside the completion record do not count as removed declarations.
Explicit dependency Pack unload still invalidates affected materials at the next frame boundary.

Run the native reload checks after building `examples/post`:

```sh
python3 -m unittest scripts/test_shader_reload.py
python3 scripts/shader_reload_check.py build/bridge-check/reload
```

The native check tests compiler failures, source correction, interface rejection, declaration correction, changed hook paths, and first-load recovery.
It also forces native program failure and pipeline pool exhaustion for Surface and Post candidates.
It checks GPU resource counts and CPU allocations after repeated swaps and retirement.
Desktop CI runs these checks on Metal, GL, and D3D11.

A shader's `name` is its Roc module name.
Its asset key is `shader/NAME`.
Its file is `assets/shaders/NAME.shaderpack`.
A mesh helper uses the existing Mesh asset key: the source file stem.
The Surface loader exposes the `shader/` asset namespace through Packs.
See [runtime Surface materials](SURFACE-RUNTIME.md) for assignments and resource ownership.
See [runtime Post effects](POST-RUNTIME.md) for ordered effect instances and optional inputs.

A Surface requires `kind: "surface"` and finite, nonnegative `max_displacement`.
The bound measures maximum displacement vector length in mesh-local units.
The host expands local bounds before the Draw transform.
`skinning` and `instancing` default to true.
Set either field to false to omit those variants.
Omitted hook paths use the engine's default behaviour.
An empty Surface hook preserves imported material values.

The hooks have these signatures:

```glsl
void rocco_vertex(inout Vertex vertex) {}
void rocco_surface(inout Surface surface, SurfaceInput data) {}
vec3 rocco_lighting(Lighting data) {
    return (data.diffuse + data.specular) * data.radiance
         * (clamp(dot(data.normal, data.direction), 0.0, 1.0) * data.attenuation);
}
vec4 rocco_post(PostInput data) {
    return sample_scene_colour(data.uv);
}
```

| Hook input | Fields |
| --- | --- |
| `Vertex` | `position`, `normal`, `tangent`, raw `colour`, `uv`, simulation `time`, `draw`, `world_position`, `world_origin` |
| `SurfaceInput` | Raw `colour`, `uv`, `world`, `geometric_normal`, simulation `time` |
| `Surface` | RGB `base_colour`, `opacity`, `occlusion`, `metallic`, `roughness`, `emission`, shading `normal`, `unlit` |
| `Lighting` | `normal`, `view`, light `direction`, `radiance`, `attenuation`, PBR `diffuse`, `specular`, `base_colour`, `roughness`, `metallic` |
| `PostInput` | `uv`, `pixel_size`, simulation `time` |

Skinning runs before the vertex hook.
World transformation runs after the vertex hook.
`world_position` snapshots the posed world position before the vertex hook changes local geometry.
`world_origin` holds the resolved model's world origin.
Both values use the instance model for instanced Draws and the uniform model for rigid or skinned Draws.
They need no additional GPU resources and remain consistent across colour, shadow, and selection.
The vertex colour input contains raw `COLOR_0`.
It excludes the imported base factor and instance tint.
The wrapper preserves geometric normals independently from hook shading normals.
It adjusts tangent handedness for reflected world transforms.
All Surface passes share vertex deformation and the Surface opacity hook.
They receive the same simulation time, parameters, textures, pose, and Draw data.

The lighting hook runs for each engine-selected light.
It can add transmission from back-facing lights.
The engine retains clusters, Sun shadows, fog, and the default PBR response.
`rocco_environment(direction, lod)` exposes the engine cubemap when a hook uses it.
Hooks cannot declare GPU resources, shader inputs, shader outputs, or entry points.
Hooks change coverage through `Surface.opacity`.
The wrapper owns fragment discard and depth.
Hooks cannot use includes or macros.
Conditional backend directives remain available.
The build reports hook filenames and source lines for compiler errors.

Each parameter declares `name`, `type`, `scope`, `stage`, and `default`.
Names use lowercase letters, digits, and underscores, starting with a letter.
Numeric names and texture names have separate unique namespaces.
Types are `F32`, `Vec2`, `Vec3`, `Vec4`, `Colour`, `Bool`, and `Mat4`.
Defaults contain the type's required components in a JSON array.
`Bool` requires a JSON boolean.
Matrices use sixteen column-major components.
All numeric components must fit finite binary32 values.

Scopes are `Scene`, `Material`, and `Draw`.
Stages are `vertex` and `fragment`.
Declaration order assigns separate stage offsets at 16-byte boundaries.
A matrix uses 64 bytes.
Every other parameter uses 16 bytes.
Each stage permits 256 bytes of game parameters.
Use separately named parameters when both stages need a value.

The generated module provides typed numeric records and declared defaults:

```roc
scene_values = Foliage.scene("trees", { ..Foliage.scene_default, wind: 0.2 })
draw_values = Foliage.draw("trees", { ..Foliage.draw_default, phase: 0.5 })
```

These records reject unknown fields and wrong value types during the Roc build.
Texture helpers also reject the wrong texture dimension.
The public value shapes live in [Shader.roc](../platform/Shader.roc).
The Scene, Material, Draw, and Post APIs must consume these shapes.
The host must validate scope, duplicate assignments, finite values, and asset compatibility before upload.

Textures declare `name`, `scope`, `stage`, `type`, `colour_space`, `sampler_policy`, and `default`.
Dimensions are `2d` and `cube`.
Sample type is fixed to float in version 1.
Colour space is `linear` or `srgb`.
Sampler policy declares `min`, `mag`, and `wrap`.
Filters are `nearest` or `linear`.
Wrap choices are `clamp`, `repeat`, and `mirror`.
At most four game textures share logical slots 8 through 11.

A texture default names a Pack asset or an imported material semantic.
An optional texture can declare a constant RGBA default.
Imported defaults require Material scope and matching colour space.
Base colour and emissive use `srgb`.
Normal, occlusion, and metallic/roughness use `linear`.
A missing default, failed asset, or incompatible texture must fail explicitly.
The host resolves references through their named live Pack each frame.
Explicit Pack unload invalidates dependent materials before submission.
Retired GPU resources remain protected until in-flight use ends.
Constant defaults contain linear shader values, including negative values and HDR values.

Use the combined helper to replace one texture and numeric values together:

```roc
leaves = Foliage.material_with_textures(
    "trees",
    { ..Foliage.material_default, tint: { r: 0.8, g: 1.0, b: 0.8, a: 1.0 } },
    {
        ..Foliage.material_textures_default,
        detail: Image2D({ pack: "textures", asset: "image/leaf_detail" }),
    },
)
assignment = Tree.leaves("trees", leaves)
```

The example declares `detail` and `cutout` in Material scope.
This assignment changes `detail` and keeps the declared `cutout` default.
A texture's `Default` tag omits its assignment from the public value.
It preserves the declaration's constant, imported semantic, or Pack reference.
Numeric-only helpers also retain declared texture defaults.
Individual texture helpers produce partial `Shader.Values` assignments.
The host must reject conflicting assignments for the same shader, scope, and name.

Add `meshes: [{ "name": "Tree", "source": "assets/meshes/tree.glb" }]` to generate named slot helpers.
The generator accepts GLB and glTF JSON.
A slot stores the source material index, including gaps from unnamed materials.
Part position never identifies a slot.
The generator rejects duplicate source names and colliding Roc identifiers.
Unnamed materials have no generated named helper.
A named slot overrides the whole-Draw assignment for that slot.
Unspecified slots retain imported materials.

A Post requires `kind: "post"`, a `post` hook, `inputs`, and `locations`.
Inputs are `scene_colour`, `scene_depth`, `selection_coverage`, and `selection_depth`.
Declare only the inputs required by the hook.
Their helpers are `sample_NAME(uv)`.
Locations are `before_bloom` and `after_tone_map`.
A declaration can compile either location or both locations.
Post parameters accept Scene or Draw scope in the fragment stage.
HDR output is linear RGBA16F before bloom.
LDR output is encoded RGBA8 after tone mapping, before UI.
The host produces selection inputs only when enabled effects request them.
Reversed depth increases towards the camera.
The example checks each selected neighbour's depth before it expands outline coverage.

The compiler emits nine Surface programs when both optional layouts are enabled.
Each layout has colour, shadow, and selection programs.
Rigid uses five attributes.
Skinned uses seven attributes and the existing 64-joint palette.
Rigid instancing uses thirteen attributes without additional storage bindings.
Skinned instancing is outside version 1.
The host may batch only identical parameter, texture, material, and Draw-data assignments.
Per-instance model, inverse-transpose normal, and linear tint data can differ.
See [the loader handoff](SHADER-LOADER-HANDOFF.md) for exact bindings.

Run independent compiler checks:

```sh
ROCCO_SHDC=/path/to/pinned/sokol-shdc python3 -m unittest scripts/test_shader_assets.py
python3 scripts/shader_assets/native.py --shdc /path/to/pinned/sokol-shdc
```

The first command copies published tools into a clean external game.
It checks repeatable output, backend variants, defaults, source locations, and typed numeric/texture helpers.
Invalid assignments fail `roc build` before runtime linkage.
The test supplies empty target files only to reach type checking without a runtime loader.
The second command draws eleven production variants and checks outline pixels through the native graphics API.
Its two instance records exercise the thirteen-attribute layout.
Selection readback checks world inputs for rigid, skinned, and both instance records.
Each layout shares identical vertex code across colour, shadow, and selection programs.
The native fixture adds this coverage check to a copy of the wind hook.
It leaves the authored example files unchanged.
The outline test checks visible selection over nonzero floor and wall depths.
It also checks hidden selection with both occlusion policies.
The wind example moves only x and clamps the final offset to its declared 0.25 bound.
Metal passed locally on 2026-11-05.
Production GL and D3D execution remains pending CI evidence.

The integration checks passed 48 compiler, package, helper, and release tests.
The original eight-program golden proof remained unchanged and passed Metal execution.
The production Metal proof passed all eleven variants and both outline occlusion policies.
An extracted platform bundle compiled Surface and Post packages and three Roc helpers without engine source.
The bundle and native readback evidence are in `/tmp/rocco-compiler-merged/`.
