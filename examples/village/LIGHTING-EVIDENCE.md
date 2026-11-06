# Isolated lighting evidence

Date: 2026-11-05.
Status: implementation verified on the baseline subset; complete-layout integration and acceptance remain pending.

The isolated scene retains the 33 baseline meshes and all 154 source placements.
The approved camera equations, 75-degree lens, route points, and cumulative source transforms remain unchanged.
The lighting module replaces the ground and environment and adds six source practical lights.
The source window override targets only named glass slots.
No complete-layout or foliage result is claimed by these captures.

## Verification

The required `roc scripts/build.roc -- game village` command passed.
The isolated village passed all 165 Roc tests.
The ground declaration compiled Metal, GL 4.3, and D3D11 payloads through the pinned shader compiler.
The generated helper files match a separate build from `lighting-shaders.json`.
Native rendering ran on Metal.
New native GL and D3D11 scene checks remain for combined integration.

Two lighting preparations produced identical manifests and output hashes.
Both preparations verified the source archive checksum.
The standalone mask and noise PNGs match the archive bytes.
The tracked manifest records every prepared image hash and the clipping count.

The native fixture captured 24 images at 1920 by 1080 physical pixels.
Each capture used seed zero and 480 simulation steps after complete readiness.
Each process reached readiness at step 34.
The fixture used a 960 by 540 logical window with `--retina-1080`.
The default 1x display configuration remains 1920 by 1080 with high DPI disabled.
Window changes require a restart.

The fixture captured hero, square, and tour with all switches enabled.
It also captured each view with sun, sky, exposure, ground, lamps, bloom, or haze disabled independently.
Every view kept an identical camera across its eight comparisons.
All 24 native processes exited successfully.
Their logs contain no graphics errors, graphics panics, or missing-resource diagnostics.

Removing the sky changed surface lighting and the background together.
The lower image quarter contains ground and buildings in these approved views.
Mean absolute RGB differences in that quarter were:

| View | Mean channel difference, 0 to 255 |
| --- | ---: |
| Hero | 44.337 |
| Square | 65.597 |
| Tour | 66.932 |

The agent inspected hero, square, and tour sky comparisons.
The agent also inspected the ground and lamp comparisons.
Window emission remains visible when the sky is disabled.
The ground comparison shows source wear and terrain variation instead of the flat baseline colour.
The lamp comparison restores imported glass when the lamp switch is disabled.

The hero and square all-on images match an earlier capture byte for byte.
Those captures used separate processes and an earlier binary with identical scene values.
The sky, ground, and lighting output therefore repeat at equal simulation inputs in this isolated scene.

Artifacts remain outside the repository:

- `/tmp/village-lighting-final/lighting.json`
- `/tmp/village-lighting-final/{hero,square,tour}-{all,sky,sun,exposure,ground,lamps,bloom,haze}.png`
- `/tmp/village-lighting-final/*.log`
- `/tmp/village-lighting-comparisons.bin`
- `/tmp/village-lighting-repeat/source/lighting-manifest.json`
- `/tmp/village-lighting-integration.patch`

The comparison binary SHA-256 is `0f416a0cd4b6578e2df49b2672e7c533e721c4aacb69895db43357bbdea46f9a`.
The linked host archive SHA-256 is `ff6429340e08d8e3493ec230005814f2241191da44b8ba8148ed02469b485c8c`.
The host archive came from the current main checkout's prepared platform target.
This work did not independently establish its optimization or instrumentation mode.
No timing or frame-budget result is claimed.
Other development work shared the machine.

The final build also captured the initial hero pose after two steps, matching the baseline fixture's capture point.
The agent inspected `/tmp/village-lighting-source-hero/hero-all.png` at 1920 by 1080 physical pixels.
Its metadata is `/tmp/village-lighting-source-hero/lighting.json`.
The final binary SHA-256 is `d07f83130ca73ec329a124cb842c9eab5a2d8a0757ebe87e94d7d842c7f16d04`.
This build includes the final record argument for window overrides.

Reproduce the comparisons after connecting the documented integration seam:

```sh
roc scripts/build.roc -- game village
python3 examples/village/fixtures/lighting.py /tmp/village-lighting-final --retina-1080 --require-1080
```

## Integrated baseline checks

The lighting module and village entry point are integrated.
The village now loads the complete lighting Pack after the mesh Packs.
Readiness checks every required asset name, including Sky, Image, and Shader assets.
Two regressions reject mesh-only readiness and a missing shader with the correct manifest count.
The village passed 167 Roc tests and the build script passed 146 tests.
The required village build, Roc checks, and formatting passed.
All eight prepared image hashes and three independently generated helpers match.
The generated shader assets and mesh metadata match the isolated declaration build.

The integrated hero and square captures use 480 steps after readiness.
Both processes reached readiness at step 34 and exited without native diagnostics.
Both captures are 1920 by 1080 physical pixels with `--retina-1080`.
Their image hashes, cameras, and environments match the isolated captures exactly.
The agent inspected both integrated images.
The [integration report](../../docs/evidence/village-lighting/metal-integration.json) records hashes and checks.
The raw images and logs remain at `/tmp/village-lighting-merged`.
These checks cover the baseline subset on Metal.
Combined foliage, full-layout, human, GL, D3D11, and performance gates remain open.

## Remaining gates

Merge the lighting module with the complete layout, vegetation, effects, and combined loading state.
Check clustered lamp stability across the complete source route.
Check native Metal, GL, and D3D11 scene rendering after integration.
Obtain the combined foliage and lighting human review.
Measure independent effect costs and complete-scene CPU and GPU work.
Choose measured Mac and PC presets.
Complete the final desktop run and complete-scene human review.

The cubemap remains a fixed-time LDR approximation.
Its source limits and the atmosphere choices are explicit in `LIGHTING.md`.
Height fog, contact occlusion, custom sky rendering, and a specific GI technique remain deferred.
