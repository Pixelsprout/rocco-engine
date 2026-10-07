# rocco design

This document says where the line between Roc and Odin goes, and why. It is
the guiding document for the engine. A change that contradicts it needs a
change to this document first.

Roc authors the game. Odin manages the systems beneath the game. The engine is
a Roc platform. The game is a Roc app.

Written 2026-09-22. Verified claims name their evidence. Claims without
evidence are marked as decisions.

## 1. The seam in one table

| Odin manages | Roc manages |
|---|---|
| the window, the clock, the accumulator | the `Model`: the one value that is the game |
| input, and turning it into levels and edges | the rules, as `step` |
| GPU resources, meshes, shaders, the level arena | the picture, as `view` |
| the mesh table and its ids | which mesh a game object uses |
| the audio callback and its thread | what should be heard, as data |
| finding the Contacts between Colliders | which shapes touch, as Colliders; what a Contact means |
| the Roc heap, the six hooks, hot reload | nothing about memory |
| the vocabulary types: `Config`, `Input`, `Contact`, `Scene` | the `Model` type, which the host never reads |

Odin produces facts. Roc produces decisions. Both cross the seam as plain
values. Roc never asks the engine a question mid-step. Roc never calls a draw
function.

## 2. The three functions

```roc
init : Config -> Model                             # once, at startup
step : Model, Input, List(Contact), F32 -> Model   # once per fixed step, 120 Hz
view : Model -> Scene                              # once per fixed step, after step
```

The host calls `step` then `view` inside the fixed-step loop. The host holds
the current `Scene` and the previous `Scene`. At render time the host
interpolates between them by the accumulator remainder. Roc never sees a
previous `Model` and never sees an alpha.

The host computes the Contacts from the Colliders in the previous `Scene`.
The host tests overlap, not sweep, so the normal and depth describe where
the shapes are now. The first step gets empty Contacts. Decision.

Until the host computes Contacts, every step gets empty Contacts.

```
             fixed step, 120 Hz                        render frame, display rate
  ┌────────────── Odin ───────────────┐      ┌────────────── Odin ────────────────┐
  │ clock, key codes held and pressed │      │ accumulator remainder → alpha       │
  │ mouse delta                       │      │ Scene[n-1], Scene[n]                │
  │ Contacts from Scene[n-1]          │      └──────────────┬─────────────────────┘
  └──────────────┬────────────────────┘                     │ pair draws by id, lerp
                 │ Input, Contacts, dt                      ▼
                 ▼                                 model matrix per draw
   step : Model, Input, List(Contact), F32 -> Model   mesh id → mesh handle
                 │ Model (one reference, mutated in place)
                 ▼
   view : Model -> Scene
                 │ Scene[n]
                 ▼
  ┌────────────── Odin ───────────────┐
  │ keep Scene[n]; drop Scene[n-2]    │
  └───────────────────────────────────┘
```

The Frame render is the host module on the render frame side. Once per
frame it builds the Pairing from the previous `Scene`, then interpolates each
draw at the Alpha and submits it.

## 3. The vocabulary

The platform header names four types. Nothing in them names a game. The
test: if a field would be meaningless to a different game, the field belongs
in the app.

```roc
Vec3     : { x : F32, y : F32, z : F32 }
Rgb      : { r : F32, g : F32, b : F32 }
Config   : { seed : U64, meshes : List({ name : Str, id : U32 }) }
Input    : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
Draw     : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }
Camera   : { eye : Vec3, target : Vec3, fov_y : F32 }
Collider : { id : U64, kind : U8, pos : Vec3, yaw : F32, extent : Vec3 }
Contact  : { a : U64, b : U64, normal : Vec3, depth : F32 }
Scene    : { camera : Camera, draws : List(Draw), colliders : List(Collider) }
```

| Type | Carries | Does not carry |
|---|---|---|
| `Config` | a seed; the mesh manifest for every asset the engine loaded | how many pickups a round has |
| `Input` | sokol key codes held (levels) and pressed (edges); mouse delta | a movement vector; a jump flag |
| `List(Contact)` | each overlapping pair of Colliders, once, with `a < b`, sorted by `(a, b)`; the normal from a to b and the depth | what the Contact means; a time of impact |
| `Scene` | draws by mesh id with a stable draw id; a camera eye, target and field of view; the Colliders that can touch | an entity kind; a score; a mesh catalogue; quit; cursor mode; a physics body |

