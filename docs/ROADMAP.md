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
- Rendering through sokol: one pipeline, one cube mesh, index buffers,
  back-face culling, reversed-Z depth, one directional light. The backend is
  Metal on macOS, GL core on Linux and D3D11 on Windows. One shader
  source in `engine/shaders/basic.glsl` compiles to all three with
  `sokol-shdc`.
- Camera with mouse look and quaternion orientation.
- The engine links as one host library per target into a Roc platform. The
  game owns its state. The host honours `roc_dealloc`. Hot reload works
  under `roc run` on macOS.
- The generated Odin ABI comes from `roc glue` with the spec in the
  `glue/` submodule (roc-odin-glue).
- `examples/bodies` builds and runs from one checkout on three targets:
  `arm64mac`, `x64glibc` and `x64win`. `scripts/build.roc` runs every step.
  `ROCCO_EXIT_AFTER_FRAMES` makes a run end cleanly for checks.

Not built: the generic platform in `docs/DESIGN.md`. The current
`platform/main.roc` names a concrete `Body` record. It is the last
game-specific header. Milestone 2 replaces it.

## Milestone 1: one source tree, three desktop targets (done)

Cross-platform came first, while the engine was small. Every line written
after this milestone lands in a file that already has a home per platform.

Done: `examples/bodies` builds and runs on three machines from one checkout,
with one host library per target.

| Host | Target | Host library | How it was checked | Result |
|---|---|---|---|---|
| macOS arm64 | `arm64mac` | `libhost.a` | Natively, `ROCCO_EXIT_AFTER_FRAMES=120` | Exit 0, `Frame Count: 120` |
| Linux x64 | `x64glibc` | `libhost.a` | `./scripts/linux/check.sh`: the Docker image, `xvfb-run`, software GL, `ROCCO_EXIT_AFTER_FRAMES=120` | Exit 0, one `Frame Count: 120` line, about 15 seconds with the image built |
| Windows x64 | `x64win` | `host.lib` | By hand with Visual Studio Build Tools 2026 and a Windows SDK, `ROCCO_EXIT_AFTER_FRAMES=120`, then a look at the picture | Exit 0, `Frame Count: 120`, three bodies drawn correctly |

Checks that passed: `git grep "when ODIN_OS"` returns only the platform
files. Today it returns no code file at all. `git grep "SOKOL_METAL\|MTL"`
returns nothing outside `platform_darwin.odin` and the generated shader
file, apart from this document.

The pattern is karl2d's, adapted to an engine that keeps sokol as the floor:

- One file per platform, selected by `#+build darwin`, `#+build linux`,
  `#+build windows`. No `when ODIN_OS` inside shared files. Each file holds
  the one real per-OS constant that exists today: the expected sokol backend,
  checked at init.
- Where a subsystem has more than one implementation, a struct of procedures
  per implementation and one constant chosen at compile time, with a
  `#config` override. karl2d does this for its render and audio backends and
  panics at compile time on an invalid name. rocco adds it when the audio
  backend or the file system arrives. Nothing has two implementations yet, so
  this milestone did not build the chooser.
- Shaders compile from one source to every backend at build time.
  `sokol-shdc` emits an Odin file with MSL, GLSL and HLSL from one `.glsl`
  source. The generated file is committed. shdc is a dev-only tool.

What the Roc linker needs:

- A `targets:` input is only ever a file in `targets/<target>/`. There is no
  library-name syntax. Roc links with `-nostdlib`, so the platform lists
  every CRT object and library as a file, and the validator rejects
  undeclared files in that directory. The `inputs` step of
  `scripts/build.roc` fills the directory for the OS of the machine.
- `x64glibc` refuses to link from a machine that does not run Linux.
  `x64musl` cross-links from macOS but forces `-static`, and sokol needs
  shared X11 and GL. So the Linux binary is linked on Linux, in the Docker
  image.
- `x64win` needs a Windows SDK on the machine. sokol's own Windows script needs
  `cl`. So the Windows binary is linked on Windows.
- No cross-compiling from one machine, then. Each machine builds its own
  target.

What the work found:

- Linux needs nine system files: `Scrt1.o`, `crti.o`, `crtn.o`, `libc.so.6`,
  `libm.so.6`, `libX11.so.6`, `libXi.so.6`, `libXcursor.so.1` and
  `libGL.so.1`. They must be the soname-versioned files, because lld records
  the soname as `DT_NEEDED`. No compiler-rt or libgcc file is needed.
- Windows needs seven SDK import libraries: kernel32, user32, gdi32, shell32,
  ole32, d3d11 and dxgi. No CRT library is needed.
