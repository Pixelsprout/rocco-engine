# 0024: An Image is a Pack asset

Status: accepted, 2026-11-01. Milestone 34.

## Context

Agent Town and Kula need pictures in the UI: status icons in a ledger
table, key and fruit icons in a HUD. A later 2D mode needs sprites. The
engine could load a PNG only as a mesh texture or a sky face.

Godot splits this in two. One `Texture2D` holds the pixels and has many
users. A small `AtlasTexture` names a texture and a region of it. The
engine follows that model, so the UI and sprites share one asset and one
value.

## Decision

- An Image is a Pack asset. Its name has the `image/` prefix, and its file
  is `assets/images/<stem>.png`. The noun is Image. PNG is the only format.
- One `Image` value names an Image and how to show it:
  `{ id : U32, region : [Whole, Px({ x, y, w, h })], tint : Rgba, filter : [Linear, Nearest] }`.
  The region counts in source pixels from the top-left corner. UI Panels
  take it now, and 2D sprites will take it later. A flipbook is a region
  that changes. The Panel adds its own `[Stretch, Fit]`.
- The filter is a field of each Image value. `Image.default` has `Linear`.
  The host keeps one Linear and one Nearest sampler, both clamped to the
  edge, and every Image shares them. Launch has no filter default yet.
- An Image has no mipmaps. It uploads as SRGB8A8 with one level.
- Each Manifest entry carries `size : { w : U32, h : U32 }`. An Image fills
  it. Every other kind, and a name that did not load, gives 0 by 0.
  `Image.size` reads it, so a game can count a region without the file.
- `Launch.capacity.images` sizes the Image table, 256 by default, at least
  2 and at most 65536. Slot 0 is no Image. A full table gives id 0 and one
  log line, as for meshes. The sokol image and view pools grow by the
  capacity, and the sampler pool by 2.
- After the decode, the loader gives each fully transparent pixel the
  average colour of the nearest pixels that have one. The UI blend stays
  straight alpha, so linear filtering does not darken a visible edge.
- An Image's GPU image and view go when its last Pack unloads, as a mesh's
  do. The slot's generation goes up, so a kept id no longer finds it.

## Considered options

- An `Image` Element tag beside Panel and Text. Rejected: a Panel already
  has a size, a radius and a hit test, and an icon Button needs all three.
- A Panel-only image record. Rejected: sprites would need a second value
  for the same pixels.
- Mipmaps. Rejected for now: UI icons draw near their own size, and
  mipmaps blur pixel art. A 2D mode that scales far down can add them.
- Premultiplied alpha. Rejected for now: it changes the UI blend for every
  quad, and the bleed already removes the dark fringe at a visible edge.
- A filter default in Launch. Deferred to the 2D mode, as a dex task.

## Consequences

- Adding `size` to the Manifest and `images` to the Capacity changes the
  vocabulary. Every hand-written Manifest literal gains `size`.
- An Image costs its pixels on the heap until the upload, then its GPU
  memory only. A Load in `init` uploads when the renderer starts; a later
  Load uploads at once.
- Nine-slice and tiled images, JPG and hot reload stay out. Each is a later
  dex task or not planned.