Key codes are sokol's: `SPACE = 32`, `A = 65`, `W = 87`. Games name them with
`pf.Key`, for example `Key.held(input, W)`. `Input` still carries `U16` codes.
The game binds keys to intent. The engine does not. The host filters no key
out of `held` or `pressed`, including the keys it reacts to itself.

A Collider has the id of the entity it belongs to. An entity with no
Collider touches nothing, so a game opts in per entity. The render shape is
not the collision shape. `kind` is a number because the Odin glue has no tag
unions yet: 0 is a box, 1 a sphere, 2 a capsule. For a box, `extent` is the
half extents and `yaw` turns it in the ground plane. For a sphere,
`extent.x` is the radius. For a capsule, `extent.x` is the radius and
`extent.y` the half height of the segment. Games build Colliders with
`pf.Collider`, for example `Collider.box(id, pos, yaw, half)`, and never
write a kind number. A new shape is a host branch, not a vocabulary change.
Decision.

The host latches input between fixed steps. A key press waits in a pending
set until a step takes it as `pressed`. The mouse delta waits the same way.
So the first step of a frame gets them, and later steps in that frame get an
empty `pressed` and a zero delta. If a frame runs no step, the next step that
runs gets them. `held` is the key state when the step runs. When the
window loses focus, the host releases every held key, because their key-up
events go to the other window. Decision.

A tint is an `Rgb`, not a `Vec3`. Roc records are structural, so the two
names keep a position from passing as a colour. Each channel runs from 0 to
1 and is linear, like a glTF colour. The host multiplies the mesh colour by
the tint, lights the result in linear, and the shader encodes it to sRGB for
the screen. Decision.

The seed is the start value for any randomness in the game. Roc has no random
effect, so a game keeps a generator state in its `Model` and advances it in
`step`. The same seed and the same `(Input, dt)` log give the same run. The
host reads the seed from `ROCCO_SEED`. The default is 0. Decision.

### The camera is a description

The game decides the camera. `Scene.camera` says where the eye is, what it
looks at and the vertical field of view. The up vector is +Y. The host
interpolates `eye` and `target` like a draw. Pure helpers such as `look_at`
and `follow` live in the camera package in `packages/camera/`. The package
does not depend on the platform: Roc records are structural, so its `View`
record fits `Scene.camera`. Decision.

`ROCCO_DEBUG_CAMERA=1` gives the host a fly camera for debugging. The host
then ignores `Scene.camera`, and the game still gets all input.

### Meshes are ids

The engine loads every asset it finds at startup and registers its own
primitives in the same table. It assigns a `U32` to each and hands the
name-to-id manifest to `init`. The game resolves the names it needs once and
keeps the ids in its `Model`. A name the engine did not load resolves to id 0.
The engine draws id 0 as the fallback mesh. A typo is visible, not fatal.

A closed tag union of mesh names is not allowed in `Scene`. It would rebuild
`libhost.a` for every new asset.

Games treat mesh ids as opaque. A game never hard-codes an id and never does
maths on one. It gets each id from the manifest in `init`.

Assets are `.glb` files in `assets/meshes/`, in the directory of the
program path (`argv[0]`). `roc run` sets `argv[0]` to the game's `main.roc`,
and a built game has its binary in the game directory, so both find the
game's assets from any working directory. `ROCCO_ASSETS` replaces the
`assets` path. The engine reads the top
level only, in sorted order, so ids are stable across runs. A file goes into
the manifest under its stem, such as `sprout`. Names are case-sensitive. The
primitives go in as `primitive/fallback`, `primitive/cube`, `primitive/sphere`
and `primitive/plane`. A file stem cannot contain `/`, so a file never takes
the name of a primitive. A file that does not load is skipped and logged, and
its name resolves to id 0.

The primitives have type-safe tags in the mesh package:
`Mesh.primitive(config, Cube)`. `Mesh.resolve(config, "name")` resolves the
name of a loaded file to its mesh id. Both return 0 and print a `dbg` line on
a miss. The tags live in the package only. The vocabulary still carries only
a `U32`.