- The glue declared the Roc entry points with `foreign import "system:c"`.
  On Windows, `lib.exe` read that as an input file named `c`. The glue now
  emits a foreign block with no library, because the Roc app defines the
  symbols at the final link.
- GL needs sokol-shdc's `fixup_clipspace` option so that its depth values
  match Metal and D3D11. It does not give GL the precision of float
  reversed-Z. That needs `glClipControl` and a 32-bit float depth target.
- sokol is the `sokol-odin/` submodule, pinned. A fresh
  `git clone --recurse-submodules` passes the Linux check with no other setup.
- The Docker image writes into the same checkout as the macOS build, so the
  Linux binary is `bodies_linux.bin`.

Not in this milestone: web. The pinned Roc nightly has a `wasm32` target, but
Odin's JavaScript target and sokol's Emscripten path are separate work.

Not in this milestone: CI and a published platform bundle. Both are alpha
work. See "Beside the milestones".

## Milestone 2: the platform stops naming the game

Done when `platform/main.roc` is the header in `docs/DESIGN.md` section 4 and
`examples/cards` and `examples/entity-game` link and run against it on three
targets.

Decisions for this milestone, agreed 2026-09-24. `docs/DESIGN.md` records the
ones that change the design.

- The vocabulary is `Config`, `Input` and `Scene` in `docs/DESIGN.md` section
  3. `Scene` carries a `camera` record with `eye`, `target` and `fov_y`, not a
  `camera_target`.
- The engine demo goes: the fixed `SCENE` array, the spin, the probes, the `C`
  pipeline toggle and the `SPACE` pause. The `Scene` from `view` is the only
  source of draws.
- `ESC` quits. The host filters no key out of `held` or `pressed`. Quit and
  cursor mode stay host policy until the first command arrives.
- `ROCCO_SEED` gives `Config.seed`. The default is 0.
- `ROCCO_DEBUG_CAMERA=1` turns on the fly camera and the mouse lock. Then the
  host ignores `Scene.camera`. The game still gets all input.
- Every mesh id draws as the cube, with the draw's scale. The fallback colour
  arrives in milestone 3. `tint` is a fragment shader uniform.
- Hot reload keeps working when the `Model` type does not change.

Steps, in order. Each step ends with something that runs.

1. Audit the glue. Run the `glue/` spec against the new header and add every
   type it rejects: `U32` first, then `Str`, `Box` as `rawptr` and
   `List(U16)`. Add the refcount helpers the host needs:
   `Roc_Str.from_slice` and `decref`, list `decref` for flat lists and for
   lists of records that hold a `Str`, one `decref` per struct, and
   `incref_box`. Add the platform as a second glue example with a committed
   expected file. Compare its sizes and offsets with the Zig glue output.
2. Write the camera package in `packages/camera/`: a nominal `Camera` type
   with `View`, `look_at` and `follow`. It does not depend on the platform.
   Games import it as `import cam.Camera as Cam`.
3. Link `examples/cards` end to end. Write the new `platform/main.roc`, the
   `drop_model_for_host` export, the call protocol in `docs/DESIGN.md`
   section 5, `Config` from the glue helpers, the input latch for `pressed`,
   and the camera from `Scene.camera` without interpolation. Delete the
   engine demo. Call `view` once after `init`, so the first frame has a
   `Scene`.
4. Write the host side of `Scene`: keep two, pair draws by id, interpolate,
   write one model matrix per draw. Then link `examples/entity-game` with
   `held` and the mouse delta.
5. Add `ROCCO_ALLOC_REPORT=1` and `scripts/alloc-check.sh`. The report prints
   allocs, deallocs, reallocs, live blocks, and step and view time for each
   fixed step.
6. Update `scripts/build.roc` so `all` builds both games. Point
   `scripts/linux/check.sh` at `cards`. Delete `examples/bodies` and
   `docs/examples/`. Point the evidence line in `docs/DESIGN.md` section 4
   and the README at `examples/`. Add a check that the host library does not
   rebuild between the two games.
7. Check `x64win` by hand with both games.

The input latch: a key down event adds the key to a pending set. The first
fixed step of a frame takes the pending set as `pressed` and takes the mouse
delta of the frame. Later steps in the same frame get an empty `pressed` and a
zero delta. `held` is the key state when the step runs.

Pairing: the host builds a map from draw id to index once per fixed step. The
map lives in permanent memory and keeps its capacity. If two draws share an
id, the first wins and the host logs the id once. `pos`, `scale` and the
camera `eye` and `target` interpolate linearly. `yaw` takes the shortest arc.
`tint` and `fov_y` take the new value.

The `drop_model_for_host` export frees the `Box(Model)` at shutdown, because
the host cannot know the payload layout. roc-ray does the same. Roc issue
9536 is closed, but the glue at `nightly-2026-09-12-220fd47` still emits only
generic box helpers. Remove the export when the glue can drop the payload.

