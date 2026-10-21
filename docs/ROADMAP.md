# rocco roadmap

Engineering milestones. Each milestone names what exists when it is done and
how to check it. Order matters: each one unlocks the next. `docs/DESIGN.md`
governs every entry here. If a milestone needs the design to change, change
the design first.

## Where the engine stands

Built and running:

- Fixed-timestep loop with an accumulator and interpolation.
- Two arenas by lifetime: permanent and frame. Each loaded mesh lives on
  the heap from the first Pack that names it to the unload of the last one.
- Rendering through sokol: one mesh pipeline, a mesh table, index buffers,
  back-face culling, reversed-Z depth, PBR shading from `Scene.lights`, a
  shadow map from one sun, a cubemap sky and an ACES tone map. The backend
  is Metal on macOS, GL core on Linux and D3D11 on Windows. One shader
  source in `engine/shaders/basic.glsl` compiles to all three with
  `sokol-shdc`.
- The generic platform in `docs/DESIGN.md`. `platform/main.roc` names no
  game. The host holds the `Model` as one boxed pointer. The Seam keeps the
  two `Scene`s. The Frame render pairs draws by id and interpolates them at
  the Alpha.
- The mesh table holds the magenta fallback mesh at id 0 and the cube,
  sphere and plane primitives, named `primitive/<name>`. A game loads the
  `.glb` files, textures and skies in `assets/` as Packs with `Load` and
  `Unload`. `loaded` gives the game each Pack's Manifest. `ROCCO_ASSETS`
  replaces the `assets` path. Each draw names its mesh by id, and an unknown
  id draws the fallback mesh.
- The game defines five calls: `launch`, `init`, `step`, `loaded` and
  `view`. `launch` sets the window, the step rate, the shadow map size and
  the table capacities before the window opens.
- `Scene.ui` carries a HUD that Clay lays out in the host.
- `Scene.queries` asks for Raycasts, Overlaps and ContactsOf. The answers
  come back in the next step's `QueryResults`.
- Games import the seam types from `pf.Vocabulary` and name keys with
  `pf.Key`, which `scripts/build.roc` generates from sokol.
- The game gives colliders in `Scene.colliders`. The host finds the
  contacts and passes them to the next `step` as `List(Contact)`.
  The game decides what each contact means.
- The entity game is playable start to finish: jump, collect the pickups,
  pass the door, win on the goal pad and start a new round. Two strangers
  finished it with no instructions.
- Kula is playable start to finish: roll, climb, edge rolls, jump,
  keys, the exit, falling and the restart, on three textured levels with a
  keys HUD. Kula lives in `Pixelsprout/kula` and runs from the v0.1.0
  bundle URLs.
- Each draw carries `rot`, a quaternion. The camera carries `up`.
- The camera comes from `Scene.camera`. `ROCCO_DEBUG_CAMERA=1` gives a fly
  camera with mouse look.
- `step` returns a `List(Command)` with the next `Model`. The host runs each
  command after `step` and before `view`. The commands are `Quit`, `Load`
  and `Unload`. The host binds no key; the entity game binds `Escape` to
  `Quit`. The mouse lock comes from `Scene.cursor`, apart from the debug
  camera.
- The engine links as one host library per target into a Roc platform. The
  game manages its state. The host honours `roc_dealloc`. The game calls sit
  behind a struct of procedures, with a fake game in the Odin tests, so the
  call protocol has a test without a Roc app. Hot reload works under
  `roc run` on macOS when the `Model` type does not change.
- The generated Odin ABI and its refcount helpers come from `roc glue` with
  the spec in the `glue/` submodule (roc-odin-glue).
- `examples/cards`, `examples/entity-game` and `examples/pong` build and
  run from one checkout on `arm64mac`, `x64glibc` and `x64win`. CI runs
  them on all three for every push to main and every pull request.
  `scripts/build.roc` runs every step.
  `ROCCO_EXIT_AFTER_FRAMES` makes a run end cleanly for checks.
  `scripts/alloc-check.sh` and `scripts/host-check.sh` check the seam.
- A `v*` tag publishes the platform, `linalg`, `mesh` and `ui` as Roc
  bundles. v0.1.0 is the only release.
- `ROCCO_HEADLESS` and `ROCCO_LOCKSTEP` give a fixed workload per run. The
  bench games in `bench/` measure the cost of each Span. `docs/BENCHMARKS.md`
  gives the method.

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

## Milestone 2: the platform stops naming the game (done)

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
  cursor mode stay host policy until the first command arrives. Milestone 9
  moved both to the game, apart from the debug camera.
- `ROCCO_SEED` gives `Config.seed`. The default is 0.
- `ROCCO_DEBUG_CAMERA=1` turns on the fly camera and the mouse lock. Then the
  host ignores `Scene.camera`. The game still gets all input.
- Every mesh id draws as the cube, with the draw's scale. The fallback colour
  arrives in milestone 3. `tint` is an `Rgb` and a fragment shader uniform.
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

Pairing: the Frame render builds a map from draw id to index once per frame,
from the previous Scene. The map lives in permanent memory and keeps its
capacity. If two draws share an id, the first wins and the Frame render logs
the id once. `pos`, `scale` and the camera `eye` and `target` interpolate
linearly. `yaw` takes the shortest arc. `tint` and `fov_y` take the new value.

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

Results, 2026-09-25:

