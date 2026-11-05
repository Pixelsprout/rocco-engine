# Immersive village scope

Date: 2026-11-05.
Status: scope confirmed; implementation authorized on 2026-11-05.

## Outcome

Recreate the supplied village's layout, composition, and overall appearance in `examples/village`.
Rendering techniques can differ from Godot.
Support first-person walking on flat ground, coarse building collisions, mouse look, a free camera, and fixed comparison views.
Support object selection through a game-authored outline.

Require ground variation, moving trees and grass, correct foliage shadows, sky lighting, haze, lamps, smoke, dust, and outlines.
Animated villagers, jumping, stairs, interiors, depth of field, TAA, volumetric fog, and a specific GI method are not completion requirements.
Custom sky shaders, arbitrary render passes, render scaling, and variable-penumbra shadows also remain optional later work.

## Assets and scene preparation

Start with Ground, Lane, HouseA, HouseB, nearby lamps, and nearby trees.
Expand to the complete agreed layout after the small baseline and shader proof pass.
Use `world.tscn` for placement and hierarchy.
The supplied layout JSON is supplemental.

Ordinary builds use prepared assets without Blender or Godot.
Preserve a repeatable source conversion process, archive checksum, credits, and asset terms.
Keep units, textures, tangents, material names, and vertex colours through conversion.
Prepare deforming meshes around their own roots, with scene placement separate.

The [source investigation](RESEARCH-GODOT-SCENE.md) identifies the archive and its terms.
The [gap analysis](RESEARCH-IMMERSIVE-SCENE.md) records the original renderer evidence.

## Shader authoring

[ADR 0028](adr/0028-game-shaders-are-pack-assets.md) defines the planned engine contract.

| Area | Agreed behaviour |
| --- | --- |
| Build | Compile GLSL hooks during the game asset build through sokol-shdc. |
| Distribution | Load versioned Shader assets through Packs against published platform bundles. |
| Independence | Adding a compatible game shader requires no engine rebuild or Odin edits. |
| Surface hooks | Expose vertex movement, surface properties, normals, and lighting response. |
| Engine inputs | Supply transforms, lights, shadows, and related pass variants. |
| Material inheritance | Preserve imported textures and properties unless the game explicitly overrides them. |
| Material selection | Preserve named Material slots; allow per-slot and whole-Draw overrides. |
| Typed helpers | Generate Roc helpers for mesh slots and shader declarations. |
| Parameters | Support Scene, material, and per-Draw values with declared defaults. |
| Post order | Run ordered effects before bloom in HDR or after tone mapping before UI. |
| Post inputs | Provide declared scene colour, scene depth, and Selection input. |
| Extra buffers | Produce extra inputs only when an enabled effect needs them. |
| Deferred buffers | Normals, motion vectors, and history require later extensions. |

The loader must preserve material identity before merging materials or sorting Mesh parts.
Current part indices cannot provide stable author-facing slot names.
The loader must also preserve vertex colours for grass weights.

Shaders declare their maximum vertex displacement.
The engine expands culling bounds by that displacement.
Colour, shadow, and selection passes share deformation, alpha rules, and simulation-derived render time.
Fixed Bridge steps reproduce the same wind pose.

The initial sky uses a cubemap for both background and environment lighting.

## Selection and outlines

The engine supplies selected geometry coverage and nearest selected depth, including geometry hidden behind other objects.
It supplies scene depth separately.
A game-authored Post shader chooses edge detection, width, colour, pulse, glow, and occlusion policy.
The engine must not force visible-only or through-wall outlines.

The small proof demonstrates both behaviours using the same Selection input.
The selected Group remains the unit whose Draws contribute to the combined selection.
Milestone 40 provides these reusable inputs and an example shader.
It no longer prescribes an engine-owned outline style field.

## Reload and failures

One development command watches shader dependencies and compiles outside the running game.
Successful builds replace related variants together at a frame boundary.
Interface-preserving changes reload live.
Interface changes initially require rebuilding the game and restarting.

| Event | Required result |
| --- | --- |
| Invalid shader source | Stop the asset build and report the error. |
| Failed reload | Keep the previous valid shader and log the error. |
| No valid Surface shader | Log and omit affected Mesh parts from colour, shadow, and selection passes. |
| No valid Post shader | Log and skip the affected effect. |
| Incompatible asset contract | Reject the asset and log the incompatibility. |

Do not substitute a shader or material after failure.
Diagnostics belong in the development log.

Assets record the platform contract version and binding layout.
The build emits backend code and metadata for Metal, GL, and D3D.
CI checks the respective backend on each target platform.

## Quality controls

Expose shadow distance, bias, cascade distribution, blend, filter quality, and per-Draw casting.
Retain existing choices for shadow resolution, cascade count, and MSAA.
Provide named quality presets with explicit overrides.
Expose vegetation density and visibility distance in the village.

Appearance changes apply live.
Allocation-heavy settings can initially require a restart.
The controls must state that requirement.
Keep existing engine defaults until measurements justify a change.
Derive village presets from both reference machines.

## Performance and reviews

| Reference | Recorded hardware |
| --- | --- |
| Mac | Apple M5, 10-core GPU, 16 GB RAM |
| PC | Intel i7-9700F, RTX 2070 SUPER, 16 GB RAM, Windows 11, 60 Hz display |

Target 60 FPS at 1920 × 1080 physical pixels on both machines.
Different documented presets are allowed if they preserve core features and overall appearance.
Check Metal, GL 4.3, and D3D11 compatibility.
The final PC check uses the user's desktop.

Use the source camera route and equal scene inputs for comparisons.
Record warmup, power state, build mode, settings, sample counts, and instrumentation.
Require warm-run p95 CPU frame work and p95 GPU frame work each within 16.67 ms.
Report p99 spikes and inspect real-clock frame pacing separately.
CPU submit time alone does not establish GPU performance.

Human reviews cover three points:

1. Baseline composition.
2. Foliage and lighting.
3. The complete scene and final PC run.

## Delivery and task ownership

The separate dex parent **Immersive scene lane** owns assets, composition, integration, and acceptance evidence.
The **rocco roadmap** owns reusable engine work.
Existing shader, cutout-shadow, instancing, clustered-lighting, outline, particle, and per-Draw casting tasks remain the shared implementation tasks.

The shader task now has bounded children for the portable contract, imports, compilation, Surface integration, Post integration, and reload.
New engine tasks cover shadow quality controls and cubemap environment lighting.
The baseline and independent engine prerequisites can proceed under the confirmed scope.

Before full village integration, complete a small shader proof with:

- Named bark and leaf slots.
- Game-authored wind and matching cutout shadows.
- A game-authored outline with both occlusion styles.
- Successful reload and failed-reload recovery.
- An external game using a published platform bundle.
- Rendering checks on all three backends.

Then complete foliage, lighting, and post/particle integration.
Finish with the two-machine performance checks and human reviews.

Exact binary encoding, helper names, numeric resource limits, and instrumentation remain implementation details.
The first portable-contract task must validate those details against the agreed behaviour.
Any conflicting result must return for a design decision.
