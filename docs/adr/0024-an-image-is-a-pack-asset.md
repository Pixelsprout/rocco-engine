# 0024: An Image is a Pack asset

Status: accepted, 2026-11-01.

## Context

Agent Town and Kula need pictures in the UI: status icons in a ledger
table, key and fruit icons in a HUD. A later 2D mode needs sprites. The
engine could load a PNG only as a mesh texture or a sky face.

Godot splits this in two. One `Texture2D` holds the pixels and has many
users. A small `AtlasTexture` names a texture and a region of it. The
engine follows that model, so the UI and sprites share one asset and one
value.

## Decision

- An Image is a Pack asset with the `image/` prefix. PNG is the only
  format.
- One `Image` value names an Image id, a region of it, a tint and a filter.
  UI Panels take it now, and 2D sprites will take it later. A flipbook is
  a region that changes. The Panel adds its own fit.
- The filter is a field of each Image value, not a Launch default. Every
  Image shares one Linear and one Nearest sampler.
- An Image has no mipmaps.
- Each Manifest entry carries a size, which an Image fills. A game can
  count a region without the file.
- Id 0, or a stale id, draws a magenta and black checker and logs once for
  each id. A game shows `NoImage` until `loaded` gives the id.
- The loader fills the colour of fully transparent pixels from their
  neighbours, so the UI blend stays straight alpha with no dark fringe.
- An Image's GPU resources go when its last Pack unloads, as a mesh's do.

## Considered options

- An `Image` Element tag beside Panel and Text. Rejected: a Panel already
  has a size, a radius and a hit test, and an icon Button needs all three.
- A Panel-only image record. Rejected: sprites would need a second value
  for the same pixels.
- Mipmaps. Rejected for now: UI icons draw near their own size, and
  mipmaps blur pixel art. A 2D mode that scales far down can add them.
- Premultiplied alpha. Rejected for now: it changes the UI blend for every
  quad, and the colour fill already removes the dark fringe.
- A filter default in Launch. Deferred to the 2D mode.

## Consequences

- An Image costs its pixels on the heap until the upload, then its GPU
  memory only.
- Nine-slice and tiled images, JPG and hot reload stay out.
