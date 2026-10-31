# rocco

rocco is a game engine written in Odin that hosts games written in Roc. The
two meet at a seam of five pure functions, and this glossary fixes the words
on both sides of it. `docs/DESIGN.md` decides meaning; `docs/GLOSSARY.md`
explains the general graphics and memory concepts the engine is built from.

## The two sides

**Engine**:
The Odin code that manages the window, the clock, input, the GPU and memory.
It is the whole of the non-Roc half.
_Avoid_: runtime, backend, native side, C side

**Host**:
The engine seen from the seam: the party that calls `launch`, `init`,
`step`, `loaded` and `view`, owns the one pointer to the Model, and drops
it at shutdown. Same code as the engine; say "host" when the sentence is about the
seam.
_Avoid_: script host, runtime

**Platform**:
The Roc platform package every game builds on: the vocabulary types, the
binding of `Model`, the boxed wrappers, and the host they link against. There
is exactly one.
_Avoid_: SDK, framework, engine API

**Game**:
A Roc app built on the platform. It declares `Model` and defines `launch`,
`init`, `step`, `loaded` and `view`. "App" is Roc's word for the file kind;
"game" is what it is.
_Avoid_: script, scripting, application code, client

**Seam**:
The boundary between game and engine. Only plain values cross it: facts go in
through `launch`, `init`, `step` and `loaded`, and decisions come out as a
Launch, a Scene and Commands. Nothing effectful crosses in either direction.
_Avoid_: API, FFI boundary, scripting API, bridge

**Game calls**:
What the host calls on the game: the five calls, and `drop_model`, the
platform export that frees the Model at shutdown. The Seam reaches them
through a struct of procedures, so a fake game can stand in for the Roc app
in tests.
_Avoid_: callbacks, vtable, bindings

**Glue**:
The generated Odin bindings for the vocabulary, produced by `roc glue` from
the spec in the `glue/` submodule. Never written by hand.
_Avoid_: bindings, FFI header, ABI file

## The five calls

**launch**:
The game's function from Config to a Launch. Called once, before `init` and
before the window opens.
_Avoid_: setup, start, conf, boot, configure

**init**:
The game's function from Config to a record of the Model and a list of
Commands. Called once, at startup. Its Commands can load the first Pack.
_Avoid_: setup, start, new

**step**:
The game's function from Model, Input, QueryResults and dt to a record of
the next Model and a list of Commands. Called once per fixed step. Pure: the
same Model, Input and QueryResults give the same Model and Commands.
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
The types that cross the seam: Config, Launch, Input, QueryResults, Scene and
Command. They are the engine's public API. Nothing in them names a game. Games import
them, and the records inside them, from `pf.Vocabulary`.
_Avoid_: protocol, schema, contract, ABI

**Vocabulary change**:
Any edit to Config, Launch, Input, QueryResults, Scene or Command. It rebuilds
the host and every game.
Adding an asset, an entity kind or a game rule is never one.
_Avoid_: breaking change, API change

**Config**:
What the host gives `launch` and then `init`, the same value both times: a
seed, the Args and the asset names found on disk, with no ids. Tests start
from `pf.Config.empty`.
_Avoid_: settings, options, init args, environment

**Launch**:
What the game decides once before the window opens: its window, its step
rate, its shadow map size and its capacities. The host reads it before
`init` and never again. A game starts from `pf.Launch.default`.
_Avoid_: settings, options, project file, conf, window config

**Args**:
The words after the game's name on the command line, in the order typed, as
a list of strings in Config. The host does not parse them; what they mean is
the game's decision.
_Avoid_: flags, options, parameters, argv

**Seed**:
The number in Config that starts the game's randomness. The game keeps a
generator state in its Model; the same seed and the same Inputs give the same
run. The host reads it from `ROCCO_SEED`, default 0.
_Avoid_: random seed, RNG, salt

**Input**:
What the host gives `step` each fixed step: the keys held, the keys pressed
since the previous step, the mouse delta, one Gamepad for each connected
pad, the window size in logical pixels and the Pointer. Key codes are
sokol's; which key means what is the game's decision.
Tests start from `pf.Input.empty`.
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

**Gamepad**:
One connected pad in `Input.gamepads`, at one step: its Gamepad slot, the
Buttons held and pressed, two sticks inside the unit disc with +y up, and
two triggers from 0 to 1. The host applies the dead zones; the Bridge
applies none. At most 4.
_Avoid_: Pad (it can mean padding), controller, joystick

