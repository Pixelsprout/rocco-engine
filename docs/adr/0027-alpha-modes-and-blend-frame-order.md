# 0027: Alpha modes and Blend frame order

Status: accepted, 2026-11-05. Milestone 38.
The temporary MASK shadow rule is superseded by [ADR 0031](0031-cutout-shadow-coverage.md).

## Context

The host drew every glTF material as Opaque. An Alpha below 1 did not show
the Draws behind it, and glass cast a solid shadow. Cutout materials also
drew as solid parts. The Main pass needed an order that kept the sky behind
glass and kept the existing Opaque path fast.

## Decision

- The loader reads `alphaMode`, `alphaCutoff` and `doubleSided` into each
  Mesh part. The index buffer orders Opaque, Mask and Blend parts.
- Opaque parts keep a shader without discard and always cull back faces.
  Blender writes `doubleSided: true` by default, so Opaque ignores it.
- Mask parts discard fragments below the cutoff and write depth. A
  double-sided Mask part culls neither face and flips the normal on a back
  face.
- The Main pass draws Opaque and Mask parts in Scene order, then the sky,
  then Blend parts. Blend parts sort back to front by the centre of each
  Draw's world box. Ties keep Scene order, and parts of one Draw keep file
  order. The host selects lights once per Draw.
- Blend pipelines test depth without writing it. They use premultiplied
  alpha with ONE and ONE_MINUS_SRC_ALPHA. Diffuse and fog scale by Alpha;
  specular and emissive keep their strength. A double-sided Blend part
  draws back faces, then front faces, and costs two submits.
- The shadow pass draws one range per Draw over its Opaque and Mask parts.
  Blend parts cast no shadow. Mask shadows use the whole triangle shape
  from faces that point at the Sun.
- `Launch.capacity.draws` counts Main pass submits. A double-sided Blend
  part costs two. Skin blocks count each pipeline used by a skinned Draw
  before the sky and each pipeline run among its Blend submits.
- A pipeline change drops sokol's lights uniform block. Sorted Blend
  submits can change pipeline on each submit, so `uniform_buffer_size`
  reserves MAIN + max(cascades * SHADOW, LIGHTS) slots per submit. At two
  or more cascades, this does not change the size or `DRAW_LIMIT`. At one
  cascade, the uniform buffer grows by 25%.

## Consequences

- An existing `.glb` with MASK or BLEND now draws by that mode. An Opaque
  `.glb` keeps its earlier look and draw cost.
- Sorting is per Draw. Intersecting Blend triangles in one Draw can appear
  in the wrong order. Authors can split glass into separate Draws.
- Mask cutouts do not cut their shadows. Cutout shadows need another
  shadow path.
- A double-sided Blend part consumes two units of draw capacity. A Scene
  with many skinned pipeline changes can reach its skin block limit sooner.
- The Vocabulary and Bridge protocol do not change.
