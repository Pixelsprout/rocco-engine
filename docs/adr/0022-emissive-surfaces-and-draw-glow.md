# 0022: Emissive surfaces and Draw glow

Status: accepted, 2026-10-31.

## Context

Agent Town draws its lit windows and orbs as primitives with a tint above 1
(`stage/Buildings.roc`, `stage/Theme.roc`). A tint multiplies the lit base
colour, so such a window is dark in the dark. It shows only where a Light
reaches it.

The glTF loader ignored `emissiveFactor`, `emissiveTexture` and
`KHR_materials_emissive_strength`, so a glTF mesh could not glow either.

The host lights at most 8 Lights per Scene.

## Decision

- The loader reads the three emissive inputs into the mesh Material and a
  third mesh texture. The mesh emissive is
  `clamp(emissiveFactor, 0, 1) * max(emissiveStrength, 0)`. A missing
  factor is black and a missing strength is 1. The emissive texture is
  sRGB and uses `TEXCOORD_0`. A mesh with no emissive texture binds the
  white image, so the factor alone sets the emissive.
- A mesh has one Material, from its first part. A part with another
  emissive factor or emissive texture notes `Mixed_Materials`.
- `Draw` gains `glow : Rgb`. It adds to the mesh emissive. A channel can
  exceed 1, and the host counts a negative channel as 0.
  `Draw.default.glow` is black.
- The shader adds `emissive * emissive_tex + glow` after the lights and
  before the ACES tone map. An unlit mesh adds it to its base colour, with
  no tone map.
- Emissive lights no other surface, as in Godot and Bevy without global
  illumination.
- `Glow.orb` in `pf.Glow` pairs a glowing sphere with a Point Light of the
  same colour, so a game that wants a glow to light the Scene says so.
- The fallback mesh ignores the glow, as it ignores the tint.
- `BRIDGE_PROTOCOL` rises to 6, because each Draw in the `scene` reply
  gains `glow`.

## Considered options

- Emissive lights the Scene, through global illumination or a Light that
  the host adds for each glowing Draw. Rejected: global illumination is out
  of scope, and a hidden Light would spend the 8-light cap without the
  game knowing.
- A tint above 1 stays the way to glow. Rejected: it multiplies the lit
  colour, so it shows only where a Light reaches.
- Bloom. Rejected for now: it is a post-process pass, and no such pass
  exists yet.
- `Glow.orb` in a package. Rejected: a package cannot use `Draw.default`,
  so it repeats every Draw field and breaks each time `Draw` changes.
- `Glow.orb` as `Light.orb`. Rejected: the helper returns a Draw and a
  Light, not a Light.

## Consequences

- This is a Vocabulary change. The host and every game rebuild. A Draw
  that starts from `Draw.default` does not change. A full Draw literal adds
  `glow`.
- Each mesh can hold a third texture, so the image, sampler and view pools
  grow by one for each mesh slot.
- The ACES fit rolls a large glow off towards white.
- With no bloom, a glow does not spill past its surface.
- Each `Glow.orb` spends one of the 8 Lights of the Scene.
