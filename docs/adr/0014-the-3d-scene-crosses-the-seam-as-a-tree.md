# 0014: The 3D Scene crosses the seam as a tree

Status: accepted, 2026-10-23. It replaces the parenting decision of
Milestone 5, "Parenting stays in the game". It extends ADR 0013 to the 3D
side of the Scene.

## Context

Milestone 5 kept parenting in the game. `examples/entity-game` holds
`Entity.parent : [Root, Child(U64)]` and an invariant that a parent precedes
its child in the entity list. Its `view` composes each world pose by hand,
for Draws, Colliders and Lights. It keeps a separate `World.yaw` and pulls
yaw back out of a quaternion, because a Collider turns by yaw only.

The Scene shows none of these relations. It carries three flat lists in
world space: `draws`, `colliders` and `lights`. The host lerps world
positions, so a drop on a turning player takes a chord between two steps,
not an arc.

ADR 0013 taught the glue a nominal union that recurses through a `List`,
and moved the UI to a tree. It deferred the 3D side to this decision.

## Decision

- `Node := [Group({ id : U64, pos : Vec3, rot : Quat }, List(Node)),
  Draw(Draw), Light(Light), Collider(Collider)]`. It is nominal, as
  `Element` is.
- `Scene.nodes : List(Node)` holds the roots. It replaces `draws`, `lights`
  and `colliders` in one change, with no deprecated path. Every game,
  bench game, tutorial chapter and guide page in this repo moves in the
  same change. A game with no Groups writes a flat list of leaves.
- A Group carries a Pose: a position and a rot. Its children's Poses are
  local to it. A Group has no scale, and a scale on a Draw acts on that
  Draw only.
- Group ids and draw ids are apart. A Group pairs only with a Group, so an
  entity's Group and its Draw can both carry the entity id. A duplicate
  Group id pairs the first in tree order, and the host logs the first
  duplicate once per run. Both Groups still draw their children.
- `Launch.capacity.groups`, default 1024, sizes the Group pairing map. It
  must be above zero and at most 1048576. The frame still never allocates.
  Past the capacity, the host pairs the first Groups and logs once.
- The host interpolates in local space and then composes. If a Node's
  parent Group id is the same in both Scenes, it lerps and slerps the local
  Pose. If the parent changed, it composes both world Poses and
  interpolates those. If the parent changed and the previous parent Group
  did not pair, as a duplicate or past the capacity, a Draw does not
  pair. It draws at its current Pose.
- A Light has no id. It follows its Group's interpolated Pose, but its own
  local Pose comes from the current Scene. A Group moves a Point, turns a
  Directional `dir` and does not change an Ambient. "First", for the Sun
  and the light cap, is the order the game wrote the Nodes in: a
  depth-first, pre-order walk.
- `Collider.yaw : F32` becomes `rot : Quat`. The collision code tests a
  general oriented box: three axes per box, 15 separating axes for two
  boxes. The host composes each Collider's world Pose from the current
  Scene before it answers the Queries. With no Queries, it skips that
  walk.
- Queries stay a flat list in world space. Contacts, RayHits and
  OverlapHits stay in world space.
- `packages/linalg` gains `Pose`, with `Pose.compose(parent, local)` and
  `Pose.relative(parent, world)`. The game uses them when a Node changes
  parent, or when a Query starts from a child.
- The Bridge `scene` reply mirrors the tree with local Poses:
  `{"Group":{"id":N,"pose":{"pos":{...},"rot":{...}},"children":[...]}}`,
  `{"Draw":{...}}`, `{"Light":{...}}` and `{"Collider":{...}}`.
- The tree is still a Description. The host keeps no Node from one Scene
  to build the next.

## Considered options

- Keep the flat lists and parenting in the game. Rejected: the Scene hides
  the relations, the game repeats the composition for three kinds of leaf,
  and interpolation takes a chord.
- Add `nodes` beside `draws` for one release. Rejected for the reasons in
  ADR 0013: two shapes double the host walk, the JSON and the tests.
- Let a Group pass its scale down, as Godot, Unity and Bevy do. Rejected:
  a non-uniform parent scale on a rotated child shears it. The model matrix
  `T · R · F · S · F⁻¹` of ADR 0002 and its normal matrix would not hold.
  A uniform Group scale can be added later without a break.
- A Group that passes its position only. Rejected: the children would not
  turn with their parent, and the arc interpolation would not exist.
- One id namespace for Groups and Draws. Rejected: an entity's Group and
  its mesh would need two ids.
- Pair a Group by its place in the tree, as a Box is. Rejected: a Node
  that changes parent could no longer pair with its previous self.
- Keep Lights and Colliders as flat lists. Rejected: the tree is there to
  show what belongs to what. A lantern belongs to the player.
- Keep `Collider.yaw` and drop a Group's pitch and roll for Colliders.
  Rejected: a Collider and the Draw beside it would disagree with no
  warning.
- Give a Light an id and interpolate it. Rejected: a Light rarely moves
  inside its Group, and its Group already interpolates.
- Put Queries in the tree. Rejected: a Query is a question, not a thing on
  screen, and `step` reasons in world space.

## Consequences

- Each Group adds one list allocation. Leaves add none. One `nodes` list
  replaces three lists, so entity-game went from 5 allocs per quiet step
  to 3. The player's Group adds one more while it carries drops.
- Game code stays idiomatic, and an alloc count is a record, not a target.
  entity-game was first written to keep the 3: one `List.with_capacity`
  for the roots and a counting pass for each Group. It now builds its
  Scene with list literals, `List.keep_if` and `List.join_map`, and makes
  33 allocs and 4 reallocs per quiet step under `--opt=speed`. Its release
  `view` Span median went from 0.83 us to 2.25 us. Most of the new allocs
  are one list per entity and one per root that `List.keep_if` keeps. The
  alloc check records the new counts.
- `examples/entity-game` drops its hand-written composition and its
  `World.yaw`. It may still keep `Entity.parent` in its Model.
- A Roc test reads the tree with a pattern, such as `Group(_, [Draw(d), ..])`.
- The general box test was expected to cost more than the yaw-only one.
  `bench/colliders` measured no loss: the `queries` Span median went from
  97.6 us to 93.8 us at N = 4096, because the Shapes no longer call
  `sincos`.
- The tree walk costs time. The first version raised the `interpolation`
  Span median of `bench/draws` by about 8% and the `queries` Span median of
  `bench/colliders` by about 9%. Now a root Draw or Collider skips the
  walk, because its Pose is already a world Pose. On an Apple M5, Headless
  and Lockstep, the flat `bench/draws` `interpolation` median is within 1%
  of the flat list before the tree, at N = 1024 and N = 16384. The
  `queries` median of `bench/colliders` stays 4% to 7% above it, for the
  copy of each Collider into the list that the search reads.
- An agent that reads the Bridge `scene` reply composes world Poses itself.
- More than one shadow caster stays a separate task. This decision keeps
  one Sun.