The manifest is the one place a refcounted type (`Str`) enters the
vocabulary. `init` reads it once. The cost is glue coverage, not time.

### Draws carry a stable id

The host pairs draws across two `Scene`s by `id` and interpolates position
and yaw between them. A draw whose id has no partner in the previous `Scene`
is drawn where it is. Entities use their entity id. Fixed scenery uses ids the
entities never reach.

Draw ids must be unique in a `Scene`. The Frame render pairs each current
draw with the previous `Scene`. If the previous `Scene` has two draws with
one id, the first one pairs, and the Frame render logs the id once per run.
If the current `Scene` has two draws with one id, each one draws and
interpolates from the same previous draw. The log then comes at the next
frame, if that `Scene` is the previous one when the frame renders. The
Pairing is built once per frame, so a `Scene` that is previous only between
two steps inside one frame is never checked. A duplicate that persists is
still logged.

## 4. The platform does not know the game

The platform header binds `Model` with a for-clause:

```roc
platform ""
    requires {} {
        [Model: model] for init : Vocabulary.Config -> model,
        step : Model, Vocabulary.Input, List(Vocabulary.Contact), F32 -> Model,
        view : Model -> Vocabulary.Scene,
    }
    exposes [Vocabulary, Key, Collider]
```

The clause appears on one entry. It declares the alias `Model` for the rest
of the header and the platform body. The app must declare a type named
exactly `Model`. The compiler names the missing type if it does not.

The host cannot hold a value whose layout differs per game. The wrappers box
it:

```roc
init_for_host : Config -> Box(Model)
init_for_host = |config| Box.box(init(config))

step_for_host : Box(Model), Input, List(Contact), F32 -> Box(Model)
step_for_host = |boxed, input, contacts, dt| Box.box(step(Box.unbox(boxed), input, contacts, dt))

view_for_host : Box(Model) -> Scene
view_for_host = |boxed| view(Box.unbox(boxed))
```

The glue emits `Model` as one opaque pointer. The three entrypoints are:

```
roc_init(Config)                          -> ptr
roc_step(ptr, Input, List(Contact), f32)  -> ptr
roc_view(ptr)                             -> Scene
```

Nothing about the game appears in the generated ABI. `libhost.a` is rebuilt
only when `Config`, `Input`, `Contact` or `Scene` change. Those four types
are the engine's public API.

The vocabulary lives in `platform/Vocabulary.roc`. The header must use
qualified names such as `Vocabulary.Config`, because it does not see the
body's `import`. Games import the vocabulary and declare none of it:

```roc
import pf.Vocabulary exposing [Config, Input, Scene]
```

Packages declare the types they need by shape and never import the platform,
so they stay publishable. The aliases are structural, so a package's
`{ x : F32, y : F32, z : F32 }` and the vocabulary's `Vec3` are one type.

Evidence: two unrelated games link and run against one host library on
`nightly-2026-09-27-a3ce7f1`. See `examples/cards` and `examples/entity-game`.
`scripts/host-check.sh` links both and checks that the host library and the
glue do not change. The Zig glue output for that platform contains no game
word.

## 5. Memory: one reference, mutated in place

Axiom: every Roc value the host holds or passes has a refcount of 1. The one
exception is the increment before `roc_view`, and `roc_view` consumes that
reference before it returns. The host never passes static (refcount 0) data
into Roc. A static list would make Roc copy it on write, and a game that kept
it would hold a pointer into a host buffer.

The host keeps exactly one reference to the `Model`. This is a decision with
consequences, and it answers a question from the Roc community: how do you
provide a previous `Model` for interpolation without cloning?

You do not. Holding a previous `Model` while stepping the current one gives
the current one a refcount of two. Roc must then copy every list it writes.
The spike measured that copy at one allocation per step, the size of the
entity list. Keeping the refcount at one lets Roc mutate the entity list in
place. The spike measured that mode at zero allocations per step at small
sizes.

So interpolation moves out of Roc. `view` runs at step rate and returns a
`Scene`. The host keeps two `Scene`s and interpolates between them. A `Scene`
is the render extract the host needs anyway, so this trades two copies for
one.

