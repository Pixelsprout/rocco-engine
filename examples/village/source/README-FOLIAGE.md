# Complete layout and vegetation

Implementation date: 2026-11-05.
The human foliage and lighting review remains pending.
The final Mac and PC presets remain pending.
The final per-effect costs remain pending.
The source composition approval remains valid.

## Prepared source

The converter includes every PackedScene instance in `world.tscn`.
The complete layout contains 1,436 placements and 93 unique meshes.
The converter preserves the approved baseline IDs.
The converter preserves cumulative source transforms.
Mesh placement remains separate from mesh vertices.
The converter preserves source material names, roots, vertex colours, UVs, and existing tangents.
The converter generates missing tangents.
The converter keeps original PNG payloads at source resolution.

Two source bark images use JPEG.
Nine meshes share those images.
Pillow converts their decoded pixels to PNG at 2048 by 2048.
The converter checks exact decoded-pixel equality.
The manifest records source hashes, prepared hashes, dimensions, pixel hashes, Pillow version, and JPEG codec version.
The checked conversion used Pillow 11.3.0 and JPEG codec 8.0.
The committed GLBs occupy 738,500,960 bytes.
Ordinary builds require neither Pillow nor the archive.

Prepare the complete source with these commands:

```sh
python3 -m venv /tmp/village-converter
/tmp/village-converter/bin/pip install Pillow==11.3.0
/tmp/village-converter/bin/python examples/village/source/prepare.py /tmp/cq-godot-3d-village-look.zip
python3 examples/village/source/validate.py --archive /tmp/cq-godot-3d-village-look.zip
```

