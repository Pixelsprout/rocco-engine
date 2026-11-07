# Research: an immersive 3D scene for Rocco

Date: 2026-11-05. Code reviewed: `6a436bf`.
Status: original analysis with subsequent scoping notes.
[The consolidated scope](IMMERSIVE-SCENE.md) records the confirmed decisions and implementation authorization.
Recommendations below can be superseded by that scope and ADR 0028.

Scoping update, 2026-11-05: the user accepted the reference appearance, first-person walking, and shader assets compiled by the game build.
Shader assets must work with published platform bundles.
Shader reload must work before the lane finishes.
Appearance changes apply live; allocation-heavy settings may initially require a restart.
Core features must work on all three desktop backends.
The final check includes the user's desktop PC from the benchmark records.
[ADR 0028](adr/0028-game-shaders-are-pack-assets.md) records the shader ownership decision.
Other architecture details below remain proposals until scoping settles them.

Round 2 accepts Surface shaders and Post shaders as the initial extension types.
The sky begins as a cubemap for its background and environment lighting.
The scene lives in `examples/village`, with a separate published-platform compatibility proof.
Ordinary builds use prepared assets; regeneration uses a repeatable conversion process.
Walking uses flat ground and building collisions, with no required jumping, stairs, or interiors.
Both the M5 and the benchmark desktop must reach 60 FPS at 1080p.
Each machine may use a documented quality preset that preserves core features and overall appearance.
The agreed gate uses warm-run p95 CPU and GPU frame work within 16.67 ms.
Record p99 spikes and inspect real-clock frame pacing separately.
Human reviews occur at baseline composition, foliage and lighting, and the complete scene.
The required contents are village layout, ground variation, moving foliage, correct shadows, sky lighting, haze, lamps, smoke, dust, and outlines.
Animated villagers, depth of field, TAA, volumetric fog, and a specific GI technique remain optional.

Round 3 accepts GLSL hooks, generated typed Roc helpers, and Scene, material, and per-Draw value scopes.
Post effects run before bloom in HDR or after tone mapping before UI.
They can request scene colour, depth, and selection masks.
Interface-preserving shader changes reload live; interface changes initially require rebuilding the game and restarting.
The user rejected shader fallback substitution.
Load failures must log clearly; rendering without an initial valid shader still needs a decision.
Named material slots and generated helpers were accepted after a concrete authoring example.
The accepted quality controls cover shadow distance, bias, splits, blend, filtering, per-Draw casting, and example vegetation density and distance.
Quality presets allow overrides and use measurements from both machines.

Round 4 accepts shader watch mode, versioned assets, and backend code generation for all three desktop targets.
Invalid source stops the asset build.
A first-load Surface shader failure logs and omits affected parts from colour, shadow, and selection passes.
A first-load Post shader failure logs and skips the effect.
Failed reloads keep the last valid shader.
The outline remains a game-authored Post shader; its style and occlusion policy belong to the game.
Round 5 accepts selected coverage and nearest depth even behind other objects.
It also accepts inherited material inputs, imported vertex colours, local roots, declared displacement, and shared simulation-derived render time.
A small shader workflow proof must pass before full village integration.

Tracking: the separate dex parent, **Immersive scene lane**, owns scene work and acceptance evidence.
Its index links to reusable engine tasks under **rocco roadmap**.
The lane contains research, scoping, the baseline, three integration tasks, and final validation.

## Proposed goal

Build a small, walkable village with a wooded edge, using the guide's free assets.
Use one scene to prove lighting, atmosphere, moving foliage, material control, and stable performance.
Let a game author change the style through game assets and Roc values.
The author must not edit the engine's Odin code for each new material or effect.

Agreed performance target: 60 FPS at 1920 × 1080 physical pixels on both reference machines.
Use the Apple M5 with its 10-core GPU and 16 GB RAM as the Mac reference.
Use the benchmark desktop with an i7-9700F, RTX 2070 SUPER, 16 GB RAM, and Windows 11 as the PC reference.
Keep Metal, GL 4.3, and D3D11 as supported paths.
Record separate results for Windows and Linux hardware; compilation alone does not establish performance.

