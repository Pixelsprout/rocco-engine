# 0008: A shared grid answers the Queries

Status: accepted, 2026-10-21. It replaces the search parts of ADR 0005.

## Context

ADR 0005 tested each Raycast and each Overlap against every Collider, and
ran a sweep and prune on x over all Colliders for the Contacts. The
reference run of 2026-10-21 showed that this search sets the headline
figure. With 8 Raycasts, 8 Overlaps and one ContactsOf, the queries Span
took 15.5 ms at 16,384 Colliders, the same in Roc and in the Odin twin.

A timing harness in Odin repeated the bench's Queries outside the game. It
gave 15.7 ms in total and split the cost at 16,384 Colliders:

- Contacts took 9.4 ms. The sweep on x grows as N times the square root of
  N in a square arena, and the host then kept only the asking owners'
  pairs.
- Raycasts and Overlaps took 3.2 ms and 3.1 ms. Each tested every Collider.
- Each of the three built the Shapes again, with a map of the ids.

## Decision

- The host builds the Shapes and a uniform grid over them once per step,
  on the first Query that needs them. Every Query of the step searches it.
- The grid lies on the ground plane, x and z. Its cell is twice the
  geometric mean of the Shapes' ground-plane sizes, so one huge Shape, such
  as a ground box, does not set it. It has at most about 4 cells per Shape.
- A Shape that spans more than 8 cells on x or z stays out of the grid.
  Every Query tests it. So does a Shape at infinity, with a NaN, or with a
  negative size, which the grid cannot place. An Overlap or a Raycast with
  such a value tests every Shape, as before.
- ContactsOf searches only the cells under each asking owner.
- A Raycast walks the cells along the ray and stops once the next cell
  starts past the nearest hit.
- An Overlap tests only the Shapes in the cells under its box.
- An open-addressing set of the ids replaces the map. It still keeps the
  first Collider of a shared id.
- The answers do not change. Every rule of ADR 0005 about owners, slots,
  exclude lists, ties, order and logging still holds. One case was never
  fixed: when two Shapes start at the same x, the sweep's heap sort put them
  in no set order. The host now takes the lower index first, so where two
  axes of a box test tie, the normal can differ from an old run.

## Considered options

- Keep the brute force and remove only the waste: one Shape build per step,
  a box test before each narrowphase and a sweep on the longer axis. It was
  rejected. It saves 2 to 3 times and keeps the growth.
- A bounding volume tree. It was rejected for now. The Colliders change
  every step, so the tree must be rebuilt or refitted each step, and a grid
  is simpler for Shapes of similar size.

## Consequences

- At 16,384 Colliders, the timing harness gives 1.1 ms for all the Queries,
  against its 15.7 ms before. The new colliders and mixed sweeps give the
  bench figures.
- The cost now comes from the build, which grows with N. A step with
  Colliders and no Query still builds nothing.
- Shapes of very different sizes make the grid less useful. Big Shapes go to
  the list that every Query tests, so many big Shapes cost one test each per
  Query.
- `contacts_find`, which gives every pair, uses the same grid. It tests the
  pairs in each cell, and the cell that holds the corner where two boxes
  start to overlap gives each pair once.
