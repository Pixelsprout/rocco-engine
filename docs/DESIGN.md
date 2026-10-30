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
| opening the window, sizing the GPU resources and the tables | the window, the step rate, the shadow map size and the capacities, once, as `launch` |
| input, and turning it into levels and edges | the rules, as `step` |
| GPU resources, meshes, shaders | the picture, as `view` |
| the asset tables, their ids and each asset's lifetime | which assets load together, as Packs; which mesh a game object uses |
| the audio device, the mixer and their thread | what should be heard, as a Play Command or a Speaker Node in the Scene |
| answering Queries about the Colliders | which shapes touch, as Colliders; which facts it asks for, as Queries; what a Contact means |
| the hit test and the scroll sizes, after the layout | which Boxes it tags, and what a hover, a click or a scroll means |
| messages from a Driver or an extension, as a port queue | which ports it Listens on, as Queries; what it Tells, as Commands |
| the Roc heap, the six hooks, hot reload | nothing about memory |
| the vocabulary types: `Config`, `Launch`, `Input`, `QueryResults`, `Scene`, `Command` | the `Model` type, which the host never reads |

Odin produces facts. Roc produces decisions. Both cross the seam as plain
values. Roc never asks the engine a question mid-step. Roc never calls a draw
function.

## 2. The five functions

```roc
# once, before init and before the window opens
launch : Config -> Launch
# once, at startup
init : Config -> { model : Model, commands : List(Command) }
# once per fixed step, at the Launch's step_hz
step : Model, Input, QueryResults, F32 -> { model : Model, commands : List(Command) }
# once per Load, before the next view
loaded : Model, Str, Manifest -> Model
# once per fixed step, after step
view : Model -> Scene
```

`launch` returns the Launch: the window, the fixed step rate, the shadow map
size and the table capacities. The host calls it once, with the same Config
that `init` gets. The host checks the Launch and sizes its tables from it.
Then the host calls `init`. If a numeric field is zero, or a capacity is
outside its bounds, the host prints the field's name and exits with code 1.
Hot reload does not call `launch` again. ADR 0007 records the decision.

`init` returns Commands so that a game can load its first pack before the
first step. See section "Packs own asset lifetimes".

The host calls `step` then `view` inside the fixed-step loop. The host holds
the current `Scene` and the previous `Scene`. At render time the host
interpolates between them by the accumulator remainder. Roc never sees a
previous `Model` and never sees an alpha.

Between `step` and `view`, the host runs each command in list order, then
frees the list. The list does not stay in the Seam. A command means do this
once, and `view` runs again from the same `Model`. So commands come from
`step`, not from `Scene`. `Quit` asks sokol to quit, and the current frame
finishes. The Commands from `init` run the same way, before the first
`view`. A `Load` calls `loaded` before the next `view`. A `Play` starts
after `view`, once the Listener has moved to the new Camera, because a
device can mix a voice as soon as it starts. Decision.

The host answers the Queries in the previous `Scene` against that `Scene`.
The next `step` gets the QueryResults. The first step gets
empty QueryResults. ADR 0005 records the decision.

A message for a port waits in the host's port queue until the next step
runs. That step gets the messages of each port that a `Listen` Query in the
previous `Scene` names, and the host drops the rest. A `Tell` is a Command
the host does not act on: the Bridge writes it in the `step` reply, and
ADR 0018 records both rules.

With no `ContactsOf` Query, the host does no contact search. With one or
more, it searches the grid cells under each asking owner. It gives each
Contact that involves an asking owner, once, in id order. The host tests
overlap, not sweep, so the normal and depth describe where the shapes are
now. Decision.

The host walks the grid cells along each Raycast and tests the box and
sphere Colliders in them. It skips the owner's Collider and each excluded
id. It measures the distance in world units along `dir`, up to
`max_distance`. A ray that starts inside a Collider hits it at the origin,
with the normal against `dir`. Equal distances go to the lower id. The host
skips a capsule Collider and logs one line. If two Raycasts share an owner
and a slot, the host logs once and answers the first.

The host tests each Overlap against the box and sphere Colliders in the grid
cells under it. An Overlap box does not turn. The host skips the owner's
Collider and each excluded id. Shapes that only touch at a face do not
overlap. The host gives the hits of one Overlap in id order. The host skips
a capsule Collider and logs one line. If two Overlaps share an owner and a
slot, the host logs once and answers the first. A Raycast and an Overlap can
use the same owner and slot.

The host answers the Queries in `engine/collision.odin`. Once per step it
composes each Collider's world Pose down the tree of the current Scene. It
skips that walk when the Scene has no Queries. Then it builds the Shapes and
a uniform grid over them on the ground plane. ADR 0008 records the grid. The
grid finds the pairs whose world boxes overlap. A test for each pair of
shapes then gives the normal and depth. Two boxes get a separating axis test
on 15 axes. Two spheres, and a box and a sphere, get direct tests. When two
Colliders share an id, the first one collides. The host logs each shared id
and each unknown kind once per run, and skips the Collider. A skipped
Collider does not claim its id. Decision.

```
             fixed step, step_hz                       render frame, display rate
  ┌────────────── Odin ───────────────┐      ┌────────────── Odin ────────────────┐
  │ clock, key codes held and pressed │      │ accumulator remainder → alpha      │
  │ mouse delta                       │      │ Scene[n-1], Scene[n]               │
  │ QueryResults from Scene[n-1]      │      │ cursor from Scene[n] → mouse lock  │
  │                                   │      │ ui from Scene[n] → layout, quads   │
  └──────────────┬────────────────────┘      └──────────────┬─────────────────────┘
                 │ Input, QueryResults, dt                  │ pair Draws, Groups by id
                 ▼                                          ▼
   step : Model, Input, QueryResults, F32          lerp local, compose world
                 │ Model (one reference, mutated in place)  model matrix per Draw
                 │ and List(Command)                        mesh id → mesh handle
                 ▼
  ┌────────────── Odin ───────────────┐
  │ run each command in list order;   │
  │ free the list                     │
  └──────────────┬────────────────────┘
                 │ Model
                 ▼
   view : Model -> Scene
                 │ Scene[n]
                 ▼
  ┌────────────── Odin ───────────────┐
  │ keep Scene[n]; drop Scene[n-2]    │
  └───────────────────────────────────┘
```