| Host | Target | How it was checked | Result |
|---|---|---|---|
| macOS arm64 | `arm64mac` | Both games with `ROCCO_EXIT_AFTER_FRAMES=120`, `scripts/alloc-check.sh`, `scripts/host-check.sh`, hot reload by hand | Pass. 2 allocs, 2 deallocs, 0 reallocs per step. No Roc block left at shutdown. |
| Linux x64 | `x64glibc` | `./scripts/linux/check.sh`: both games, the alloc check and the host check in the Docker image | Pass, in about 50 seconds with the image built |
| Windows x64 | `x64win` | By hand: both games, then a look at the picture | Both games run and draw correctly |
| Arch Linux x64 desktop | `x64glibc` | By hand on Omarchy, Hyprland through XWayland: `build all`, then the game | Builds and runs. System libraries come from `/usr/lib`. |

What the work found:

- The glue pointer in a pushed rocco commit must be on the glue remote. A
  Windows clone could not fetch an unpushed glue commit, and an agent then
  rebuilt the glue from an old version. Push the glue first, and check it
  with `git branch -r --contains <sha>`.
- `roc build` defaults to `--opt=speed`. Only `roc run` uses the dev backend.
  Under dev, `List.map` copies the list. See `docs/DESIGN.md` section 10.
- Git for Windows checks files out with CRLF. `.gitattributes` keeps the
  generated files at LF, so a regenerated file matches the committed one.
- The Windows build links the sokol debug libraries. They ask D3D11 for its
  debug layer. Without the Windows Graphics Tools feature, sokol logs
  `WIN32_D3D11_CREATE_DEVICE_AND_SWAPCHAIN_WITH_DEBUG_FAILED` and retries
  without it. The game then runs normally.

## Milestone 3: mesh handles and the manifest (done)

Done when `Scene` draws by id resolve to more than one mesh.

1. Give the renderer a mesh table indexed by id. Load the three primitives
   into it at startup. Reserve id 0 for a magenta fallback cube.
2. Publish the table to `init` as the manifest.
3. Draw every entry in a `Scene` with its own mesh and transform.

Check: the entity game shows a cube player, sphere pickups, a plane floor and
a cube door. A misspelt mesh name draws magenta and logs once.

## Milestone 4: geometry from disk (done)

Results, 2026-09-29: the entity game draws `sprout.glb` from
`examples/entity-game/assets/meshes/` with no host library rebuild. The
Odin tests, the Roc tests, `scripts/alloc-check.sh` and `scripts/host-check.sh`
pass on `arm64mac`. `scripts/linux/check.sh` passes on `x64glibc`. `x64win`
was not checked.

Done when a Blender export appears in the manifest without an engine change.

1. Pick one format. glTF binary is the default choice. Load positions,
   normals and indices only.
2. Load every file in `assets/meshes/` into the level arena at startup. This
   is the first caller of the level arena.
3. Add each file to the manifest under its file stem.

Check: drop a new `.glb` into the directory, restart, name it from Roc, see
it. No rebuild of the host library.

Decisions for this milestone, agreed 2026-09-29. `docs/DESIGN.md` records the
ones that change the design.

- The engine accepts `.glb` only. The parser is Odin: the GLB header, the JSON
  chunk through `core:encoding/json`, the BIN chunk and the accessors. It does
  not use `vendor:cgltf`, because that adds link inputs on three targets.
- The engine loads positions, normals, indices and the
  `pbrMetallicRoughness.baseColorFactor` of each primitive's material. That
  colour goes into the vertex `color` of the primitive. A primitive with no
  material is grey 0.8. The shader multiplies the vertex colour by `tint`.
- Index accessors can be `u8`, `u16` or `u32`. The engine converts them to
  `u16`. A mesh with more than 65,535 vertices is rejected.
- One file is one mesh. The engine merges every triangle primitive of every
  mesh node and bakes each node's world transform into the positions and
  normals. A primitive whose mode is not triangles is rejected.
- The engine does not flip winding. The pipeline is `face_winding = .CCW`,
  the same as glTF.
- The engine scans `assets/meshes/` in the directory of `argv[0]`. `roc run`
  sets `argv[0]` to the game's `main.roc`, so the game finds its assets from
  any working directory. The `ROCCO_ASSETS` environment variable replaces the
  `assets` path. Changed on 2026-09-29 from "relative to the working
  directory", because `roc run` from the repo root drew the fallback.
- The scan reads the top level only, in sorted order, so ids are stable
  across runs. Names are case-sensitive.
- File bytes go into the frame arena. Names and the decoded vertex and index
  slices go into the level arena.
- A file that fails is skipped with one log line that gives the reason. The
  reasons are a bad file, no normals, too many vertices and a full table at
  `MESH_CAPACITY` (64). The engine does not exit. The name then resolves to
  the fallback mesh.
- The primitives go into the manifest as `primitive/fallback`,
  `primitive/cube`, `primitive/sphere` and `primitive/plane`. Files go in
  under the bare stem. A file stem cannot contain `/`, so the two never
  collide. `primitive_name` in `packages/mesh/` changes. The vocabulary
  and the glue do not change.
- Parser tests build GLB bytes in Odin test code. There are no committed
  fixtures.
- The checks find each game's assets with no `ROCCO_ASSETS`.
- The mesh id generation moves out of this milestone. It must land before
  the first caller of `level_unload`.
- The entity game draws the player with `Mesh.resolve(config, "sprout")` and
  tint `(1, 1, 1)`. `step` turns the player to face its velocity and keeps
  the last yaw when it stops. Until `sprout.glb` exists, the player draws
  magenta.
- Colours and tints are linear, like glTF. The fragment shader lights in
  linear and encodes the result to sRGB, because the swapchain is not sRGB on
  every backend. The game tints were converted once to keep their look.
  Agreed 2026-09-29, after the sprout drew redder than in Blender.
- No ADR.

### The sprout asset contract

