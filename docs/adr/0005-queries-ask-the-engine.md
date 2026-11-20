# 0005: Queries ask the engine

Status: accepted, 2026-10-16.
Supersedes: ADR 0008 (A shared grid answers the Queries).

## Context

A game needs facts that only the engine has: what a ray hits, what touches
a volume. Contacts already worked as a request and a reply, and `Load` and
`loaded` follow the same pattern. A reply that is an argument to `step`
keeps `step` pure, so replay still works. The reply arrives one step late.
A fact that the game needs in the same step, such as UI layout, stays in
the host (ADR 0004).

A first search tested each Raycast and Overlap against every Collider and
ran a sweep and prune over all Colliders for the Contacts. At bench sizes
that search set the cost of the whole step.

## Decision

- The game puts its Queries in `Scene.queries`. The host answers them
  against Scene N and gives the QueryResults to step N+1. The first step
  gets empty QueryResults.
- The Collider Queries are `ContactsOf(owner)`, `Raycast` (the nearest hit
  only) and `Overlap` (each Collider that a shape touches).
- Queries test Colliders only. The host skips a capsule Collider and logs
  one line.
- Raycast and Overlap take an Owner, a Slot and an exclude list. The Owner
  and Slot link a result to its Query. The host skips the Owner's own
  Collider. If two Queries of one kind share an Owner and Slot, the host
  logs once and keeps the first.
- A miss has no row. QueryResults holds one flat list per kind of Query.
- With no ContactsOf Query, the host does no contact search.
- The host builds the shapes and one uniform grid over them once per step,
  on the first Query that needs them. Every Query of the step searches it.
- The grid lies on the ground plane, x and z. Its cell size follows the
  typical shape size, so one huge shape, such as a ground box, does not set
  it. A shape too big or too odd for the grid (huge, infinite, NaN) goes to
  a list that every Query tests.
- ContactsOf searches only the cells under each asking Owner. A Raycast
  walks the cells along the ray and stops past the nearest hit. An Overlap
  tests only the cells under its box.

## Considered options

- One list of a union of answer kinds. Rejected: no union that the host
  builds carries a list yet, and each answer costs one allocation.
- Keep the brute-force search and remove only the waste. Rejected: it saves
  a small constant factor and keeps the growth.
- A bounding volume tree. Rejected for now: the Colliders change every
  step, so the tree must be rebuilt or refitted each step, and a grid is
  simpler for shapes of similar size.

## Consequences

- A game that sends no ContactsOf Query gets no Contacts, and a step with
  Colliders and no Query builds nothing.
- The cost now comes from the grid build, which grows with the Collider
  count.
- Shapes of very different sizes make the grid less useful. Many big shapes
  cost one test each per Query.
- Future work: RaycastAll, shape casts, layers and masks, and capsule tests.