The goal is a useful acceptance test for Rocco's rendering capabilities.
One scene cannot establish quality across every modern game genre.

## Evidence and scope

The [Coding Quests guide](https://codingquests.io/blog/how-to-make-godot-3d-look-better) improves one village through lighting, atmosphere, foliage, and presentation.
Its useful method is to isolate each change and measure its cost.
Its reported frame rates are not predictions for Rocco.

[The source investigation](RESEARCH-GODOT-SCENE.md) records the guide, official Godot documentation, and the downloadable project.
That note covers asset provenance, shader source, and differences between the article and project.
This note compares those findings with Rocco's code and roadmap.
No renderer changes or scene benchmarks ran during this analysis.

Primary Rocco evidence:

- [Vocabulary](../platform/Vocabulary.roc), [Launch defaults](../platform/Launch.roc), and [Environment defaults](../platform/Environment.roc).
- [Frame render](../engine/frame_render.odin), [renderer](../engine/render.odin), and [render targets](../engine/render_target.odin).
- [Built-in shaders](../engine/shaders/basic.glsl), [cascades](../engine/cascade.odin), [glTF loader](../engine/gltf.odin), and [image processing](../engine/image.odin).
- [Roadmap](ROADMAP.md), dex task descriptions, and [benchmarks](BENCHMARKS.md).
- [Design](DESIGN.md) and ADRs [0003](adr/0003-packs-own-asset-lifetimes.md), [0023](adr/0023-a-light-list-per-draw.md), [0025](adr/0025-a-normal-map-uses-the-file-tangents.md), [0026](adr/0026-the-look-lives-in-scene-environment.md), and [0027](adr/0027-alpha-modes-and-blend-frame-order.md).

## Gap analysis

Priority means dependency on the proposed scene, not general engine importance.
P0 establishes the reference and author controls.
P1 completes the main scene.
P2 adds features only when a comparison shows their value.

| Capability | Implemented in Rocco | Gap and proposed action | Priority |
| --- | --- | --- | --- |
| Art direction and camera | Directional colour, intensity, direction, camera pose, and field of view | Author the composition first. Existing controls can provide warm light and clear silhouettes. | P0 |
| Shadow quality | One Sun; 1–4 cascades; configurable map size | Expose distance, bias, cascade distribution, blend, and filter quality. Add clear presets and cost measurements. | P0 |
| Foliage shadows | MASK cuts the visible surface | The shadow pass draws solid triangles and culls back faces. Add cutout and two-sided shadow paths. | P0 |
| Anti-aliasing | MSAA Off/2/4/8; default 4 | Add foliage edge treatment and coverage-preserving mips. Evaluate spatial post AA before committing to temporal AA. | P0/P1 |
| Material authoring | Imported PBR materials per mesh part; Draw tint and glow | No game shader, material override, or custom parameter contract. Add shader assets and stable material slots. | P0 |
| Foliage movement | Rigid transforms and skeletal animation | Add vertex deformation hooks, root weights, shared wind values, normal edits, and matching shadow deformation. | P0 |
| Foliage lighting | Normal maps; flipped back-face normals for double-sided MASK/BLEND | Add a material route for canopy normals and stylized backlighting. Imported normals can already supply a static canopy shape. | P1 |
| Sky and ambient light | Visible cubemap; constant ambient colour | The sky does not light surfaces. Add sky-derived diffuse and specular lighting; evaluate procedural sky later. | P1 |
| Surface contact | Imported occlusion map multiplies ambient light | No screen-space contact occlusion. Evaluate SSAO after the reference shows where baked occlusion is insufficient. | P1 |
| Indirect lighting | Constant ambient approximation | No bounced light, lightmap path, probes, SSIL, or SDFGI. Choose a static or dynamic approach through a prototype. | P2 |
| Tone and colour | HDR, ACES, AgX, Neutral, exposure, bloom | No general colour grade or game post effects. Add colour controls through post shaders. | P1 |
| Atmosphere | Linear distance fog | No height fog or volumetric light scattering. Add height fog first if the scene needs ground haze. | P1/P2 |
| Dense vegetation | One submit per placed mesh part; separate shadow submits | No general instancing, camera frustum culling, or LOD. Add batching, chunk bounds, and distance control. | P1 |
| Ground materials | One UV set; imported textures; material colour stored per vertex | No game ground shader for world-space noise, colour variation, or grass matching. The material extension should provide this. | P1 |
| Practical lights | Point lights, emissive surfaces, and glow | Eight direct lights per Draw can omit nearby lights. No light layers, spot lights, or local-light shadows. | P1/P2 |
| Particles | No general emitter path | Add smoke, dust, and sparks through Milestone 41. Reuse game materials where practical. | P1 |
| Selection and stylization | Fixed built-in post chain | No selection mask or game post pass. Use Milestone 40 to prove a general post extension. | P1 |
| Lens and final polish | Camera field of view | No depth of field, grain, vignette, or debanding controls. Keep them optional and protect gameplay visibility. | P2 |
| Asset workflow | GLB meshes, Packs, images, cubemap skies | Convert source glTF assets; preserve material slots and layout. Godot scenes and shaders cannot load directly. | P0 |
| Performance evidence | CPU Spans, Bridge screenshots, manual Metal GPU traces | Add repeatable scene runs and effect comparisons. CPU submit time alone cannot identify shader cost. | P0 |

### Shadow and AA controls already exist

`Launch.default` selects a 2048 map, one cascade, and 4× MSAA.
The game can change these values before the window opens.
`Launch.window.samples` accepts `Off`, `X2`, `X4`, and `X8`.
`launch_check` limits cascade count to four.

The remaining shadow controls are fixed in engine code:

| Control | Current value or behaviour | Location |
| --- | --- | --- |
| Cascade distance | 150 units with 2–4 cascades | `cascade.odin: SHADOW_DISTANCE` |
| Cascade distribution | 0.5 linear/log split weight | `cascade.odin: CASCADE_SPLIT_WEIGHT` |
| Cascade blend | 10% of each range | `cascade.odin: CASCADE_BLEND` |
| Receiver normal offset | 0.05 world units | `frame_render.odin: SHADOW_NORMAL_OFFSET` |
| Depth and slope bias | 0 and −2 under reversed Z | `render.odin: SHADOW_DEPTH_BIAS`, `SHADOW_SLOPE_BIAS` |
| Filtering | Nine comparison taps; hardware filtering per tap | `basic.glsl: sun_visibility_in` |
| Single cascade | Fits all placed casting geometry | `frame_render.odin`, shadow view construction |

One cascade does not use the same camera-distance rule as multiple cascades.
Increasing map size alone can waste memory when distant scenery expands the single-cascade bounds.
Rocco's fixed PCF filter does not provide the guide's angular-size soft shadows.
Variable penumbra shadows need renderer work beyond exposing a setting.
MSAA also does not resolve every alpha edge or shader highlight.
Rocco's mip builder averages alpha without preserving cutout coverage.
This can reduce visible leaves at a distance.

Keep allocation choices in `Launch` initially.
Put per-scene shadow appearance in a proposed `Environment.shadows` record, consistent with ADR 0026.
Keep per-light and per-Draw casting choices near those descriptions.
Use a pure Roc helper to produce quality presets with explicit overrides.
Presets should describe cost; they should not choose the game's colour palette or wind strength.

Keep current engine defaults until measurements justify a change.
Start the village comparison with 2048 shadows, two cascades, a short measured shadow range, and 4× MSAA.
Compare 2× MSAA and 4096 shadows separately.
These are experiment inputs, not approved defaults.
Add render scale and anisotropic filtering to the quality investigation.
Neither has a developer control in the inspected rendering path.

Validate values against device limits before allocating resources.
Test invalid combinations and report the effective settings.
If settings must change during play, define resource replacement separately.
Changing `Launch` after startup currently has no effect.

TAA needs more than a fullscreen shader.
It requires history, jitter, reprojection, rejection rules, and motion data for moving geometry.
Wind deformation needs consistent previous-frame positions or another explicit history policy.
Start with MSAA, alpha-to-coverage, and mip coverage tests.
Add TAA only if moving-camera comparisons justify its complexity.

## Proposed shader pipeline

### Keep the seam pure

The game selects shader assets, material values, and effect descriptions.
The engine owns compilation integration, GPU objects, execution order, and resource lifetime.
Only plain values cross the seam.
This follows `DESIGN.md`; no GPU callback from Roc is required.

Start with two extension types: surface shaders and post shaders.
Keep built-in PBR as the default surface shader.
Defer an unrestricted render graph until these two types expose a concrete missing requirement.

### Surface shaders

Provide defined hooks for vertex deformation and surface values.
Expose position, normal, tangent, UV, vertex colour, instance data, and material parameters.
Support texture sampling in vertex hooks for shared wind noise.
The current GLB loader does not read `COLOR_0`.
It fills vertex colour from the material factor, so imported grass weights need loader support or another agreed input.
The loader also bakes node transforms into positions.
Define asset roots and pivots explicitly before using object height for wind.
Let the shader produce base colour, roughness, metallic, emission, opacity, and a shading normal.
Add a bounded lighting hook or backlighting term for stylized foliage.
Normal replacement alone does not provide light transmission through a leaf.

Generate shadow and selection variants from the same deformation and alpha rules.
Define the order of skinning, deformation, normal changes, and world transforms.
Keep the geometric normal available for shadow bias when a shader changes the shading normal.
Require conservative displacement bounds so wind cannot escape the culling or shadow bounds.
Declare time and seed inputs so Bridge runs remain repeatable.
Define time interpolation once for all passes.

Provide game overrides per stable material slot, plus an optional Draw-wide default.
Current tint and glow affect every part of a mesh.
A tree needs separate trunk and leaf materials without splitting every asset by hand.
The current loader omits material names and merges materials with equal resolved values.
It then sorts Mesh parts by Alpha mode.
Current part indices cannot provide stable public material slots.
Preserve source material identity before merging if the contract permits named overrides.
Include typed parameter defaults, textures, samplers, and instance parameters in the contract.
Avoid a separate material allocation for every blade's wind phase or colour.

### Shader assets and builds

Use the existing `sokol-shdc` route for Metal, GLSL 4.3, and HLSL5.
The current build emits one generated Odin file for the engine's shaders.
That is not yet a game asset loader.

Proposed flow:

1. Write a shader and its material declaration in the game.
2. Compile supported variants during the asset build.
3. Package backend code and binding metadata as a versioned asset.
4. Load the asset through Packs and publish its id through `loaded`.
5. Select that id and typed parameters in the Scene.

Upstream shdc supports raw shader files with YAML reflection.
That provides a possible input for an asset packer.
Verify the pinned compiler's support before fixing the package format.
Rocco still needs the packer, loader, validation, and pipeline cache.
See [the upstream shdc documentation](https://github.com/floooh/sokol-tools/blob/master/docs/sokol-shdc.md).

Version the shader interface and reserve engine binding slots.
Validate parameter types, texture counts, and variants before accepting an asset.
Define fallback behaviour for missing or stale shader ids.
Keep the last valid pipeline when a development reload fails.
Replace all related pass variants together at a frame boundary.
Retire old GPU objects only when they are safe to release.
Account for shader variants and parameter blocks in the existing capacity budgets.

### Post shaders

Provide declared inputs and bounded insertion points.
Useful points are before bloom in HDR and after tone mapping before UI.
Specify whether each input uses linear colour, encoded colour, physical pixels, or logical pixels.
Specify pass order and use separate read/write targets when necessary.
Keep the UI outside world colour effects by default, as ADR 0026 requires.

Rocco has an HDR colour image, a depth attachment, bloom images, and a final colour image.
It has no public sampleable scene-depth, normal, velocity, or object-mask contract.
The depth attachment is multisampled when MSAA is enabled.
Depth-aware post effects need an explicit depth production or resolve strategy across all three backends.
They cannot assume that a portable sampled depth texture already exists.

Add only the inputs required by enabled effects.
SSAO needs depth and a normal strategy.
Soft particles and depth of field need scene depth.
TAA needs additional temporal resources.
Document transparent-surface limitations for each input.

### Milestone 40 as the proof

Keep the existing requirement for one outline around a selected Group.
Use a generic mask or selection description instead of making outline style an engine-only field.
The engine produces the selected coverage and optional depth.
A game post shader chooses edge detection, width, colour, pulse, and glow.
Ship a reusable default outline with the example.

Preserve the milestone's pre-bloom HDR composition and group union behaviour.
Decide whether selection should remain visible behind walls.
Test MASK holes, displaced foliage, skinned meshes, and the existing full-shape policy for BLEND parts.
The mask still needs engine support; shader authoring does not remove that requirement.

This proposal changes Milestone 40's planned `Group.outline` contract.
Record the new decision before implementation.
Do not silently replace the milestone's existing agreement.

## Existing roadmap work

Statuses below describe the checkout and dex, not an assumption that every completed milestone has a published release.

| Existing work | Status | Contribution and recommendation |
| --- | --- | --- |
| Milestone 12: Packs, textures and PBR | Complete | Asset lifetime and material foundation. Extend Packs for shaders. |
| Milestone 13: Shadows | Complete | Existing Sun shadow foundation. |
| Milestone 24: Animation | Complete | Useful for a character and shader variant compatibility. |
| Milestone 33: Lighting | Complete | Emissive surfaces, per-Draw lights, and cascades. |
| Milestone 35: Materials per primitive | Complete | Required for separate trunk, leaf, roof, and window materials. |
| Milestone 36: Surface detail | Complete | Normal and occlusion maps. Imported tangents remain important. |
| Milestone 37: Post and Environment | Complete | HDR, tone maps, exposure, bloom, and distance fog. |
| Milestone 38: Transparency | Complete in checkout | Visible leaf cutouts and glass. Cutout shadows remain separate. |
| Milestone 39: Clustered lights | Open | Valuable for village lamps. Does not add GI or local-light shadows. |
| Milestone 40: Selection outline | Open | First general post-shader example. Revisit the dedicated outline contract. |
| Milestone 41: Particles | Open | Smoke, dust, and sparks. Its instance buffer does not automatically solve vegetation batching. |
| Milestone 42: Game fonts | Open | Useful for settings and demonstrations; not a scene-fidelity dependency. |
| Shader loading and reload | Open, later arc | Promote to an early dependency. Existing scope needs materials, parameters, variants, and post hooks. |
| Cutout shadows for MASK parts | Open | Promote before the foliage comparison. Existing research already describes implementation options. |
| Instancing and frustum culling | Open, later arc | Promote when the baseline reaches the draw budget. Dense grass makes this likely. |
| More than one shadow caster | Open | Optional for local lamps. Separate from clustered lighting. |
| A Draw that casts no shadow | Open | Useful for distant grass and explicit quality choices. |
| An equirectangular sky loader | Open | Easier sky input. It does not provide environment lighting by itself. |
| Blender as a level editor | Open | Useful for repeatable scene authoring. A small layout converter can start the reference sooner. |
| A Zelda-style open-world demo | Open | Later consumer. A bounded village is a smaller first test. |
| Benchmark regression tracking | Open | Compare the same camera path and effect settings across changes. |

Milestone 37 deferred shadow controls because no fidelity goal required them.
This scene supplies that goal.
The current fidelity arc excludes SSAO and depth of field.
The proposed scene can reconsider SSAO without making every lens effect mandatory.

New work needs explicit scope for shader contracts, quality presets, scene-depth access, sky lighting, and the reference scene.
Height fog, SSAO, vegetation LOD, and indirect lighting also lack a complete implementation plan.
Do not duplicate existing tasks for cutout shadows, shaders, clusters, or particles.

## Asset-based reference and delivery order

Use the downloadable project's layout and assets as source inputs.
The source investigation records the archive checksum and included permission files.
Most supplied models use separate `.gltf` and `.bin` files.
Rocco's current import path expects `.glb`.
Create a reproducible conversion step with explicit units, transforms, textures, tangents, and material names.
Keep source credits and terms with any imported subset.
Use `world.tscn` for the complete placement hierarchy.
The supplied `layout_data.json` contains vegetation exclusions, lanterns, and trees, but does not contain the complete layout.

Use a proposed `examples/village` with one fixed seed and repeatable camera positions.
Start with a few buildings, a ground patch, trees, grass, and lamps.
Expand only when the small scene answers its rendering questions.
Port the source shaders to Rocco's shader contract; do not expect Godot shader code to compile unchanged.

| Stage | Work | Acceptance evidence |
| --- | --- | --- |
| 1. Reference | Convert a small asset subset and layout. Add walking or camera movement, fixed views, and effect switches. | Bridge screenshots, source provenance, dimensions, material checks, and initial CPU/GPU measurements. |
| 2. Quality and foliage correctness | Add shadow controls, cutout shadows, mip coverage checks, and documented presets. | Roof edges, thin grass, leaf shadows, and cascade motion remain stable across a camera path. |
| 3. Surface authoring | Add shader assets, material slots, typed parameters, and shared pass variants. | Game-authored leaf wind, canopy normals, grass wind, and ground variation work without engine source edits. |
| 4. Vegetation scale | Add instancing, independent camera/shadow culling, conservative wind bounds, and distance control. | Dense grass fits the measured budget without disappearing shadows or visible culling errors. |
| 5. Atmosphere and lighting | Add sky lighting and selective height fog or SSAO. Apply clustered lights where lamp overlap requires them. | Side-by-side changes show better surface contact and depth, with separate effect costs. |
| 6. Post authoring and motion | Rework Milestone 40 around masks and game post shaders. Add Milestone 41 smoke and dust. | A game-authored outline, one colour effect, and repeatable particles run on all three backends. |
| 7. Remaining fidelity | Compare GI options, TAA, volumetric fog, and depth of field individually. | Adopt only features that improve the reference within its budget. Record rejected options. |

Define both shader extension contracts during stage 3, even if their implementations ship separately.
Milestone 39 can proceed independently if Agent Town needs it first.
A sparse sunlit scene does not need hundreds of lights before it can prove foliage and materials.

## Verification and completion criteria

- Capture fixed views and a moving-camera sequence at 1920 × 1080 physical pixels.
- Keep seed, camera, light placement, and simulation steps equal between comparisons.
- Expose independent switches for each effect and a reset to the baseline.
- Record CPU frame percentiles, GPU frame percentiles, pass costs, submits, and GPU resource estimates.
- Use native GPU tracing until Rocco provides equivalent GPU measurements.
- Record hardware, power state, build mode, warmup, and sample count.
- Use a proposed warm-run p95 frame target of 16.67 ms and report p99 spikes separately.
- Measure the full scene under a real clock; lockstep screenshots alone cannot prove frame pacing.
- Test shadows while the camera moves and foliage bends.
- Check foreground edges, distant grass, shadow acne, detached shadows, and cascade transitions.
- Verify shader compile failures, stale ids, reload failure, Pack unload, and capacity limits.
- Verify Metal, GL, and D3D screenshots with tolerances rather than exact cross-backend pixel equality.
- Demonstrate two game-authored surface shaders and two game-authored post styles through the same public contract.
- Require a human visual review of composition and motion before declaring the scene complete.

The reference is complete when it looks coherent, moves convincingly, meets its agreed budget, and supports game-authored style changes.
Open design choices remain: exact reference machine, runtime quality changes, shader package format, post inputs, and the first indirect-lighting method.
