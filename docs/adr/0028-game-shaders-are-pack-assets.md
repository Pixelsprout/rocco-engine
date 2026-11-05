# 0028: Game shaders are Pack assets

Status: accepted design, 2026-11-05. Not implemented.

The immersive village needs game-authored shaders that work with a published platform bundle.
Generating engine source for each shader would require an engine build for each game's shader changes.

The game asset build compiles shaders.
The engine loads Shader assets through Packs and owns their GPU resources.
Adding a compatible Shader asset requires no engine source change or engine rebuild.
The game selects appearance through plain values, consistent with the Seam and ADR 0003.

The immersive scene lane must demonstrate Shader reload before completion.
A failed reload keeps the last valid shader active and reports the error.
The initial shader implementation may require a restart while reload support follows.

Core scene features must work on Metal, GL 4.3, and D3D11.
Optional effects can use documented fallbacks.
This requires a shader contract that the asset build can validate against the published platform.

The first extension types are Surface shaders and Post shaders.
Surface shaders control vertex movement, normals, material properties, and custom lighting response.
Post shaders operate at defined points around bloom and tone mapping.
The initial sky uses a cubemap for its background and environment lighting.
Custom sky shaders and arbitrary render passes remain outside this lane's required scope.
These boundaries cover the reference scene while limiting resource and scheduling complexity.

Authors write GLSL hooks compiled through sokol-shdc.
The engine supplies transforms, lights, shadows, and related pass variants.
Default hooks preserve built-in PBR behaviour.
Surface hooks inherit imported material textures and properties unless the game overrides them.
The importer preserves vertex colours for inputs such as grass weights.
Deforming assets keep their geometry around an authored local root, with scene placement separate.
Shaders declare their maximum vertex displacement so culling bounds can include the movement.
Colour, shadow, and selection passes share one simulation-derived render time.
Fixed Bridge steps reproduce the same shader animation pose.
The game build generates typed Roc helpers from shader declarations.
Values can have Scene, material, or per-Draw scope, with declared defaults for omitted values.

Meshes preserve named Material slots for game overrides.
A Draw can override individual slots or its whole material assignment.
Unspecified slots keep their imported materials.
Generated helpers expose slot names and typed shader parameters to the game.
The importer must preserve source material identity before merging or reordering Mesh parts.

Post effects run in declared order before bloom in HDR or after tone mapping before UI.
They can declare scene colour, depth, and selection-mask inputs.
The selection outline is a game-authored Post shader.
The engine provides selection data; the shader owns outline style and occlusion policy.
Selection data includes the selected geometry's coverage and nearest depth, including geometry hidden behind other objects.
The Post shader can compare selected depth with scene depth or ignore that comparison.
The engine does not force visible-only or through-wall outlines.
The engine produces extra inputs only when enabled effects require them.
Normal buffers, motion vectors, and frame history require later extensions.

Shader reload accepts changes that preserve the shader interface.
Interface changes initially require rebuilding the game and restarting.
The engine replaces related colour, shadow, and selection variants together.
A development command watches shader dependencies and compiles outside the game.
Successful builds replace their loaded variants at a frame boundary.
Errors appear in the development log.

A shader load failure must produce a clear log entry.
The engine must not substitute a fallback shader or material.
Without a valid Surface shader, the engine omits the affected Mesh parts from colour, shadow, and selection passes.
Without a valid Post shader, the engine skips that effect.
Invalid shader source stops the asset build.

Shader assets target a versioned platform contract.
Each asset records its contract version and binding layout.
The asset build emits backend code and metadata for Metal, GL, and D3D.
CI checks each backend on its target platform.
The engine rejects incompatible assets with a clear log.

The on-disk encoding and numeric resource limits remain implementation details to validate across the three backends.

Before full village integration, a small example must prove named slots, game-authored wind, matching shadows, and a game-authored outline.
It must also prove successful reload, failed-reload recovery, published-platform loading, and all three desktop backends.
