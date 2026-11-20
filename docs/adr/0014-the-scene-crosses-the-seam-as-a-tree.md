# 0014: The Scene crosses the seam as a tree

Status: accepted, 2026-10-23.
Supersedes: ADR 0013 (The Scene crosses the seam as a tree).

## Context

The UI crossed the seam as a flat stream of `Open`, `Text` and `Close`,
because the glue could not carry a recursive tag union. Games write nested
code, so a helper flattened it, at a cost in allocations every step. Tests
had to count brackets, and the host repaired unbalanced streams.

The 3D side carried flat lists of Draws, Colliders and Lights in world
space. Parenting lived in the game, which composed every world Pose by hand
for three kinds of leaf. The host lerped world positions, so a drop on a
turning player took a chord between two steps, not an arc.

Roc can carry a nominal tag union that recurses through a `List` across the
host boundary, and the Odin glue learned to generate it.

## Decision

- `Scene.ui` is a list of root Elements and `Scene.nodes` a list of root
  Nodes. Both are nominal recursive unions, because only a nominal one
  crosses the host boundary. The trees replaced the flat forms in one
  change, with no deprecated path.
- The trees are Descriptions: plain data with no events or closures. The
  host keeps no Node from one Scene to build the next.
- An Element keeps its identity by its place in the tree. Games write the
  tags directly; `packages/ui` gives defaults and small helpers.
- A Group carries a Pose. Its children's Poses are local to it. A Group has
  no scale: a scale on a Draw acts on that Draw only.
- Group ids and Draw ids are apart, so an entity's Group and its Draw can
  carry the same id. A duplicate Group id pairs the first in tree order and
  logs once.
- The host interpolates in local space, then composes. If a Node's parent
  changed between Scenes, it interpolates the two world Poses instead.
- A Light has no id. It follows its Group's interpolated Pose. "First", for
  the Sun and the light cap, is depth-first pre-order.
- A Collider carries `rot : Quat`, and collision tests general oriented
  boxes, so a Collider turns with its Group as the Draw beside it does.
- Queries and their results stay flat and in world space. `packages/linalg`
  gives `Pose.compose` and `Pose.relative` for a game that needs to convert.
- The glue supports recursion through a `List` only, not through a
  compiler-inserted Box.

## Considered options

- Keep the flat forms. Rejected: they cost allocations, hide what belongs
  to what, and make the game repeat the composition.
- Add the trees beside the flat forms for one release. Rejected: two shapes
  double the host walk, the Bridge reply and the tests.
- A parent index on each Element or Node. Rejected: it does not give the
  pre-order that Clay needs, and the host would check every index.
- Let a Group pass its scale down, as Godot, Unity and Bevy do. Rejected: a
  non-uniform parent scale on a rotated child shears it, and the model and
  normal matrices of ADR 0001 would not hold. A uniform Group scale can be
  added later without a break.
- A Group that passes its position only. Rejected: children would not turn
  with their parent, and the arc interpolation would not exist.
- Pair a Group by its place in the tree, as an Element is. Rejected: a Node
  that changes parent could no longer pair with its previous self.
- Keep Lights and Colliders as flat lists. Rejected: a lantern belongs to
  the player.
- Keep a yaw-only Collider. Rejected: a Collider and the Draw beside it
  would disagree under a pitched Group, with no warning.
- Give a Light an id and interpolate it. Rejected: a Light rarely moves
  inside its Group, and its Group already interpolates.
- Put Queries in the tree. Rejected: a Query is a question, not a thing on
  screen, and `step` reasons in world space.

## Consequences

- A Roc test reads a tree with a pattern, such as `Group(_, [Draw(d), ..])`.
- An unbalanced UI cannot be written, so the host has no repair to make.
- An agent that reads the Bridge `scene` reply composes world Poses itself.
- A root Draw or Collider skips the tree walk, because its Pose is already
  a world Pose.
