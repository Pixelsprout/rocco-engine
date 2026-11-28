# 0047: Emitters are Nodes

Status: accepted, 2026-11-28.
Amends: ADR 0045 (Draw and Group ids are optional and generated in Roc),
for Emitter ids.

## Context

Milestone 41 gave the Scene a flat list, `Scene.emitters`, with each
Emitter at a world `position`. ADR 0014 moved Lights and Colliders into the
tree because a lantern belongs to the player, and ADR 0017 did the same for
Speakers. An Emitter was the last world-space list. A torch on the player,
exhaust on a car or sparks from a sword made the game compose the world
position from the Model each step.

The outdoor fields (`acceleration`, `spawn_radius`, `swirl`, `outward`)
describe gravity, lift and wind round a level disc and an upright line.
They assume a world up.

## Decision

- `Emitter(Emitter)` is a leaf of `Node`. `Scene.emitters` goes, with no
  deprecated path.
- `position` becomes `pos`, local to the parent Group by the rule of a
  Draw. At the root it is a world position.
- A Particle lives in the world after it spawns. A moving Emitter leaves a
  trail. No local-space mode exists.
- `velocity` and `velocity_spread` turn with the Group, because they aim
  the emission. `acceleration`, the `spawn_radius` disc and the `swirl` and
  `outward` line stay in the world, because they stand for gravity, lift
  and wind.
- The host pairs an Emitter with the Emitter of the same id anywhere in
  the previous tree, so an Emitter that moves to another Group keeps its
  Particles and its random sequence. If two share an id, the first in
  depth-first pre-order wins and the host logs once.
- An Emitter with id 0 pairs by its Position key, as a Draw does. A Burst
  cannot name id 0. This replaces "Emitter ids stay explicit" in ADR 0045.
- The host takes the world pose from the current Scene, with no
  interpolation, as for a Speaker. Continuous spawns in one step spread
  along the line from the previous world position to the current one. A
  Burst spawns at the current world position.
- An Emitter under an Attach follows the Joint's world pose by the same
  rule.
- A removed Emitter's Particles drain with its last world pose and
  settings, so a trail stays where it was.
- The Alpha sort uses the composed world position.
- The Bridge `scene` reply shows each Emitter in the `nodes` tree with its
  local `pos`.

## Considered options

- Keep `Scene.emitters`. Rejected for the reasons of ADR 0014 and ADR 0017.
- Particles that move with their Group. Rejected for now: smoke from a
  moving chimney must trail. A mode can be added later without a break.
- Only `pos` follows the Group. Rejected: exhaust would not turn with the
  car.
- Every vector turns with the Group. Rejected: a tilted Group would tilt
  gravity and a dust devil's axis.
- Interpolate the world pose, as for a Draw. Rejected: the host steps
  Particles at the fixed step, so a spawn needs a step pose. The spread
  along the line removes the clumps a fast parent would leave.
- Explicit ids only. Rejected: a repeated torch Group or a placed Prefab
  would give many Emitters one id, and only the first would emit.

## Consequences

- The particles example, the village Effects, the benches, `Scene.empty`,
  the glue and `guide/scene.md` change in one step.
- A game that wants a world-fixed Emitter puts it at the root.
- A game that bursts an Emitter gives it a non-zero id.
- Until the Position key for Draws exists, the host keys an id-0 Emitter
  by the nearest Group with an id (or the Attach) and its order among all
  id-0 Emitters under it, not among its siblings. An id-0 Emitter added in
  an earlier id-0 sub-Group shifts the later ones, which restart their
  Particles and random sequence.
- The host tree walk visits the children of an Attach after the rest of
  the tree. Until that order changes, a duplicate id under an Attach can
  lose to a later Emitter elsewhere. Speakers share this gap.
