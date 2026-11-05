---
title: Shadow quality
summary: Live shadow appearance, startup allocations and cost tradeoffs.
order: 12
---

# Shadow quality

Set `Scene.shadow` to change shadow appearance on the next rendered frame.
The host reads the current Scene without interpolation.
Start from `Shadow.default`, `Shadow.low`, `Shadow.balanced` or `Shadow.high`.
Use a record update for explicit overrides:

```roc
shadow = { ..Shadow.balanced, distance: 80.0, normal_bias: 0.02, filter: Pcf5 }
scene = { ..Scene.empty, shadow }
```

These names describe engine choices.
They do not claim measured village settings on Mac or PC.
The village integration task owns those measurements.

| Live field | Default | Effective behaviour and cost |
| --- | --- | --- |
| `distance` | 0 | Legacy fitting: all casters with one cascade, or 150 units with multiple cascades. |
| Positive `distance` | Above 0.1, at most 1000000 | Fit camera slices through this view depth, including with one cascade. Shorter ranges increase detail. |
| `normal_bias` | 0.05 | Move the comparison point along the geometric normal, in world units. Range: 0 to 10. |
| `depth_bias` | 0 | Add comparison depth in reversed Z. Range: 0 to 0.1. Larger values reduce acne but can detach shadows. |
| `distribution` | 0.5 | Mix linear splits (0) and logarithmic splits (1). A single cascade ignores this field. |
| `blend` | 0.1 | Blend over this fraction of each cascade. Range: 0 to 0.5. Zero gives hard transitions. |
| `filter` | `Pcf3` | `Hard`: one comparison sample. `Pcf3`: nine samples. `Pcf5`: 25 samples. More samples cost more fragment work. |

Longer ranges and wider filters can require larger bias values.
`Shadow.high` adds a depth bias of 0.0005 as a starting point.
Tune bias against the scene scale and light direction.

All comparison samples use the hardware's linear depth filter.
The last cascade fades to no shadow across its blend band.
Legacy single-map fitting has no distance fade.
Cascade transitions sample both maps, including with a zero blend band.

The host replaces each invalid live field with its `Shadow.default` value.
Invalid fields include NaN, infinity and values outside the documented ranges.
The host logs each invalid field once per run.
Other valid fields remain active.
The Bridge `scene` response includes the requested `shadow` values.
Apply the rules above to determine effective values after a diagnostic.

## Startup allocations

Set these fields in `launch` before the window opens.
Restart the game after changing them.
No live shadow field changes these allocations.

| Pure helper | Map size | Cascades | MSAA | Restart required |
| --- | --- | --- | --- | --- |
| `Shadow.startup_default` | 2048 | 1 | `X4` | Yes |
| `Shadow.startup_low` | 1024 | 1 | `Off` | Yes |
| `Shadow.startup_balanced` | 2048 | 2 | `X4` | Yes |
| `Shadow.startup_high` | 4096 | 4 | `X4` | Yes |

```roc
startup = { ..Shadow.startup_balanced, shadow_map: 1024 }
launch = |_config| {
    ..Launch.default,
    shadow_map: startup.shadow_map,
    shadow_cascades: startup.shadow_cascades,
    window: { ..Launch.default.window, samples: startup.samples },
}
```

Map sizes range from 8 to 16384 texels.
The host checks the device's shadow array size and layer limits before allocation.
An invalid startup choice ends the run with a field diagnostic.
The map must leave room for the widest filter, even when live controls change.
Each cascade adds one depth map and one shadow pass.
Doubling map width uses four times the depth storage per cascade.
MSAA changes colour and depth storage and sample work for the main view.
The shadow maps remain single sampled.

## Example controls

Build and run `examples/mask`.
Use `--shadow-low` or `--shadow-high` to select startup allocations.
Use `--far-shadows` to inspect distant shadows with four cascades.
The default launch retains the existing engine allocations.

| Input | Live change |
| --- | --- |
| L, B, H | Low, balanced, high appearance |
| Down, Up | Decrease or increase view depth |
| J, K | Decrease or increase normal bias |
| R, T | Decrease or increase comparison depth bias |
| U, I | Decrease or increase logarithmic distribution |
| N, M | Decrease or increase blend fraction |

Use the same camera and scene inputs when comparing appearance choices.
Record startup allocations and live values with performance measurements.

## Integration checks

Both merged engine suites passed 787 tests with vet and strict style checks.
All example, package, and benchmark checks passed with the new Scene field.
The build script passed all 146 tests and retains every example in its expected lists.
The production compiler and package checks passed 50 tests.
The Metal proof drew all eleven variants with tiny and zero blend bands and all three filter radii.
Its world-input and outline readbacks also passed.
The Bridge passed default single-map, multiple-cascade, low-startup, and high-startup cases.
Each case checked live presets, numeric controls, changed images, graphics validation, and a clean exit.
The local evidence is in `/tmp/rocco-shadow-merged/`.
[CI run 41963156762](https://github.com/Pixelsprout/rocco-engine/actions/runs/41963156762) passed all jobs.
Metal, GL, and D3D11 passed all four native shadow-control cases.
The native environment checks also passed on all three backends.
Measured village presets remain a separate acceptance gate.