The model is a 3D version of the pixel-art "pixelsprout" character: an orange
flower pot with a cute face, green leaves on top, small arms and feet. Smooth
low-poly style.

- File: `examples/entity-game/assets/meshes/sprout.glb`, exported from
  Blender as glTF Binary with the default "+Y Up".
- Origin at the bottom centre, between the feet. It stands on `y = 0`.
- About 1 unit tall.
- Front faces glTF +Z (Blender -Y).
- Triangles, or triangulated on export.
- No textures, UVs, vertex colours, armatures or animations.
- One material per colour, flat Base Color: orange pot, dark soil, green
  leaves, near-black eyes and mouth, pink blush, orange arms and feet.
- Fewer than 65,535 vertices in total. Smooth shading is allowed.
- Node transforms do not need to be applied.

## Milestone 5: entities in Roc (done)

Results, 2026-10-01: the entity game spawns and sweeps water drops at
runtime, with parenting. The Pairing map reserves room for 4096 draws. The
user confirmed a hand run and `scripts/alloc-check.sh`.

Done when the entity game creates and destroys entities at runtime.

Milestone 2 deleted the fixed scene array. The `Scene` from `view` is already
the only source of draws.

1. Entities live in the game's `Model` as a `List(Entity)` with explicit ids.
   The game hands out new ids at runtime.
2. Parenting is a `parent : [Root, Child(U64)]` field and one fold over the
   list. No pointer tree.

Check: the entity game creates and destroys entities at runtime. The renderer
never allocates per frame.

Decisions for this milestone, agreed 2026-09-30. All of it lands in
`examples/entity-game`. The vocabulary, the glue and the host library do not
change, except for the pairing map capacity below.

- No package. Parenting stays in the game until a second game copies it.
- `Model` gains `next_id : U64`. It only grows and an id is never reused.
  `new_game` sets it past the last pickup.
- Scenery ids count down from the top of `U64`, so no counter reaches them.
  The floor moves off `1_000_000`.
- `Entity` gains `parent : [Root, Child(U64)]`. A tag, not a sentinel id.
- Ordering invariant: a parent precedes its child in the entity list. A child
  spawns after its parent and `append` places it later, and `keep_if` keeps
  the order. Depth is unbounded and a cycle cannot exist. This is the flat
  array of Bitsquid and Our Machinery, where a parent index is always lower
  than its child's. The one way to break it is to reparent an entity to a
  younger one.
- An entity stores `pos` and `yaw` local to its parent. `view` composes the
  world values inside the one fold that builds `draws`. A child finds its
  parent's Draw in the accumulator by id, so a child of the door lifts with
  the slab. World pos is parent pos plus the local pos rotated about y by the
  parent yaw. World yaw is the sum. Scale is not inherited.
- A child whose parent is missing, or later in the list, draws at its local
  values and `dbg` logs its id once per run. A test covers it.
- Sweep is one fold over the same order. An entity is dropped if it is dead
  or its parent was dropped earlier in the same pass.
- Collecting a pickup spawns 6 water drops as children of the player, kind
  `Drop({ age : F32, phase : F32, delay : F32 })`. The player is a plant, so
  the drops water it. Each drop waits for its own delay, up to 0.45 seconds,
  and is not drawn until then. It then starts on a ring of radius 0.35 at
  height 1.6, spread by phase. It falls with the square of its age and draws
  in to land on the soil, at radius 0.1 and height 0.52. Sphere mesh, scale 0.07 by 0.1, blue
  tint in linear. An `expire` stage marks a drop dead 1 second after its
  delay ends and sweep drops it. Changed from orbiting sparks on 2026-10-01.
- Pickups become cubes at scale 0.4 so the spin shows. Drops are the
  spheres.
- Roc tests prove spawn, expiry, id growth, composition, the sweep cascade
  and the missing-parent case. A hand run confirms it on screen.
- `scripts/alloc-check.sh` does not change. Spawn happens only on input, so
  the no-input run keeps 2 allocs and 2 frees per step.
- The host reserves the pairing map for 4096 draws at init and logs once if
  a Scene exceeds it. "Never allocates per frame" then holds by construction
  up to that count.
- The `Model` type changes, so a hot reload across this change loses state.
  That is the documented limit from milestone 2.
- Two follow-ups are in `docs/NOTES.md`: a scripted input switch for the
  alloc check, and a host allocation count on the report line.
- No ADR.

## Milestone 6: collision as data (done)

Results, 2026-10-08: the player stops at the closed door and walks under it
once it lifts. A contact collects a pickup. The game reads the contacts in
its `block` and `collect` stages. The Odin tests, the Roc tests,
`scripts/alloc-check.sh` and `scripts/host-check.sh` pass on `arm64mac`.
`scripts/linux/check.sh` passes on `x64glibc`. Nobody checked `x64win`.

Done when contacts cross the seam as a list.

1. `Scene` gains `colliders : List(Collider)`. The host finds the overlapping
   pairs with a broadphase and a narrowphase per shape pair.
2. `step` gains a third argument: `List(Contact)`. This is a vocabulary
   change and rebuilds the host library.
3. The game decides what a contact means. The engine never does.

Check: the player stops at the door while it is closed and walks under it
once it lifts.

Decisions for this milestone, agreed 2026-10-07. The ones that change the
seam go into `docs/DESIGN.md` sections 1, 2, 3 and 9 when the vocabulary
task lands.

- Colliders come from the game, not from Draw bounds. Opting in is the
  filter: the floor and the water drops have none. The render shape is not
  the collision shape. Decided by reasoning, not by the measurement the old
  text asked for. An Odin test times the host at 1,000 colliders and the
  number goes into `docs/DESIGN.md` section 10.