Check:

- `scripts/alloc-check.sh` runs each game with `ROCCO_EXIT_AFTER_FRAMES` and
  no input. It skips the first 10 steps. Each later step must show 2 allocs,
  2 deallocs, 0 reallocs and a constant live block count. It runs under
  `--opt=dev` and `--opt=speed`. It reads exit codes, not text: `roc test`
  prints "All tests passed" and exits 1 when `roc check` fails.
- A change to either game's `Model` does not touch `engine/` and does not
  rebuild the host library.
- Both games pass on `arm64mac` and `x64glibc` in every session and on
  `x64win` once, by hand.
- Hot reload keeps the state on macOS when the `Model` type is unchanged.

## Milestone 3: mesh handles and the manifest

Done when `Scene` draws by id resolve to more than one mesh.

1. Give the renderer a mesh table indexed by id. Load the three primitives
   into it at startup. Reserve id 0 for a magenta fallback cube.
2. Publish the table to `init` as the manifest.
3. Draw every entry in a `Scene` with its own mesh and transform.

Check: the entity game shows a cube player, sphere pickups and a slab door.
A misspelt mesh name draws magenta and logs once.

## Milestone 4: geometry from disk

Done when a Blender export appears in the manifest without an engine change.

1. Pick one format. glTF binary is the default choice. Load positions,
   normals and indices only.
2. Load every file in `assets/meshes/` into the level arena at startup. This
   is the first caller of the level arena.
3. Add each file to the manifest under its file stem.

Check: drop a new `.glb` into the directory, restart, name it from Roc, see
it. No rebuild of the host library.

## Milestone 5: entities in Roc

Done when the entity game creates and destroys entities at runtime.

Milestone 2 deleted the fixed scene array. The `Scene` from `view` is already
the only source of draws.

1. Entities live in the game's `Model` as a `List(Entity)` with explicit ids.
2. Parenting is a `parent : U64` field and a fold over the list. No pointer
   tree.

Check: the entity game creates and destroys entities at runtime. The renderer
never allocates per frame.

## Milestone 6: collision as data

Done when contacts cross the seam as a list.

1. The host computes swept AABB contacts from the current `Scene` bounds or
   from a `List(Collider)` the game returns in `Scene`. Decide which by
   measuring which is smaller at 1,000 entities.
2. `step` gains a third argument: `List(Contact)`. Update `Input` or add the
   list to it. This is a vocabulary change and rebuilds the host library.
3. The game decides what a contact means. The engine never does.

Check: the player stops at the door while it is closed.

## Milestone 7: one gameplay verb

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
- **Commands.** When the first command arrives, quit becomes a command and
  cursor mode becomes a field in `Scene`. Until then, `ESC` quits and the
  host sets the cursor.
- **Shader loading and reload.** The shader is a `sokol-shdc` output.
  Reload means re-running the compiler and swapping the pipeline; the
  platform files decide how each OS watches the file.
- **The allocation pool.** A fixed region reserved once at startup with a
  free list behind `roc_alloc` and `roc_dealloc`. Removes the system heap
  from the step path. Satisfies static allocation. Measure before and after
  with the tracking allocator.
- **Debug and speed parity.** Run the allocator counters under both
  `--opt=dev` and `--opt=speed` after every memory change.

Alpha work, once the experiment earns it and not before milestone 2 is done:

- **CI.** GitHub Actions with one runner per OS. Roc refuses `x64glibc` from
  a machine that does not run Linux, and `x64win` needs a Windows SDK. So no
  single runner builds all three. Each job runs the build script for its
  runner OS, runs `examples/bodies` under a virtual display with
  `ROCCO_EXIT_AFTER_FRAMES`, and runs `roc check` and `roc test` on every
  app under `examples/`. The Linux job reuses
  `scripts/linux/Dockerfile`.
- **A published platform bundle.** `roc bundle` into a release asset holding
  every target directory with prebuilt host libraries, as roc-ray does. A
  game header points at the URL and the author runs `roc main.roc` with
  nothing but Roc installed. Needs committable Linux inputs: checked-in CRT
  objects and assembly stubs for libc, libm and the X11 libraries instead of
  copies from a container. Windows import libraries can come from MinGW
  `.def` files through `zig dlltool`, so no SDK at bundle time.

## Out of scope

- A Vulkan or Metal backend by hand. sokol is the floor.
- Networking.
- An editor.
- Dynamics beyond simple collision until milestone 4 is done.
- Web builds until Odin and sokol have a shared web path.
- CI and a published platform bundle until alpha.
- A scripting API where Roc calls the engine. Roc returns descriptions. The
  engine acts on them.
