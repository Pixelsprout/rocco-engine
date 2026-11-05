# 0033: Clustered forward lights

Status: accepted, 2026-11-05. Supersedes [ADR 0023](0023-a-light-list-per-draw.md).

A large Draw can receive hundreds of lamps.
A list of eight lights drops most lamps and changes abruptly when lamps move.
The CPU now builds one camera grid each Frame, and fragments read their local Point lights through storage buffers.

The grid has 16 by 9 screen tiles and 24 logarithmic depth slices.
Each cluster retains at most 64 Point lights.
Overflow keeps lights nearest its centre, with Scene order resolving equal distances.
The host logs each limit once per run.
The host accepts the first 1,024 Point lights in Scene order.
It accepts four Directional lights, with the Sun always first.
A late Sun replaces the last retained Directional when necessary.
Point lights cast no shadows.
The Sun retains its cascaded shadows.

The CPU tests conservative sphere bounds against cluster planes.
The grid uses the interpolated camera and physical output size.
Depth extends to every accepted Point sphere, with a minimum far depth of 100 units.
The build uses the Frame arena and uploads three buffers once per Frame.
Headless runs build no clusters.
The `cluster_build` Span excludes this work from `render_submit`.

The built-in PBR shader retains its BRDF, normal mapping, alpha rules, fog, and skinning.
Material slot 1 uses 80 bytes.
Lighting slot 2 uses 512 bytes.
The Point, cluster range, and packed index records use the reserved storage slots 12, 13, and 14.
GL maps these slots to physical storage bindings 0, 1, and 2.
[The shader contract](../SHADER-CONTRACT.md) records the exact layout and budgets.

A larger per-Draw list still drops lamps on large meshes.
A GPU grid build adds compute scheduling and synchronization before measurements establish a need.
The CPU build preserves the three required graphics backends.
Measurements can justify a GPU build later.

The renderer reuses unchanged mesh bindings and Material uniforms until the pipeline changes.
This avoids repeated storage bindings for repeated mesh parts.
[The benchmark evidence](../BENCHMARKS.md#clustered-point-lights) records the resulting CPU cost and its measurement limits.
