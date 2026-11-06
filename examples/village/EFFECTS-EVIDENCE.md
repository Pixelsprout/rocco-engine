# Isolated effects evidence

Date: 2026-11-05.
Status: baseline effects verified on Metal; combined-layout validation and acceptance remain pending.

The effects branch starts from the verified lighting integration.
It retains all 154 baseline placements, 33 meshes, approved camera equations, and route points.
The shared integration changes Group selection, asset readiness, Post effects, particles, and optional UI controls.
It preserves ray selection and removes selection tint.
The full-layout merger keeps its expanded Groups, colliders, and vegetation controls.

The required village build passed with zero errors and warnings.
The village passed all 167 Roc tests.
The build script passed all 146 Roc tests.
Roc check, Roc formatting, Python compilation, and git whitespace checks passed.
The effects declaration produced `glsl430`, `hlsl5`, and `metal_macos` payloads.
This proves package compilation for those targets.
Native scene rendering in this worktree used Metal only.

Both effects-only helpers match their combined-build helpers byte for byte.
Both effects-only shader packages match their combined-build packages byte for byte.
The verified lighting host library remains unchanged.
Its SHA-256 is `ff6429340e08d8e3493ec230005814f2241191da44b8ba8148ed02469b485c8c`.
No engine source changed.

All 15 final captures use one binary and 480 steps after each fixed view.
Every capture has 1920 by 1080 physical pixels with `--retina-1080`.
Every process reaches readiness at step 35.
The fixture loads every mesh and effect asset before showing the scene.
Disabling effects restores the verified lighting hero PNG byte for byte at equal 480-step inputs.
It selects Group 20 through the existing Enter ray.
It checks that selected Group 20 contains 24 Draws with unchanged white tint.
It compares visible-only, through-wall, and disabled outlines from the same selected Group.
It also compares colour, smoke, dust, and all effects independently.
The repeat capture uses equal seeds and fixed steps.
The alternate seed changes particle pixels.
The controls panel supplies an opaque UI region for colour-effect parity checks.

Equal seeds and steps produce identical decoded hero pixels.
The UI comparison preserves all 124656 tested opaque panel pixels.
Changing the particle seed changes 2123 pixels.
Disabling smoke changes 3719 pixels; disabling dust changes 38 pixels.
Disabling colour changes all 2073600 world pixels.
The square visible/through comparison changes 61480 pixels.
The square visible/disabled comparison changes 521235 pixels.

The agent inspected hero, square, and both outline policies.
The final behind-tree pair shows the selected house through one unselected tree.
Visible-only coverage follows the exposed house edges around that tree.
Through-wall coverage keeps the hidden roof and base contour across the tree.
That pair changes 221397 pixels at equal camera and simulation inputs.
The square view shows smoke emerging above the transformed chimney rim.
The group contour has no line at ordinary boundaries between its Draws.
Dust remains small warm specks beside the route.
The engine applies no scene fog to particles.
The finite source region and lifetimes limit that difference; they do not provide particle fog.

The unchanged particle implementation also ran in a temporary standalone Odin harness.
The harness changed only the package name in its copied source.
The replay used the village rates, lifetimes, source IDs, seeds, and 120 Hz steps.
It reached 196 live particles at 1800 and 3600 steps: 36 smoke and 160 dust.
Every source and particle drained within 1800 steps after removal.
`docs/evidence/village-effects/particle-replay.json` records the source hash and exact results.
The raw harness remains at `/tmp/village-effects-particle-count`.

Repeated sprite preparation produced identical sprite and manifest hashes.
The preparation verifies the established archive checksum and chimney opening corners.
`source/effects-manifest.json` records those source facts and generated asset hashes.

## Costs and remaining gates

| Effect | Structural cost | Measured frame cost |
| --- | --- | --- |
| Selected outline | One HDR Post, scene-depth pass, and selected geometry pass | Pending complete-layout measurement |
| Colour | One LDR Post and final colour copy | Pending complete-layout measurement |
| Smoke | One source batch and 36 steady particles | Pending complete-layout measurement |
| Dust | 40 source batches and 160 steady particles | Pending complete-layout measurement |

The outline requests depth and Selection only while a Group is selected and the outline is enabled.
The total particle limit remains 8192, with 128 source slots.
The scene uses 41 source slots and a conservative bound of 236 live particles.
It adds two Images, two Shaders, zero Meshes, and zero Draws.

These captures do not establish a 60 FPS preset or GPU performance.
Complete-layout Metal, GL, and D3D11 scene checks remain pending.
Per-effect CPU/GPU timings, route p95/p99, and real-clock pacing remain pending.
The combined scene still needs foliage/lighting review and complete-scene review.
The reference Windows desktop run remains pending.
The effects task must retain these acceptance gates.

## Artifacts and reproduction

The final raw captures, scene JSON, host logs, and reports remain outside the repository:

- `/tmp/village-effects-final`

`docs/evidence/village-effects/metal.json` records the combined results and image hashes.
`docs/evidence/village-effects/shaders.json` records package hashes, budgets, and backend payloads.
One intermediate capture was retried after the disk filled.
Every recorded final capture exited successfully and logged no graphics or resource diagnostics.
The final binary SHA-256 is `1e10127e463cbe36c590cdfa090656d96efe79a931c8ba12998666185b26a1c4`.

Reproduce the complete fixed-input comparison set:

```sh
roc scripts/build.roc -- game village
python3 examples/village/fixtures/effects.py /tmp/village-effects --retina-1080 --steps 480
```

Use the default 1800 steps for a longer particle buildup comparison.
The particle replay supplies the exact steady counts independently of rendering.

## Complete-layout integration

The combined scene preserves 1,436 source placements, 93 meshes, and the full 22,000-placement field.
All 175 village tests and 146 build tests passed.
The required build compiled five shader packages and two mesh helpers.
The effects packages and helpers match the independent declaration build.
Both sprite hashes match the prepared manifest.

The targeted Metal fixture reaches complete readiness at step 96.
It advances 432 hero steps so smoke and dust can spawn before the comparisons.
It selects Group 20 through the existing Enter ray with unchanged white Draw tints.
Visible-only and through-wall policies change 64,408 pixels.
Disabling the outline changes 542,693 pixels.
Colour changes preserve all 15,500 tested opaque UI pixels.
The fixture verifies live smoke, dust, field, casting, and colour controls.
Equal seeds and inputs reproduce every captured image and camera.
An alternate seed changes particle source streams.
All native logs are clean and every process exits successfully.
The [combined report](../../docs/evidence/village-effects/combined-metal.json) records exact inputs, cameras, sources, and hashes.

The raw package remains at `/tmp/village-effects-combined-final` with replay and seed-seven sibling directories.
The agent inspected hero, both policies, and the UI comparison.
The eight-second source-tour preview is `route.mp4` in that package.
The fixture retains its eight camera records and frame hashes, then removes raw frames.
The long route fixture now checks full source counts and Group selection.
The village README contains current build and capture commands.

All three CI jobs now run the targeted combined fixture.
It keeps full density and uses two repeat processes plus one short alternate-seed check.
The fixture replaces repeated isolated effect cases in native scene CI.
Native GL and D3D11 acceptance remains pending.
Human review and controlled performance gates remain open.
The canopy correction is integrated and the complete scene captures are refreshed.
Read the [final combined evidence](COMBINED-EVIDENCE.md) for current review artifacts.
