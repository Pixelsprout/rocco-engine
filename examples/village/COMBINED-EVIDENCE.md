# Combined foliage and lighting evidence

Status: local Metal compatibility passed; human and native GL/D3D11 acceptance remain open.
The complete layout contains 1,436 source placements and 93 prepared meshes.
The prepared field contains 22,000 placements with source seed 777.
Visibility uses the source 65-metre distance and a ten-metre fade margin.
No source content or texture resolution was reduced.

## Integration

The game requests each mesh Pack separately.
The game requests the complete lighting and vegetation assets in separate Packs.
Both Packs retain the shared terrain noise image.
Readiness requires every Pack callback and every required asset name with a valid ID.
Failed assets keep the loading error visible.
The game prepares source and field Draws once after complete readiness.
Prepared source Draws retain their asset names for window material overrides.
The scene retains four house Groups and all six rotated source colliders.
Lighting window overrides preserve imported maps and other material slots.

The required village build passed with three Surface packages and two mesh helpers.
All 172 village Roc tests and 146 build tests passed.
The asset validator passed all 93 GLBs, 1,436 source placements, and 22,000 field placements.
The three shader packages and five helpers match independent lighting and foliage declarations.
The pinned shader compiler built the actual Metal, GL 4.3, and D3D11 payloads.
Native scene execution in this checkpoint used Metal.
The prepared host uses ordinary release settings and pinned Odin `902106f`.

## Human review package

The review images and metadata remain at `/tmp/village-combined-review-final`.
The matching replay remains at `/tmp/village-combined-review-final-replay`.
The agent inspected hero, square, grass, and canopy images.
All eight captured images match the replay byte for byte.
Both native logs are clean and both processes exit successfully.
The [review metadata](../../docs/evidence/village-combined/metal-review.json) records cameras and hashes.
`REVIEW.md` beside the images records settings and caveats.

| View | Image | Steps after the readiness-relative hero reset |
| --- | --- | ---: |
| Hero | `hero.png` | 240 |
| Square | `square.png` | 241 |
| Grass | `foliage.png` | 242 |
| Canopy | `canopy.png` | 243 |

Each new fixed view receives one step before capture.
Readiness completes at step 95.
The initial view emits 1,436 source Draws, 21,686 field Draws, and the ground.
The remaining prepared field roots are outside the visibility envelope.
The Bridge seed is zero.
All captures verify 1920 by 1080 physical pixels.
The Retina window uses 960 by 540 logical pixels with high DPI enabled.
The approved lens remains 75 degrees.
Startup uses 2048 shadow maps, two cascades, and X4 MSAA.
Appearance uses legacy fitting and Pcf3 filtering.
Wind, canopy shading, grass shading, source casting, and all lighting switches remain enabled for the four views.
Field Draws retain their source non-casting policy.
Exposure is 1.12 with AgX.
Bloom strength is 0.18.
Haze spans 14 to 120 metres with amount 0.38.

Reproduce the review with these commands:

```sh
roc scripts/build.roc -- game village
python3 examples/village/fixtures/foliage.py /tmp/village-review --hero-steps 240 --replay --retina-1080
```

The review binary precedes a loading-progress text correction.
The correction changes no ready scene values or rendering settings.
The bounded native report records the final binary separately.

## Bounded CI checks

All three native CI jobs build the actual village shaders and run `fixtures/foliage.py --compat --replay`.
The Metal job also passes `--retina-1080`.
Linux uses the existing Xvfb and Mesa prefix.
Each pass retains full source content and the default 22,000-placement field.
Each pass advances two hero steps after readiness.
It then captures square, grass, and canopy after one step each.
Two additional steps verify moving wind.
Two steps with wind disabled verify stable pixels.
The fixture checks source casting, field visibility, sky lighting, and a live shadow setting.
Each replay compares every image hash, camera, and readiness step.
The fixture verifies physical dimensions, clean native logs, and process exit.
The [local bounded report](../../docs/evidence/village-combined/metal-compat.json) passed twice from the final binary.
These bounded checks establish backend compatibility and deterministic controls.
They make no performance claim.

Functional captures do not enable Spans automatically.
Performance captures must explicitly select an instrumented host and set its output path.

## Open gates

The sky remains a fixed-time LDR approximation with clipped HDR values and shared sky intensity.
Canopy normals, backlight, specular response, and tint interpolation approximate the source shaders.
The close canopy view retains very dark underside regions for human review.
The joint foliage and lighting human review remains open.
Outline and particle effects remain a separate integration step.
Native GL and D3D11 scene acceptance remains open.
The complete route, independent effect costs, measured presets, and final PC run remain open.

The preliminary development Roc CPU diagnostic reported p95 48.89 ms under contention.
Interpolation dominated that diagnostic.
This checkpoint preserves that deficit and makes no frame-budget or pacing claim.
Controlled CPU and GPU profiling must retain every slow sample.
