# 0023: A light list per Draw

Status: accepted, 2026-10-31. It replaces the cap of 8 Directional and
Point lights per Scene.

## Context

Agent Town carries one Point light per orb, for any number of otters,
beside a Sun. Kula's key light and the Zelda-style demo also need more than
8 lights in a Scene.

The host sent one light list per frame, and every Draw got the same list. It
kept the first 8 Directional and Point lights in walk order and dropped the
rest. A Sun past the 8th light lost its slot. `docs/RESEARCH-LIGHTS.md`
compares Bevy, Godot and raylib.

## Decision

- A Scene holds any number of Directional and Point lights. The host gathers
  them once per frame into two lists in the frame arena.
- Each Draw gets at most 8 lights (`MAX_LIGHTS`), in this order:
  1. The Sun, if the Scene has one, in slot 0.
  2. The other Directionals, in walk order.
  3. The Point lights whose range reaches the Draw's world box, nearest
     first.
- "Reaches" means that the squared distance from the light to the box is
  less than the squared range. "Nearest" means the smaller distance to the
  box. A tie goes to the smaller distance to the box centre, and a second
  tie keeps walk order.
- The world box comes from the mesh box and the Draw's model matrix, by
  Arvo's method. The host builds it only when the Scene has a Point light.
- The list goes in the per-draw fragment block `fs_params`, sent with each
  Draw. `fs_lights` keeps the frame values: the ambient, the camera, the
  Sun's shadow values and the shadow matrix. The shader loop does not
  change, and it still reads the Sun's slot from `shadow.y`.
- An unlit Draw gets an empty list.
- A Draw that loses a Directional or a Point light in reach logs once per
  run. The log for a Scene with more than 8 lights goes. The other drops
  stay: a second ambient, a Directional with a zero `dir` and a Point with
  a range of 0 or less.

## Considered options

- Raise `MAX_LIGHTS` per Scene. Rejected: every pixel pays for every light,
  and a cap per Scene stays.
- Clustered forward lighting, as in Bevy and Godot Forward+. Rejected for
  now: it needs a light grid per frame and storage buffers or a large
  uniform array. A list per Draw keeps Metal, GL core and D3D11 on uniform
  blocks.
- A per-frame light array with 8 indices per Draw. Rejected: a fixed
  uniform array caps the Scene again.
- Rank the lights by how much light they give the Draw, not by distance.
  Rejected for now: it adds a colour term, and lights can pop either way.

## Consequences

- Lights can pop on a large mesh with more than 8 lights in reach. Split a
  large floor into tiles.
- `fs_params` grows from 64 to 320 bytes. On Metal it takes 2 uniform
  slots, so a Draw takes 1,024 bytes of the uniform buffer, up from 768.
  `DRAW_LIMIT` falls from 2,793,466 to 2,095,099.
- GL uploads 20 `vec4` per Draw instead of 4. D3D11 fits the block in one
  constant buffer with a wide margin.
- The selection costs CPU time per Draw per Point light, in the
  `render_submit` Span. `docs/BENCHMARKS.md` records it, with the `lights`
  bench game.
- No game changes. No Vocabulary type changes, and `BRIDGE_PROTOCOL` does
  not change.
- Cascaded shadows change `fs_lights`. They do not touch the list.