The archive checksum remains `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.
The archive validator compares every source transform.
The archive validator also repeats the complete field recipe.
It checks original texture hashes and conservative shader displacement bounds.
The normal validator checks committed products without the archive.

## Field recipe

The prepared field contains 22,000 placements.
Its source seed is 777.
Its seven species, probabilities, ranges, scale ranges, exclusions, and rejection rule follow `scripts/look.gd`.
The exclusions come from supplemental `layout_data.json`.
The complete fixed layout still comes from `world.tscn`.
The source recipe required 41,035 attempts.
The source field remains complete before visibility filtering.
Density controls select a stable prefix of the generated placement IDs.
They do not regenerate the field.

`SourceRandom` follows Godot 4.5 RandomPCG float sampling.
Its independent Python calculation uses binary64 for geometric distance and quaternion construction.
It does not claim bit-identical Godot transform matrices.
The converter and validator reproduce the committed sequence exactly.

Generator references:

- [Godot RandomPCG](https://github.com/godotengine/godot/blob/4.5/core/math/random_pcg.h).
- [Godot RandomNumberGenerator](https://github.com/godotengine/godot/blob/4.5/core/math/random_number_generator.h).
- [PCG32 implementation](https://github.com/godotengine/godot/blob/4.5/thirdparty/misc/pcg.cpp).

Godot distributes its wrapper under the MIT licence.
The PCG source identifies its Apache 2.0 licence and M.E. O'Neill attribution.
The archive's original model and shader terms remain in the adjacent source files.

## Shader behaviour

`VillageCanopy` changes named leaf and flower slots only.
Bark retains its imported Surface and maps.
`VillageGrass` preserves imported maps and source vertex weights.
The grass vertex hook reads red as the root weight before replacing its display colour.
Zero root weights produce zero wind movement.
Plants without weights use their mesh height.

Both shaders calculate world offsets with simulation time.
They convert offsets through public `Vertex.world_to_local_direction`.
Neighbours share world-space gusts and wind direction.
World origins determine canopy phase and hue variation.
Material values repeat by mesh.
No instance has unique shader parameters or Draw data.
Rigid and instanced variants remain enabled.

The canopy shader blends imported normals with outward canopy normals.
The grass shader blends imported normals with world-up normals.
Both Surface hooks cancel the renderer's back-face normal reversal.
The renderer retains the geometric normal for shadow bias.
Imported alpha cutoffs remain unchanged on source placements.

The field uses `Mask(0.2)` for its coverage fade.
Its four source Opaque grass images have alpha 255 at every pixel.
Its flower and clover materials already use source cutoff 0.2.
The field therefore preserves imported coverage before applying its fade.
The Surface multiplies opacity by stable world-space dither coverage.
Colour, shadow, depth, and Selection variants compile the same opacity hook.
Field Draws remain non-casters, as in the source.

The visibility distance remains 65 metres.
A ten-metre margin fades field coverage from 65 through 75 metres.
The game omits roots beyond that outer envelope.
Source placements remain available to independent camera and shadow culling.
The source uses MultiMesh chunk visibility; this port applies visibility to individual roots.
The dither approximation replaces the source's renderer-specific visibility fade.

The canopy local displacement bound is 0.3 metres.
The grass local displacement bound is 2 metres.
The bounds include the smallest positive source scales.
The archive validator checks both bounds against the shader amplitudes.
The shader declarations preserve expanded bounds in every pass.

Root and canopy tint interpolation occurs in the vertex hook.
The source applies its nonlinear tint after interpolating its custom varyings.
The Surface estimates occlusion from the interpolated tint.
The lighting hooks approximate source backlight and specular response.
These differences require the joint visual review.
They introduce no engine styling or renderer extension.

## Controls

Keys 4 through 8 toggle wind, canopy shading, grass shading, the field, and source casting respectively.
The field keeps its source non-casting policy when source casting changes.
The `vegetation` Bridge port accepts these same switch names:

```text
wind
canopy
grass
field
casting
density=22000
distance=65
```

The initial flags accept `--density=22000` and `--distance=65`.
The default density remains 22,000.
The live controls require no restart.

The `quality` Bridge port accepts these live shadow controls:

```text
shadow-distance=60
normal-bias=0.05
depth-bias=0.0005
distribution=0.5
blend=0.1
filter=hard
filter=3
filter=5
```

Initial shadow flags use the same names with a `--` prefix.
The named startup presets are `--quality=low`, `--quality=balanced`, and `--quality=high`.
They use the public `Shadow` presets.
The default preserves the previous two-cascade startup and existing shadow appearance.
These presets are diagnostic choices, not measured machine recommendations.
All presets preserve the full field and source layout.

Explicit startup overrides apply after the selected preset:

```text
--shadow-map=2048
--cascades=2
--msaa=off
--msaa=2
--msaa=4
--msaa=8
```

Shadow resolution, cascade count, and MSAA changes require a restart.

## Capacity and integration

| Budget | Count |
| --- | ---: |
| Prepared meshes | 93 |
| Source Draws | 1,436 |
| Prepared field Draws | 22,000 |
| Source material part budget | 1,942 |
| Field material part budget | 23,297 |
| Ground part budget | 1 |
| Maximum combined part budget | 25,240 |
| Requested mesh capacity | 128 |
| Requested part capacity | 32,768 |

The part budget includes double-sided Blend submissions.
The renderer may merge compatible source parts.
The part capacity applies separately to each admitted rendering pass.
The engine reserves its shadow, colour, depth, and Selection ranges from that capacity.
The renderer performs separate camera and shadow culling.
No scene content was removed to meet the capacity.

`Vegetation.prepare(manifest)` creates cached source and field Draw descriptions after readiness.
`Vegetation.draw(placement, settings)` applies source switches and source casting.
`Vegetation.field_nodes(prepared, { settings, eye })` applies field density and visibility.
`Vegetation.scene_values(settings, eye)` supplies shared wind and visibility values.
The foliage declarations use helper names `VillageCanopy` and `VillageGrass`.
The helper modules are generated from the combined `shaders.json`.
The standalone declarations live in `shaders/foliage-declarations.json`.

Load these assets together in Pack `village-vegetation`:

```text
shader/VillageCanopy
shader/VillageGrass
image/T_Noise_Terrain
```

The shared noise image path is `assets/images/T_Noise_Terrain.png`.
Its SHA-256 is `42667fd6c362524a1870b65294e360b97831c0fa0da9d22964a558e01e9dcb5e`.
The lighting owner supplies that exact image.
The grass sampler uses linear colour, linear filtering, and repeat wrapping.

Each mesh retains a separate Pack named after its asset.
`Layout.mesh_info` preserves source slot names and indices.
`Layout.colliders` contains all six source collision boxes, including rotations.
Buildings A through D use Groups 10, 20, 30, and 40.
Their collision boxes use the same IDs.
The remaining source prop colliders use IDs 50 and 60.
Walking transforms the player into each box's local frame.
It keeps the previous 0.3-metre margin.
The free camera ignores those boxes.

The isolated main preserves hero, square, and tour cameras.
It also supplies `foliage` and `canopy` Bridge views for close inspection.
The merger owns combined main, requests, readiness, declarations, fixtures, and final evidence.
A Pack must receive its complete asset request in one Load command.
Repeated Load commands do not extend an already loaded Pack.
The isolated main hides all geometry until every mesh, shader, and image resolves.
Failed IDs keep the loading error visible.

## Verification and remaining gates

Run the native verification with these commands:

```sh
roc scripts/build.roc -- game village
python3 examples/village/fixtures/foliage.py /tmp/village-foliage --hero-steps 1680 --replay
```

The fixture checks complete loading, four Groups, six colliders, source casting, field casting, camera poses, motion, and replay.
Its default hero duration is 1,680 steps after resetting the view.
A 240-step diagnostic is also available.
The final combined route fixture still belongs to integration.
The capture uses seed zero and source field seed 777.

The first complete Bridge scene emitted 21,686 field Draws at the initial hero eye.
It also emitted all 1,436 source Draws and the ground.
Its 23,123 Draws differ from the generated 23,437 because of visibility filtering.
The fixture records generated counts and emitted counts separately.
The first two diagnostic hero PNGs had identical SHA-256 values.
The final diagnostic replay hash was `6db0bedcb3070e3e42decf781fcb3d4b30fcd23f89fbe2d5790d06f39f82df81`.
Its binary hash was `c86f0c2c5aabb24a42039ea6b66e8d2122226df999063fd163ceadc82c80c035`.
The fixed capture used 1920 by 1080 physical pixels.
The Retina window used 960 by 540 logical pixels with high DPI enabled.

The first full-density CPU diagnostic used 121 hero samples after 120 warmup steps.
Median CPU work was 39.78 ms.
P95 CPU work was 48.89 ms.
P99 CPU work was 58.51 ms.
Median interpolation work was 25.87 ms.
Median view work was 7.28 ms.
Median render submission work was 6.14 ms.
The release host used pinned Odin `902106f` and CPU Spans.
The Roc game used development compilation.
The machine used AC power.
Other development work shared the machine.
This diagnostic exceeds the target and does not measure GPU work or real-clock pacing.
It does not justify a density reduction before the combined performance investigation.

The final evidence must retain every slow sample.
The final evidence must measure GPU work, real-clock pacing, per-effect costs, and both reference presets.
The human must review foliage and lighting together.
The human must also review the complete scene and the desktop run.

Native artifacts remain outside the repository:

- `/tmp/village-foliage-final/` contains the final images, camera records, host log, and CPU CSV.
- `/tmp/village-foliage-final-replay/` contains the matching replay.
- `/tmp/village-foliage-evidence/capture-spans.csv` contains the first full-density CPU diagnostic.
- `/tmp/village-foliage-evidence-replay/` contains its replay.
- `/tmp/village-foliage-hero.png` contains the earlier final hero push.

The final fixture ran `python3 examples/village/fixtures/foliage.py /tmp/village-foliage-final --hero-steps 240 --replay`.
The earlier hero push used `scripts/screenshot.sh village /tmp/village-foliage-hero.png 1776`.
The earlier capture reached the end of the source easing.
The final replay reset the hero view after readiness and advanced exactly 240 steps.
The combined comparison must use equal readiness-relative steps and recorded camera poses.