- `Collider : { id : U64, kind : U8, pos : Vec3, yaw : F32, extent : Vec3 }`.
  Kind 0 is a box: `extent` is the half extents and `yaw` turns it in the
  ground plane. Kind 1 is a sphere: `extent.x` is the radius. Kind 2 is a
  capsule, reserved: `extent.x` is the radius and `extent.y` the half height
  of the segment. A kind number because the Odin glue has no tag unions yet.
  A new shape is a host branch, not a vocabulary change. The host logs an
  unknown kind once per run and skips it.
- `pf.Collider` names the kinds and builds the records, as `pf.Key` names
  key codes. Games never write a kind number.
- `Contact : { a : U64, b : U64, normal : Vec3, depth : F32 }`. `a < b`.
  `normal` points from a to b on the least-overlap axis and `depth` is the
  overlap on it. One contact per pair, sorted by `(a, b)`, so a replay gets
  the same list.
- `step : Model, Input, List(Contact), F32 -> Model`. The bare list, not a
  record. `Input` stays what the person did. cards ignores the argument. The
  platform header and both games change.
- The host tests overlap, not sweep. Contacts for Scene n reach step n + 1,
  after the move, so a time of impact would describe the past. The normal
  and depth fix the current state. Swept replaces overlap the first time a
  speed per step exceeds a thickness. At 120 Hz the player moves 0.05 units
  per step and the door is 0.3 thick.
- Broadphase is sweep and prune on x: sort the colliders by their world
  AABB min x on the frame arena each step, then scan. The host derives the
  world AABB from kind, pos, yaw and extent.
- Narrowphase this milestone: box-box by a separating axis test on five axes
  (y and the two ground-plane axes of each box), sphere-sphere, and
  box-sphere. Capsule waits for the first game that slides along walls.
- Duplicate collider ids: the first wins and the host logs once per run, as
  the pairing does.
- The first step gets an empty list. With no input the entity game has no
  overlapping pair, so the contact list allocates nothing.
- Entity game colliders, built in the same `view` fold as the draws so a
  child's world pos and yaw are reused. Player: box, half extents 0.3 by 0.5
  by 0.3, centred 0.5 above its pos, with its yaw. Door: box, 1.5 by 1.5 by
  0.15 at the lifted draw pos, so an open door lifts out of the way.
  Pickups: sphere, radius 0.4. Floor and drops: none.
- A `block` stage runs after `steer` and before `integrate`. For each
  player-door contact it moves the player out by normal times depth and
  removes the velocity component into the normal, so `integrate` cannot push
  back in on the same step.
- `collect` reads player-pickup contacts instead of measuring distance. The
  same Contact is a stop in one branch and a score in another.
- `scripts/alloc-check.sh` takes expected counts per game: cards 2,
  entity-game 3. The third is the colliders list.
- Roc tests cover `block`, `collect` by contact, and the collider list. Odin
  tests cover each pair test, the broadphase, the sort order, the duplicate
  log and the unknown kind.
- `x64win` is checked by hand or recorded as not checked.
- No ADR.

## Milestone 7: one gameplay verb (done)

Results, 2026-10-11: two strangers played the entity game with no words
from the author, and both finished. The player jumps onto the block for the
eighth pickup, walks under the open door and wins on the goal pad. The
camera circles the player in the rain, and a new round starts after 4
seconds. Neither tester had a problem with the air jump after a walk off the
block or with the camera cuts at the win and the restart. The Roc tests,
the Odin tests, `scripts/alloc-check.sh` and `scripts/host-check.sh` pass on
`arm64mac`. `scripts/linux/check.sh` passes on `x64glibc`. Nobody checked
`x64win`.

Done when the entity game is playable start to finish.

1. Add one verb as a stage in the `step` pipeline with a test.
2. Add a win state to the `Model` and a `Scene` that shows it.

Check: a stranger plays it without instructions.

Decisions for this milestone, agreed 2026-10-11. All of it lands in
`examples/entity-game`. The vocabulary, the glue, the host library and the
assets do not change. The game is a demo a stranger can finish, not a game.

- The verb is jump, on Space pressed. Jump speed 7, gravity 20, so the apex
  is about 1.2 units. A `gravity` stage pulls the player down. The floor is
  y 0 for the player and has no collider. Space is the key a stranger tries
  first, and this is the first use of `pressed` and of the y axis.
- `Player({ grounded : Bool })`. Grounded is set at y 0 or on a contact with
  a +y normal, and cleared by a jump. No double jump. Stored, not derived,
  because contacts arrive one step late and a derived flag would flicker
  for one step after a landing.
- `solid` is derived from kind. Door and Block are solid. Pickup and Goal
  are triggers. The `block` stage pushes the player out of every solid
  contact, so a landing from above is the same push-out with a +y normal.
- The level: seven pickups on an arc of radius 4 across the front half, from
  the player's left to right, so all are in view at start. A 1 by 1 by 1
  block at x -4.5, z -4 with the eighth pickup on top, so the door only
  opens after a jump. The door stays at z -8. A goal pad behind it: a flat
  cube 2 by 0.1 by 1.5 at y 0.05 and z -9.2, bright tint, with a matching
  box collider. A plane would z-fight the floor.
- A player-goal contact sets the win. `Model` gains
  `phase : [Playing, Won(F32)]`, the number being seconds since the win.
- While Won: `steer` and jump ignore input. A `celebrate` stage spawns one
  drop onto the player every 0.08 seconds, with its phase taken from the
  step count. `view` orbits the camera round the player at radius 6, height
  3, 0.8 radians per second, with the camera package's look-at.
