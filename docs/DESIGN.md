# rocco design

This document says where the line between Roc and Odin goes, and why. It is
the guiding document for the engine. A change that contradicts it needs a
change to this document first.

Roc authors the game. Odin owns the systems beneath the game. The engine is a
Roc platform. The game is a Roc app.

Written 2026-09-22. Verified claims name their evidence. Claims without
evidence are marked as decisions.

## 1. The seam in one table

| Odin owns | Roc owns |
|---|---|
| the window, the clock, the accumulator | the `Model`: the one value that is the game |
| input, and turning it into levels and edges | the rules, as `step` |
| GPU resources, meshes, shaders, the level arena | the picture, as `view` |
| the mesh table and its ids | which mesh a game object uses |
| the audio callback and its thread | what should be heard, as data |
| the collision broadphase, when it exists | what a contact means |
| the Roc heap, the six hooks, hot reload | nothing about memory |
| the vocabulary types: `Config`, `Input`, `Scene` | the `Model` type, which the host never reads |

Odin produces facts. Roc produces decisions. Both cross the seam as plain
values. Roc never asks the engine a question mid-step. Roc never calls a draw
function.

## 2. The three functions

```roc
init : Config -> Model          # once, at startup
step : Model, Input, F32 -> Model   # once per fixed step, 120 Hz
view : Model -> Scene           # once per fixed step, after step
```

The host calls `step` then `view` inside the fixed-step loop. The host holds
the current `Scene` and the previous `Scene`. At render time the host
interpolates between them by the accumulator remainder. Roc never sees a
previous `Model` and never sees an alpha.

```
             fixed step, 120 Hz                        render frame, display rate
  ┌────────────── Odin ───────────────┐      ┌────────────── Odin ────────────────┐
  │ clock, key codes held and pressed │      │ accumulator remainder → alpha       │
  │ mouse delta                       │      │ Scene[n-1], Scene[n]                │
  │ later: broadphase contacts        │      └──────────────┬─────────────────────┘
  └──────────────┬────────────────────┘                     │ pair draws by id, lerp
                 │ Input, dt                                ▼
                 ▼                                 model matrix per draw
   step : Model, Input, F32 -> Model               mesh id → mesh handle
                 │ Model (one reference, mutated in place)
                 ▼
   view : Model -> Scene
                 │ Scene[n]
                 ▼
  ┌────────────── Odin ───────────────┐
  │ keep Scene[n]; drop Scene[n-2]    │
  └───────────────────────────────────┘
```

## 3. The vocabulary

The platform header names three types. Nothing in them names a game. The
test: if a field would be meaningless to a different game, the field belongs
in the app.

```roc
Vec3   : { x : F32, y : F32, z : F32 }
Rgb    : { r : F32, g : F32, b : F32 }
Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }
Input  : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }
Draw   : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }
Camera : { eye : Vec3, target : Vec3, fov_y : F32 }
Scene  : { camera : Camera, draws : List(Draw) }
```

| Type | Carries | Does not carry |
|---|---|---|
| `Config` | a seed; the mesh manifest for every asset the engine loaded | how many pickups a round has |
| `Input` | sokol key codes held (levels) and pressed (edges); mouse delta | a movement vector; a jump flag |
| `Scene` | draws by mesh id with a stable draw id; a camera eye, target and field of view | an entity kind; a score; a mesh catalogue; quit; cursor mode |

Key codes are sokol's: `SPACE = 32`, `A = 65`, `W = 87`. The game binds keys
to intent. The engine does not. The host filters no key out of `held` or
`pressed`, including the keys it reacts to itself.

A tint is an `Rgb`, not a `Vec3`. Roc records are structural, so the two
names keep a position from passing as a colour. Each channel runs from 0 to
1. The host multiplies the mesh colour by the tint. Decision.

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

The manifest is the one place a refcounted type (`Str`) enters the
vocabulary. `init` reads it once. The cost is glue coverage, not time.

### Draws carry a stable id

The host pairs draws across two `Scene`s by `id` and interpolates position
and yaw between them. A draw whose id has no partner in the previous `Scene`
is drawn where it is. Entities use their entity id. Fixed scenery uses ids the
entities never reach.

## 4. The platform does not know the game

