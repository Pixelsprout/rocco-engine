# rocco

rocco is a game engine written in Odin that hosts games written in Roc. The
two meet at a seam of three pure functions, and this glossary fixes the words
on both sides of it. `docs/DESIGN.md` decides meaning; `docs/GLOSSARY.md`
explains the general graphics and memory concepts the engine is built from.

## The two sides

**Engine**:
The Odin code that owns the window, the clock, input, the GPU and memory. It
is the whole of the non-Roc half.
_Avoid_: runtime, backend, native side, C side

**Host**:
The engine seen from the seam: the party that calls `init`, `step` and
`view` and owns the one pointer to the Model. Same code as the engine; say
"host" when the sentence is about the seam.
_Avoid_: script host, runtime

**Platform**:
The Roc platform package every game builds on: the vocabulary types, the
binding of `Model`, the boxed wrappers, and the host they link against. There
is exactly one.
_Avoid_: SDK, framework, engine API

**Game**:
A Roc app built on the platform. It declares `Model` and defines `init`,
`step` and `view`. "App" is Roc's word for the file kind; "game" is what it
is.
_Avoid_: script, scripting, application code, client

**Seam**:
The boundary between game and engine. Only plain values cross it: facts go in
through `init` and `step`, decisions and a Scene come out. Nothing effectful
crosses in either direction.
_Avoid_: API, FFI boundary, scripting API, bridge

**Glue**:
The generated Odin bindings for the vocabulary, produced by `roc glue` from
the spec in the `glue/` submodule. Never written by hand.
_Avoid_: bindings, FFI header, ABI file

## The three calls

**init**:
The game's function from Config to Model. Called once, at startup.
_Avoid_: setup, start, new

**step**:
The game's function from Model, Input and dt to Model. Called once per fixed
step. Pure: the same Model and Input give the same Model.
_Avoid_: update, tick, simulate, advance

**view**:
The game's function from Model to Scene. Called once per fixed step, after
`step`. It sees one Model and no alpha.
_Avoid_: render, draw, extract, present

**Stage**:
One function from Model to Model inside the `step` pipeline. The order of the
stages is the schedule; each stage is a unit test.
_Avoid_: system, pass, phase

## The vocabulary

**Vocabulary**:
The three types that cross the seam: Config, Input and Scene. They are the
engine's public API. Nothing in them names a game.
_Avoid_: protocol, schema, contract, ABI

**Vocabulary change**:
Any edit to Config, Input or Scene. It rebuilds the host and every game.
Adding an asset, an entity kind or a game rule is never one.
_Avoid_: breaking change, API change

**Config**:
What the host gives `init` once: a seed and the manifest.
_Avoid_: settings, options, init args, environment

**Seed**:
The number in Config that starts the game's randomness. The game keeps a
generator state in its Model; the same seed and the same Inputs give the same
run. The host reads it from `ROCCO_SEED`, default 0.
_Avoid_: random seed, RNG, salt

**Input**:
What the host gives `step` each fixed step: the keys held, the keys pressed
since the previous step, and the mouse delta. Key codes are sokol's; which
key means what is the game's decision.
_Avoid_: events, controls, actions, commands

**Held**:
A key in Input that is down at this step. A level: asking twice gives the
same answer.
_Avoid_: down, level, pressed

**Pressed**:
A key in Input that went down since the previous fixed step. An edge: it
appears in exactly one Input, the first fixed step after the key event. A
key tapped between two steps is pressed but not held.
_Avoid_: held, down, just pressed, triggered, edge

**Scene**:
What `view` returns each fixed step: a Camera and a list of Draws. It
describes what should be on screen now. Derived from the Model, rebuilt every
step, stored by the host and never by the game.
_Avoid_: world, level, frame, render state, render list, scene graph

**Draw**:
One entry in a Scene: a draw id, a mesh id, a position, scale, yaw and tint.
It is a description, not a command.
_Avoid_: sprite, renderable, instance, draw call (the GPU term), object

