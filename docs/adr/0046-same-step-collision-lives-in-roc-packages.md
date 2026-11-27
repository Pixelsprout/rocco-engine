# 0046: Same-step collision lives in Roc packages

Status: accepted, 2026-11-28. Grilled for Milestone 48 (b1jaxkte).
Builds on: ADR 0005 (Queries ask the engine).

## Context

ADR 0005 answers a Query against Scene N and gives the answer to step N+1,
so every answer is one step late. A character controller needs the ground
under its feet and the walls around it in the same step that it moves. One
step late, a fast fall passes through a thin platform and a wall pushes a
character back after it has already entered.

The host cannot fill the gap today. It skips capsule Colliders, has no
heightfield and has no shape casts. The unicorn-game movement prototype
showed that game-side ground heights and push-out against boxes feel right
with no engine Colliders.

Until now no package imported another package. The camera package keeps its
own vector helpers so that it does not import linalg.

## Decision

- Same-step collision is pure Roc in `packages/collide`. The game holds the
  shapes in its Model and calls the package from `step`. The host takes no
  part.
- The character is a vertical capsule. The static shapes, the Solids, are
  boxes turned by a yaw about `+y` and spheres. `Solids.build(list,
  cell_size)` files them once in a uniform grid on x and z. A Solid wider
  than eight cells goes to a list that every query tests, as ADR 0005 does
  for huge shapes.
- `Solids.push_out` moves the capsule out of each Solid it overlaps and
  returns the new foot position and the normal. Against a box, the capsule
  is a vertical segment against the box grown by the radius.
- Ground is a function `F32, F32, F32 -> [Hit({ y, normal }), Miss]` that
  answers the highest surface at or below a height. `flat`, `heights`,
  `tops` and `highest` build one. `Ground.sweep` asks from the height before
  a fall, so a fast fall stops on a thin platform.
- A package can import another package. `packages/collide` imports
  `packages/linalg` for `Vec3`. A game that imports collide does not need
  linalg in its own header. No package imports the platform.
- Engine Colliders and Queries stay for what the game can wait one step
  for: picking, triggers and Contacts between moving things.

## Considered options

- Host capsule Queries answered in the same step. Rejected: `step` would
  call into the host for an answer, which breaks the pure `step` that ADR
  0005 keeps for replay.
- Accept the step of delay and correct it the next step. Rejected: a fast
  fall passes a 0.1 m platform before the answer arrives, and a correction
  one step later shows as a jump.
- A dynamic grid or tree that the game rebuilds each step. Rejected for now:
  the Solids do not move, so one build is enough. Moving Solids are a
  separate task.
- Copy the vector helpers into collide, as camera does. Rejected: Roc RC2
  resolves a package's own dependencies, so the import costs nothing.

## Consequences

- A game that uses collide keeps two sets of shapes. The host gets Draws
  and Colliders. The game collides with Solids and a Ground in Roc. A game
  builds both sets from one list, so they stay the same.
- The collision cost is Roc code in `step`, and the grid keeps it to the
  Solids near the capsule.
- Box edges are square, not rounded, so a capsule rests a little past the
  edge of a box.
- `packages/controller` builds the character on collide and is the next
  package that imports another.
- Future work: moving Solids, a host heightfield, camera shape casts and
  capsule Queries in the host.
