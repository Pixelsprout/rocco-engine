# 0005: Queries ask the engine

Status: accepted, 2026-10-16.

## Context

A game needs facts that only the engine has: what a ray hits, what touches
a volume. Contacts already work as a request and a reply. The game returns
Colliders in the Scene, and the host gives the Contacts to the next step.
`Load` and `loaded` follow the same pattern. A reply that is an argument to
`step` keeps `step` pure, so replay still works. The reply arrives one step
late. A fact that the game needs in the same step, such as UI layout, stays
in the host (ADR 0004).

## Decision

- A Query asks the engine about something. A Command tells the engine to do
  something.
- The game puts its queries in `Scene.queries`. The host answers them
  against Scene N and gives the QueryResults to step N+1. The first step
  gets empty QueryResults.
- `step` takes QueryResults in place of the Contacts.
- Queries test Colliders only. The host skips a capsule Collider and logs
  one line.
- There are three kinds of Query:
  - `ContactsOf(owner)`: the Contacts of the owner's Collider.
  - `Raycast`: the nearest hit only.
  - `Overlap`: each Collider that a shape touches.
- Raycast and Overlap take an owner, a slot and an exclude list.
- An owner and a slot link a result to its query. The host skips the
  owner's own Collider. If two queries have the same owner and slot, the
  host logs once and keeps the first.
- A miss has no row.
- QueryResults is a record of flat lists: `{ contacts, rays, overlaps }`.
  A `contacts` row is a Contact, a `rays` row is a RayHit, and an
  `overlaps` row is an OverlapHit.
- With no ContactsOf query, the host does no contact search. With one or
  more, the host runs the sweep and prune over all Colliders. It returns
  each pair that involves any asking owner, once, in id order.
- The host tests each Raycast and each Overlap against every Collider.
  There is no cap and no broad phase for them.

## Considered options

- One list of a union of answer kinds. It was rejected. No union that the
  host builds carries a list yet, and each answer costs one allocation.

## Consequences

- A game that sends no ContactsOf query gets no Contacts. Each game that
  reads Contacts today must ask for them.
- The Contact search runs only when a game asks, so a game with Colliders
  and no ContactsOf query pays nothing for it.
- Future work: RaycastAll, shape casts, raymarching against SDFs, a broad
  phase for Raycast and Overlap, layers and masks, and capsule tests.
