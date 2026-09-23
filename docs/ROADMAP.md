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
- The generated Odin ABI comes from `roc glue` with the spec in the
  `glue/` submodule (roc-odin-glue).

Not built: the generic platform in `docs/DESIGN.md`. The current
`platform/main.roc` names a concrete `Body` record. It is the last
game-specific header.

macOS only, today. Three things pin it there: the vertex and fragment shader
is a Metal Shading Language string in `render.odin`; the link inputs are the
Metal debug archives; and the sysroot script reads the Xcode SDK. Everything
else already goes through sokol, which has GL, D3D11 and Metal backends.

## Milestone 1: one source tree, three desktop targets

Cross-platform comes first, while the engine is small. Every line written
after this milestone lands in a file that already has a home per platform.
Doing it later means porting the host code that milestones 2 to 4 add.

Done when `examples/bodies` builds and runs on three hosts from one checkout,
with one host library per target:

- macOS arm64, natively, target `arm64mac`.
- Linux x64, inside the committed Docker image, target `x64glibc`, under
  `xvfb-run` with software GL and `ROCCO_EXIT_AFTER_FRAMES` set. Pass is exit
  code 0 and one printed frame count line.
- Windows x64, by hand on a Windows machine with Visual Studio Build Tools and
  a Windows SDK, target `x64win`.

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
  this milestone does not build the chooser.
- Shaders are compiled from one source to every backend at build time.
  sokol ships `sokol-shdc`, which emits an Odin file with MSL, GLSL and HLSL
  from one `.glsl` source. The generated file is committed. shdc is a
  dev-only tool.

What the Roc linker needs, found before the work started:

- A `targets:` input is only ever a file in `targets/<target>/`. There is no
  library-name syntax. Roc links with `-nostdlib`, so the platform lists
  every CRT object and library as a file, and the validator rejects
  undeclared files in that directory. Each OS gets a script that populates
  its directory. The macOS sysroot script is one of them.
- `x64glibc` refuses to link from a non-Linux host. `x64musl` cross-links
  from macOS but forces `-static`, and sokol needs shared X11 and GL. So the
  Linux binary is linked on a Linux host, in Docker.
- `x64win` needs a Windows SDK on the host. sokol's own Windows script needs
  `cl`. So the Windows binary is linked on Windows.
- No cross-compiling from one machine, then. Each host builds its own target.

1. Linux link spike in Docker. Write `scripts/linux/Dockerfile` with the
   pinned Odin and Roc Linux releases, the X11 and GL headers, Mesa and xvfb.
   Build the sokol `SOKOL_GLCORE` archives and the host library inside it.
   Copy the CRT objects and the shared libraries sokol needs into
   `platform/targets/x64glibc/`. Add the `x64glibc` entry to
   `platform/main.roc`. Link `examples/bodies` and see the process start. The
   shader fails on GL at this point, and that is expected. This step gates
   every other step. If it has no answer, stop and redesign.
2. Replace the MSL string with `sokol-shdc` output. Source in
   `engine/shaders/basic.glsl`, generated `engine/shader_basic.odin` with the
   command that made it in a comment at the top.
3. Add `engine/platform_darwin.odin`, `platform_linux.odin` and
   `platform_windows.odin`.
4. Write `scripts/build.roc` on basic-cli with the commands `inputs`, `glue`,
   `host`, `game <example>`, `shaders` and `all`. The target defaults to the
   host. A game author runs only `inputs` and `game`. Add the Windows input
   command that copies the SDK import libraries into
   `platform/targets/x64win/`. If Roc scripting blocks the milestone, fall
   back to a shell script.
5. Read `ROCCO_EXIT_AFTER_FRAMES` once at startup in the host. Set means quit
   cleanly after that many frames and print the count. Unset means run
   forever.
6. Run `examples/bodies` on Linux in Docker under `xvfb-run` with the exit
   switch. One wrapper command on the Mac builds the image and runs the check.
7. Build and run `examples/bodies` on Windows by hand. Add the `x64win` entry
   to `platform/main.roc`. Record the input list and the components installed.
8. Rewrite this section and the README with the results.

Steps 2 to 5 run in parallel after step 1. Step 6 needs all of them.

Check: three binaries from one tree. `git grep "when ODIN_OS"` returns only
the platform files. `git grep "SOKOL_METAL\|MTL"` returns nothing outside
`platform_darwin.odin` and the generated shader file.

Not in this milestone: web. The pinned Roc nightly has a `wasm32` target, but
Odin's JavaScript target and sokol's Emscripten path are separate work. Web
stays out of scope until the three desktop targets build from one tree.

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
   `roc build`. `libhost.a` must not rebuild between them.

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
it. No rebuild of `libhost.a`.

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
   list to it. This is a vocabulary change and rebuilds `libhost.a`.
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
- **Shader loading and reload.** After milestone 1 the shader is a
  `sokol-shdc` output. Reload means re-running the compiler and swapping the
  pipeline; the platform files decide how each OS watches the file.
- **The allocation pool.** A fixed region reserved once at startup with a
  free list behind `roc_alloc` and `roc_dealloc`. Removes the system heap
  from the step path. Satisfies static allocation. Measure before and after
  with the tracking allocator.
- **Debug and speed parity.** Run the allocator counters under both
  `--opt=dev` and `--opt=speed` after every memory change.

Alpha work, once the experiment earns it and not before milestone 2 is done:

- **CI.** GitHub Actions with one runner per OS. Roc refuses `x64glibc` from
  a non-Linux host and `x64win` needs a Windows SDK, so no single runner
  builds all three. Each job runs the build script for its host, runs
  `examples/bodies` under a virtual display with `ROCCO_EXIT_AFTER_FRAMES`,
  and runs `roc check` and `roc test` on every app under `examples/` and
  `docs/examples/`. The Linux job reuses `scripts/linux/Dockerfile`.
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
- Web builds until the three desktop targets build from one tree and Odin
  and sokol have a shared web path.
- CI and a published platform bundle until alpha.
- A scripting API where Roc calls the engine. Roc returns descriptions. The
  engine acts on them.