The Frame render is the host module on the render frame side. Once per
frame it builds the Pairing from the previous `Scene`. Then it walks the tree
of the current `Scene`, interpolates each Group and Draw at the Alpha, and
submits each Draw.

## 3. The vocabulary

The platform header names five types. Nothing in them names a game. The
test: if a field would be meaningless to a different game, the field belongs
in the app.

```roc
Vec3     : { x : F32, y : F32, z : F32 }
Rgb      : { r : F32, g : F32, b : F32 }
Rgba     : { r : F32, g : F32, b : F32, a : F32 }
Config   : { seed : U64, assets : List(Str), args : List(Str) }
Launch   : { window : Window, step_hz : U32, shadow_map : U32, capacity : Capacity }
Window   : { width : U32, height : U32, title : Str, fullscreen : Bool, high_dpi : Bool, samples : Msaa, vsync : Bool }
Msaa     : [Off, X2, X4, X8]
Capacity : { meshes : U32, skies : U32, draws : U32, groups : U32, ui_quads : U32, sounds : U32, voices : U32 }
Manifest : List({ name : Str, id : U32, duration : F32, clips : List({ name : Str, id : U32, duration : F32 }) })
Input    : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 }, gamepads : List(Gamepad), window : { width : F32, height : F32 }, pointer : { x : F32, y : F32, inside : Bool, held : List(U8), pressed : List(U8), released : List(U8), wheel : { dx : F32, dy : F32 } } }
Gamepad  : { slot : U8, held : List(U8), pressed : List(U8), left_stick : { x : F32, y : F32 }, right_stick : { x : F32, y : F32 }, left_trigger : F32, right_trigger : F32 }
Quat     : { x : F32, y : F32, z : F32, w : F32 }
Draw     : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, rot : Quat, scale_rot : Quat, tint : Rgb, glow : Rgb, pose : Pose }
Pose     : { clip : U32, time : F32, fade_clip : U32, fade_time : F32, fade : F32 }
Camera   : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }
Collider : { id : U64, pos : Vec3, rot : Quat, shape : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] }
Contact  : { a : U64, b : U64, normal : Vec3, depth : F32 }
RayHit   : { owner : U64, slot : U32, id : U64, point : Vec3, normal : Vec3, distance : F32 }
OverlapHit : { owner : U64, slot : U32, id : U64 }
QueryResults : { contacts : List(Contact), rays : List(RayHit), overlaps : List(OverlapHit), ports : List({ port : Str, msg : Str }), ui : { over : List(U64), scroll : List({ id : U64, view : { width : F32, height : F32 }, content : { width : F32, height : F32 } }) } }
Query    : [ContactsOf(U64), Raycast({ owner : U64, slot : U32, origin : Vec3, dir : Vec3, max_distance : F32, exclude : List(U64) }), Overlap({ owner : U64, slot : U32, shape : [Box(Vec3), Sphere(F32)], pos : Vec3, exclude : List(U64) }), Listen(Str)]
Light    : [Ambient(Rgb), Directional({ dir : Vec3, color : Rgb, shadow : Bool }), Point({ pos : Vec3, color : Rgb, range : F32 })]
Node     := [Group({ id : U64, pos : Vec3, rot : Quat }, List(Node)), Draw(Draw), Light(Light), Collider(Collider), Speaker(Speaker)]
Cursor   : [Free, Locked]
Sizing   : [Fit({ min : F32, max : F32 }), Grow({ min : F32, max : F32 }), Fixed(F32), Percent(F32)]
Align    : [Start, Center, End]
AttachPoint : [LeftTop, LeftCenter, LeftBottom, CenterTop, CenterCenter, CenterBottom, RightTop, RightCenter, RightBottom]
BoxConfig : { id : U64, width : Sizing, height : Sizing, pad : { left : F32, right : F32, top : F32, bottom : F32 }, gap : F32, direction : [Row, Col], child_align : { x : Align, y : Align }, background : Rgba, radius : F32, overflow : [Visible, Clip, Scroll({ x : F32, y : F32 })], floating : [NoFloat, Float({ to : [Window, Parent], attach : AttachPoint, on : AttachPoint, offset : { x : F32, y : F32 } })] }
Text     : { str : Str, size : F32, color : Rgba, wrap : [Words, None] }
Element  := [Box(BoxConfig, List(Element)), Text(Text)]
Scene    : { camera : Camera, nodes : List(Node), cursor : Cursor, sky : U32, clear : Rgb, ui : List(Element), queries : List(Query) }
Place    : [Here, At({ pos : Vec3, range : F32 })]
Speaker  : { id : U64, sound : U32, gain : F32, pitch : F32, at : Place, repeat : [Loop, Once] }
Command  : [Quit, Load({ pack : Str, assets : List(Str) }), Unload(Str), Play({ sound : U32, gain : F32, pitch : F32, at : Place }), Tell({ port : Str, msg : Str })]
```

| Type | Carries | Does not carry |
|---|---|---|
| `Config` | a seed; the asset names found on disk, with no ids; the Args | how many pickups a round has; an id |
| `Launch` | the window size, title, fullscreen, `high_dpi`, MSAA and vsync; the fixed step rate; the shadow map size; the table capacities | anything that changes after the window opens |
| `Manifest` | each name one `Load` asked for, with its id or 0, and a Sound's length in seconds | a name the `Load` did not ask for |
| `Input` | sokol key codes held (levels) and pressed (edges); mouse delta; one `Gamepad` for each connected pad, at most 4: its slot, the Button codes held and pressed, the sticks and the triggers after the host's dead zones; the window size in logical pixels | a movement vector; a jump flag; a pad's brand or button labels; a dead zone setting |
| `QueryResults` | one list for each kind of Query in the last `Scene`. `contacts` holds each overlapping pair that involves an asking owner, once. Each pair has `a < b`, the normal from a to b and the depth. The list is sorted by `(a, b)`. `rays` holds one RayHit for each Raycast that hits, for the nearest Collider, in Query order. `overlaps` holds one OverlapHit for each Collider that an Overlap touches, in Query order and then id order. `ports` holds the messages for each port that a Listen names, in arrival order | what the Contact means; a time of impact; a Contact that no Query asked for |
| `Scene` | a camera eye, target, up and field of view; the 3D tree of Nodes as a list of roots: Groups by a stable Group id, Draws by mesh id with a stable draw id, the Lights, the Colliders that can touch and the Speakers by a stable Speaker id; the cursor mode; a sky id; a clear colour; the UI as a list of root Elements, each a tree; the Queries | an entity kind; a score; a mesh catalogue; quit; a physics body; the window size |
| `List(Command)` | what the host does once after this step: `Quit`, `Load`, `Unload`, `Play`; and `Tell`, which only a Driver reads | anything that should exist every step |

