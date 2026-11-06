# Complete village checkpoint

Status: local Metal checks passed; human review, native GL/D3D11 scene acceptance, and performance gates remain open.

The complete scene retains 1,436 source placements, 93 meshes, and 22,000 generated field placements.
Field visibility uses the source 65-metre distance plus a ten-metre fade margin.
The initial hero view emits 21,686 field Draws and every source placement.
The game preserves four house Groups and all six rotated source colliders.
Source textures, imported material maps, source casting, and field non-casting remain intact.
No density or texture reduction establishes a preset in this checkpoint.

## Integration and checks

Each mesh keeps its own complete Pack request.
Lighting, vegetation, and effects each receive one complete Pack request.
Lighting and vegetation retain the same terrain noise image through shared references.
Readiness requires every Pack callback and valid IDs for every required asset name.
The game caches prepared source and field Draws after complete readiness.
Source Draws retain asset names for named window overrides.
Effects use the existing Post, Selection, and particle APIs.
Keyboard controls remain independent across foliage, lighting, and effects.

The indirect-light correction uses the view-cosine magnitude for indirect response only.
It adds no resources or public fields.
Direct lighting, coverage, deformation, material factors, and casting remain unchanged.
The [diagnosis](../../docs/evidence/canopy-indirect-light-2026-11-05.md) records controlled comparisons.

| Check | Result |
| --- | --- |
| Strict engine, pinned Odin 902106f | 855 passed |
| Strict Spans engine | 855 passed |
| Python shader/package/reload/provenance suite | 78 passed; two Windows-only skips |
| Surface Roc tests | 100 passed |
| Village Roc tests | 175 passed |
| Build Roc tests | 146 passed |
| Source asset validation | 93 GLBs, 1,436 source placements, 22,000 field placements |
| Required village build | Five shader packages and two mesh helpers |
| Independent package/helper checks | Passed |
| Built-in shader generation drift | Passed |
| Village package interfaces | All five unchanged after indirect-light correction |
| Native Surface regression | Passed |
| Native opposite-normal regression | Rigid, instanced, and built-in/default image differences all zero |

The host uses ordinary release settings and pinned Odin `902106f`.
Native checks in this checkpoint use Metal.
The actual shaders also compile GL 4.3 and D3D11 payloads.
Payload compilation does not establish native backend acceptance.

## Joint foliage and lighting review

The corrected review package is `/tmp/village-final-joint`.
The matching replay is `/tmp/village-final-joint-replay`.
Both runs reach complete readiness at step 96.
Both reproduce every captured image and camera.
All captures verify 1920 by 1080 physical pixels.
The Retina window requests 960 by 540 logical pixels with high DPI enabled.
Effects are disabled for this joint lighting comparison.
The agent inspected all four views.

| View | Image | Steps after the readiness-relative hero reset |
| --- | --- | ---: |
| Hero | `hero.png` | 240 |
| Square | `square.png` | 241 |
| Grass | `foliage.png` | 242 |
| Canopy | `canopy.png` | 243 |

Each new fixed view receives one step before capture.
The approved lens remains 75 degrees.
The Bridge seed is zero and the field seed is 777.
The full field remains enabled with source casting and all lighting switches enabled.
Startup uses X4 MSAA, 2048 shadow maps, and two cascades.
Appearance preserves legacy fitting and Pcf3 filtering.
Exposure is 1.12 with AgX.
Bloom strength is 0.18.
Haze spans 14 to 120 metres with amount 0.38.

The corrected canopy has 2,994 near-black pixels in the diagnostic region.
The original diagnostic had 35,549 pixels.
Normal grazing-angle darkness and source shading approximations remain.
The [joint report](../../docs/evidence/village-combined/final-joint-metal.json) records exact cameras, settings, and hashes.

## Complete effects and route review

