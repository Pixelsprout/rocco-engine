# rocco

rocco is a game engine written in Odin that hosts games written in Roc. The
two meet at a seam of four pure functions, and this glossary fixes the words
on both sides of it. `docs/DESIGN.md` decides meaning; `docs/GLOSSARY.md`
explains the general graphics and memory concepts the engine is built from.

## The two sides

**Engine**:
The Odin code that manages the window, the clock, input, the GPU and memory.
It is the whole of the non-Roc half.
_Avoid_: runtime, backend, native side, C side

**Host**:
The engine seen from the seam: the party that calls `init`, `step`,
`loaded` and `view`, owns the one pointer to the Model, and drops it at
shutdown. Same code as the engine; say "host" when the sentence is about the
seam.
_Avoid_: script host, runtime

**Platform**:
The Roc platform package every game builds on: the vocabulary types, the
binding of `Model`, the boxed wrappers, and the host they link against. There
is exactly one.
_Avoid_: SDK, framework, engine API

**Game**:
A Roc app built on the platform. It declares `Model` and defines `init`,
`step`, `loaded` and `view`. "App" is Roc's word for the file kind; "game" is what it
is.
_Avoid_: script, scripting, application code, client

**Seam**:
The boundary between game and engine. Only plain values cross it: facts go in
through `init`, `step` and `loaded`, and decisions come out as a Scene and Commands.
Nothing effectful crosses in either direction.
_Avoid_: API, FFI boundary, scripting API, bridge

**Game calls**:
What the host calls on the game: the four calls, and `drop_model`, the
platform export that frees the Model at shutdown. The Seam reaches them
through a struct of procedures, so a fake game can stand in for the Roc app
in tests.
_Avoid_: callbacks, vtable, bindings

**Glue**:
The generated Odin bindings for the vocabulary, produced by `roc glue` from
the spec in the `glue/` submodule. Never written by hand.
_Avoid_: bindings, FFI header, ABI file

## The four calls

**init**:
The game's function from Config to a record of the Model and a list of
Commands. Called once, at startup. Its Commands can load the first Pack.
_Avoid_: setup, start, new