- At 4 seconds `new_game` runs again with the current `next_id`, so every
  fresh entity has a new id and the host pairs nothing across the restart.
  The player is found by kind, not by id.
- Roc tests: jump rises and lands, no double jump, landing on the block
  through a +y contact, a goal contact sets Won, Won ignores input, restart
  after 4 seconds with fresh ids, and rain while Won.
- `scripts/alloc-check.sh` does not change. No input means no jump, no
  contact and no win.
- The stranger check: at least two people who have not seen the game, with
  no words from the author. The results line records how many finished.
- The `Model` type changes, so a hot reload across this change loses state.
- The one-step contact latency is a consequence of the design and the
  industry norm, not a flaw. If a game ever needs same-step resolution, the
  escape is a `settle` call. See `docs/NOTES.md`.
- No ADR.

## The second arc: a Kula World clone

Agreed 2026-10-11. Milestones 3 to 7 were pulled by the entity game. The
second arc is pulled by a clone of Kula World: a ball rolls on blocks that
float in a sky, gravity is relative to the surface the ball is on and flips
when it rolls over an edge, the ball jumps one block, keys open the exit.
The minimum is three levels and a HUD that shows the keys collected. Fruit, the
time limit, bonus levels and sound come after.

The clone starts in this repo under `games/kula/` on the local platform. It
moves to its own repo on the published bundle URL as the last milestone, so
it is the bundle's first consumer. Kula now lives in `Pixelsprout/kula`
on the v0.1.0 bundle URLs. Levels are ASCII layer maps in `.txt`
files, embedded at compile time with Roc's file import and parsed by a
tested `Level` module. The game is laid out by concern: `main.roc` holds
the two pipelines, `World` the types, and `Level`, `Grid`, `Ball`, `Rules`,
`View` and `Hud` one concern each, imports pointing downward only. Tests are
inline `expect`s and `roc test main.roc` runs them all. The entity game
stays one file and stays the alloc-check subject.

Each milestone gets its own grilling before implementation. The entries
below are the roadmap, not the designs.

Decisions that span the arc:

- Forward rendering stays, with a light cap of 8. No deferred pass. A
  directional shadow map from the sun is the first upgrade that changes
  the look, in Milestone 13.
- The Kula look keeps the original's feel and draws it with modern
  lighting. `games/kula/SPEC.md` states each choice.
- Textures come with the mesh through glTF materials. Draw does not gain a
  texture id.
- Tag unions cross the seam once the glue emits them. No new kind numbers.
- A game never asks the engine for a file. Compile-time file import is not
  asking.
- Second copies become packages: `packages/linalg` with Vec3 and Quat
  at milestone 10, the entity store package at the first copy of
  `map_entities`.

## Milestone 8: tag unions in the glue (done)

Results, 2026-10-11: `Collider.shape` crosses the seam as a tag union that
the Odin glue emits. Both games draw with 4x MSAA.

Done when a tag union crosses the seam and both games draw with 4 samples.

1. Extend the Odin glue in `glue/` with non-recursive tag unions: a raw
   union payload and the discriminant at its offset, with the Zig glue as
   the reference. Recursive unions stay unimplemented.
2. Make `Collider` a tag union and delete its kind number. `pf.Collider`
   keeps building the records.
3. Set the window and pipeline sample count to 4. sokol resolves the
   multisample surface in end-pass. This is the first host change of the
   arc, so the host rebuilds once for both.

Check: `host-check.sh` shows the glue emitting the union. The entity game
renders with no stair-stepped edges.

## Milestone 9: commands (done)

Results, 2026-10-11: the entity game returns `Quit` from `step` on an
`Escape` press, and `Escape` quits the running game. `cards` returns no
commands and has no quit key. The host binds no key. Roc tests check
`step(...).commands` for an `Escape` press, for idle input and for `Escape`
during the win. The Roc tests, the Odin tests, `scripts/alloc-check.sh` and `scripts/host-check.sh` pass on
`arm64mac`. A step with no commands adds no allocation. Nobody checked
`x64glibc` or `x64win`.

Done when a game quits itself.

1. `step` returns `{ model, commands : List(Command) }`, with `Quit` as
   the only tag. The glue learns single-tag unions and a `Box` inside a
   returned record first.
2. Cursor mode becomes `cursor : [Free, Locked]` in `Scene`. The host
   stops setting it, apart from the debug camera.
3. ESC leaves the host. The game binds it.

Check: ESC still quits the entity game, from Roc. `cards` ignores the list.

## Milestone 10: Kula slice one (done)

Results, 2026-10-13: the user finished `level1` with the keyboard on
`arm64mac`. The route rolls over an edge onto the side of a block and keeps
rolling. Both keys collect, the exit brightens when open, entering it wins,
and a jump into nothing falls and restarts the level. Blocks draw as
`face.glb` and the ball as `ball.glb`, both built by a committed Blender
script. The Roc tests, the Odin tests, `scripts/alloc-check.sh` (cards and
entity-game only) and `scripts/host-check.sh` pass on `arm64mac`. `scripts/linux/check.sh` runs
Kula for 120 frames on `x64glibc` with exit code 0. Nobody checked `x64win`.

Done when the first Kula level is finishable.

1. Draw's `yaw` becomes `rot`, a quaternion. The host interpolates with
   slerp, with the sign check the glossary records. `Collider` keeps `yaw`.
   `Quat` in `packages/linalg` gives `from_yaw`, `mul` and
   `from_axis_angle`. The entity game composes parents with it.
