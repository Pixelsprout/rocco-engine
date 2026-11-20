# rocco roadmap

This page says where rocco is going and why the work runs in its order.
It holds no task list and no status.

dex holds every milestone, task, decision and result. The parent task is
**rocco roadmap** (`7mpm5az4`).

- `dex list` shows the open tree. The first unblocked task is next.
- `dex show <id> --full` shows a milestone's "Done when" criteria, its
  decisions and, when it is done, its result.

If this page and dex disagree, dex is right. Fix this page.
`docs/DESIGN.md` governs both. If a milestone needs the design to change,
change the design first.

## The destination

A person who knows Roc and nothing else makes a complete 3D game with
rocco, ships it, and never touches the engine's Odin code.

- **Only Roc to make a game.** Each release ships the engine prebuilt. A
  game author installs Roc, follows the tutorial and has a running game.
- **Every target from one source.** The same game runs on macOS, Linux,
  Windows and the web, with no platform flags in the game.
- **A modern look.** A game reaches the fidelity of the village example
  at 60 FPS on the reference machines, and authors its own look through
  Surface and Post shaders.
- **Bigger worlds.** A small open world loads its scenery as Packs, culls
  what is out of view and draws far meshes at a lower detail.
- **An editor.** The Rocco Editor, a Rocco app, inspects a running game
  over the Bridge and grows into a level editor, in the way Godot has one.
- **Other people's games.** An author outside this repo starts a game with
  `rocco new`, reaches other systems through Ports and extensions, and
  saves the game's state.
- **Games that tools can play.** The Bridge lets a script, CI or an agent
  drive any game and check what it draws.

The design stays fixed on the way: the game is pure functions, facts come
in, decisions go out, and both cross the seam as plain values.

## Where rocco stands

As of 2026-11-20 the latest release is v0.15.1. Four arcs of work are
behind it.

1. **The entity game.** A fixed-timestep loop, meshes from disk, entities
   in Roc and collision as data, on three desktop targets.
2. **Kula.** A clone of Kula World pulled tag unions, Commands, lights,
   Packs, textures, shadows and a HUD into the engine. Kula lives in
   `Pixelsprout/kula` on the published bundle.
3. **Ready to announce.** The docs and tutorial, the Bridge, audio, the
   Scene as a tree, gamepads, animation, Ports, UI text, pointer input and
   widgets, then the announcement release.
4. **Fidelity.** Agent Town's dusk town and the immersive village pulled
   materials per primitive, normal maps, HDR post effects, transparency,
   clustered lights, game shaders, Selection outlines and particles. Web
   builds through WebGPU and the in-browser Tour came beside this arc.

## The order from here

**Finish the fidelity arc.** Game fonts, foot grounding and a walk-to-run
fade, more than one shadow caster, foot contacts and IK, and render scale
with upscaling. The immersive scene lane (`mq4bgt5o`) closes when the full
village meets its frame budget on both reference machines
(`examples/village/SCOPE.md`).

**Start the Rocco Editor.** ADR 0042 sets its shape. The first milestone,
Editor 1, inspects only: a Node tree, read-only properties, a Scene pane,
pause, step and a log. Generated Draw and Group ids (ADR 0045) come first.
Prefabs (ADRs 0043 and 0044) say how an author makes a Pack.

**Pick the next candidate.** Each candidate gets a milestone number and a
grilling when it starts. dex holds the members of each.

- glTF animation coverage: cubic keys, morph targets, more Joints.
- UI 2: nine-slice and tiled Panels, and the cost of an empty UI.
- Perf and bench hygiene: the allocation pool and regression tracking.
- Platform health: open Linux, Windows, macOS and CI bugs.
- The open-world demo: distance culling, mesh LODs and an
  equirectangular sky.

**Beside the milestones.** Small work that pays for itself goes in when it
fits, not as a block. dex keeps it under one parent.

## Later arcs

These arcs are a direction, not a plan. Each gets milestone numbers and a
grilling when it starts.

**Bigger worlds.** The Zelda-style demo pulls this arc: scenery as a Pack,
static and triangle mesh colliders, and a third-person controller with
capsule tests and shape casts.

**Other people's games.** An outside author, or a second game in its own
repo, pulls this arc: saves, the extension ABI, and an author kit with
`rocco new`, `--replace-dep` and hot reload across a Model change. The
first proof of the extension ABI is a database: SQLite for local data, or a
client for a server database such as SpacetimeDB. The game Tells it to write
and Asks it to read, and each answer arrives in the next step.

**2D games.** A 2D game made with rocco pulls this arc. It starts with an
orthographic Scene camera and world-space sprites (dex task `elqpa9x2`),
which Agent Town has also asked for. The HUD pass already draws images in
screen space, so the arc builds on it. The grilling decides what a 2D game
needs beyond that, such as sprite sheet animation, tile maps and 2D
collision.

**The editor as a level editor.** After Editor 1 the editor grows toward
authoring levels. Blender as a level editor and debug drawing sit under it
in dex.

## Out of scope

- A Vulkan or Metal backend by hand. sokol is the floor.
- Networking inside the engine. The debug Bridge listens on localhost only.
  An extension can talk to a server.
- Pathfinding and navmeshes. A game that needs paths computes them in Roc.
- Dynamics beyond simple collision. Host-side bodies wait for a game that
  needs them.
- A WebGL2 fallback for web builds. The clustered lights need storage
  buffers (ADR 0036).
- A scripting API where Roc calls the engine. Roc returns descriptions. The
  engine acts on them.

## Change this page

- Put scope, steps, checks and results in dex, not here.
- Change this page when the destination, the order or an arc changes.
- Name a dex parent by its id. Do not copy its tasks or their status here.
