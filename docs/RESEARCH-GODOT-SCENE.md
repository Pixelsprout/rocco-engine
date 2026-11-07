# Research: the Godot village reference

Date: 2026-11-05

## Purpose

Use one reference scene to test Rocco's rendering features, developer controls, and performance.
This note records external evidence.
The companion gap analysis compares that evidence with Rocco's source and roadmap.

## The reference scene

The guide demonstrates these changes:

| Step | Technique |
| --- | --- |
| 1 | A lower, warmer sun with softer shadows. |
| 2 | A custom sky that supplies ambient lighting. |
| 3 | AgX tone mapping, exposure, and a colour grade. |
| 4 | SSAO and SSIL for contact detail. |
| 5 | SDFGI for indirect light. |
| 6 | Distance fog, ground mist, and volumetric fog. |
| 7 | Canopy normals, tree movement, and leaf backlighting. |
| 8 | Grass movement, root shading, and a ground material. |
| 9 | Chunked grass instances with distance limits. |
| 10 | Lantern lights, emissive windows, and a character light layer. |
| 11 | Camera framing and depth of field. |
| 12 | MSAA, TAA, debanding, vignette, grain, and dust. |

The author reports large performance gains after reducing shadow quality and vegetation range.
Those measurements describe one GPU and scene.
They do not establish Rocco's performance targets.
Compare each effect separately, with fixed content and camera positions.
[Coding Quests guide](https://codingquests.io/blog/how-to-make-godot-3d-look-better).

## Assets and reuse

The public [village archive](https://codingquests.io/api/downloads/blog-godot-3d-village-look) downloaded successfully.
Its size is 243,669,141 bytes.
Its SHA-256 is `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.
The inspected copy remains at `/tmp/cq-godot-3d-village-look.zip`.

The archive contains 106 `.gltf` files, 108 `.bin` files, two `.glb` files, seven shaders, and five scenes.
External textures accompany the glTF files.

The archive's README names Quaternius as the model and texture creator.
The packs include Medieval Village MegaKit, Fantasy Props MegaKit, Stylized Nature MegaKit, and Ultimate Stylized Nature.
Character packs include Universal Base Characters, Modular Character Outfits - Fantasy, and Universal Animation Library 1 and 2.
`assets/LICENSE_CC0_Quaternius.txt` declares CC0 1.0.
The README permits use of CodingQuests scripts and shaders in games.

Quaternius also labels the [village pack](https://quaternius.com/packs/medievalvillagemegakit.html) and [nature pack](https://quaternius.com/packs/stylizednaturemegakit.html) CC0.
The creator distinguishes free model downloads from paid source packages with engine setup and shaders.

## Archive inspection

Paths in this section are relative to the archive's `cq-godot-3d-village-look/` directory.
The observations below come from the downloaded source, not a local execution.

### Reusable inputs

| Input | Purpose |
| --- | --- |
| `assets/` | Models, buffers, textures, and the asset license. |
| `scenes/world.tscn` | Asset references, scene hierarchy, placement transforms, and object groups. |
| `scenes/actors.tscn`, `scenes/ranger.tscn` | Character and camera setup. |
| `scenes/layout_data.json` | 176 vegetation exclusion rectangles, six lantern records, and 159 tree records. |
| `textures/ground_mask.png` | Ground wear and shade mask. |
| `textures/T_Noise_Terrain.png` | Shared noise for ground, wind, and sky. |
| `scripts/look.gd` | Material assignments, quality profiles, vegetation generation, and effect switches. |
| `scripts/camera_rig.gd` | Reference camera positions and movement. |
| `scenes/finished.tscn` | Lights, dust, ground mist, and camera attributes. |

The JSON file does not contain the complete village layout.
A conversion must also read `world.tscn` or export its instantiated hierarchy through Godot.
The ground shader names `tools/build.gd` as the mask generator.
That script is absent from the archive.
The existing mask is available for reuse.

### Shader behaviour

`shaders/foliage.gdshader` uses object height for canopy movement and world position for leaf flutter.
It blends imported normals with outward canopy normals.
Its fragment stage preserves the canopy normal on both card faces.
The shader uses alpha cutouts, interior darkening, per-instance colour variation, and `BACKLIGHT`.
This backlighting is an artistic material response, not a general transmission simulation.

`shaders/grass.gdshader` reads the red vertex-colour channel as the root-to-tip weight.
It uses object height when vertex colours are absent.
The squared weight anchors roots while tips move.
World-space noise coordinates keep gusts consistent across neighbouring instances.
The shader also changes normals, colour, ambient occlusion, and backlighting.

`shaders/ground.gdshader` combines world-space noise with the supplied ground mask.
`shaders/cloth.gdshader` moves banners away from their pole.
`shaders/sky.gdshader` renders clouds and distant ridges.
`shaders/post.gdshader` applies colour grading, vignette, and grain.

These files show why one generic fragment replacement would be insufficient.
The contract also needs vertex inputs, instance parameters, normal outputs, and texture access in vertex shaders.

### Settings and comparison limits

`project.godot` declares Godot 4.7, Forward+, and a 1920 × 1080 viewport.
`look.gd` selects the advertised optimised profile: a 4096 shadow atlas, medium soft shadows, MSAA 2×, and 22,000 grass instances.
Its polish switch also enables TAA and debanding.
Its environment values enable SSAO, SSIL, SDFGI, ordinary fog, and volumetric fog.
The finished scene contains 160 dust particles.

The source adds details beyond the guide's short descriptions:

- The foliage switch also enables banner movement.
- The lights switch also changes glow and window materials.
- Every switch starts enabled, including the lens switch.
- The added grass field always uses its grass shader while the field remains visible.

Consequently, the grass and field switches do not isolate movement and density independently.
Rocco's benchmark should separate those controls.
The source agrees with the guide's main numeric quality settings.
The reported frame rates and visual equivalence remain unverified locally.

## Quality controls

Godot separates environment appearance from project quality settings.
Camera attributes supply exposure and depth of field.
[Environment documentation](https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html).

Recommended Rocco separation:

| Role | Controls |
| --- | --- |
| Appearance | Sun direction, colour, exposure, fog density, material parameters. |
| Quality profile | Shadow resolution, cascades, filtering, AA, render scale, effect quality. |
| Object policy | Shadow casting, visibility distance, light layers, material override. |
| Camera | Field of view, exposure override, focus distance, optional depth of field. |

Profiles should provide defaults and explicit overrides.
The renderer should report the settings it accepted.
Unsupported settings need documented fallbacks.

Godot exposes shadow resolution, splits, range, filtering, bias, normal bias, and angular light size.
Each cascade can add geometry submissions.
Reducing shadow range can improve both detail and cost.
[Lights and shadows](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html).

MSAA smooths geometry edges but does not directly solve alpha-test or specular aliasing.
Alpha to coverage addresses cutout edges when MSAA is available.
TAA uses frame history and can introduce blur or ghosting.
FXAA and SMAA provide spatial alternatives.
[3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html).

Test fences, leaf cards, glossy surfaces, camera cuts, and moving grass.
Measure each pass separately.
Screenshots alone cannot establish temporal quality.

## Shader extension boundaries

Godot exposes vertex, fragment, and light functions for spatial shaders.
Its inputs include transforms, vertex colour, UVs, normals, time, and instance data.
Custom materials can retain engine lighting.
[Spatial shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

Recommended Rocco extension surfaces:

| Surface | Developer supplies | Renderer supplies |
| --- | --- | --- |
| Material | Vertex deformation, surface values, textures, parameters. | Transforms, lighting, shadows, pass variants. |
| Sky | Background radiance by direction. | Camera direction, sun inputs, lighting updates. |
| Screen effect | Image operation at a declared stage. | Textures, dimensions, depth conventions, output target. |

The developer should replace a material without editing Odin.
Parameters need global, material, and instance scopes.
The contract must define normal spaces and two-sided behaviour.
Custom deformation must preserve silhouettes across shadow, depth, colour, and future velocity passes.
The renderer needs expanded bounds for displaced vertices.
Godot provides custom bounds and extra culling margins for related cases.
[GeometryInstance3D](https://docs.godotengine.org/en/stable/classes/class_geometryinstance3d.html).

A first version can compile shaders during the build.
Runtime compilation can follow after diagnostics and compatibility rules exist.
Godot also identifies precompilation and caching limits for runtime shader source.
[Compositor](https://docs.godotengine.org/en/stable/tutorials/rendering/compositor.html).

### Selection outlines

A selection outline can test the screen effect contract.
Depth and normals locate visible edges.
They cannot identify the selected object alone.
Rocco needs a selection mask, an identifier texture, or a separate selected-object pass.
The game should choose outline colour, width, pulse, and occlusion policy.
The renderer should supply buffers and execution order.

Godot documents depth reconstruction and differences between graphics backends.
Rocco's contract must state its own depth conventions.
[Advanced post-processing](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html).
This outline design is an architectural recommendation.
The guide does not implement an outline.

### Sky and scale

Godot uses sky shaders for backgrounds and radiance cubemap updates.
Time-dependent shaders can force frequent lighting updates.
[Sky shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html).
Rocco should allow separate update rates for background rendering and environment lighting.

MultiMesh batches repeated geometry, but visibility applies to the whole batch.
Spatial chunks restore useful culling granularity.
[MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html).
Rocco's vegetation target should include batching, chunk bounds, distance limits, and instance variation.

## Optional effects

Godot offers baked lighting, probes, voxel methods, and SDFGI with different costs and limitations.
SSIL complements other indirect lighting methods.
[Global illumination comparison](https://docs.godotengine.org/en/stable/tutorials/3d/global_illumination/introduction_to_global_illumination.html).
Rocco can evaluate baked lighting or probes before committing to SDFGI.

Volumetric fog interacts with lighting and has finite range.
Temporal filtering can cause trails behind moving lights or volumes.
[Volumetric fog](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html).
Distance and height fog provide a smaller initial target.

## Verification limits

This research inspected the guide, Godot documentation, creator pages, and the supplied archive.
No assets entered the repository.
No shader was compiled for Rocco.
No performance figure was measured locally.
Godot documentation under `stable` can change after this research date.
