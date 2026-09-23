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
game-specific header.

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

Done when `platform/main.roc` is the header in `docs/DESIGN.md` section
4 and both games in `docs/examples/` link and run against it.

1. Extend the glue spec in the `glue/` submodule with `Str`, `Box` as
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
6. Move the two games from `docs/examples/` to `examples/entity-game/` and
   `examples/cards/`, pointing at `../../platform/main.roc`. Build each with
   `roc build`. The host library must not rebuild between them.

Expect a `drop_model_for_host` export that frees the `Box(Model)` at shutdown
until `roc glue` emits box refcount helpers (roc issue 9536). roc-ray does the
same, and its `update_for_host!` unboxes the only reference so `update!` sees
uniquely referenced lists. That matches `docs/DESIGN.md` section 5.

Check: the allocator counters show in-place mutation. A change to either
game's `Model` does not touch `engine/`.

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

Done when the engine has no fixed scene array.

1. Delete the fixed `scene` array from the engine. The `Scene` from `view`
   is the only source of draws.
2. Entities live in the game's `Model` as a `List(Entity)` with explicit ids.
3. Parenting is a `parent : U64` field and a fold over the list. No pointer
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
  app under `examples/` and `docs/examples/`. The Linux job reuses
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
