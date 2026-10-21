---
title: Important defaults
summary: The defaults and rules that most often surprise new rocco authors, in one place, with a link to the page that explains each one.
order: 2
---

# Important defaults

Most of rocco's defaults are chosen so that a small game works with little
code. A few of them can still catch you out, usually as a black screen, a
magenta cube or an object that slides across the scene. This page lists
those defaults in one place. Each one links to the page that explains it.

## Drawing

- **The host has no light of its own.** `Scene.empty` has no Lights, so a
  Scene with no Lights draws its meshes black. Add at least an ambient light
  and a directional light. See [The Scene](scene.md#lights).
- **Mesh id 0 is the fallback mesh, a magenta cube.** A misspelt asset name,
  a file that does not load, a stale id and a full mesh table all give id 0.
  If you see a magenta cube, read the log. See
  [Assets and Packs](assets.md#the-fallback-mesh).
- **`Draw.default` has mesh 0 and id 0.** Set `mesh` and `id` on each Draw.
  If you forget `mesh`, the Draw shows the magenta cube.
- **Draws pair by id.** The host draws smooth frames by pairing each Draw
  with the Draw that had the same `id` in the previous Scene. If a new thing
  reuses an old id, it slides from the old thing's place. See
  [Pairing by id](scene.md#pairing-by-id).
- **Colours are linear, not sRGB.** Tints and Light colours are linear. The
  host converts to sRGB for the screen. A Light colour carries its
  intensity, so it can go above 1: a directional colour of about 3.14 lights
  a white surface that faces it to about 1. See
  [Colours](scene.md#colours).
- **Only the sun casts a shadow.** `Light.directional` casts no shadow. Use
  `Light.sun` for the one light that does.
- **Lights and the UI do not interpolate.** They change once per fixed step,
  so a light that moves jumps a little each step.
- **The default camera** in `Scene.empty` is at (0, 5, 10), looks at the
  origin, and has a vertical field of view of about 60 degrees.

## Time

- **120 fixed steps each second.** The host calls `step` and `view` 120
  times each second, whatever the display rate. `dt` is the same at every
  step. Change the rate with `step_hz` in the Launch. See
  [The five calls](calls.md#fixed-steps-and-frames).
- **A key is pressed for one step only.** A press shows in the first step
  after the key goes down. Mouse movement also arrives in the first step of
  a frame, and later steps of that frame get zero. See [Input](input.md).
- **Query results are one step old.** `step` gets the answers to the
  Queries of the previous Scene. The first step gets empty QueryResults. See
  [The one-step latency](collisions.md#the-one-step-latency).
- **No Contacts without a `ContactsOf` Query.** The host finds Contacts only
  for the owners of a `ContactsOf` Query.

## Startup

- **The host binds no key to Quit.** Escape does nothing until your game
  returns the `Quit` Command for it. See [Input](input.md).
- **A `Quit` from `init` stops only a Headless run.** To reject bad Args in
  a windowed run, return `Quit` from the first `step`.
- **`launch` runs once.** The host reads the Launch before the window opens
  and never again. Hot reload calls neither `launch` nor `init` again, so
  restart the game after you change them. See [Launch](launch.md).
- **The default window** is 960 by 540, titled `rocco`, with `high_dpi` on,
  4x MSAA and vsync on.
- **The run mode can override the Launch.** Lockstep and Headless turn
  vsync off. Headless opens no window. See
  [Running and debugging](running.md#lockstep-and-headless).
- **The default capacities** are 64 meshes, 16 skies, 16384 Draws and 16384
  UI quads, with a 2048 shadow map. Past a capacity, the host logs once and
  keeps running, but it drops what does not fit. See
  [Launch](launch.md#past-a-capacity).
- **The seed is 0** unless you set `ROCCO_SEED`. So each run gets the same
  randomness by default.
- **The host loads no assets at startup.** It lists the asset names in
  `Config.assets`, but your game must send `Load` to get ids. Asset names
  are case-sensitive. See [Assets and Packs](assets.md).

## Building

- **`roc main.roc` and `roc run` use the dev backend.** It builds fast, and
  hot reload needs it. `roc build` uses `--opt=speed`, which gives a fast
  binary but builds slower.
- **On Linux, always give `--target=x64glibc`.** Without it, `roc build`
  picks a static musl target, and the platform has no musl target.
- **`roc build` can exit with code 2 and still work.** If your game imports
  the mesh package, Roc warns about the `dbg` in `Mesh.resolve` and exits
  with code 2, but it writes the binary. See
  [Shipping a game](shipping.md#build-for-each-target).