**Button**:
A gamepad button named by its place on the pad, from `pf.Button`, such as
`South` for the bottom face button. Not its label: `South` is A on Xbox,
Cross on PlayStation and B on Switch. A Gamepad carries the code. The
triggers are not Buttons.
_Avoid_: key, face button label (A, Cross), action

**Gamepad slot**:
A Gamepad's number, from 0 to 3. A pad keeps its slot while it stays
connected, and a new pad takes the lowest free slot. A game tells players
apart by slot. Not the Slot of a Query.
_Avoid_: player index, port, controller id, XInput index

**Scene**:
What `view` returns each fixed step: a Camera, a list of root Nodes, a
Cursor, a sky id, a clear colour, the UI and a list of Queries. It
describes what should be on screen now and what can touch. Derived from the
Model, rebuilt every step, stored by the host and never by the game. Its
Nodes form a tree, but the host keeps no Node from one Scene to build the
next.
A game starts from `pf.Scene.empty` and sets only the fields it decides.
_Avoid_: world, level, frame, render state, render list, scene graph

**Node**:
One part of the Scene's 3D tree: a Group, which holds its children, or a
leaf, which is a Draw, a Light, a Collider or a Speaker. The game writes
the tags itself, such as `Group({ id, pos, rot }, [...])` and `Draw(...)`.
"First" among Nodes means first in a depth-first, pre-order walk: a Group,
then its children, then the Group's next sibling. That is the order the
game wrote them, read top to bottom.
_Avoid_: scene node, game object, entity, object

**Group**:
A Node that carries a Group id and a Pose, and holds a list of child Nodes.
Its children's Poses are local to it: they inherit its position and rot,
never a scale. It draws nothing itself. The host interpolates it and pairs
it by its Group id, up to `Launch.capacity.groups` Groups per Scene.
_Avoid_: parent, frame (a display refresh), transform, pivot, container, entity

**Pose**:
A position and a rot. A Node's Pose is local to its Group, or to the world
at the root; its world Pose composes every Group above it.
`Pose.compose` and `Pose.relative` in `packages/linalg` use the rule that the
host uses.
_Avoid_: frame, transform, matrix, placement

**Draw**:
A leaf Node: a draw id, a mesh id, a position, scale, rot, scale_rot, tint,
glow and Pose, local to its Group or to the world at the root.
The scale acts along the axes of scale_rot, then rot turns the result.
It is a description, not a command. `rot` is a unit quaternion. The host
interpolates it between two Scenes. A game starts from `pf.Draw.default`.
_Avoid_: sprite, renderable, instance, draw call (the GPU term), object

**Tint**:
The colour of a Draw, as an `Rgb` record with linear channels from 0 to 1.
The host multiplies the mesh colour by it. A Light colour or a Glow can
exceed 1; a tint cannot.
_Avoid_: colour (for the field), albedo, Vec3 colour

**Glow**:
The light that a Draw's surface gives off, in `Draw.glow`, as a linear
`Rgb` that can exceed 1. The host adds it to the mesh's Emissive after the
lights and before the tone map, so it shows in the dark. It lights no other
surface; a Point Light beside the Draw does that.
_Avoid_: emission (for the field), bloom, self-illumination, a tint above 1

**Emissive**:
The light that a glTF material gives off: `emissiveFactor`, times
`emissiveTexture`, times `KHR_materials_emissive_strength`. A mesh has one,
from its first part. A Draw's Glow adds to it. It lights no other surface.
_Avoid_: glow (for the material), emission map

**Rgba**:
A colour with alpha, as linear channels from 0 to 1. Alpha is not
premultiplied. UI colours use it; a Tint stays `Rgb`.
_Avoid_: colour with opacity, Vec4

**Light**:
A leaf Node: `Ambient`, `Directional` or `Point`. Its colour
is a linear `Rgb` that carries intensity, so a channel can exceed 1. A
Directional `dir` is the way the light travels. A Point light falls off to
zero at its `range`. `pf.Light` builds each one. Lights have no id. A Light
follows its Group's interpolated Pose but does not interpolate its own.
A Group turns a Directional `dir` and moves a Point; an Ambient ignores it.
A Scene with no Light draws black.
_Avoid_: lamp, light source, colour (for intensity)

