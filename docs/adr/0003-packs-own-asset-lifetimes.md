# 0003: Packs own asset lifetimes

Status: accepted, 2026-10-14.

## Context

The host loaded every mesh in `assets/meshes/` once, before `init`, and
kept it for the whole run. Nothing could change what was loaded while the
game ran. Kula needs a different block set and sky for each Theme, and a
larger game needs to stream content in and out. The engine had one
lifetime for loaded assets, the level, and no way for a game to end it.

## Decision

- A Pack is the unit of asset lifetime. The engine has no level.
- The game sends `Load` and `Unload` Commands. The host runs each one after
  the `init` or `step` that returned it, and before the next `view`.
- `init` returns `{ model, commands }`, so a game can load its first Pack
  before the first step.
- A fourth call, `loaded`, gets the Pack name and its Manifest. The host
  loads synchronously and calls `loaded` before the next `view`.
- `Config` carries the asset names found on disk, with no ids.
- Packs are independent. Any number can be loaded at once, and each unloads
  by name, in any order. An asset that two loaded Packs name loads once
  and keeps one id.
- Assets sit on disk by kind, not by Pack. A Pack is a list of names in
  game data, not a directory.
- Every name in a Load appears in the Manifest. A missing name or a failed
  load gets id 0 and one log line.
- The Primitives load at startup, belong to no Pack and never unload. A
  game can draw them before any Load.

## Considered options

- One Pack at a time, where a Load replaces the loaded Pack. Rejected: a
  world Pack and a room Pack cannot live together, and a swap cannot keep
  the old Pack drawn until the new one is ready.
- A stack of Packs. Rejected: it fits menus over a world, but streamed
  chunks behind the player must unload in any order.
- A directory per Pack. Rejected: one file then cannot serve two Packs
  without a copy, and a game cannot choose its Packs in Roc.

## Consequences

- A later background loader changes no game, because games already wait
  for `loaded`.
- Each asset table reuses freed slots. The slot generation in an id makes
  an id from an unloaded Pack stale, and a stale id draws the Fallback mesh.
- GPU resources belong to the asset, not the Pack. A Pack keeps only its
  name and its asset list.
- `Config` carries no ids, so the Primitive ids are fixed constants. No
  Primitive slot goes on a free list.