Call protocol, per fixed step:

1. The host owns one box pointer `m`.
2. Call `roc_step(m, input, dt)`. Roc consumes `m` and returns `m'`. The
   host must not use `m` again. Passing `m` twice is a double free.
3. Increment the refcount on `m'`. Call `roc_view(m')`. Roc consumes one
   reference and returns a `Scene`. The host still holds `m'` with refcount
   one.
4. Store the `Scene` as current. Free the `Scene` that was previous. The one
   that was current becomes previous.

After `init`, the host runs steps 3 and 4 once. The first frame then has a
`Scene` to draw.

The host allocates the `Input` lists and the `Config` manifest with
`roc_alloc` at refcount 1, through glue helpers. An empty list allocates
nothing. The glue helpers also free each `Scene` the host drops. The host
never computes a header offset itself.

At shutdown the host calls the `drop_model_for_host` export. Roc frees the
box, because only the compiler knows the layout of the `Model` inside it.
The glue at `nightly-2026-09-12-220fd47` emits only generic box helpers.

The refcount is an `isize` eight bytes before the data pointer. Zero marks
static data.

The host honours `roc_dealloc`. Every allocation Roc frees goes back to the
Roc heap the same frame. There is no arena and no harvest. Evidence: one live
block at steady state over 888 steps, zero bad frees over 899.

`roc_realloc` carries no old size. The copy length must come from the
allocator's own record. The tracking allocator is load-bearing for this
reason, not for observability. The Roc heap in `engine/roc_runtime.odin`
manages the tracking allocator, the alloc counters and the six hooks; the
Seam in `engine/seam.odin` manages only the game calls and the call protocol
above.

The box shell costs one allocation and one free per step. The pool described
in the roadmap removes the system heap from that path.

## 6. What is refused

- **No hosted draw functions.** `draw_cube!` makes Roc immediate-mode and
  chatty. It takes interpolation, batching and draw order away from the host,
  which is the only party that knows the GPU.
- **No mutable engine handles in Roc.** That is Unity's `MonoBehaviour` with
  a refcount to get wrong.
- **No game type in the platform header.** See section 3.
- **No previous `Model` across the seam.** See section 5.
- **No quit or cursor field in `Scene` yet.** Until the first command
  arrives, `ESC` quits and the host sets the cursor. Then quit becomes a
  command, and cursor mode becomes a field in `Scene`, because it is a state.
- **No hosted function until a pure value cannot express the need.** A sound
  with a duration or a physics body with a warm-start cache has host-side
  lifetime. When the first one arrives, Roc returns a `List Command` with
  `Spawn` and `Destroy` by id and the host reconciles. Descriptions first.
  Commands only when a description cannot say it.

## 7. Where the design comes from

| Engine | Game state lives in | Script reaches the engine by | Verdict |
|---|---|---|---|
| Unity classic | engine GameObjects | `Update()` mutating through handles | chatty, impure, refused |
| Unity DOTS | blittable structs in chunks | systems over queries | right data, wrong granularity for an FFI |
| Godot | a Node tree | per-node callbacks on a boxed `Variant` | refused; but its Servers layer is what Odin should be |
| Bevy | the World, as tables | systems as functions over typed queries; extract per frame | right data; the seam sits where Bevy places a system call |
| Elm | an opaque `model` the runtime holds | it does not; `update` and `view` are pure | the control model rocco uses |

Godot's `RenderingServer` takes ids and commands and never knows what a
player is. Odin is that layer. Bevy's extract copies render data out of the
World once per frame. `view` is that copy, written in Roc. Elm's runtime owns
`model` as an opaque value and calls `update` and `view`. The host owns the
`Model` as an opaque pointer and calls `step` and `view`.

## 8. What functional programming buys

- **Replay.** `step` is pure. A log of `(Input, dt)` reproduces any bug.
- **Tests without an engine.** `roc test` runs `step` and `view` directly.
  The example game's six tests run in 34 ms.
- **The schedule is composition.** `model |> steer(input) |> integrate(dt)
  |> collect`. Each stage is `Model -> Model` and a unit test. Reordering the
  pipeline reorders the systems.