2. `packages/linalg` takes the Vec3 maths both games copy.
3. `games/kula/` on the local platform: a ball rolls on vertex-coloured
   blocks, gravity flips at edges, it jumps, keys open the exit. One level
   from `levels/level1.txt`, parsed by `Level` with tests.

Check: a ball rolls over an edge onto the side of a block and keeps
rolling. The level is finishable with the keyboard.

## Milestone 11: lights as data (done)

Done when all three games (cards, entity-game, kula) light their own scene
and the host has no light of its own.

1. `Scene` gains `lights : List(Light)` with `Ambient(Rgb)`,
   `Directional({ dir, color })` and `Point({ pos, color, range })`. Colour
   carries intensity and can exceed 1. A tint stays 0 to 1. `pf.Light`
   builds each one. `dir` is the way the light travels.
2. The host takes the first ambient and the first 8 directional and point
   lights, in list order, into a new `fs_lights` uniform block. It drops a
   second ambient, a light past the 8th, a Directional with a zero `dir`
   and a Point with a range <= 0. It logs each reason once per run. An
   empty list draws black. Lights do not interpolate. A point light falls
   off as `clamp(1 - (d/range)^2, 0, 1)^2`. Shading stays Lambert diffuse
   only.
3. Each game copies the old lights: a 0.1 grey ambient and a white
   directional light travelling `-(2,3,6)/7`. Kula adds a warm placeholder
   point light near the start, range 6, until the Kula look task chooses
   its lights. Spot lights wait for a game that needs one.

Check: an empty list draws black. A point light falls off with range.

## Milestone 12: packs, textures and PBR (done)

Results, 2026-10-15: the user played Kula through all three levels on
`arm64mac`. Each level draws under its own Theme, with textured faces and a
sky, and the level swap shows no magenta. The Odin tests,
`scripts/host-check.sh`, the build script tests and the Roc tests of every
game pass.

Done when a Pack unloads and the next loads with no stale id drawn, and
Kula plays three textured, sky-lit levels with no magenta. The full spec
is the dex task nc3cv6do.

Before it (done): the shader tone maps with ACES fitted before the sRGB
encode, the host clears to black with the sRGB encode, and each game
retunes its lights. Cards and entity-game raise the ambient to 0.2 and the
directional light to 1.6. Kula lights each level with a sun, a dim fill
opposite it and an ambient, and drops the placeholder point light.

1. Pack term and docs. A Pack is a named set of assets that load and
   unload together. CONTEXT.md and GLOSSARY.md gain Pack. ADR 0003 records
   that packs own asset lifetimes.
2. The seam. `Command` gains `Load({ pack, assets })` and `Unload(pack)`.
   `init` returns commands. A fourth function, `loaded : Model, Str,
   Manifest -> Model`, runs before the next `view`. `Config` lists the
   asset names on disk, with no ids. Cards, entity-game and Kula move to
   it. Only the primitives load at startup.
3. The host tables. Packs are independent. A shared asset loads once and
   is refcounted. The mesh table and a 16-slot sky table reuse slots
   through a free list and the generation (done: jzvojfn9). Done for the
   mesh table: `Unload(pack)`, the free list and per-pack lifetimes
   (7zk6yajs). The sky table comes with the sky (mlhioxmj).
4. Textures and PBR. UVs, the glTF base colour texture and sampler, sRGB
   images and linear-light mipmaps. The loader reads roughness, metallic,
   the metallic-roughness texture and the unlit extension. The shader uses
   GGX, Smith visibility, Schlick Fresnel and Lambert diffuse, with an
   approximate ambient specular. Light colours follow physical units, and
   each game retunes its lights by pi.
5. The sky. `Scene.sky : U32`, 0 meaning none. A cubemap of six PNGs in
   `assets/sky/<name>/`. The sky and unlit meshes skip the lights and the
   tone map. Done (mlhioxmj).
6. Kula. A pack per Theme, three levels, generated textures and skies.
   Finishing level 3 keeps Won. Done (bfn69njy): each Theme pack holds its
   textured face and a sky rendered by Blender. The user checked all three
   levels by eye on 2026-10-15.

Check: finish level one, see level two under a new Theme, with no magenta.

## Milestone 13: shadows (done)

Results, 2026-10-15: the user jumped gaps in Kula on `arm64mac` and saw the
ball's shadow on the landing block. Cards and entity-game draw as before.
The shadow edge is a little soft, and the settings task z851lo4y records
it. The Odin tests and `scripts/host-check.sh` pass. The full spec is the
dex task cxtqbqrl.

Done when the ball casts a shadow on the blocks from the Kula sun.

1. `Directional` gains `shadow : Bool`. `pf.Light.directional` sets
   `False`. `pf.Light.sun` sets `True`. If two lights set it, the host
   uses the first and logs once.
2. The host renders one depth map from the sun over the bounds of the
   Scene's Draws, and the shader samples it with a small PCF filter.
3. Kula's Theme sun casts the shadow. Cards and entity-game do not change.

Check: jump over a gap and see the shadow on the landing block. A Scene
with no sun draws as before.

## Milestone 14: the HUD (done)

Results, 2026-10-15: Kula shows "Keys 0 / 2" in a panel at the top-left.
Screenshots at 960x540 and 1280x800 show the panel in the same corner, and
both show "Keys 0 / 2". A Roc expect shows "Keys 1 / 2" after the ball
collects one key. The Linux container run exits 0. The full spec is the dex
task w0y0eore.

Done when the key count changes on screen without a 3D draw. Grilled
2026-10-15; `docs/adr/0004-ui-layout-runs-in-the-host.md` records the
layout decision.