**Sun**:
The first Directional Light, in Node order, that sets `shadow`. It is the only Light that
casts a shadow. `pf.Light.sun` sets `shadow` and `pf.Light.directional` does
not. If a second Directional sets it, the host logs once. With no Sun,
nothing casts a shadow.
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

**Pointer**:
The position, the buttons and the wheel of the mouse in Input, as
`Input.pointer`. The position is in logical window pixels, with the origin
at the top left. It is not inside while the pointer is outside the window
or the Cursor is `Locked`. `pf.MouseButton` names the button codes. The
mouse delta in Input is for mouse look; the Pointer is for pointing at the
UI.
_Avoid_: cursor (the lock), mouse (the delta), touch

**Clear colour**:
The field of a Scene, `clear`, that sets the colour behind the 3D view. It is
a linear `Rgb`. The host clears to it every frame, before any mesh, and
encodes it to sRGB without the tone map. A sky draws over it. `pf.Scene.empty`
has black.
_Avoid_: background, clear color, sky colour

**UI**:
The field of a Scene that lists the root Elements drawn flat over the 3D
view. It is a Description: rebuilt every step, drawn from the current Scene
only, never interpolated. The UI is a tree, but it is still a Description and
not a retained scene graph: the host keeps no Element from one step to the
next. Sizes are in logical pixels. The layout fits the Elements to the
window; the game reads the window size from Input. After the layout, the
host sends back only the tagged Boxes under the Pointer and the sizes of
the Scroll Boxes, in QueryResults. "HUD" is a game's word for what its UI
shows.
_Avoid_: HUD (in the engine), overlay, GUI, canvas, widget tree

**Element**:
One part of the UI tree: a Box, which holds its children, or a Text. The
game writes the tags itself, `Box(config, [...])` and `Text(...)`. An
Element's identity is its place in the tree. The tree crosses the seam as
it is; it is not flattened into a list.
_Avoid_: widget, Node (the 3D tree), control, view (the call), parent index

**Box**:
An Element that is a rectangle and holds a list of child Elements. Its
config carries its Hit id, sizing, padding, gap, direction, child
alignment, background, corner radius and Overflow, and its type is
`BoxConfig`. A floating Box puts one of its points on a point of the
window or of its parent Box, and ignores its parent's layout.
_Avoid_: panel, div, container, frame

**Hit id**:
The `id` of a Box. A Box with a non-zero id is tagged: the host hit tests it
and lists it in `QueryResults.ui`. 0 is not tagged. A floating Box that
holds a tagged Box blocks the Pointer from the Boxes under it.
_Avoid_: element id, key, name

**Overflow**:
What a Box does with children that reach past its edges: `Visible` draws
them, `Clip` cuts them at the edges, and `Scroll` cuts them and moves them
by an offset from the Scene. The game owns the offset.
_Avoid_: scroll view, viewport, mask

**Text**:
An Element that draws one string in the engine's font, at a size and colour.
The layout measures it. A game that must choose what to show measures it
first with `Ui.measure`, `Ui.fit` or `Ui.wrap`, which use the host's numbers.
_Avoid_: label, string, glyph run

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

**Group id**:
A stable number on a Group that pairs it with its predecessor, as a draw id
pairs Draws. Group ids and draw ids are apart: an entity's Group and its
Draw can both carry the entity id. If two Groups share an id, the first
pairs and the host logs once.
_Avoid_: parent id, node id, draw id

