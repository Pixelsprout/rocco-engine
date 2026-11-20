# 0044: An author makes a Pack from Prefabs

Status: accepted, 2026-11-20. Grilled for Milestone 47 (rj6fwia8).

## Context

A game names its assets in Roc and sends `Load({ pack, assets })`
(ADR 0003). ADR 0043 adds the Prefab: a JSON Pack asset in
`assets/prefabs/`, and a Load of a Prefab also loads every asset and
Prefab it names. The Editor will author Prefabs (ADR 0042). This ADR
decides how an author describes a Pack, where import settings live, when
assets are baked, how a web build ships them, and how names state their
kind.

Today the host scans five folders. A mesh in `meshes/` takes its bare
stem, such as `pip`. Every other kind has a prefix: `sky/`, `sound/`,
`image/`, `shader/`, and `primitive/` for the built-in meshes. There are
no per-asset import settings. The image filter is chosen per draw on the
Image value. Release and debug builds differ only in the host archives,
and no asset bake depends on the mode. A web build preloads all of
`assets/` as one `index.data`.

## Decision

- A Load takes Prefab names and loose asset names together. The
  Vocabulary of ADR 0003 does not change. There is no Pack file: the
  Editor writes Prefabs, and a Prefab is the authored description of what
  loads.
- The direction is a game that Loads only Prefabs. It becomes a rule only
  when a game shows that it wants it.
- The Manifest lists the whole closure of a Load: its names and every
  asset and Prefab reached through Prefabs, each once, with one id.
- The kind of an asset name is the text before its first `/`. Meshes gain
  the prefix `mesh/`, so no kind is an exception. The primitives keep
  their `primitive/` names and fixed ids.
- A missing name in a Prefab gets id 0 and one log line, as in ADR 0003.
  The host expands a Prefab cycle to its first repeat and logs it once.
  The Editor shows both as errors and does not save a cycle.
- The host always reads source files. A bake is an optional speed-up that
  `scripts/build.roc` runs in Odin or Roc. A baked file goes only into the
  shipped output: a release folder or `index.data`. The source tree never
  holds a baked file, so the host never sees both forms of one asset. The
  release bake of Prefab JSON in ADR 0043 is such a speed-up.
- Import settings have no home yet, because no asset needs one. The first
  real setting, such as a mesh scale or a font size, goes in a sidecar
  file named after its asset, so a rename or a merge moves both together.
  A choice made per draw, such as the image filter, stays in the
  Vocabulary.
- The Editor lists the assets it can place by scanning `assets/` with the
  same code as the host's `packs_init`. The `manifest` op of ADR 0042 is
  for a running game.
- A web build keeps one preloaded `index.data`. A fetch per Pack stays
  deferred. When it comes, the closure of a Prefab is its unit.

## Considered options

- A Pack file, `assets/packs/<name>.json`. Rejected: a second authored
  format that says what a Prefab already says.
- Loads of Prefabs only, now. Deferred: every asset that code uses would
  need a Prefab before any game asks for it.
- A Manifest of only the Load's own names. Rejected: a game would look up
  ids in two places.
- Bare mesh names kept for good. Rejected: every name reader needs the
  exception, and mesh subfolders such as `meshes/trees/oak.glb` would read
  as a kind.
- A required bake for release builds, or a bake for every build. Rejected:
  an author has only Roc installed, and the Editor reloads source files.
- Baked files next to their sources, with the newer one chosen. Rejected:
  a stale bake can hide an edit.
- A Godot-style `.import` file for every asset now. Deferred until a
  setting needs one.
- A failed Load for a missing name or a cycle. Rejected: a bad name falls
  back to id 0 and never stops the game.

## Consequences

- The `mesh/` rename is a Vocabulary change on its own task. The host,
  every example game and Kula rebuild, and their asset lists change.
- Prefab expansion in the host must compute the closure of a Load before
  it builds the Manifest.
- `packs_init`'s scan becomes code the Editor shares.
- `build.roc` gains an asset output step the first time a bake exists.
- Pack authoring itself ships with the level-editing milestone, not with
  Editor 1.