**Tint**:
The colour of a Draw, as an `Rgb` record with channels from 0 to 1. The host
multiplies the mesh colour by it.
_Avoid_: colour (for the field), albedo, Vec3 colour

**Camera**:
The field of a Scene that says where the eye is, what it looks at and the
vertical field of view. The game decides it; the host interpolates it. The
camera package in `packages/camera/` builds one.
_Avoid_: view (the call), viewport, camera target

**Model**:
The one value that is the game. The game declares its type; the host holds
it as one opaque pointer and never reads inside it.
_Avoid_: State, game state, script state, world, save

**Entity**:
A record with an explicit id that a game keeps in its Model. It belongs to
the game, not the vocabulary: the engine has no entity type and never stores
one, and a game may have none.
_Avoid_: game object, GameObject, body, node, actor

## Ids

**Draw id**:
A stable number on a Draw that the host uses to pair a draw with its
predecessor in the previous Scene and interpolate between them. Entities use
their entity id; fixed scenery uses ids no entity reaches.
_Avoid_: handle, key, index, entity id (when the draw is scenery)

**Mesh id**:
A number the engine assigns to each mesh it loaded, published in the manifest
and carried on Draws. Id 0 is the fallback mesh.
_Avoid_: mesh handle (the engine's internal GPU handle), mesh name, asset id

**Manifest**:
The name-to-mesh-id list in Config: every asset loaded from disk plus the
primitives. The game resolves the names it needs once, in `init`, and keeps
the ids in its Model.
_Avoid_: mesh table, catalogue, registry, asset list

**Mesh table**:
The engine's table from mesh id to GPU resources. The game never sees it; it
sees the manifest.
_Avoid_: manifest, asset store, resource cache

**Fallback mesh**:
The mesh at id 0, drawn for any id the engine does not know. A magenta cube:
a typo is visible, not fatal.
_Avoid_: default mesh, error mesh, placeholder, missing mesh

**Primitive**:
A mesh the engine builds itself rather than loads: the cube, the sphere and
the slab. They sit in the manifest beside loaded assets.
_Avoid_: built-in, shape, basic mesh

## Time

**Fixed step**:
One advance of the simulation by the fixed interval. The host calls `step`
then `view` once per fixed step. A frame runs zero or more of them.
_Avoid_: tick, update, iteration, frame, sim step

**Frame**:
One display refresh: one sokol frame callback, zero or more fixed steps, one
render.
_Avoid_: step, tick, render pass

**dt**:
The third argument to `step`: the length of this fixed step in seconds.
_Avoid_: delta, elapsed, frame time

**Alpha**:
How far the display sits between the previous Scene and the current one, in
`[0, 1)`. Host-only. The game never sees it and never sees a previous Model.
_Avoid_: interpolation factor, t, blend, remainder

## Effects

**Description**:
A value that says what should exist now, returned every step, which the host
reconciles against the last one. A Scene is one. Descriptions first.
_Avoid_: command, request, event, intent

**Command**:
A value that says do this once: spawn, destroy, play a sound. Reserved for
things with host-side lifetime. Not in the vocabulary yet. Quit becomes the
first command; until then the host quits on `ESC`.
_Avoid_: description, effect, action, message, event

**Contact**:
A fact the host computes: two bounds overlapped this step. The game decides
what a contact means; the engine never does.
_Avoid_: collision (the game's response), hit, overlap event, trigger

**Collider**:
A shape a game may return in its Scene for the host to sweep. Whether Scenes
carry colliders or the host derives bounds from Draws is undecided.
_Avoid_: hitbox, body, rigidbody, bounds (the derived alternative)

## Memory lifetimes

**Permanent**:
The lifetime of the program: renderer, input, config.
_Avoid_: global, static, forever

**Level**:
The lifetime of everything loaded from disk for the current world: meshes
and textures. It never holds entities; those live in the Model.
_Avoid_: scene, world, map, stage; and "level" for an input that holds (say
held)

**Frame**:
The lifetime of one frame: scratch that dies when the frame ends.
_Avoid_: temp, transient, per-tick