**Mesh id**:
A number the engine assigns to each mesh it loaded, published in a Manifest
and carried on Draws. Id 0 is the fallback mesh. An id from an unloaded
pack is stale and draws the fallback mesh.
_Avoid_: mesh handle (the engine's internal GPU handle), mesh name, asset id

**Manifest**:
The name-to-id list the host hands `loaded` for one Pack. It holds every name
the Load asked for. A name that did not load has id 0. A skinned mesh's
entry also lists its Clips. The game keeps the ids it needs in its Model.
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
(`packages/mesh/`). `Mesh.primitive` resolves one to its fixed mesh id:
cube 1, sphere 2, plane 3. It needs no Config and no Pack. It belongs to the package, not the vocabulary: Draws still carry
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
Alpha into one submitted draw per Draw, then draws the current Scene's UI.
It manages the Pairing.
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
in list order after `step` and before `view`, except that a Play starts
after `view`. `init` returns them too.
`Quit`, `Load`, `Unload` and `Play` are the Commands; spawn and destroy may
follow. The host binds no key to `Quit`; a game binds `Escape`
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
A fact the host computes from the previous Scene for a ContactsOf Query: two
Colliders overlapped, with the normal and depth that separate them. The game decides what a contact
means; the engine never does.
_Avoid_: collision (the game's response), hit, overlap event, trigger

**Contacts**:
The `contacts` list in QueryResults: each overlapping pair that involves an
owner of a ContactsOf Query, once, in id order. With no ContactsOf Query,
the host finds no Contacts. Not part of Input, which is what the person did.
_Avoid_: collision list, events, physics state

**Collider**:
A leaf Node: a shape with a draw id, a position and a rot, that Queries can
test. The position and rot are local to its Group. The host tests it at its
world Pose, composed from the current Scene, and does not interpolate it. The shape is a tag
union of box, sphere and capsule. The host does not test capsules yet. The host finds Contacts only for a ContactsOf Query.
An entity with no Collider touches nothing.
_Avoid_: hitbox, body, rigidbody, bounds

## Queries

`docs/adr/0005-queries-ask-the-engine.md` records the decision.

**Query**:
A value in `Scene.queries` that asks the engine about the Colliders:
`ContactsOf`, `Raycast` or `Overlap`. The host answers it against this Scene
and gives the result to the next `step`. A Query asks; a Command tells. It
is not Bevy's ECS query.
_Avoid_: request, question, Answer, Event

**Owner**:
The draw id that a Query belongs to. The host skips the owner's own
Collider. An owner and a slot link a result to its Query.
_Avoid_: source, caller, query id

**Slot**:
A number that tells apart the Raycast or Overlap Queries of one owner. Two
Queries of one kind with the same owner and slot: the host keeps the first.
Not the Gamepad slot.
_Avoid_: index, channel, query id

**QueryResults**:
What the host gives `step` each fixed step: the record `{ contacts, rays,
overlaps, ports, ui }`, with one flat list for each kind of Query. A miss
has no row. `ui` needs no Query: it holds the tagged Boxes under the Pointer
and the sizes of the tagged Scroll Boxes, from the layout the window last
showed. The first step gets empty QueryResults.
_Avoid_: Answer, Answers, Result, Response, Event

**RayHit**:
One row in `QueryResults.rays`: the nearest Collider that a Raycast hit, with
the owner and slot of its Query.
_Avoid_: Answer, Result, Response, Event, hit

**OverlapHit**:
One row in `QueryResults.overlaps`: one Collider that an Overlap touched,
with the owner and slot of its Query.
_Avoid_: Answer, Result, Response, Event, overlap event

## Sound

**Sound**:
An asset that holds audio, loaded and unloaded by a Pack. It is named with
a `sound/` prefix, such as `sound/jump`. The game never touches its
samples; it sees a Sound id.
_Avoid_: clip (an animation word), sample, audio file, track, sfx

**Sound id**:
A number the engine assigns to each Sound it loaded, published in a
Manifest with the Sound's duration and carried on a Play or a Speaker. Id 0,
or an id from an unloaded pack, plays nothing and logs once.
_Avoid_: sound handle, voice, Speaker id

**Play**:
The Command that starts one Sound once. Nothing pairs it and the game
cannot stop it; it plays to its end, or until its pack unloads. The host
starts it after the `view` of the same fixed step, so it sounds from the
Listener of that Scene. A sound the game must stop, or one that follows a
moving object, is a Speaker.
_Avoid_: one-shot (in the vocabulary), trigger, emit, sfx

**Speaker**:
A Node that plays a Sound while it stays in the Scene. Its `repeat` is
`Loop` or `Once`; a `Once` that ends stays silent until it leaves. A new
Speaker id starts it and a missing one stops it. A changed gain, pitch or
place applies on the next fixed step; a changed Sound id restarts it. It
takes its place from the Groups above it. It is a Description (ADR 0017).
Music that repeats is a Speaker.
_Avoid_: emitter, source, track, channel, voice, audio player

**Speaker id**:
A stable number on a Speaker that pairs it with the Speaker of the previous
Scene anywhere in the tree. Apart from draw ids and Group ids.
_Avoid_: Sound id, voice id, Loop id

**Listener**:
The ear for a Play or a Speaker placed at a point: the Camera of the current
Scene, not the interpolated one. A Sound placed `Here` plays at the
Listener with no direction.
_Avoid_: microphone, audio camera, ears

**Place**:
Where a Play or a Speaker sounds: `Here` or `At`. It is their `at` field.
A Play's `At` is in the world. A Speaker's `At` is local to its Group, as a
Draw's `pos` is.
_Avoid_: position, location, spatial mode

**Here**:
The Place at the Listener, with no direction and no falloff. `Sound.play`
and `Speaker.default` use it. A `Here` Speaker ignores its Group, as an
Ambient Light does.
_Avoid_: 2D, non-spatial, global, unplaced

**At**:
The Place `At({ pos, range })`: a point. The gain falls off
linearly from full at the Listener to zero at `range`, as a Point Light
does, and pans to the side the point is on. A range of 0 or less is silent.
_Avoid_: 3D, positional, spatial, emitter

**Voice**:
One Play or one Speaker that sounds now. The voice capacity in Launch caps
how many sound at once. When the voices are full, a Play takes the voice of
the oldest Play, and a new Speaker waits silent for a free voice.
_Avoid_: channel, source, instance, Sound

## Animation

**Skin**:
The Joints of a skinned mesh and the inverse bind matrix of each. A .glb
holds at most one Skin, with at most 64 Joints. A skinned mesh with no
Clip named draws in its bind pose.
_Avoid_: skeleton, armature (the Blender term), rig

**Joint**:
One node of a Skin. The host poses each Joint and moves the vertices
weighted to it.
_Avoid_: bone

**Clip**:
One entry in the `animations` array of a skinned .glb: named, timed keys
for the Joints of its Skin. A Clip loops only if the game wraps its time.
_Avoid_: animation (the feature, or a value the Model moves each step),
action (the Blender term), track

**Clip id**:
A number the engine assigns to each Clip it loaded, published in the
Manifest entry of its mesh with the Clip's name and duration. Ids are unique
across a Pack. Id 0 is no Clip.
_Avoid_: animation index, clip handle

**Pose**:
The `pose` field of a Draw: a Clip and its time, a fade Clip and its time,
and the fade weight from 0 to 1. The Model owns every value. The host
samples both Clips and mixes them by the fade.
_Avoid_: anim, animation state, blend tree

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
The host allocator behind roc_alloc, roc_dealloc and roc_realloc. A header
before each block records its size, because roc_realloc carries no old size.
_Avoid_: Roc allocator, host heap, seam heap

## Benchmarks

**Lockstep**:
A run mode in which each Frame runs exactly one fixed step and one render,
whatever the wall-clock time. The same run always does the same work.
Under the Bridge it pauses: a Frame runs zero fixed steps while the Driver
has asked for none.
_Avoid_: fixed mode, deterministic mode, frame lock

**Headless**:
A run with no window and no GPU: the host calls the game and runs the
queries, but renders nothing. It always runs in lockstep.
_Avoid_: offscreen, no-render, server mode

**Bench game**:
A game that exists only to stress one axis, such as Draw count or Collider
count, while every other axis stays fixed.
_Avoid_: stress test, benchmark example, perf game

**Odin twin**:
An Odin stand-in for one bench game, behind the same Game calls, with the
same logic and the same Model layout. It isolates the cost of the seam.
_Avoid_: native version, baseline game, control

**Span**:
One named, timed section of a Frame, such as the step span or the render
submit span. A build has Spans only when it asks for them.
_Avoid_: phase, section, lap, timer

## The Bridge

**Bridge**:
The host module that lets one outside process drive a run over a localhost
socket. It injects Input, advances fixed steps on request and reports what
the host sees. The game does not know it exists, and nothing in the
Vocabulary names it.
_Avoid_: debug server, remote, Seam, port, debugger

**Driver**:
The outside process at the other end of the Bridge: a script, a CI test or
an agent. One Driver at a time. While a Driver controls the run, the host
ignores the real keyboard, mouse and gamepads, unless the Driver turns
devices on in hello.
_Avoid_: client, controller, bot, harness

**Port**:
A named channel between the game and a Driver or an extension. The game
names it with a `Str`. The socket port in `ROCCO_BRIDGE` is not a Port.
_Avoid_: channel, topic, event, subscription

**Tell**:
A Command that sends a message to a Port. The host does not act on it; a
Driver reads it in the `step` reply.
_Avoid_: publish, emit, send event

**Listen**:
A Query that asks for the messages sent to a Port since the last step. The
game puts it in `Scene.queries` every step for each Port it reads.
_Avoid_: subscription, subscribe, topic