1. Clay in the host, through its Odin bindings, as a pinned submodule whose
   prebuilt lib the `inputs` step copies beside sokol's. One arena at init,
   no allocation per frame.
2. `Scene` gains `ui : List(Element)`: a flat stream of `Open(Box)`, `Text`
   and `Close`, in the order Clay reads them. A box carries Clay's sizing,
   padding, gap, direction, alignment, an `Rgba` background, a radius and a
   float to the window. Text carries the string, size and colour. The
   `packages/ui/` helpers build the stream from nested code.
3. The host lays out once per frame against the window size and draws
   Clay's render commands as one batch of quads in the Main pass, after the
   sky. It measures text through the callback.
4. One SDF font baked into the host: an atlas and metrics generated from
   Atkinson Hyperlegible by a dev-only Odin tool and committed as an Odin
   file, like `engine/shader_basic.odin`.
5. Kula shows the keys collected.

Check: a box anchored to a corner stays there when the window resizes. The
count reads right at two window sizes.

## Milestone 15: CI and the bundle (done)

Results, 2026-10-16: the v0.1.0 tag published the platform, `linalg`, `mesh`
and `ui` bundles. Kula moved to `Pixelsprout/kula` on those URLs. Kula's CI
passed on clean macOS, Ubuntu and Windows runners with only the pinned Roc
nightly installed.

Done when Kula builds on a clean machine with only Roc installed. Grilled
2026-10-15. The dex task pa2v63ro holds the decisions and the tasks.

1. Pong moves to the current seam and joins `all`. CI here runs cards,
   entity-game and pong. Pong's score, banner and key hints replace Kula
   as the UI test. Entity-game replaces Kula as the test for the sun
   shadow, point lights and the sky.
2. `x64win` links Clay. Windows links with no Visual Studio: sokol, Clay
   and the host build with no default C runtime, and the C runtime comes
   from `ucrtbase.dll`.
3. `platform/main.roc` names the archives without a debug or release
   suffix. `inputs --release` copies the release archives. Local work stays
   debug. CI and the bundle use release.
4. The Linux CRT objects and library stubs, and the MinGW `.def` files for
   the Windows import libraries, are committed with their `.so` and `.lib`
   outputs. CI makes them again, and a diff is the reproducibility check.
5. A reviewed catalog makes the macOS sysroot, as in roc-ray. No file
   taken from Apple's SDK goes in the bundle.
6. Three GitHub Actions runners: macOS arm64, Ubuntu and Windows. Each
   builds the host for its OS, runs the examples with
   `ROCCO_EXIT_AFTER_FRAMES`, and runs `roc check`, `roc test` and
   `odin test`. The Linux job reuses `scripts/linux/Dockerfile` and keeps
   the alloc check and the host check.
7. A release workflow runs on a `v*` tag. It collects the three host
   archives into the target directories and runs `roc bundle` for the
   platform and for `linalg`, `mesh` and `ui`. It publishes a prerelease,
   runs cards from those URLs on clean runners, then makes the release
   final. The release notes name the Roc nightly.
8. Kula moves to `Pixelsprout/kula` with its history. Its header names the
   four bundle URLs. Its README names the Roc nightly. `scripts/local.sh`
   points the header at a local checkout of this repo. `games/` leaves
   this repo.

Check: clone the Kula repo on a machine with Roc and nothing else, run
`roc main.roc`, play level one.

## Milestone 16: Benchmarks

Done when `docs/BENCHMARKS.md` states the headline figure from a reference
run. The full spec is the dex task zbygy2an.

Built: true `--release` builds, `Config.args`, the Headless and Lockstep run
modes, a Span per stage of the Frame, the bench games for Draws, Colliders,
Model size and UI, the Odin twins, the Roc heap A/B and the mixed bench game.
The method document is merged.

Open: the reference run (dex task 3aczuxv8). It needs a machine on mains
power that nobody uses during the run.

## Milestone 17: Launch (done)

Results, 2026-10-21: every game defines `launch : Config -> Launch`, the
fifth call. The host reads the window, the sample count, vsync, the step
rate, the shadow map size and the table capacities from it before the window
opens. `pf.Launch.default` turns `high_dpi` on. ADR 0007 records the
decision. The full spec is the dex task nm2ai3l5.

Before it (done): every record a game builds has a default, such as
`pf.Scene.empty` and `pf.Draw.default`. A new field then costs a game no
edit when the game builds its records from these defaults.

## The third arc: ready to announce

Agreed 2026-10-21. The engine gets no announcement until a stranger can make
a small game with it. The arc starts with the docs and the tutorial, so each
later milestone adds its own guide page in the same commit as its code. Then
it adds what such a game needs: sound, a gamepad, animated characters and
its own look. It ends with a release that the announcement names.

On 2026-10-21 Audio and Gamepad moved ahead of Animation and Look. Without
sound and a pad the engine feels incomplete, and Look is polish. The Bridge
stays first, because it lets a script inject Input for the gamepad tests.
`docs/RESEARCH-SCALING.md` holds the research behind each milestone.

Check for the arc: Kula plays with a gamepad, with a landing sound and fog,
from the release URLs. A person with only Roc installed follows the tutorial
to a running game.

## Milestone 18: docs and v0.2.0

Done when v0.2.0 is published, pixelsprout.dev shows the guides and the API
from that tag, and Kula runs on v0.2.0. Grilled 2026-10-21. The dex
milestone task holds the decisions and the tasks.

1. `guide/` holds Markdown pages for game authors, in plain, readable prose. The ten
   guide pages cover the five calls, the Scene, assets and Packs, Input,
   Collisions and Queries, the UI, Launch, running and debugging, and
   shipping a game.