Key codes are sokol's: `SPACE = 32`, `A = 65`, `W = 87`. Games name them with
`pf.Key`, for example `Key.held(input, W)`. `Input` still carries `U16` codes.
The game binds keys to intent. The engine does not. The host filters no key
out of `held` or `pressed`, including the keys it reacts to itself. The host
binds no key to quit. A game returns `Quit` from `step`, for example on
`Escape`. A game with no quit key closes when the player closes the window,
or with Cmd+Q on macOS.

The cursor is a state, so it is a field in `Scene` and not a command. Once
per render frame the host reads `cursor` from the current `Scene`. It locks
or frees the mouse only when the state changes. The debug camera forces
`Locked` and ignores `Scene.cursor`. Decision.

A Collider has the id of the entity it belongs to. An entity with no
Collider touches nothing, so a game opts in per entity. A Collider is a leaf
Node, and its `pos` and `rot` are local to its Group. The render shape is
not the collision shape. `shape` is a tag union. `Box` carries the half
extents, and `rot`, a unit quaternion, turns the box in any direction. Two
boxes are tested on 15 separating axes: three face axes each and nine edge
cross products. `Sphere` carries the radius. `Capsule` carries the radius
and the half height of a segment along its own y, which `rot` turns. The
host does not test capsules yet. Games build Colliders with
`pf.Collider`, for example `Collider.box(id, pos, rot, half)`. The host
switches on every tag, so a new shape breaks the Odin compile until the host
adds a case for it. Decision.

A game puts its Queries in `Scene.queries` and builds them with `pf.Query`,
for example `Query.contacts_of(owner)` or `Query.ray(owner, origin, dir,
max_distance)`. `Query.ray` uses slot 0, and `Query.ray_slot` takes a slot.
`QueryResults.ray(results, owner)` gives the RayHit in slot 0, or `Err(Miss)`.
`QueryResults.ray_slot` takes a slot. `Query.overlap(owner, shape, pos)`
uses slot 0, and `Query.overlap_slot` takes a slot.
`QueryResults.overlaps(results, owner, slot)` gives the ids that Overlap
touched. A game with no Queries gets empty
QueryResults. `QueryResults.empty` gives empty QueryResults for tests.

The host latches input between fixed steps. A key press waits in a pending
set until a step takes it as `pressed`. The mouse delta waits the same way.
So the first step of a frame gets them, and later steps in that frame get an
empty `pressed` and a zero delta. If a frame runs no step, the next step that
runs gets them. `held` is the key state when the step runs. When the
window loses focus, the host releases every held key, because their key-up
events go to the other window. Decision.

The host polls the gamepads once per frame, before the steps of that frame,
through one Gamepad reader per OS (ADR 0015). Button presses latch as key
presses do. A button that is down when its pad connects is held, not
pressed. The sticks and the triggers carry the last polled value, after the
dead zones. When the window loses focus, the host releases every held
button and sets the axes to zero. While the Bridge is on, the Bridge pads
replace the real pads. Decision.

A tint and a light colour are each an `Rgb`, not a `Vec3`. Roc records are
structural, so the two names keep a position from passing as a colour. Each
channel is linear, like a glTF colour. A tint channel runs from 0 to 1. A
light colour carries intensity, so a channel can exceed 1. The host
multiplies the mesh base colour by the tint and lights the result in linear.
The tint does not multiply the lit result, so a dielectric's highlight
keeps the light's colour. A metal's highlight takes its tinted base colour
through F0. The shader tone maps the result with a fixed ACES fit, so a
bright channel rolls off towards 1 instead of clipping. Then it encodes the
result to sRGB for the screen. The tone map has no knob. Decision.

A glow is an `Rgb` that carries intensity, like a light colour. The shader
adds the mesh emissive and the Draw glow after the lights and before the
tone map. Emissive lights no other surface. Decision.

The seed is the start value for any randomness in the game. Roc has no random
effect, so a game keeps a generator state in its `Model` and advances it in
`step`. The same seed and the same `(Input, dt)` log give the same run. The
host reads the seed from `ROCCO_SEED`. The default is 0. Decision.

### The camera is a description

The game decides the camera. `Scene.camera` says where the eye is, what it
looks at, which way is up and the vertical field of view. The host
interpolates `eye`, `target` and `up` like a draw. If `up` is zero or lies
along the view, the host uses +y and logs once. See
`docs/adr/0001-orientation-crosses-the-seam.md`. Pure helpers such as `look_at`,
`follow` and `project` live in the camera package in `packages/camera/`.
`project` gives the window pixel of a world point, so a game can place UI over
it. The package does not depend on the platform: Roc records are structural,
so its `View` record fits `Scene.camera`. Decision.

`ROCCO_DEBUG_CAMERA=1` gives the host a fly camera for debugging. The host
then ignores `Scene.camera`, and the game still gets all input.

### Lights are data

The game decides the Lights in its Scene. A Light is a leaf Node:
`Light(light)`, where `light` is `Ambient`, `Directional` or `Point`. Games
build them with `pf.Light`, for example `Light.point(pos, color, range)`.
The host has no light of its own, so a Scene with no Light draws black.
Decision.