- **Hot reload keeps the state.** The `Model` lives in host-owned memory.
  Replacing the code that produces it does not disturb it. Measured.
- **Render state is derived.** `view` recomputes the `Scene` every step and
  stores nothing.

## 9. Costs, stated

- `List(Record)` is array-of-structs. Bevy stores columns. The repack at the
  seam is where to fix it if it ever matters.
- One allocation per step for each non-empty `Scene` list: the draws, and
  the colliders when a game returns any. It is the extract; it would exist
  anyway.
- One allocation and one free per step for non-empty Contacts, once the
  host computes them. Empty Contacts allocate nothing.
- A Collider kind is a `U8`, not a tag union, until the glue emits tag
  unions. `pf.Collider` hides the number from games.
- One box shell allocation and free per step. The pool removes it.
- One allocation and one free per step for each non-empty `Input` list. The
  refcount-1 axiom costs this. The pool removes it.
- `List.map`, `List.keep_if` and `List.concat` can allocate where a
  `List.update` loop does not. Under `--opt=dev`, `List.map` always copies.
  See section 10.
- Functional entities need explicit ids. Put `id : U64` on the entity record.
- The glue must learn `U32`, `Str`, `Box` and `List(U16)` before this
  platform links. The Zig glue emits all four and is the reference.
- `roc check` on `nightly-2026-09-12-220fd47` segfaults for some
  platform-module alias shapes. Write wrapper signatures inline when it does.
  Minimal reproduction is recorded in the old course notes.

## 10. Verified and not verified

Milestone 2 verified these items on `arm64mac` and `x64glibc`, with
`nightly-2026-09-12-220fd47`. `scripts/alloc-check.sh` runs each game for 240
frames with no input, under `--opt=dev` and `--opt=speed`. It checks every
fixed step after the first 10. On `x64glibc`, the Docker image runs the check
under `xvfb-run` with software GL.

- Both games run against the engine: `examples/cards` and
  `examples/entity-game`.
- The call protocol in section 5 holds. Each step makes 2 allocations and 2
  frees: the new box shell and the new `Scene` draws list, then the old box
  and the dropped `Scene`. No step reallocates. The live block count stays
  constant: 3 for cards, 4 for entity-game. Shutdown leaves no Roc block.
- In-place mutation with a boxed `Model`. `Box.unbox` on a unique box does
  not copy the `Model`, and a `List.update` loop over the entity list
  mutates in place on both backends.
- `view` at step rate is under budget. Mean time per fixed step, in
  microseconds, including the host's `Input` lists and `Scene` drop:

  | Game | Backend | `step` | `view` |
  |---|---|---|---|
  | cards | dev | 7.1 | 4.9 |
  | cards | speed | 8.5 | 5.2 |
  | entity-game | dev | 27.0 | 10.2 |
  | entity-game | speed | 7.9 | 5.7 |

  These are `arm64mac` numbers. On `x64glibc` in the Docker image, under
  x86_64 emulation, entity-game takes 62.7 and 13.0 microseconds for `step`
  under dev and speed. One fixed step is 8,333 microseconds.
- Hot reload keeps the state when the `Model` type does not change. The
  user checked this by hand on macOS with entity-game.

The measurement found these costs in game code. Section 9 lists them.

- `List.map` copies the list under `--opt=dev`. Under `--opt=speed` it
  mutates in place. entity-game uses a `List.update` loop for this reason.
- On `nightly-2026-09-27-a3ce7f1`, the loop copies the list on every update
  under `--opt=dev` if the fallback of `??` names the list. A fallback that
  holds the list is a second reference. entity-game uses `?? []`.
- `List.keep_if` allocates even when it keeps every element.
  `List.concat([x], list)` allocates twice. entity-game skips the first on a
  quiet step and builds its draws with `List.with_capacity`.

Not verified:

- Hot reload after a change to the `Model` type. The host cannot see the
  layout, so the new code reads the old bytes. This is undefined.
- The allocation counts with input. A pressed key adds one allocation and
  one free for each non-empty `Input` list, and a stage that changes the
  entity list may allocate. The check runs with no input.
- The allocation counts on `x64win`. Both games run there, checked by hand,
  but the alloc check is a shell script and has not run on Windows.
