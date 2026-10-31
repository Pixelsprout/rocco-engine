# 0013: The Scene crosses the seam as a tree

Status: accepted, 2026-10-22. It replaces the transport part of ADR 0004.
The layout part of ADR 0004 stands. On 2026-10-31 the `Box` tag became
`Panel`, so `Element := [Panel(BoxConfig, List(Element)), Text(Text)]`.
The decision stands.

## Context

ADR 0004 made `Scene.ui` a flat stream of `Open`, `Text` and `Close`,
because the glue could not carry a recursive tag union. Games write nested
code, and `Ui.box` flattens it with a concat and an append.
`docs/RESEARCH-SCALING.md` links that flattening to pong's 13 allocations
and 6 reallocs per step. A Roc test must count `Open` and `Close` to read the UI. The host repairs
two errors: an extra `Close` and an unclosed `Open`.

The pinned Roc nightly `nightly-2026-10-11-7d256b9` carries a nominal
recursive tag union across the host boundary. A union that refers to
itself through a `List` is stored inline, with no compiler-inserted Box.
`Element` is then 40 bytes with its tag at byte 32. The Odin glue refuses
the union with one check in `glue/OdinGlue.roc`. With that check removed,
the generator emits the layout and mutually recursive release procs that
match the Zig glue. A trial host walked a UI tree and freed every
allocation. Milestone 21 makes this change.

## Decision

- `Element := [Box(BoxConfig, List(Element)), Text(Text)]`. It is nominal,
  because only a nominal recursive union crosses the host boundary. It
  adds no new kinds of Element.
- `Scene.ui : List(Element)` holds the roots. An empty list allocates
  nothing.
- The tree replaces the flat stream in one change, with no deprecated
  path. Every game, bench game, package and tutorial chapter in this repo
  moves in the same change.
- The value changes shape and nothing else. It is plain data, with no
  events, no closures and no `Html.map`.
- An Element keeps its identity by its place in the tree. Ids wait for
  pointer input.
- Games write the tags directly: `Box(config, [...])` and `Text(...)`.
  `packages/ui` keeps the defaults, such as `Ui.default_box`, and small
  helpers, such as a panel or a label. It has no `Ui.box` or `Ui.text`.
- The Odin glue learns recursion through a `List` only. It refuses direct
  recursion through a compiler-inserted Box, such as `Fork(Tree, Tree)`,
  with an error that names the type. `glue/README.md` records the limit.
- The host walks the tree with one recursive procedure and drops both
  repairs. Clay keeps the layout in the host, as ADR 0004 decided.
- The Bridge `scene` reply mirrors the tree, as it mirrors Commands:
  `{"Box":{"config":{...},"children":[...]}}` and `{"Text":{...}}`.

## Considered options

- Keep the flat stream. Rejected: the stream costs allocations in every
  step, makes tests count brackets, and needs two host repairs that a
  tree makes impossible.
- Add the tree beside the flat stream for one release. Rejected: two
  shapes double the host walk, the JSON and the tests. Every game that
  uses the UI is in this repo, apart from Kula, which pins a release.
- Wrap the tags in `Ui.box` and `Ui.text`. Rejected: the tags already read
  as the value, and a Roc test matches the same tags that the game wrote.
- Give each Box an id now. Rejected: nothing reads an id until pointer
  input arrives.
- Teach the glue direct recursion through a Box. Deferred: neither tree
  needs it. It needs a typed Box release in the generator, about 50 to 100
  lines with tests.
- Move the 3D Draws into a tree in the same milestone. Deferred to
  Milestone 22, which gets its own grilling. It changes the parenting of
  Milestone 5 and needs its own ADR.

## Consequences

- Each Box's children list is one allocation, and nothing is joined. The
  alloc check records pong's new count per step. It sets no target.
- A Roc test reads the UI with a pattern, such as
  `Box(_, [Text(t), _, _]) => t.str == "x"`.
- An unbalanced UI cannot be written, so the host has no repair to log.
- Every game that builds a UI changes its code. Kula changes when it moves
  to the release that carries the tree.
- A Box can later carry an event tag for pointer input (dex task
  5rxq8tn7). The tree does not block it. Pointer input still reopens the
  layout part of ADR 0004.
- `drop_model_for_host` stays. The glue sees `Box(Model)` as an unknown
  type of size 0, so the host cannot free the Model.