2. `guide/tutorial/` holds chapters 1 to 7. They build a small game in the
   style of the entity game, with one app per chapter in
   `examples/tutorial/`. CI builds every chapter app. A script copies code
   regions from the apps into the pages, and CI fails on a diff.
3. Every exposed type and function in the platform and in `linalg`, `mesh`
   and `ui` has a `##` comment. `roc docs` makes the API reference.
   `roc scripts/build.roc docs` fails on an item with no comment.
4. The release workflow attaches the API and the bundle URLs as
   `docs.tar.gz`. pixelsprout.dev reads `guide/` at the latest release tag
   and renders it at `/projects/rocco/docs/`, with the API at
   `/projects/rocco/api/`.

Check: open pixelsprout.dev/projects/rocco/docs/, copy the chapter 1 header,
and run it with only Roc installed.

## Milestone 19: the Bridge

Done when a script plays a game over a localhost socket in Lockstep. The
script injects Input for N steps, reads the Scene as text and saves a
screenshot. The engine is then a harness for agents and for CI.

The debug Bridge needs no Vocabulary change, because the host injects the
Input and reads the Scene itself. The grilling decides whether game-facing
Ports (`Tell`, `Ask` and `Listen`) join this milestone or wait for the
extensions.

## Milestone 20: Audio

Done when Kula plays a landing sound on all three targets. miniaudio goes in
the host as one archive per target. A one-shot is the `Play` Command. A loop
or music is an entry in `Scene.sounds`, paired by id. Sounds are Pack assets
with ids in the Manifest. Tutorial chapter 8 adds sound. Closes dex tasks
79n12xde and x7mwcd0w.

## Milestone 21: Gamepad

Done when Kula plays with a gamepad on all three targets. sokol_app reads no
gamepad, so this is a host module with one file per OS. `Input` gains the
sticks, the triggers and the buttons. The grilling chooses the OS interface
per target and counts the catalog cost of each. The Bridge from Milestone 19
can inject the new Input, so CI can test it with no pad. Tutorial chapter 9
adds the gamepad.

## Milestone 22: Animation

Done when the tutorial character plays a walk clip in chapter 10. The glTF
loader reads skins and animation clips. The Manifest gives the clip ids of
each mesh. A Draw names a clip and a time, so the Model owns the time and
`step` stays pure. The host samples the skeleton and skins the mesh on the
GPU with a second vertex layout. The tutorial character's Blender script
gains a rig.

## Milestone 23: Look

Done when a game sets its tone map, its exposure, its fog and its shadow
knobs in `Scene.look`, and Kula fades distant blocks toward its Theme colour.
One Vocabulary change. Closes dex tasks yjtqgdd4 and s1zhf2hf.

## Milestone 24: the announcement release

Done when the release is published, the docs show it, and the announcement
links the release, the docs and Kula. Each of milestones 19 to 23 adds its
guide page, so this milestone checks the docs end to end and does not write
them.

## Later arcs

These arcs are a direction, not a plan. Each gets milestone numbers and its
own grilling when it starts.

**Bigger worlds.** The Zelda-style demo (dex task yzm5w6ji) pulls this arc.

- Instancing, and frustum culling from the mesh boxes.
- Scenery as a Pack: Blender as the level editor, with static colliders and
  triangle mesh colliders (dex task 99iz77jj).
- Particles: `Scene.emitters` and `Burst`, on the instanced pipeline.
- Cascaded shadow maps (dex task 75ah1rr3) and light selection (dex task
  87xcx7ms).
- A third-person controller: capsule tests and shape casts.

**Other people's games.** An outside author, or a second game in its own
repo, pulls this arc.

- Pointer input, `Scene.window` and world-space sprites (dex tasks 5rxq8tn7
  and elqpa9x2). Decide first whether the UI crosses as a tree, which
  reopens ADR 0004.
- Ports and saves.
- The extension ABI, with FMOD as its first proof.
- Materials on the Draw and shading modes, then post-processing, then game
  shaders as Pack assets (dex task bdathrx5).
- The author kit: `rocco new`, `--replace-dep` in place of Kula's header
  swap, and hot reload across a Model change.

## Beside the milestones

Slot these in when they pay for themselves. Do not run them as a block.

- **Debug drawing.** Lines, wireframe, text. `Scene` gains a `lines` list.
  This is a vocabulary change.
- **Game-provided fonts.** Faces in `assets/fonts/`, beside the one the
  host bakes in.
- **An equirectangular sky loader.** One panorama converted to the six
  cubemap faces at load.
- **A `settle` call.** Same-step contact resolution. See `docs/NOTES.md`.
- **The allocation pool.** A fixed region reserved once at startup with a
  free list behind `roc_alloc` and `roc_dealloc`. Removes the system heap
  from the step path. Satisfies static allocation. Measure before and after
  with a bench sweep and the Roc heap counters.
- **Debug and speed parity.** Run the allocator counters under both
  `--opt=dev` and `--opt=speed` after every memory change.
- **Benchmark regression tracking.** Compare each reference run with the
  last one (dex task uanu7pa4).

Audio and fog moved into milestones 20 and 23. World-space sprites, Blender
as a level editor and shader loading moved into the later arcs.

## Out of scope

- A Vulkan or Metal backend by hand. sokol is the floor.
- Networking between players. The debug Bridge listens on localhost only.
- An editor. Blender as a level editor is the nearest thing, in the later
  arcs.
- Dynamics beyond simple collision. Host-side bodies wait for a game that
  needs them.
- Web builds until Odin and sokol have a shared web path.
- A scripting API where Roc calls the engine. Roc returns descriptions. The
  engine acts on them.
