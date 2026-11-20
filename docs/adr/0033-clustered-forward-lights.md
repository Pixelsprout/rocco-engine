# 0033: Clustered forward lights

Status: accepted, 2026-11-05.
Supersedes: ADR 0023 (a light list per Draw).

## Context

Agent Town's key art has many small lamps, and one large Draw, such as a
ground plane at dusk, can be reached by hundreds of them. A fixed light list
per Draw keeps only the nearest few. It drops most lamps, and lights pop in
and out as the camera and the lamps move.

## Decision

- The host builds one cluster grid over the camera view each Frame, on the
  CPU, in the Frame arena. The grid has screen tiles and logarithmic depth
  slices.
- Point lights reach a fragment only through the clusters. The host tests a
  conservative sphere for each Point light against the cluster planes and
  uploads the lights, the cluster ranges and the light indices as storage
  buffers once per Frame. Each fragment reads the Point lights of its own
  cluster.
- Directional lights stay a short per-Frame list, with the Sun always first.
  A late Sun replaces the last Directional the host keeps.
- The host caps the Point lights per Frame and per cluster. A full cluster
  keeps the lights nearest its centre, and Scene order breaks a tie. The
  host logs each limit once per run.
- The grid uses the interpolated camera and the physical output size.
- Point lights cast no shadow. The Sun keeps its cascaded shadows.
- Headless runs build no clusters. The build has its own Span,
  `cluster_build`, apart from `render_submit`.
- `docs/SHADER-CONTRACT.md` holds the block sizes, storage slots and limits.

## Considered options

- A light list per Draw: the Sun, the other Directionals, then the nearest
  Point lights in reach of the Draw's world box, with a fixed count per
  Draw. Rejected: it was the earlier rule, and a large mesh still drops most
  lamps and pops. A longer list only moves the limit, and every pixel of the
  Draw pays for every listed light.
- Raise the light cap per Scene. Rejected: every pixel pays for every light,
  and a cap per Scene stays.
- Build the grid on the GPU with compute. Rejected for now: it adds compute
  scheduling and synchronization before any measurement shows the CPU build
  is the bottleneck. Measurements can justify it later.

## Consequences

- The renderer needs storage buffers in the fragment stage. Metal, GL 4.3
  and D3D11 all have them.
- The renderer reuses unchanged mesh bindings and Material uniforms until
  the pipeline changes, so repeated mesh parts do not rebind the storage
  buffers.
- `docs/guides/benchmarks.md` records the CPU cost of the build.