**step**:
The game's function from Model, Input, the Contacts and dt to a record of
the next Model and a list of Commands. Called once per fixed step. Pure: the
same Model, Input and Contacts give the same Model and Commands.
_Avoid_: tick, simulate, advance, update (the game's Stage pipeline)

**loaded**:
The game's function from Model, a pack name and a Manifest to Model. The
host calls it after it runs a Load, before the next `view`. It is the only
promise that ids exist.
_Avoid_: on_load, ready, callback

**view**:
The game's function from Model to Scene. Called once per fixed step, after
`step`. It sees one Model and no alpha.
_Avoid_: render, draw, extract, present

**Stage**:
One function from Model to Model inside the game's `update` pipeline, which
`step` calls. The order of the stages is the schedule; each stage is a unit
test.
_Avoid_: system, pass, phase

## The vocabulary

**Vocabulary**:
The types that cross the seam: Config, Input, Contact, Scene and Command.
They are the engine's public API. Nothing in them names a game. Games import
them, and the records inside them, from `pf.Vocabulary`.
_Avoid_: protocol, schema, contract, ABI

**Vocabulary change**:
Any edit to Config, Input, Contact, Scene or Command. It rebuilds the host
and every game.
Adding an asset, an entity kind or a game rule is never one.
_Avoid_: breaking change, API change

**Config**:
What the host gives `init` once: a seed and the asset names found on disk,
with no ids.
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

**Key**:
A named sokol key code, such as `W` or `Space`, from `pf.Key`. Input still
carries the code; the game decides what the key means. `roc scripts/build.roc
-- keys` writes `platform/Key.roc` from sokol, so the names cannot drift.
_Avoid_: keycode, button, action

**Held**:
A key in Input that is down at this step. A state, not an edge: asking
twice gives the same answer.
_Avoid_: down, level, pressed

**Pressed**:
A key in Input that went down since the previous fixed step. An edge: it
appears in exactly one Input, the first fixed step after the key event. A
key tapped between two steps is pressed but not held.
_Avoid_: held, down, just pressed, triggered, edge

**Scene**:
What `view` returns each fixed step: a Camera, a list of Draws, a list of
Colliders, a list of Lights and a Cursor. It describes what should be on
screen now and what can touch. Derived from the Model, rebuilt every step,
stored by the host and never by the game.
_Avoid_: world, level, frame, render state, render list, scene graph

**Draw**:
One entry in a Scene: a draw id, a mesh id, a position, scale, rot, scale_rot and tint.
The scale acts along the axes of scale_rot, then rot turns the result.
It is a description, not a command. `rot` is a unit quaternion. The host
interpolates it between two Scenes.
_Avoid_: sprite, renderable, instance, draw call (the GPU term), object

**Tint**:
The colour of a Draw, as an `Rgb` record with linear channels from 0 to 1.
The host multiplies the mesh colour by it. A Light colour can exceed 1; a
tint cannot.
_Avoid_: colour (for the field), albedo, Vec3 colour

**Light**:
One entry in `Scene.lights`: `Ambient`, `Directional` or `Point`. Its colour
is a linear `Rgb` that carries intensity, so a channel can exceed 1. A
Directional `dir` is the way the light travels. A Point light falls off to
zero at its `range`. `pf.Light` builds each one. Lights have no id and do not
interpolate. An empty list draws black.
_Avoid_: lamp, light source, colour (for intensity)

**Sun**:
The Directional Light that casts the shadow. If a Scene names two, the
first one is the Sun. With none, nothing casts a shadow.
_Avoid_: main light, key light, shadow light

**Camera**:
The field of a Scene that says where the eye is, what it looks at, which way
is `up` and the vertical field of view. The game decides it. The host
interpolates it. The camera package in `packages/camera/` builds one.
_Avoid_: view (the call), viewport, camera target

**Cursor**:
The field of a Scene that says if the mouse is `Free` or `Locked`. It is a
state, not a Command. The host locks or frees the mouse only when it changes.
The debug camera forces `Locked`.
_Avoid_: mouse mode, cursor command, grab

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
A number the engine assigns to each mesh it loaded, published in a Manifest
and carried on Draws. Id 0 is the fallback mesh. An id from an unloaded
pack is stale and draws the fallback mesh.
_Avoid_: mesh handle (the engine's internal GPU handle), mesh name, asset id

**Manifest**:
The name-to-id list the host hands `loaded` for one Pack. It holds every name
the Load asked for. A name that did not load has id 0. The game keeps the
ids it needs in its Model.
_Avoid_: mesh table, catalogue, registry, asset list

**Pack**:
A named set of assets that load and unload together. A game names its
assets in Roc and sends Load. Any number of packs can be loaded at once, and
each unloads by name in any order. An asset named by two loaded packs loads
once, keeps one id, and unloads with its last pack. A pack is a list of
names, not a directory. `docs/adr/0003-packs-own-asset-lifetimes.md`
records the decision.
_Avoid_: level, bundle, asset group, scene, chunk (a game's word for what a
pack can hold)

**Mesh table**:
The engine's table from mesh id to GPU resources. The game never sees it; it
sees a Manifest.
_Avoid_: manifest, asset store, resource cache

**Fallback mesh**:
The mesh at id 0, drawn for any id the engine does not know. A magenta cube:
a typo is visible, not fatal.
_Avoid_: default mesh, error mesh, placeholder, missing mesh

**Primitive**:
A mesh the engine builds itself rather than loads: the cube, the sphere and
the plane. They load at startup, belong to no Pack and never unload. They
are named with a `primitive/` prefix, such as `primitive/cube`. A loaded
asset takes its bare file stem.
_Avoid_: built-in, shape, basic mesh

**Primitive tag**:
A tag of `Primitive : [Cube, Sphere, Plane]` in the mesh package
(`packages/mesh/`). `Mesh.primitive` resolves one to its mesh id. Today it
reads the ids from Config; task `jw0tlmqt` decides the source once Config
carries no ids. It belongs to the package, not the vocabulary: Draws still carry
a `U32`.
_Avoid_: mesh enum, mesh name, primitive id

## Time

**Fixed step**:
One advance of the simulation by the fixed interval. The host calls `step`
then `view` once per fixed step. A frame runs zero or more of them.
_Avoid_: tick, update, iteration, frame, sim step

**Frame**:
One display refresh: one sokol frame callback, zero or more fixed steps, one
render.
_Avoid_: step, tick, render pass

**Frame render**:
The host module that turns the previous Scene, the current Scene and the
Alpha into one submitted draw per Draw. It manages the Pairing.
_Avoid_: renderer, draw loop, presenter, scene renderer

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
A value that says do this once. `step` returns them; the host runs each one
in list order after `step` and before `view`. `init` returns them too.
`Quit`, `Load` and `Unload` are the Commands; spawn, destroy and play a
sound may follow. The host binds no key to `Quit`; a game binds `Escape`
itself. Reserved for things a description cannot say.
_Avoid_: description, effect, action, message, event

**Load**:
The Command `Load({ pack, assets })`. The host loads each named asset that is
not loaded yet, then calls `loaded` with the pack name and the Manifest. A
Load for a loaded pack, or a second Load of one pack in one step, logs once
and does nothing.
_Avoid_: open, import, preload

**Unload**:
The Command `Unload(pack)`. The host drops the pack and unloads each asset
that no other loaded pack holds. An Unload for an unknown pack logs once and
does nothing. A swap sends it from a step after `loaded`.
_Avoid_: close, free, release

**Contact**:
A fact the host computes from the previous Scene: two Colliders overlapped,
with the normal and depth that separate them. The game decides what a contact
means; the engine never does.
_Avoid_: collision (the game's response), hit, overlap event, trigger

**Contacts**:
The list of Contacts the host hands `step`, one per overlapping pair, in id
order. Not part of Input, which is what the person did.
_Avoid_: collision list, events, physics state

**Collider**:
A shape with a draw id that a game returns in its Scene so the host can find
its Contacts. The shape is a tag union of box, sphere and capsule. The host
does not test capsules yet. An entity with no Collider touches nothing.
_Avoid_: hitbox, body, rigidbody, bounds

## Memory lifetimes

**Permanent**:
The lifetime of the program: renderer, input, config.
_Avoid_: global, static, forever

**Asset lifetime**:
The lifetime of one asset loaded from disk, such as a mesh or a sky: from
the first Pack that names it to the unload of the last one. Its GPU
resources belong to it. It never holds entities; those live in the Model.
_Avoid_: level, scene, world, map, stage

**Frame**:
The lifetime of one frame: scratch that dies when the frame ends.
_Avoid_: temp, transient, per-tick

**Roc heap**:
The host allocator behind roc_alloc, roc_dealloc and roc_realloc. Its
tracking allocator records every size, because roc_realloc carries no old
size.
_Avoid_: Roc allocator, host heap, seam heap