The platform header binds `Model` with a for-clause:

```roc
platform ""
    requires {} {
        [Model: model] for init : Config -> model,
        step : Model, Input, F32 -> Model,
        view : Model -> Scene,
    }
```

The clause appears on one entry. It declares the alias `Model` for the rest
of the header and the platform body. The app must declare a type named
exactly `Model`. The compiler names the missing type if it does not.

The host cannot hold a value whose layout differs per game. The wrappers box
it:

```roc
init_for_host : Config -> Box(Model)
init_for_host = |config| Box.box(init(config))

step_for_host : Box(Model), Input, F32 -> Box(Model)
step_for_host = |boxed, input, dt| Box.box(step(Box.unbox(boxed), input, dt))

view_for_host : Box(Model) -> Scene
view_for_host = |boxed| view(Box.unbox(boxed))
```

The glue emits `Model` as one opaque pointer. The three entrypoints are:

```
roc_init(Config)             -> ptr
roc_step(ptr, Input, f32)    -> ptr
roc_view(ptr)                -> Scene
```

Nothing about the game appears in the generated ABI. `libhost.a` is rebuilt
only when `Config`, `Input` or `Scene` change. Those three types are the
engine's public API.

Evidence: two unrelated games link and run against one host library on
`nightly-2026-09-12-220fd47`. See `examples/cards` and `examples/entity-game`.
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
host heap the same frame. There is no arena and no harvest. Evidence: one live
block at steady state over 888 steps, zero bad frees over 899.

`roc_realloc` carries no old size. The copy length must come from the
allocator's own record. The tracking allocator is load-bearing for this
reason, not for observability.

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
- One `Scene` allocation per step. It is the extract; it would exist anyway.
- One box shell allocation and free per step. The pool removes it.
- One allocation and one free per step for each non-empty `Input` list. The
  refcount-1 axiom costs this. The pool removes it.
- `List.map`, `List.keep_if` and `List.concat` can allocate where a
  `List.set` loop does not. Under `--opt=dev`, `List.map` always copies.
  See section 10.
- Functional entities need explicit ids. Put `id : U64` on the entity record.
- The glue must learn `U32`, `Str`, `Box` and `List(U16)` before this
  platform links. The Zig glue emits all four and is the reference.
- `roc check` on `nightly-2026-09-12-220fd47` segfaults for some
  platform-module alias shapes. Write wrapper signatures inline when it does.
  Minimal reproduction is recorded in the old course notes.

## 10. Verified and not verified

Verified in milestone 2 on `arm64mac` and `x64glibc`,
`nightly-2026-09-12-220fd47`, with `scripts/alloc-check.sh`: each game runs
240 frames with no input under `--opt=dev` and `--opt=speed`, and every fixed
step after the first 10 is checked. On `x64glibc` the Docker image runs it
under `xvfb-run` with software GL.

- Both games run against the engine: `examples/cards` and
  `examples/entity-game`.
- The call protocol in section 5 holds. Each step makes 2 allocations and 2
  frees: the new box shell and the new `Scene` draws list, then the old box
  and the dropped `Scene`. No step reallocates. The live block count stays
  constant: 3 for cards, 4 for entity-game. Shutdown leaves no Roc block.
- In-place mutation with a boxed `Model`. `Box.unbox` on a unique box does
  not copy the `Model`, and a `List.set` loop over the entity list mutates
  in place on both backends.
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
- Hot reload keeps the state when the `Model` type does not change. Checked
  by hand on macOS with entity-game.

What the measurement found in game code. Section 9 lists the costs.

- `List.map` copies the list under `--opt=dev`. Under `--opt=speed` it
  mutates in place. entity-game uses a `List.set` loop for this reason.
- `List.keep_if` allocates even when it keeps every element.
  `List.concat([x], list)` allocates twice. entity-game skips the first on a
  quiet step and builds its draws with `List.with_capacity`.

Not verified:

- Hot reload after a change to the `Model` type. The host cannot see the
  layout, so the new code reads the old bytes. This is undefined.
- The allocation counts with input. A pressed key adds one allocation and
  one free for each non-empty `Input` list, and a stage that changes the
  entity list may allocate. The check runs with no input.
- `x64win`. The check has run on `arm64mac` and `x64glibc` only.