A Directional `dir` is the way the light travels. The host negates and
normalises it. A Point light falls off as
`clamp(1 - (d/range)^2, 0, 1)^2 / max(d^2, 0.01^2)`. The window takes it to
zero at `range`, and the inverse square stops growing inside 1 cm.

Light colours are physical, as in glTF and Filament. A directional colour is
illuminance and a point colour is intensity, and the BRDF carries the `1/pi`.
A white matte surface facing a directional light of colour `c` shows about
`c / pi`, so a light of `pi` lights it to 1. Decision.

### Shadows

Only the Sun casts a shadow. The Sun is the first Directional, in Node
order, that sets `shadow`, which `pf.Light.sun` does. A second Directional
that sets `shadow` still lights but casts no shadow, and the host logs it
once. Decision.

The host draws one shadow map from the Sun before the main pass. Its
orthographic view covers the box of every Draw at its interpolated pose. The
host snaps that box outward to whole units, so the map changes size in steps.
A skinned mesh's box is padded at load by 25% of its largest side, so the
view also covers its posed limbs.
The shadow darkens only the Sun's own light. Unlit meshes cast a shadow but
do not receive one, and the sky does neither.

The shader moves each sample point `SHADOW_NORMAL_OFFSET` along its normal, and the shadow
pipeline adds a slope-scaled depth bias. A 3 x 3 PCF filter softens each edge
through the hardware comparison sampler. The shadow map is 2048 x 2048, and
host constants set its size and bias.

The code passes N shadow views with N = 1: `MAX_CASCADES`, the
`light_view_proj` array and a texture array with one layer. Cascades for
large worlds raise that count, and no game changes.

Each mesh has a glTF metallic-roughness material. The BRDF is the glTF 2.0
Appendix B model with Filament's terms: GGX distribution with
`alpha = roughness^2`, height-correlated Smith visibility, Schlick Fresnel
with `F0 = mix(0.04, base, metallic)`, and Lambert diffuse
`(1 - F) * (1 - metallic) * base / pi`. Roughness clamps to at least 0.045.
The ambient light adds `ambient * ((1 - metallic) * base + EnvBRDFApprox)`,
after Karis (2014), so metal keeps its colour in shade. There are no shadows
and no environment map. A mesh's glTF emissive, and the glow of each Draw,
add after the lights and before the tone map. A mesh with
`KHR_materials_unlit` skips the lights and the tone map and draws its base
colour plus the emissive.

The host takes the first ambient and the first 8 directional and point
lights, in the depth-first, pre-order walk of the tree. It drops a second
ambient, a light past the 8th, a Directional with a zero `dir` and a Point
with a range <= 0. It logs each reason once per run. The cap of 8 is the
size of the light arrays in the shader.

The host uses the current `Scene`'s lights for the whole frame. Lights have
no id, and a Light's own Pose does not interpolate. A Light in a Group
follows the Group's interpolated Pose: the Group moves a Point and turns a
Directional `dir`, and does not change an Ambient. A Light that moves inside
its Group jumps once per fixed step.

### The UI is a Description

The game decides the UI in its Scene. `Scene.ui` is a list of root
Elements, and each Element is a tree:
`Element := [Box(BoxConfig, List(Element)), Text(Text)]`. A `Box` holds its
children in its own list. A `Text` is a leaf. `Element` is nominal, because
only a nominal recursive union crosses the host boundary. The tree crosses
the seam as it is, with no flattening. An Element has no id. Its place in
the tree is its identity. Games write the tags directly, for example
`Box(config, [Text(text)])`. The UI package in `packages/ui/` gives the
defaults, `default_box` and `default_text`, and small helpers, such as
`float_at`, `panel` and `label`. A game with no UI returns `ui: []`, which
allocates nothing. Decision.
`docs/adr/0013-the-scene-crosses-the-seam-as-a-tree.md` records the tree.
`docs/adr/0004-ui-layout-runs-in-the-host.md` records the layout options.

A Box carries Clay's layout fields and Clay's defaults in its config. The
config's type is `BoxConfig`, because the `Box` tag and Roc's builtin `Box`
take the name. The tag names are short forms of Clay's, such as `Row` for
`LEFT_TO_RIGHT`:

| Field | Values | Default |
|---|---|---|
| `id` | the Hit id; 0 is not tagged | 0 |
| `width`, `height` | `Fit({ min, max })`, `Grow({ min, max })`, `Fixed(F32)`, `Percent(F32)` from 0 to 1 | `Fit` with no limit |
| `pad` | `{ left, right, top, bottom }` | 0 on each side |
| `gap` | the space between children | 0 |
| `direction` | `Row` or `Col` | `Row` |
| `child_align` | `{ x, y }`, each `Start`, `Center` or `End` | `Start`, `Start` |
| `background` | an `Rgba` | alpha 0, so nothing draws |
| `radius` | one corner radius for all four corners | 0 |
| `overflow` | `Visible`, `Clip`, or `Scroll({ x, y })` | `Visible` |
| `floating` | `NoFloat`, or `Float({ to, attach, on, offset })` | `NoFloat` |

