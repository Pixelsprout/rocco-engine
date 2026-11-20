# 0022: Emissive surfaces and Draw glow

Status: accepted, 2026-10-31.

## Context

Agent Town drew its lit windows and orbs as primitives with a Tint above 1.
A Tint multiplies the lit base colour, so such a window is dark in the dark.
It shows only where a Light reaches it. The glTF loader also ignored the
emissive inputs, so a glTF mesh could not glow either.

## Decision

- The loader reads a glTF material's emissive factor, emissive texture and
  emissive strength into the Emissive of each Mesh part.
- `Draw.glow` adds to the mesh's Emissive. A channel can exceed 1.
  `Draw.default` has no Glow.
- Emissive and Glow light no other surface. The engine has no global
  illumination, as in Godot and Bevy without it.
- A Glow spills past its surface only through bloom in the Post pass
  (ADR 0026). The surface itself gives off no light.
- No helper: a game that wants a glow to light the Scene writes the Draw
  with its Glow and a Point Light side by side.
- The Fallback mesh ignores the Glow, as it ignores the Tint.

## Considered options

- Emissive lights the Scene through global illumination. Rejected: global
  illumination is out of scope.
- The host adds a hidden Point Light for each glowing Draw. Rejected: the
  game would not see or place the Light, and it would spend the Scene's
  lighting budget without the game knowing.
- A Tint above 1 stays the way to glow. Rejected: it multiplies the lit
  colour, so it shows only where a Light reaches.
- A `pf.Glow` helper module. Rejected: glow is a Draw property, and a
  helper that pairs it with a Light names a game's object.

## Consequences

- A glowing thing that lights its surroundings costs the game one Point
  Light that it places itself.
- With bloom off, a Glow does not spill past its surface.
