# rocco

rocco is a game engine written in Odin that hosts games written in Roc. This
glossary fixes the words on both sides of the seam between them. It says what
each term is; `docs/DESIGN.md` and the ADRs say how it behaves, and
`docs/CONCEPTS.md` explains the general graphics and memory concepts.

## The two sides

**Engine**:
The Odin code that runs the window, the clock, input, the GPU and memory: the
whole of the non-Roc half.
_Avoid_: runtime, backend, native side, C side

**Host**:
The engine seen from the seam: the party that calls the five calls and owns
the one pointer to the Model.
_Avoid_: script host, runtime

**Host assembly**:
The host module that builds the host from a Launch and the Game calls before
the window opens, with a window or Headless. A run and the tests both use it.
_Avoid_: bootstrap, setup, wiring, factory

**Platform**:
The one Roc platform package every game builds on: the Vocabulary, the
binding of `Model`, and the host it links against.
_Avoid_: SDK, framework, engine API

**Game**:
A Roc app built on the platform that declares `Model` and defines the five
calls. "App" is Roc's word for the file kind; "game" is what it is.
_Avoid_: script, scripting, application code, client

**Seam**:
The boundary between game and engine, which only plain values cross: facts go
in, and a Launch, a Scene and Commands come out.
_Avoid_: API, FFI boundary, scripting API, bridge

**Game calls**:
The struct of procedures through which the host reaches the five calls and
`drop_model`, so a fake game can stand in for the Roc app in tests.
_Avoid_: callbacks, vtable, bindings

**Glue**:
The Odin bindings for the Vocabulary that `roc glue` generates. Never written
by hand.
_Avoid_: bindings, FFI header, ABI file

## The web

**Web build**:
A game built to run in a browser page through WebGPU, from the same source as
a native build.
_Avoid_: wasm build, browser port, HTML5 build

**Page**:
The HTML document that loads a Web build and shows everything outside the
canvas. A game that supplies none gets the **Default page**.
_Avoid_: web shell, shell, HTML wrapper, index, stock page, template

**Site**:
rocco's public website: its landing page, the Guide, the Tour, the API
reference and the roadmap. The devlog is not part of it. Its landing page is
not a **Page**.
_Avoid_: docs site, homepage, project page

**Tour**:
The interactive, in-browser form of the Tutorial, where a reader edits a
game's source beside the lesson text and runs it in a Preview, with assets
only the Tour supplies.
_Avoid_: playground, sandbox, interactive guide

**Tour step**:
One screen of the Tour, made from one Tutorial page: its lesson text, a
Starting source and an Answer.
_Avoid_: lesson, page, chapter

**Starting source**:
The game source a Tour step opens with: the app the previous page ends with.
_Avoid_: template, scaffold

**Answer**:
The game source a Tour step shows on Show answer: the app its Tutorial page
ends with.
_Avoid_: solution

**Preview**:
The part of a Tour step that runs the reader's game, interpreted rather than
compiled. It is not a Web build.
_Avoid_: game window, output, canvas, Web build

**Tour host**:
The web host a Preview runs, which runs the game through Roc's interpreter.
_Avoid_: playground host, interpreter host

**Preview loader**:
The engine script in a Preview that takes each lowered game from the Tour page
and starts or hot reloads the Tour host.
_Avoid_: Tour bridge, shim

**Hot reload**:
A Run that gives the running Preview a new game and keeps its Model.
_Avoid_: hot swap, live reload

**Baseline image**:
The first game image a Preview starts with. A later image hot reloads only if
its identity matches this one.
_Avoid_: base image, last image, baseline

**Build id**:
The id one CI build writes into both its Compile worker and its Tour host, so
a Preview can refuse a pair from different builds.
_Avoid_: version, FORMAT_VERSION, build number

**Compile worker**:
The part of the Tour page that checks the reader's game and lowers it for the
Tour host.
_Avoid_: compiler service, build server

**Source bundle**:
The platform and package source files the compile worker reads, for one pinned
engine release.
_Avoid_: asset pack, Pack

**Tour artifacts**:
The compile worker, the Source bundle and the Preview folder that one engine
release ships, from one build with one build id.
_Avoid_: Tour bundle, Tour pack

## The five calls

**launch**:
The game's function from Config to a Launch, called once before the window
opens.
_Avoid_: setup, start, conf, boot, configure

**init**:
The game's function from Config to the first Model and a list of Commands.
_Avoid_: setup, start, new