An empty config means the same in Roc and in Clay, except that the glue
orders tags by name, so an Odin literal must set `overflow` and `to`. A
floating Box puts its `attach` point, one of the nine `AttachPoint`s, on
the `on` point of the window (`to: Window`, Clay's root) or of its parent
Box (`to: Parent`), then moves by `offset`. So a `RightBottom` Box on
`RightBottom` of the window puts its own bottom-right corner on the
window's. It ignores its parent's layout. A root Box with `to: Parent`
floats on the window.

`Clip` and `Scroll` set Clay's clip config. `Scroll` also gives the offset
from the Scene as Clay's child offset. The game owns the offset; the host
never feeds Clay a wheel or a drag. The UI pass applies Clay's scissor
commands as one clip rect per run of quads.

A Text carries the string, a size, an `Rgba` colour and a wrap mode,
`Words` or `None`. `Words` is Clay's default. Clay takes a whole font size,
so the host rounds the size after the DPI scale. The font is the host's one
baked font, so the Text names no font.

`Rgba` is a colour with alpha. Each channel is linear, from 0 to 1, and
alpha is not premultiplied. A Tint stays `Rgb`. Decision.

Sizes are logical pixels. Two layout results flow back to the game, in
`QueryResults.ui`: the tagged Boxes under the Pointer, innermost first, and
the view and content sizes of the tagged Scroll Boxes. The host hit tests
the pointer of the last step after the Frame's layout, so `over` lags by one
step. A floating Box blocks the pointer when it, or any Box inside it, has
a Hit id. `docs/adr/0020-the-pointer-and-the-ui-hit-test.md` records the
decision. The host multiplies each size by `sapp.dpi_scale()`. `sapp.dpi_scale()` is 2 on
a Retina Mac with `high_dpi` on. It is 1 with `high_dpi` off. Headless lays
out at dpi 1. Decision.

The game learns the window size from `Input.window`, in logical pixels:
`sapp.width()` and `sapp.height()` over `sapp.dpi_scale()`, read once per
frame. Every step of a frame gets the same size. Headless gives the Launch
width and height. A game that projects a world point into the window, such
as a label over a character, uses it. See ADR 0019. Decision.

The host runs C Clay through its Odin bindings. Clay is a git submodule
pinned to a commit. The `inputs` step copies its prebuilt lib per target,
like sokol's. The Clay arena comes from the permanent arena at init, sized
by `MinMemorySize()` with a cap of 32,768 elements and 65,536 measured
words. Clay's default of 8,192 elements is below the largest N of the UI
bench game. The host allocates nothing per frame for the UI.

Once per frame, the host lays out the current Scene's UI against
`sapp.width()` and `sapp.height()`. One recursive procedure walks the tree
in pre-order. A `Box` opens and configures a Clay element, walks its
children, then closes the element. A `Text` adds text. A tree cannot be
unbalanced, so the host has no open or close to repair. The UI does not
interpolate. It changes once per fixed step. Text strings
point into the current Scene, which lives for the frame, so the host copies
no string. Decision.

The host measures text with its one baked font, in a plain procedure that
Clay calls back. The font id is always 0. The font is an SDF atlas of ASCII
32 to 126 from Atkinson Hyperlegible (OFL). A Font step in
`scripts/build.roc` runs an Odin bake tool that uses `vendor:stb/truetype`.
The tool writes `engine/font_baked.odin`, which is committed. If the tool
cannot run, the committed file stays, as for `engine/shader_basic.odin`.
The `font-table` step copies the advances and the kern pairs into
`packages/ui/Font.roc`, so Roc measures with the same numbers. `Ui.wrap`
copies Clay's `Words` rule. An Odin test and `packages/ui/TextCorpus.roc`
check both sides against one corpus.

The host draws Clay's render commands inside the Main pass, after the sky.
The UI pipeline has no depth test and no depth write. It blends by alpha
and uses sample count 4. Every rectangle and glyph goes into one dynamic
vertex buffer per frame, sized at init for 16384 quads. Rectangles and
glyphs share one program and the atlas is the only texture, so the UI is
one draw call. Clay emits scissor commands only for clip elements, which
the vocabulary does not have yet. A clip element adds one draw per scissor
change. A `ui` program in `engine/shaders/basic.glsl` draws rounded
rectangles and SDF glyphs with `smoothstep`. The glyph edge is `0.7071`
times the length of the screen-space gradient of the distance, so it covers
about one pixel. `ui_push_text` rounds each line origin to whole physical
pixels and keeps the advances fractional, so a glyph at the bake size meets
the atlas texel grid. UI colours skip the tone map and go through the sRGB encode,
like the sky, so the UI draws at its authored colour. The Frame render owns
the UI draw. It submits the quads through a submit procedure, like the
meshes, so a test can record them without sokol.

The host logs each of these errors once and keeps drawing:

- a character outside ASCII 32 to 126: the host draws `?`.
- more quads than the vertex buffer holds: the host drops the rest.

A Clay error, such as a `Percent` over 1, logs once per kind, and the host
draws what fits. The UI draws in every case. A bug is visible, not fatal.
Decision.

### The environment is Scene data, proposed

Today the shader uses one fixed ACES fit. A later change can let a game
choose the tone map, for example ACES, AgX or Khronos PBR Neutral.

The choice goes in `Scene`, like the Lights. `Config` cannot carry it,
because `Config` goes from the host to the game. A start-up `Command` locks
the choice for the whole game, but a Theme can change the look per level.

The tone map, the exposure and the fog go in one `Scene` record,
`Scene.environment`. Then `Scene` does not gain one field for each effect,
and a game builds the record once per Theme. The host passes the tone map as an int in
`fs_params`, and the fragment shader branches on it.

Proposed, not decided. The dex task `yjtqgdd4` holds the decision.

### Packs own asset lifetimes

A Pack is a named set of assets that load and unload together. The game
names the assets of each pack in Roc. "Level" is a game word. The engine
has no level. `docs/adr/0003-packs-own-asset-lifetimes.md` records the
options. Decision, built in Milestone 12.

The game sends `Load({ pack, assets })` from `init` or `step`. The host runs
it after the call that returned it. It loads each named asset that is not
loaded yet, synchronously. Then it calls `loaded` with the pack name and the
Manifest, in the same frame and before the next `view`. `loaded` is the only
promise that ids exist. A later background loader can call `loaded` frames
later, and no game changes.

The Manifest holds every name the `Load` asked for, in the order asked. A
name not on disk, or a file that fails to load, gets id 0 and one log line.
`Config.assets` lists the names on disk, with no ids, so a game can check
its names in `init`.

The game sends `Unload(pack)` when it is done with a pack. Packs are
independent. Any number can be loaded at once, and each unloads by name in
any order. An asset named by two loaded packs loads once and keeps one id.
Each asset counts the packs that hold it and unloads when the count is zero.
A pack keeps only its name and its asset list.

A swap is `Load(new)`, then `loaded`, then `Unload(old)` from a later step.
The new ids exist before the old ones go, so no frame draws a stale id.

These Commands do nothing and log once per pack name:

- a `Load` for a pack that is loaded,
- a second `Load` of one pack in one step,
- an `Unload` for a pack that is not loaded.

The primitives load at startup, before `init`. They belong to no pack and
never unload, so a game can draw them before any `Load`. Their ids are
fixed: fallback 0, cube 1, sphere 2, plane 3. Each is its slot at
generation 0. No primitive slot goes on a free list, so the ids never
change.

GPU resources belong to the asset. Vertex and image data are scratch until
the upload, and no arena holds an asset, because packs unload in any order.
The mesh table owns each mesh's name and data on the heap and frees the
vertex data after the upload. The engine has no level arena.

### Assets are organised by type

Files sit on disk by type, not by pack, so one file serves many packs:

- A mesh is a `.glb` file in `assets/meshes/`. Its name is the file stem,
  such as `sprout`.
- A sky is a directory in `assets/sky/` that holds six PNGs named `px`,
  `nx`, `py`, `ny`, `pz` and `nz`. Its name is `sky/<dir>`. Face `px`
  holds the directions nearest +x, with its top row towards +y and its left
  column towards +z; `engine/sky.odin` states the layout. The host draws
  `Scene.sky` as a cube around the camera at the far plane, after every
  mesh, with no lights and no tone map. Where no mesh and no sky draws, the
  window shows `Scene.clear`.
- A Sound is a `.wav` or `.ogg` file in `assets/sound/`. Its name is
  `sound/<stem>`. The host decodes it fully at load. If two files share a
  stem, the first in sorted order loads and the host logs once. Sound 0
  plays nothing. Decision, Milestone 20.

Each asset table uses the slot-and-generation id of the mesh table and
reuses freed slots through a free list. The mesh table has 64 slots. The
sky table has 16 slots, and sky 0 means no sky. Decision, built in
Milestone 12. The Sound table has 64 slots, and Sound 0 means no Sound. It
holds each Sound as f32 samples at the rate the engine mixes at, with the
channels of its file. Built in Milestone 20.

### Meshes are ids

The engine assigns a `U32` to each mesh it loads and hands the ids to the
game. The game keeps the ids it needs in its `Model`. A name the engine did
not load resolves to id 0. The engine draws id 0 as the fallback mesh. A
typo is visible, not fatal.

A closed tag union of mesh names is not allowed in `Scene`. It would rebuild
`libhost.a` for every new asset.

Games treat mesh ids as opaque. A game never hard-codes an id and never does
maths on one. It gets each id from the Manifest in `loaded`. The
primitive ids are the one exception: `Mesh.primitive` returns them.

The low 16 bits of a mesh id are the slot in the mesh table. The high 16
bits are the slot's generation. Unloading a mesh empties its slot and adds
1 to its generation. An id kept from an unloaded pack then resolves to the
fallback and is logged once, instead of drawing the mesh that took its
slot. A mesh unloads when the last pack that holds it unloads, and its slot
goes on the free list. The next mesh takes a freed slot before a new one.
The first generation is
0, so before any unload an id is its slot. The primitives never unload. The
generation wraps after 65536 unloads of one slot, and then a very old id can
match again. Decision.

Assets are `.glb` files in `assets/meshes/`, in the directory of the
program path (`argv[0]`). `roc run` sets `argv[0]` to the game's `main.roc`,
and a built game has its binary in the game directory, so both find the
game's assets from any working directory. `ROCCO_ASSETS` replaces the
`assets` path. At startup the engine lists the files directly in
`assets/meshes/` and loads none of them. `Config.assets` holds each stem,
such as `sprout`, in sorted order. Names are case-sensitive. A `Load` reads
each named file that is not loaded yet. Ids follow the order of the Loads,
so the same Loads give the same ids. The primitives are named
`primitive/fallback`, `primitive/cube`, `primitive/sphere` and
`primitive/plane`. A file stem cannot contain `/`, so a file never takes
the name of a primitive. A name that is not on disk, or a file that does
not load, gets id 0 in the Manifest and one log line per run.

A skinned mesh draws through its own pipeline and its own shadow
pipeline, with a 56-byte vertex that adds four Joint indices and four
weights. Once per frame, the host samples each skinned Draw's `pose` into
a skin block of 64 Joint matrices, which both passes apply. The vertex
shader moves each vertex and its normal by the weighted Joint matrices. The
uniform buffer holds skin blocks for at most 256 skinned Draws per frame.
Past that, the host drops the rest and logs once. ADR 0016 records the
decision.

The primitives have type-safe tags in the mesh package:
`Mesh.primitive(Cube)` returns the fixed id and takes no `Config`.
`Mesh.resolve(manifest, "name")` resolves a loaded name to its mesh id. It
returns 0 and prints a `dbg` line on a miss. The tags live in the package
only. The vocabulary still carries only a `U32`. A host test and a `roc
test` in `packages/mesh` pin the same four primitive ids. Decision.

A refcounted type (`Str`) enters the vocabulary in four places: the asset
names in `Config`, the Manifest, the pack names in `Load` and `Unload`, and
the strings of Text Elements. The names cross once per `init` or per pack.
Text strings cross once per fixed step, inside the `Scene`. The host reads
them in place and copies none.

### A scale acts along its own axes

`scale` acts along the axes of `scale_rot`, in the mesh's space. `rot` then
turns the result. The model matrix is `T · R · F · S · F⁻¹`, where `F` is
`scale_rot`. With `scale_rot` at `Quat.identity`, this is `T · R · S`. A
squash that must stay along a world axis while `rot` spins sets `scale_rot`
to `conjugate(rot) · F_world`. The host lights normals with the inverse
transpose of the model matrix, so a non-uniform scale keeps them correct. A
zero scale factor gives a zero normal along that axis. Decision.
`docs/adr/0002-a-scale-acts-along-its-own-axes.md` records the options.

### The 3D Scene is a tree

`Scene.nodes` holds the root Nodes. A Group carries a Group id and a Pose,
and its children's Poses are local to it. A Group has no scale, and a
Draw's scale acts on that Draw only. A game with no Groups writes a flat
list of leaves. The tree is still a Description: the host keeps no Node
from one `Scene` to build the next. The Frame render, the Pairing and the
Queries each loop over the root Nodes. A root Draw or Collider skips the
walk, because its Pose is already a world Pose. One recursive procedure,
`tree_walk` in `engine/scene_tree.odin`, walks each other root Node. Queries, Contacts, RayHits and
OverlapHits stay in world space. `Pose.compose` and `Pose.relative` in
`packages/linalg` give a game the host's rule. ADR 0014 records the
decision.

The host interpolates in local space, then composes. If a Node's parent
Group id is the same in both `Scene`s, the host lerps and slerps its local
Pose. If the parent changed, it interpolates between the two world Poses.
So a child of a turning Group follows an arc, not a chord.

A Group pairs only with a Group, by its Group id. Group ids and draw ids
are apart, so an entity's Group and its Draw can both carry the entity id.
If the previous `Scene` has two Groups with one id, the first pairs, and the
host logs the first duplicate once per run. Both Groups still draw their
children. `Launch.capacity.groups` sizes the Group map, so the Frame render
does not allocate. Past it, the first Groups pair and the host logs once.
A Draw whose parent changed, and whose previous parent Group did not pair,
does not pair. It draws at its current Pose.

### Draws carry a stable id

The host pairs draws across two `Scene`s by `id` and interpolates position,
scale, rot and scale_rot between them, in the space of their Group. A draw
whose id has no partner in the previous `Scene` is drawn where it is.
Entities use their entity id. Fixed scenery uses ids the entities never
reach.

The host also blends a draw's `pose`. A `time` blends when its `clip` is
the same in both `Scene`s and the time did not go back, as it does at a
loop's wrap. `fade_time` blends by the rule of `time` with `fade_clip`.
`fade` blends only when both `clip` and `fade_clip` are the same.
Otherwise the pose takes the current values.

Draw ids must be unique in a `Scene`, across all Groups. The Frame render
pairs each current draw with the previous `Scene`. If the previous `Scene`
has two draws with one id, the first one pairs, and the Frame render logs
the id once per run. If the current `Scene` has two draws with one id, each
one draws and interpolates from the same previous draw. The log then comes
at the next frame, if that `Scene` is the previous one when the frame
renders. The Pairing is built once per frame, so a `Scene` that is previous
only between two steps inside one frame is never checked. A duplicate that
persists is still logged.

## 4. The platform does not know the game

The platform header binds `Model` with a for-clause:

```roc
platform ""
    requires {} {
        [Model: model] for init : Vocabulary.Config -> { model : model, commands : List(Vocabulary.Command) },
        launch : Vocabulary.Config -> Vocabulary.Launch,
        step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Vocabulary.Command) },
        loaded : Model, Str, Vocabulary.Manifest -> Model,
        view : Model -> Vocabulary.Scene,
    }
    exposes [Button, Collider, Config, Draw, Input, Key, Launch, Light, Pose, Query, QueryResults, Scene, Sound, Speaker, Vocabulary]
```

The clause appears on one entry. It declares the alias `Model` for the rest
of the header and the platform body. The app must declare a type named
exactly `Model`. The compiler names the missing type if it does not.

The host cannot hold a value whose layout differs per game. The wrappers box
it. A Launch has no Model, so its wrapper boxes nothing:

```roc
launch_for_host : Vocabulary.Config -> Vocabulary.Launch
launch_for_host = |config| launch(config)

init_for_host : Vocabulary.Config -> { model : Box(Model), commands : List(Command) }
init_for_host = |config| {
    started = init(config)
    { model: Box.box(started.model), commands: started.commands }
}

step_for_host : Box(Model), Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Box(Model), commands : List(Command) }
step_for_host = |boxed, input, results, dt| {
    stepped = step(Box.unbox(boxed), input, results, dt)
    { model: Box.box(stepped.model), commands: stepped.commands }
}

loaded_for_host : Box(Model), Str, Manifest -> Box(Model)
loaded_for_host = |boxed, pack, manifest| Box.box(loaded(Box.unbox(boxed), pack, manifest))

view_for_host : Box(Model) -> Vocabulary.Scene
view_for_host = |boxed| view(Box.unbox(boxed))
```

The glue emits `Model` as one opaque pointer. The five entrypoints are:

```
roc_launch(Config)                        -> Launch
roc_init(Config)                          -> { ptr, List(Command) }
roc_step(ptr, Input, QueryResults, f32)   -> { ptr, List(Command) }
roc_loaded(ptr, Str, Manifest)            -> ptr
roc_view(ptr)                             -> Scene
```

`Load` holds a `Str` and a `List(Str)`, so the glue frees a `Command` with a
decref that switches on the tag. Decision.

Nothing about the game appears in the generated ABI. `libhost.a` is rebuilt
only when `Config`, `Launch`, `Manifest`, `Input`, `QueryResults`, `Scene` or
`Command` change. Those types are the engine's public API.

The vocabulary lives in `platform/Vocabulary.roc`. The header must use
qualified names such as `Vocabulary.Config`, because it does not see the
body's `import`. Games import the vocabulary and declare none of it. The
modules `pf.Scene`, `pf.Draw`, `pf.Launch`, `pf.Config` and `pf.Input` hold
a default for each record a game builds, so a game writes the type qualified
and starts its records from the default:

```roc
import pf.Vocabulary exposing [Command, Manifest]
import pf.Scene

view : Model -> Vocabulary.Scene
view = |m| { ..Scene.empty, camera: m.camera, nodes: [Draw(m.player)] }
```

Packages declare the types they need by shape and never import the platform,
so they stay publishable. The aliases are structural, so a package's
`{ x : F32, y : F32, z : F32 }` and the vocabulary's `Vec3` are one type.

Evidence: three unrelated games link and run against one host library on
`nightly-2026-10-11-7d256b9`. See `examples/cards`, `examples/entity-game`
and `examples/pong`. `scripts/host-check.sh` links all three and checks that
the host library and the glue do not change. The Zig glue output for that
platform contains no game word.

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
2. Call `roc_step(m, input, results, dt)`. Roc consumes `m` and returns
   `m'` and a commands list. The host must not use `m` again. Passing `m`
   twice is a double free. The host runs each command in list order, then
   frees the list. It frees only the list and keeps `m'`.
3. Increment the refcount on `m'`. Call `roc_view(m')`. Roc consumes one
   reference and returns a `Scene`. The host still holds `m'` with refcount
   one.
4. Store the `Scene` as current. Free the `Scene` that was previous. The one
   that was current becomes previous.

After `init`, the host runs steps 3 and 4 once. The first frame then has a
`Scene` to draw.

`loaded` follows the rule of step 2. Roc consumes `m` and returns `m'`, and
the host keeps only `m'`. The host allocates the pack name and the Manifest
at refcount 1 and passes them in, and Roc consumes them. The host runs each
`Load` from `init` or a step, and calls `loaded` for it, before step 3.
Decision, built in Milestone 12.

The host allocates the `Input` lists and the `Config` names with
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

`roc_realloc` carries no old size. The Roc heap writes the size in a header
of at least 16 bytes, and at least the alignment, before each block.
`roc_realloc` reads the old size there and resizes the block in the backing
allocator, so a block can grow in place. An allocation map version measured
about 3 times slower per alloc and free pair, and it always copied on
realloc. The Roc heap in `engine/roc_runtime.odin` keeps the header, the
alloc counters and the six hooks. The Seam in `engine/seam.odin` keeps only
the game calls and the call protocol above.

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
- **No command in `Scene`.** Commands come from `step`, because `view` runs
  again from the same `Model` and a command means do this once. Quit is a
  command. The cursor is a state, so it is a field in `Scene`.
- **No hosted function until a pure value cannot express the need.** A sound
  with a duration has host-side lifetime, and it arrived as a Description: a
  Speaker Node in the Scene, paired by id, with a `Play` Command for a sound
  that the game fires and forgets. `docs/adr/0012-a-play-is-a-command-a-loop-is-a-description.md`
  records why it is not `Spawn` and `Destroy`, and
  `docs/adr/0017-sounds-the-game-controls-are-speaker-nodes.md` why a sound
  the game controls is a Node. A physics body with a
  warm-start cache is the next case. Descriptions first. Commands only when
  a description cannot say it.

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
- **The schedule is composition.** A game's `update` is `model
  |> steer(input) |> integrate(dt) |> collect`, and `step` wraps it. Each
  stage is `Model -> Model` and a unit test. Reordering the
  pipeline reorders the systems.
- **Hot reload keeps the state.** The `Model` lives in host-owned memory.
  Replacing the code that produces it does not disturb it. Measured.
- **Render state is derived.** `view` recomputes the `Scene` every step and
  stores nothing.

## 9. Costs, stated

- `List(Record)` is array-of-structs. Bevy stores columns. The repack at the
  seam is where to fix it if it ever matters.
- One allocation per step for each non-empty `Scene` list: the root Nodes,
  each Group's children, the root Elements, each Box's children and the
  queries. It is the extract; it would exist anyway. A long Text
  string built at run time adds one allocation. A short one fits inside the
  `Str` and adds none.
- One allocation and one free per step for each non-empty `QueryResults`
  list. An empty list allocates nothing.
- The Query search runs only when a Query asks. It then builds the grid,
  which costs time for each Collider, not only for each pair.
  See section 10 for the cost at 1,000 Colliders.
- One box shell allocation and free per step. The pool removes it.
- One allocation and one free per step for each non-empty `Input` list. The
  refcount-1 axiom costs this. The pool removes it.
- `List.map`, `List.keep_if` and `List.concat` can allocate where a
  `List.update` loop does not. Under `--opt=dev`, `List.map` always copies.
  The example games use them anyway: game code stays idiomatic, and the
  alloc check records the counts. See section 10.
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
  under dev and speed. One fixed step at the default 120 Hz is 8,333
  microseconds.
- Hot reload keeps the state when the `Model` type does not change. The
  user checked this by hand on macOS with entity-game.

The measurement found these costs in game code. Section 9 lists them.

- `List.map` copies the list under `--opt=dev`. Under `--opt=speed` it
  mutates in place. entity-game uses `List.map` and accepts the copy under
  `--opt=dev`.
- On `nightly-2026-09-27-a3ce7f1`, a `List.update` loop copies the list on
  every update under `--opt=dev` if the fallback of `??` names the list. A
  fallback that holds the list is a second reference.
- On `nightly-2026-10-11-7d256b9`, `List.keep_if`, `List.drop_if` and
  `List.keep_oks` allocate one list for each element they keep, because
  they fold with `List.concat(acc, [item])`. `[x].concat(list)` allocates
  twice. entity-game skips the fold of `sweep` on a quiet step, and
  otherwise accepts these costs.

Milestone 6 timed the contact search on `arm64mac`.
`test_contact_search_timing_at_1000_colliders` in `engine/collision_test.odin`
scatters 1,000 Colliders over 100 by 100 units, half boxes and half
spheres, and finds 191 Contacts.

| Build | Mean per step, microseconds |
|---|---|
| `-debug`, as `scripts/build.roc` builds the debug host | about 1,300 |
| `-o:speed` | about 230 |

The cost does not come from the pairs. The same Colliders spread apart cost
about the same. The id check and the sort take most of the time.
`slice.sort_by` took about 200 microseconds for 1,000 elements, so the host
uses its own heap sort.

The grid of ADR 0008 replaced the sweep and prune on 2026-10-21. The same
test on `x64win`, an i7-9700F, before and after:

| Build | Sweep and prune, microseconds | Grid, microseconds |
|---|---|---|
| `-debug` | about 1,190 | about 450 |
| `-o:speed` | about 220 | about 110 |

The test calls `contacts_find`, which gives every pair. The Seam asks only
for the asking owners' pairs, which costs less.

Not verified:

- Hot reload after a change to the `Model` type. The host cannot see the
  layout, so the new code reads the old bytes. This is undefined.
- The allocation counts with input. A pressed key adds one allocation and
  one free for each non-empty `Input` list, and a stage that changes the
  entity list may allocate. The check runs with no input.
- The allocation counts on `x64win`. Both games run there, checked by hand,
  but the alloc check is a shell script and has not run on Windows.
