# 0003: Packs own asset lifetimes

Status: accepted, 2026-10-14.

## Context

The host loads every mesh in `assets/meshes/` once, before `init`, and
keeps it for the whole run. The game gets the ids in the `Config` manifest.
Nothing can change what is loaded while the game runs.

Kula needs a different block set and sky for each Theme. A larger game needs
to stream content in and out. The engine had one lifetime for loaded assets,
the level, and no way for a game to end it.

## Decision

- A Pack is a named set of assets that load and unload together. "Level" is
  a game word. The engine has no level.
- `Command` gains `Load({ pack : Str, assets : List(Str) })` and
  `Unload(Str)`. The host runs each one after the `init` or `step` that
  returned it, and before the next `view`.
- `init` returns `{ model, commands }`, so a game can load its first pack
  before the first step.
- A fourth seam function, `loaded : Model, Str, Manifest -> Model`, takes the
  pack name and a `Manifest : List({ name : Str, id : U32 })`. `loaded` is
  the only promise that ids exist. The host loads synchronously and calls
  `loaded` in the same frame, before the next `view`.
- `Config` carries `assets : List(Str)`, the names found on disk, with no
  ids.
- Packs are independent. Any number can be loaded at once. Each unloads by
  name, in any order.
- An asset named by two loaded packs loads once and keeps one id. Each asset
  counts the packs that hold it and unloads when the count is zero.
- Assets are organised by type on disk, not by pack: meshes in
  `assets/meshes/`, skies in `assets/sky/`. A pack is a list of names in game
  data, not a directory.
- Every name in a Load appears in the Manifest. A name not on disk, or a file
  that fails to load, gets id 0 and one log line.
- The primitives load at startup. They belong to no pack and never unload.
  They are the one exception to `loaded`: a game can draw them before any
  Load.

Three other options were rejected:

- One pack at a time. A Load replaces the loaded pack. It is simple, but a
  world pack and a room pack cannot live together, and a swap cannot keep
  the old pack drawn until the new one is ready.
- A stack of packs. A Load pushes and an Unload pops the top. It fits menus
  over a world, but streamed chunks behind the player must unload in any
  order.
- A directory per pack. The files of a pack sit in `assets/<pack>/`. One
  file then cannot serve two packs without a copy, and a game cannot choose
  its packs in Roc.

## Consequences

- A swap is `Load(new)`, then `loaded`, then `Unload(old)` from a later
  step. The new ids exist before the old ones go, so no frame draws a stale
  id.
- A later background loader changes no game. Games already wait for
  `loaded`.
- Each asset table reuses freed slots through a free list. The slot
  generation from the mesh id makes an id from an unloaded pack stale, and
  a stale id draws the fallback.
- GPU resources belong to the asset, not the pack. Vertex and image data are
  scratch until upload, so a pack keeps only its name and its asset list. The
  level arena goes.
- `Config` carries no ids, so `Mesh.primitive(config, Cube)` cannot read a
  primitive id from it. The seam task `jw0tlmqt` decides how a game gets the
  primitive ids.
- Every game changes `init` and adds `loaded`. This is a vocabulary change,
  so the host and every game rebuild.
- A Load for a loaded pack, an Unload for an unknown pack, and a second Load
  of one pack in one step each log once per pack name and do nothing.