**step**:
The game's pure function from Model, Input, QueryResults and dt to the next
Model and a list of Commands, called once per Fixed step.
_Avoid_: tick, simulate, advance, update (the game's Stage pipeline)

**loaded**:
The game's function from Model, a pack name and a Manifest to Model. It is the
only promise that ids exist.
_Avoid_: on_load, ready, callback

**view**:
The game's function from Model to Scene, called once per Fixed step after
`step`.
_Avoid_: render, draw, extract, present

**Stage**:
One function from Model to Model in the game's `update` pipeline. The order of
the stages is the schedule.
_Avoid_: system, pass, phase

## The Vocabulary

**Vocabulary**:
The types that cross the seam, from `pf.Vocabulary`: Config, Launch, Input,
QueryResults, Scene and Command. They are the engine's public API.
_Avoid_: protocol, schema, contract, ABI

**Vocabulary change**:
Any edit to a Vocabulary type, which rebuilds the host and every game. A new
asset, entity kind or game rule is never one.
_Avoid_: breaking change, API change

**Config**:
What the host gives `launch` and `init`: the Seed, the Args and the asset
names found on disk.
_Avoid_: settings, options, init args, environment

**Launch**:
What the game decides once before the window opens, such as its window, step
rate and capacities.
_Avoid_: settings, options, project file, conf, window config

**Args**:
The words after the game's name on the command line, as a list of strings in
Config. Their meaning is the game's decision.
_Avoid_: flags, options, parameters, argv

**Seed**:
The number in Config that starts the game's randomness.
_Avoid_: random seed, RNG, salt

**Model**:
The one value that is the game, whose type the game declares and the host
never reads inside.
_Avoid_: State, game state, script state, world, save

**Entity**:
A record with an explicit id that a game keeps in its Model. The engine has no
entity type, and a game may have no entities.
_Avoid_: game object, GameObject, body, node, actor

## Input

**Input**:
What the host gives `step` each Fixed step about what the person did: keys,
mouse, Gamepads, window size and the Pointer.
_Avoid_: events, controls, actions, commands

**Key**:
A named sokol key code, such as `W`, from `pf.Key`. What the key means is the
game's decision.
_Avoid_: keycode, button, action

**Held**:
A key that is down at this step: a state.
_Avoid_: down, level, pressed

**Pressed**:
A key that went down since the previous Fixed step: an edge, seen in exactly
one Input.
_Avoid_: held, down, just pressed, triggered, edge

**Gamepad**:
One connected pad in `Input.gamepads` at one step.
_Avoid_: Pad (it can mean padding), controller, joystick

**Gamepad button**:
A button of a Gamepad named by its place on the pad, such as `South`, not by
its label.
_Avoid_: key, face button label (A, Cross), action, ui.Button (the UI widget)

**Gamepad slot**:
A Gamepad's number from 0 to 3, which it keeps while connected. Not the Slot
of a Query.
_Avoid_: player index, port, controller id, XInput index

**Gamepad reader**:
The host code for one OS that reads its pads into Gamepads each Frame.
_Avoid_: driver (a Bridge client), backend, input plugin

**Pointer**:
The mouse's position, buttons and wheel in `Input.pointer`, for pointing at
the UI. The mouse delta is for mouse look.
_Avoid_: cursor (the lock), mouse (the delta), touch

**Cursor**:
The Scene field that says if the mouse is `Free` or `Locked`: a state, not a
Command.
_Avoid_: mouse mode, cursor command, grab

## The Scene

**Scene**:
What `view` returns each Fixed step: the Description of what is on screen now
and what can touch.
_Avoid_: world, level, frame, render state, render list, scene graph

**Node**:
One part of the Scene's 3D tree: a Group or an Attach, which holds children,
or a leaf: a Draw, a Light, a Collider, a Speaker or an Emitter.
_Avoid_: scene node, game object, entity, object

**Group**:
A Node with a Group id and a Pose that holds child Nodes local to it. It draws
nothing itself.
_Avoid_: parent, frame (a display refresh), transform, pivot, container, entity

**Attach**:
A Node that holds child Nodes local to one Joint of a Draw's Skin. See ADR 0034.
_Avoid_: socket, bone attachment, mount, parent

**Pose**:
A position and a rot, local to the parent Group or to the world at the root.
_Avoid_: frame, transform, matrix, placement

**Draw**:
A leaf Node that shows one mesh: a description, not a draw call.
_Avoid_: sprite, renderable, instance, draw call (the GPU term), object

**Tint**:
The colour of a Draw, which multiplies its mesh colour and never exceeds 1.
_Avoid_: colour (for the field), albedo, Vec3 colour

**Glow**:
The light a Draw's surface gives off, in `Draw.glow`. It adds to the mesh's
Emissive and lights no other surface.
_Avoid_: emission (for the field), bloom, self-illumination, a tint above 1

**Emissive**:
The light a glTF material gives off, one per Mesh part.
_Avoid_: glow (for the material), emission map

**Light**:
A leaf Node: `Ambient`, `Directional` or `Point`. A Scene with no Light draws
black.
_Avoid_: lamp, light source, colour (for intensity)

**Emitter**:
A leaf Node that the host turns into particles: smoke, dust or sparks. The
game never reads a particle.
_Avoid_: source, particle system, effect

**Particle**:
One billboard that an Emitter spawns. It lives in the world after it spawns.
_Avoid_: sprite, quad, Draw

**Sun**:
The first Directional Light that sets `shadow`: the only Light that casts a
shadow.
_Avoid_: main light, key light, shadow light

**Camera**:
The Scene field that says where the eye is and what it looks at.
_Avoid_: view (the call), viewport, camera target

**Environment**:
The Scene field that sets the look of the 3D view: sky, clear colour, tone
map, exposure, fog and bloom. See ADR 0026.
_Avoid_: look, post settings, render settings

**Sky blend**:
The Environment field that blends the sky and its light toward a second sky
by an amount.
_Avoid_: sky fade, sky transition, skybox lerp

## The UI

**UI**:
The Scene field that lists the root Elements drawn flat over the 3D view. It
is a Description, never interpolated. "HUD" is a game's word for what it shows.
_Avoid_: HUD (in the engine), overlay, GUI, canvas, widget tree

**Element**:
One part of the UI tree: a Panel or a Text. Its identity is its place in the
tree.
_Avoid_: widget, Node (the 3D tree), Ui.Node (the package tree), control, view (the call), parent index

**Panel**:
An Element that is a rectangle and holds child Elements.
_Avoid_: Box (a collider shape), div, container, frame

**Hit id**:
The `id` of a Panel. A Panel with a non-zero id is tagged, and the host hit
tests it.
_Avoid_: element id, key, name

**Overflow**:
What a Panel does with children past its edges: `Visible`, `Clip` or `Scroll`.
_Avoid_: scroll view, viewport, mask

**Text**:
An Element that draws one string in the engine's font.
_Avoid_: label, string, glyph run

**Ui.Node**:
The UI tree of `packages/ui`, with the shape of an Element. `Node.build` turns
it into an Element.
_Avoid_: Element (for the package tree), widget tree

**Widget**:
A pure Roc helper module of `packages/ui`, such as a button, whose state lives
in the Model. It is not Vocabulary.
_Avoid_: control, component

**Focus**:
Which tagged Panel the keys act on, kept in the Model by `packages/ui`. Not the
window's focus.
_Avoid_: selection, active element

## Ids

**Draw id**:
A stable number on a Draw that pairs it with its predecessor in the previous
Scene. Under ADR 0045 it is optional.
_Avoid_: handle, key, index, entity id (when the draw is scenery)

**Group id**:
A stable number on a Group that pairs it as a Draw id pairs a Draw. Group ids
and Draw ids are apart.
_Avoid_: parent id, node id, draw id

**Emitter id**:
A stable number on an Emitter that pairs it with the Emitter of the same id
anywhere in the previous Scene. A Burst names it.
_Avoid_: source id, slot

**Position key**:
How the host pairs a Draw or Group with id 0: its nearest ancestor Group with
an id, and its index among its id-0 siblings of the same kind. See ADR 0045.
_Avoid_: path (a Prefab's Path), index, slot

**Ids**:
The opaque counter in `Id.roc` that a game keeps in its Model to make fresh
ids. See ADR 0045.
_Avoid_: id generator, allocator, registry, seed

**Mesh id**:
A number the engine assigns to each loaded mesh, published in a Manifest.
_Avoid_: mesh handle (the engine's internal GPU handle), mesh name, asset id

**Image id**:
A number the engine assigns to each loaded Image, published in a Manifest.
_Avoid_: texture id, image handle

## Assets

**Pack**:
A named list of assets that load and unload together. An asset lives from the
first loaded Pack that names it to the unload of the last. See ADR 0003.
_Avoid_: level, bundle, asset group, scene, chunk (a game's word for what a pack can hold)

**Asset name**:
The name of one asset: its kind, a `/`, then its file stem, such as
`sound/jump`. See ADR 0044.
_Avoid_: path, file name, asset id, key

**Manifest**:
The name-to-id list the host hands `loaded` for one Pack.
_Avoid_: mesh table, catalogue, registry, asset list

**Mesh part**:
A share of a mesh's triangles that draws with one material.
_Avoid_: submesh, glTF primitive (a unit of the file), material slot

**Alpha mode**:
How a Mesh part's material treats alpha: Opaque, Mask or Blend, from glTF's
`alphaMode`. Not the Frame's Alpha.
_Avoid_: alpha (on its own), transparency mode, blend mode, opacity

**Fallback mesh**:
The magenta cube at Mesh id 0, drawn for any id the engine does not know.
_Avoid_: default mesh, error mesh, placeholder, missing mesh

**Primitive**:
A mesh the engine builds itself rather than loads, named with a `primitive/`
prefix, such as `primitive/cube`. It belongs to no Pack.
_Avoid_: built-in, shape, basic mesh

**Primitive tag**:
A tag of `Primitive` in `packages/mesh`, such as `Cube`, that resolves to a
Primitive's fixed Mesh id. It is not Vocabulary.
_Avoid_: mesh enum, mesh name, primitive id

**Image**:
A picture with an Image id, shown through an `Image` value. See ADR 0024.
_Avoid_: texture (the engine's GPU word), sprite, icon, picture

**Render**:
An Image that the host draws from a Scene, rather than one a Pack loads.
_Avoid_: render target, canvas, framebuffer, viewport

**Shader asset**:
A Pack asset that supplies game-authored GPU programs for the Scene's appearance.
_Avoid_: engine plugin, shader script, shader bundle

**Shader reload**:
A development update to a loaded Shader asset.
_Avoid_: game reload, Model reload

**Surface shader**:
A Shader asset that defines how a surface moves, what its normal and material
are, and how light reaches it.
_Avoid_: mesh shader, material script

**Post shader**:
A Shader asset that changes the rendered scene image at a declared stage.
_Avoid_: screen shader, post script, render pass

**Material slot**:
A named material assignment in a mesh that a game can override, owned by the
authored mesh rather than the order of Mesh parts.
_Avoid_: part index, submesh index

**Material override**:
A game-authored surface choice for a Draw or one of its Material slots.
_Avoid_: replacement mesh, shader patch

**Selection input**:
The selected geometry's coverage and nearest depth, hidden parts included, for
a Post shader to read.
_Avoid_: outline image, outline style

## Drawing

**Main pass**:
The pass that draws the Scene's mesh parts and the sky, lit, into the HDR
image.
_Avoid_: forward pass, colour pass, opaque pass

**Shadow pass**:
The pass that draws the shadow-casting mesh parts from the Sun into the shadow
map.
_Avoid_: depth pass, shadow render

**Post pass**:
The pass after the Main pass that applies exposure, the tone map, bloom and
any Post shaders, then draws the UI.
_Avoid_: post-processing, final pass, composite

## Time

**Fixed step**:
One advance of the simulation by the fixed interval: one `step` and one `view`.
_Avoid_: tick, update, iteration, frame, sim step

**Frame**:
One display refresh: zero or more Fixed steps and one render.
_Avoid_: step, tick, render pass

**Frame render**:
The host module that turns the previous Scene, the current Scene and the Alpha
into one render.
_Avoid_: renderer, draw loop, presenter, scene renderer

**dt**:
The length of this Fixed step in seconds, as the third argument to `step`.
_Avoid_: delta, elapsed, frame time

**Alpha**:
How far the display sits between the previous Scene and the current one, in
`[0, 1)`. The game never sees it.
_Avoid_: interpolation factor, t, blend, remainder

## Effects

**Description**:
A value that says what should exist now, returned every step, which the host
reconciles against the last one. A Scene is one.
_Avoid_: command, request, event

**Command**:
A value that says do this once, for what a Description cannot say: `Quit`,
`Load`, `Unload`, `Play`, `Burst`, `Tell` or `Log`.
_Avoid_: description, effect, action, message, event

**Load**:
The Command that loads a Pack's assets, after which the host calls `loaded`.
_Avoid_: open, import, preload

**Unload**:
The Command that drops a Pack.
_Avoid_: close, free, release

**Log**:
The Command that writes a line to stderr with a `game:` prefix.
_Avoid_: print, dbg (the Roc debug expression), trace, Tell

## Contacts and Queries

`docs/adr/0005-queries-ask-the-engine.md` records the decision.

**Collider**:
A leaf Node with a shape that Queries can test: a box, a sphere or a capsule.
_Avoid_: hitbox, body, rigidbody, bounds

**Contact**:
A fact the host finds for a ContactsOf Query: two Colliders overlap, with the
normal and depth that separate them. What it means is the game's decision.
_Avoid_: collision (the game's response), hit, overlap event, trigger

**Query**:
A value in `Scene.queries` that asks the engine about the Colliders:
`ContactsOf`, `Raycast` or `Overlap`. A Query asks; a Command tells.
_Avoid_: request, question, Answer, Event, ECS query (Bevy's)

**Owner**:
The Draw id that a Query belongs to.
_Avoid_: source, caller, query id

**Slot**:
A number that tells apart the Raycast or Overlap Queries of one Owner. Not the
Gamepad slot.
_Avoid_: index, channel, query id

**QueryResults**:
What the host gives `step` each Fixed step: one flat list per kind of Query,
such as `contacts` and `rays`, plus the UI hits.
_Avoid_: Answer, Answers, Result, Response, Event, RayHit list

## Same-step collision

`docs/adr/0046-same-step-collision-lives-in-roc-packages.md` records the
decision. The game asks `packages/collide` in `step`; the host takes no part.

**Solids**:
The static boxes and spheres that a character collides with in the same step,
filed once in a grid on x and z. A box turns only by a yaw. Not Colliders,
which the host tests one step late.
_Avoid_: colliders (the host's), level geometry, static bodies, obstacles

**Ground**:
A function from `x`, `z` and a height to the highest surface at or below that
height, with its normal, or a miss. Built from a flat plane, a grid of heights
or the tops of Solids.
_Avoid_: floor, terrain (one kind of Ground), heightmap, ground check

**Stick to ground**:
Keeping a walking character's foot on the Ground as it goes down a slope or a
low step, instead of letting it fall. Not Grounding.
_Avoid_: ground snap, snap down, Grounding (the host lifting a skinned Draw)

**Intent**:
What the player asks a character to do this step: a `move` direction in world
x/z, and whether jump was pressed or is held. The game builds it from Input;
`packages/controller` reads it. Not a Description.
_Avoid_: input (the host's record), command, action

**Tuning**:
The numbers that set how a character moves: speeds, turn rate, jump height,
gravity, glide, coyote time, jump buffer, step-up, slope limit and the body
size. A zero field turns off glide, coyote time, jump buffer, step-up or the
slope limit.
_Avoid_: settings, config, params

## Sound

**Sound**:
An asset that holds audio, named with a `sound/` prefix.
_Avoid_: clip (an animation word), sample, audio file, track, sfx

**Sound id**:
A number the engine assigns to each loaded Sound, published in a Manifest.
_Avoid_: sound handle, voice, Speaker id

**Play**:
The Command that starts one Sound once. The game cannot stop it.
_Avoid_: one-shot (in the vocabulary), trigger, emit, sfx

**Speaker**:
A Node that plays a Sound while it stays in the Scene: a Description. See ADR
0017.
_Avoid_: emitter, source, track, channel, voice, audio player

**Speaker id**:
A stable number on a Speaker that pairs it with the Speaker of the previous
Scene.
_Avoid_: Sound id, voice id, Loop id

**Listener**:
The ear for placed sound: the Camera of the current Scene.
_Avoid_: microphone, audio camera, ears

**Place**:
Where a Play or a Speaker sounds: `Here`, at the Listener with no direction,
or `At` a point, with falloff and pan.
_Avoid_: position, location, spatial mode, 2D, 3D

**Voice**:
One Play or Speaker that sounds now. Launch caps how many.
_Avoid_: channel, source, instance, Sound

## Animation

**Skin**:
The Joints of a skinned mesh and the inverse bind matrix of each.
_Avoid_: skeleton, armature (the Blender term), rig

**Joint**:
One node of a Skin.
_Avoid_: bone

**Clip**:
One named, timed animation in a skinned .glb.
_Avoid_: animation (the feature, or a value the Model moves each step), action (the Blender term), track

**Clip id**:
A number the engine assigns to each loaded Clip, published in its mesh's
Manifest entry. Id 0 is no Clip.
_Avoid_: animation index, clip handle

**Clip mix**:
The value of a Draw's `pose` field: a Clip and its time, a fade Clip and its
time, and the fade weight. Not a Pose.
_Avoid_: pose (for this value), anim, animation state, blend tree

**Grounding**:
The host lifting a skinned Draw so no named foot Joint sinks below its bind
height. See ADR 0035. Not Stick to ground.
_Avoid_: foot lock, foot IK (the later task that pins a foot), ground snap

## Benchmarks

**Lockstep**:
A run mode in which each Frame runs exactly one Fixed step and one render,
whatever the wall-clock time.
_Avoid_: fixed mode, deterministic mode, frame lock

**Headless**:
A run with no window and no GPU, always in Lockstep.
_Avoid_: offscreen, no-render, server mode

**Bench game**:
A game that stresses one axis, such as Draw count, while every other axis
stays fixed.
_Avoid_: stress test, benchmark example, perf game

**Odin twin**:
An Odin stand-in for one Bench game behind the same Game calls, to isolate the
cost of the seam.
_Avoid_: native version, baseline game, control

**Span**:
One named, timed section of a Frame, such as the step span.
_Avoid_: phase, section, lap, timer

## The Bridge

**Bridge**:
The host module that lets outside processes drive or watch a run. Nothing in
the Vocabulary names it.
_Avoid_: debug server, remote, Seam, port, debugger

**Driver**:
The one outside process at a time that drives a run over the Bridge: a script,
a CI test or an agent.
_Avoid_: client, controller, bot, harness

**Observer**:
An outside process that watches a run over the Bridge without driving it.
_Avoid_: client, viewer, spectator, listener

**Watch**:
An Observer's standing request for the run's Scenes, at a rate it chooses.
_Avoid_: subscription, subscribe, stream, feed

**Relay**:
The outside process that carries Bridge traffic between a Driver and a Web
build page.
_Avoid_: proxy, server, bridge server

**Port**:
A named channel between the game and a Driver, an extension or another run's
Bridge. Not the socket port in `ROCCO_BRIDGE`.
_Avoid_: channel, topic, event, subscription

**Tell**:
The Command that sends a message to a Port.
_Avoid_: publish, emit, send event

**Listen**:
The Query that asks for the messages sent to a Port since the last step.
_Avoid_: subscription, subscribe, topic

**Link**:
A Port whose far end is another run's Bridge.
_Avoid_: connection, socket, client

## The Editor

**Prefab**:
A tree of Nodes authored ahead of time and loaded by a Pack, which a game
places in its Scene. "Level" is a game's word for a large one. See ADR 0043.
_Avoid_: scene (the Description), NodePack, blueprint, template, level

**Marker**:
A Prefab node with a name, a Pose, tags and properties that draws nothing,
such as a spawn point.
_Avoid_: empty, spawn, point, locator

**Path**:
The local ids from a placed Prefab down to one of its nodes.
_Avoid_: node id, address, key

**Change**:
A game's alteration to one node of a placed Prefab for one step: replace it
or hide it.
_Avoid_: override, patch, edit, variant

**Import setting**:
A choice about how the host reads one source asset, kept in a sidecar file.
See ADR 0044.
_Avoid_: asset option, import flag, .import file

**Bake**:
An optional build step that turns a source asset into a faster form for the
shipped output only. See ADR 0044.
_Avoid_: import, compile, cook, convert

**Editor**:
A Rocco app that launches a game and inspects or edits its run over the Bridge.
_Avoid_: IDE, studio, inspector, tool

**Shell**:
The Editor app itself, which lays out the Panes and composes the Tools.
_Avoid_: frame, host, workspace, window

**Pane**:
One rectangle of the Shell's layout, filled by one Tool.
_Avoid_: panel (a UI Element), dock, tab, window, viewport

**Tool**:
A Roc package for one editing job, such as the Files Tool. Its core names no
Rocco type, so any Roc app can use it; a Pane shows it through `packages/ui`.
_Avoid_: module, plugin, panel, dock, widget

**Scene pane**:
A Pane in which the Editor draws the game's Scene with its own camera,
selection and gizmos.
_Avoid_: viewport, scene view, editor view

**Game pane**:
A Pane that shows the game's own frames.
_Avoid_: viewport, game view, play window
