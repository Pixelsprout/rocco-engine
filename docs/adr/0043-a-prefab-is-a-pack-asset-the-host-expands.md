# 0043: A Prefab is a Pack asset that the host expands

Status: accepted, 2026-11-20. Grilled for Milestone 47.

## Context

The Editor's end goal is a level editor (ADR 0042). A game rebuilds its
Scene every step, and the host keeps no Node (ADR 0014). ADR 0003
says the engine has no level.

`examples/village` is the precedent. `source/prepare.py` turns a Godot
`world.tscn` into `Layout.roc`: 1,645 lines of generated placements and an
asset list of about 90 names. `view` maps every placement to a Node each
step. The Roc language server used a lot of memory on that file, and every
change to the layout needs a rebuild.

## Decision

- A Prefab is a JSON file in `assets/prefabs/`, named with a `prefab/`
  prefix, that a Pack loads. A release build bakes it to the generated
  binary Scene codec of ADR 0042.
- A Prefab holds Groups, Draws, Lights, Colliders, Speakers, other Prefabs
  and Markers. A Marker is a named Pose with tags and properties and draws
  nothing. A Prefab holds no Attach.
- Each node has a local id, a random U64 that the Editor makes once, so two
  git branches cannot give two nodes the same id. Each node has a name, a
  list of tags and typed properties: Bool, I64, F32, Str, Vec3, Rgba or an
  asset name.
- A Load of a Prefab also loads every asset and Prefab it names, in the
  same Pack.
- A game places a Prefab with one Node: `Prefab({ id, prefab, pose,
  changes })`. The host expands it. By default every node draws as
  authored. A Change, `Replace(path, node)` or `Hide(path)`, alters one
  node for the step that sends it.
- A Path is the list of local ids from the placed Prefab down to a node.
  Results and interpolation pair a placed node by the U64
  `hash(placed id, path)`, which `Prefab.node_id` computes in Roc.
- `loaded` gives the game the whole tree once: each node's kind, Path,
  name, tags, properties and Pose in the Prefab. The game builds its
  entities from the tags and properties. The engine never runs Roc for a
  node.
- When the Editor saves a Prefab, the host loads it again and calls
  `loaded` again. The game treats it as a replacement. The Editor never
  writes into the Model.
- The Editor edits a Prefab with no game running: it builds a Scene from
  the file and draws it as a Render.

## Considered options

- Generated Roc source, as in the village. Rejected: language-server
  memory, a rebuild per edit, and an Editor that writes Roc syntax.
- The game expands the Prefab in `view`. Rejected: every placed node then
  crosses the seam and every Watch every step.
- A "game-owned" flag on nodes that the host skips. Rejected: it puts a
  runtime choice on the author. Changes let the game alter any node.
- Names or counters as node ids. Names break on a rename. Counters collide
  on a git merge.
- Scripts on nodes. Rejected: Roc returns Descriptions, and the engine
  does not call into Roc for behaviour.
- Overrides on a placed Prefab in the Editor (variants). Deferred until a
  level needs them.

## Consequences

- The Prefab Node and `Change` are a Vocabulary change. `loaded` gains a
  Prefab tree for Prefab entries in the Manifest.
- A large static level costs one Node per placed Prefab at the seam.
- A game that changes many nodes in a Prefab each step pays for each
  Change. A Prefab is cheap when most of it is static.
- Per-tag property schemas can come later as an Editor file with no
  runtime change.
