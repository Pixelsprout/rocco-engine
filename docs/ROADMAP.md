# rocco roadmap

Engineering milestones. Each milestone names what exists when it is done and
how to check it. Order matters: each one unlocks the next. `docs/DESIGN.md`
governs every entry here. If a milestone needs the design to change, change
the design first.

## Where the engine stands

Built and running:

- Fixed-timestep loop with an accumulator and interpolation.
- Three arenas by lifetime: permanent, level, frame. The level arena has no
  caller yet.
- Metal rendering through sokol: one pipeline, one cube mesh, index buffers,
  back-face culling, reversed-Z depth, one directional light.
- Camera with mouse look and quaternion orientation.
- The engine links as `libhost.a` into a Roc platform. Roc owns the script
  state. The host honours `roc_dealloc`. Hot reload works under `roc run`.
- The generated Odin ABI comes from `roc glue` with the spec in
  `../roc-odin-glue`.

Not built: the generic platform in `docs/DESIGN.md`. The current
`game/platform/main.roc` names a concrete `Body` record. It is the last
game-specific header.

## Milestone 1: the platform stops naming the game

Done when `game/platform/main.roc` is the header in `docs/DESIGN.md` section
4 and both games in `docs/examples/` link and run against it.

1. Extend the glue spec in `../roc-odin-glue` with `Str`, `Box` as
   `rawptr`, and `List(U16)`. Check the output against the Zig glue for the
   same platform.
2. Write the host side of `Input`: fill `held` and `pressed` from the
   `down` and `prev` arrays each fixed step. Fill the mouse delta.
3. Write the host side of `Config`: a seed and a manifest with the three
   primitives, ids 1 to 3. Id 0 is the fallback.
4. Write the host side of `Scene`: keep two, pair draws by id, interpolate at
   render time, write one model matrix per draw.
5. Implement the call protocol in `docs/DESIGN.md` section 5. Count
   allocations with the tracking allocator. Expect one box shell alloc and
   free per step and no list copy.
6. Run both example games. Switch between them by changing one line in
   `game/main.roc`. `libhost.a` must not rebuild.

Check: the allocator counters show in-place mutation. A change to either
game's `Model` does not touch `engine/`.

## Milestone 2: mesh handles and the manifest

Done when `Scene` draws by id resolve to more than one mesh.

1. Give the renderer a mesh table indexed by id. Load the three primitives
   into it at startup. Reserve id 0 for a magenta fallback cube.
2. Publish the table to `init` as the manifest.
3. Draw every entry in a `Scene` with its own mesh and transform.

Check: the entity game shows a cube player, sphere pickups and a slab door.
A misspelt mesh name draws magenta and logs once.

## Milestone 3: geometry from disk

Done when a Blender export appears in the manifest without an engine change.

1. Pick one format. glTF binary is the default choice. Load positions,
   normals and indices only.
2. Load every file in `assets/meshes/` into the level arena at startup. This
   is the first caller of the level arena.
3. Add each file to the manifest under its file stem.

Check: drop a new `.glb` into the directory, restart, name it from Roc, see
it. No rebuild of `libhost.a`.

## Milestone 4: entities in Roc

Done when the engine has no fixed scene array.

1. Delete the fixed `scene` array from the engine. The `Scene` from `view`
   is the only source of draws.
2. Entities live in the game's `Model` as a `List(Entity)` with explicit ids.
3. Parenting is a `parent : U64` field and a fold over the list. No pointer
   tree.

Check: the entity game creates and destroys entities at runtime. The renderer
never allocates per frame.

## Milestone 5: collision as data

Done when contacts cross the seam as a list.

1. The host computes swept AABB contacts from the current `Scene` bounds or
   from a `List(Collider)` the game returns in `Scene`. Decide which by
   measuring which is smaller at 1,000 entities.
2. `step` gains a third argument: `List(Contact)`. Update `Input` or add the
   list to it. This is a vocabulary change and rebuilds `libhost.a`.
3. The game decides what a contact means. The engine never does.

Check: the player stops at the door while it is closed.

## Milestone 6: one gameplay verb

Done when the entity game is playable start to finish.

1. Add one verb as a stage in the `step` pipeline with a test.
2. Add a win state to the `Model` and a `Scene` that shows it.

Check: a stranger plays it without instructions.

## Beside the milestones

Slot these in when they pay for themselves. Do not run them as a block.

- **Debug drawing.** Lines, wireframe, text. `Scene` gains a `lines` list.
  This is a vocabulary change.
- **Audio.** `saudio` calls back on another thread against a deadline. The
  game returns what should be heard as data. The first command with a
  duration probably arrives here.
- **Shader loading and reload.** The shader is a string constant today.
- **The allocation pool.** A fixed region reserved once at startup with a
  free list behind `roc_alloc` and `roc_dealloc`. Removes the system heap
  from the step path. Satisfies static allocation. Measure before and after
  with the tracking allocator.
- **Debug and speed parity.** Run the allocator counters under both
  `--opt=dev` and `--opt=speed` after every memory change.

## Out of scope

- A Vulkan or Metal backend by hand. sokol is the floor.
- Networking.
- An editor.
- Dynamics beyond simple collision until milestone 4 is done.
- Web builds until the desktop engine runs.
- A scripting API where Roc calls the engine. Roc returns descriptions. The
  engine acts on them.
