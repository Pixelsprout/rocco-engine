# 0027: Alpha modes and Blend frame order

Status: accepted, 2026-11-05.
Supersedes: ADR 0031 (cutout shadow coverage).

## Context

The host drew every glTF material as Opaque. An Alpha mode of Blend did not
show the Draws behind it, glass cast a solid shadow, and cutout materials
drew as solid parts. Foliage in the immersive village needs shadows that
match its visible cutouts. The Main pass needed an order that kept the sky
behind glass and kept the Opaque path fast.

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
  order.
- Blend pipelines test depth without writing it. They use premultiplied
  alpha. Diffuse and fog scale by alpha; specular and emissive keep their
  strength. A double-sided Blend part draws back faces, then front faces.
- The Shadow pass draws Opaque parts first with a position-only shader. It
  then draws each Mask part with its base texture, vertex alpha and cutoff,
  so a cutout shadow matches the visible cutout. Mask parts keep their face
  culling in the Shadow pass. Blend parts cast no shadow.
- The shadow shader reads the same vertex colour as the Main pass, so the
  base factor and `COLOR_0` apply once.
- Mask mip levels keep the base level's alpha coverage at the cutoff when
  the vertex alpha is constant. Distant thin cutouts stay visible.
- Surface shaders share deformation and alpha rules across the colour,
  shadow and selection passes.

## Considered options

- Mask shadows from the whole triangle. Rejected: the shadow fills the
  texture's holes and omits leaf faces that point away from the Sun.
- Keep coverage in the mips for variable vertex alpha. Rejected: one
  texture threshold cannot hold every interpolated cutoff, so those
  textures keep ordinary mips.

## Consequences

- An existing `.glb` with MASK or BLEND now draws by that mode. An Opaque
  `.glb` keeps its earlier look and draw cost.
- Sorting is per Draw. Intersecting Blend triangles in one Draw can appear
  in the wrong order. Authors can split glass into separate Draws.
- A double-sided Blend part costs two submits of draw capacity.
- Mask parts add submits, texture reads and discard work to each shadow
  cascade they cover. Opaque parts keep their cheap shadow path.
- A texture variant includes its cutoff, so materials that share a texture
  with another cutoff keep their own mips.