The corrected effects package is `/tmp/village-final-effects`.
Replay and alternate-seed packages use the `-replay` and `-seed7` suffixes.
The fixture advances 432 hero steps before effect comparisons.
This permits smoke and dust spawning before native capture.
It uses the full scene and actual scene shaders.
It selects Group 20 through the existing Enter ray without changing Draw tint.
Both outline policies, disabled outline, colour, opaque UI, wind, field, casting, smoke, and dust controls pass.
Every repeated image and camera matches.
The alternate game seed changes particle source streams.
All native logs are clean and all processes exit successfully.
The agent inspected both policy images and the route preview.

`route.mp4` contains eight seconds from the unchanged source tour.
The fixture retains eight camera records and frame hashes, then removes raw frames.
The preview establishes no pacing or performance result.
It does not replace complete-route acceptance.
The [effects report](../../docs/evidence/village-combined/final-effects-metal.json) records exact inputs, sources, cameras, and hashes.

All three CI jobs run the targeted complete-scene fixture.
Each job uses two repeat processes and one short alternate-seed check.
All three jobs pass `--hosted-compat` for fixed 960 by 540 physical and logical pixels.
This mode disables high DPI and preserves the 16:9 camera aspect.
It retains every source placement, field placement, effect, and particle source.
Hosted compatibility does not establish final 1080p visual acceptance or performance.
Linux uses the existing Xvfb and Mesa prefix.
The fixture retains full density during its bounded compatibility checks.
The fixture records its evidence mode, expected dimensions, and actual physical and logical dimensions for every capture.
It verifies both Bridge dimensions and decoded PNG dimensions.
The default remains strict 1920 by 1080 with high DPI disabled.
The local `--retina-1080` option requests 960 by 540 logical pixels for a 2x display.
Both strict modes require exactly 1920 by 1080 physical pixels.
The UI assertion scales an interior panel region from logical coordinates using the verified physical dimensions.
It compares 7,350 opaque UI pixels at 1x and 29,400 at 2x.
Outline policies and colour changes must exceed the same image-area fraction at both resolutions.
The strict threshold remains 1,000 changed pixels; hosted compatibility requires more than 250.
Long Bridge advances use requests of at most 24 steps without changing simulation totals or route capture times.
The 432-step warmup, source-camera inputs, seed checks, and replay assertions remain unchanged.

CI run `42017935944` passed the earlier native suites before the complete-village fixture failed.
Those earlier native results remain separate from complete-village acceptance.
The Mac fixture received 960 by 540 physical pixels from its Retina option on a 1x display.
The Windows desktop clamped its large window to 1028 by 749 physical pixels.
Linux passed initial 1080p captures and wind checks, then timed out during one 432-step request.
These failures establish no complete-village native acceptance.
The hosted correction requires new native results on all three systems.
The [local hosted Metal report](../../docs/evidence/village-combined/hosted-metal.json) passes both full replays and the alternate-seed check.
Every Bridge capture and decoded PNG verifies 960 by 540 physical and logical pixels.
The opaque UI comparison preserves 7,350 pixels.
The agent inspected the hero, selected outline, and readable opaque controls panel.
The four fixture unit tests, 178 village Roc tests, and required game build passed.
Native GL and D3D11 hosted results remain pending.
Functional captures do not enable Spans automatically.
Performance captures must explicitly select an instrumented host and output path.

## Open gates

Human joint appearance review remains open.
Native GL and D3D11 scene checks remain open.
The sky remains a fixed-time LDR approximation with clipped HDR values and shared sky intensity.
Canopy normals, backlight, specular response, and tint interpolation approximate the source shaders.
Smoke and dust receive no scene fog.

The preliminary development Roc CPU diagnostic reported p95 48.89 ms under contention.
Interpolation dominated that diagnostic.
This checkpoint preserves that deficit and makes no frame-budget or pacing claim.
Controlled CPU and GPU profiling must retain every slow sample.
Independent effect costs, measured Mac and PC presets, complete-route checks, and the final desktop run remain open.
The complete-scene human review remains open.
