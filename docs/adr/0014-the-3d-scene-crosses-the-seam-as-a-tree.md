# 0014: The 3D Scene crosses the seam as a tree

Status: proposed, 2026-10-23. It replaces the parenting decision of
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
  Group id pairs the first in tree order, and the host logs once. Both
  Groups still draw their children.
- `Launch.capacity.groups`, default 1024, sizes the Group pairing map. The
  frame still never allocates. Past the capacity, the host pairs the first
  Groups and logs once.
- The host interpolates in local space and then composes. If a Node's
  parent Group id is the same in both Scenes, it lerps and slerps the local
  Pose. If the parent changed, it composes both world Poses and
  interpolates those.
- A Light has no id. It follows its Group's interpolated Pose, but its own
  local Pose comes from the current Scene. A Group moves a Point, turns a
  Directional `dir` and does not change an Ambient. "First", for the Sun
  and the light cap, is the order the game wrote the Nodes in: a
  depth-first, pre-order walk.
- `Collider.yaw : F32` becomes `rot : Quat`. The collision code tests a
  general oriented box: three axes per box, 15 separating axes for two
  boxes. The host composes each Collider's world Pose from the current
  Scene before it answers the Queries.
- Queries stay a flat list in world space. Contacts, RayHits and
  OverlapHits stay in world space.
- `packages/linalg` gains `Pose`, with `Pose.compose(parent, local)` and
  `Pose.relative(parent, world)`. The game uses them when a Node changes
  parent, or when a Query starts from a child.
- The Bridge `scene` reply mirrors the tree with local Poses:
  `{"Group":{"pose":{...},"children":[...]}}` and `{"Draw":{...}}`.
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

- Each Group adds one list allocation. Leaves add none. The alloc check
  records entity-game's count per step and sets no target.
- `examples/entity-game` drops its hand-written composition and its
  `World.yaw`. It may still keep `Entity.parent` in its Model.
- A Roc test reads the tree with a pattern, such as `Group(_, [Draw(d), ..])`.
- The general box test costs more than the yaw-only one. `bench/colliders`
  records the time before and after.
- An agent that reads the Bridge `scene` reply composes world Poses itself.
- More than one shadow caster stays a separate task. This decision keeps
  one Sun.
