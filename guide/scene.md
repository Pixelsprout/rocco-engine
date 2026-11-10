---
title: The Scene
summary: Why your game describes each frame instead of drawing it, the tree of Nodes, how the host pairs Draws and Groups by id to draw smoothly, and the camera, lights and colours.
order: 4
---

# The Scene

In many engines, game code draws things: it calls a draw function for each
object, every frame. That ties your game to the display rate, and it makes
the drawing code hard to test.

In rocco, your game never draws. Instead, `view` returns a [Scene] each
fixed step: a plain value that describes what should be on the screen now,
and which shapes can touch. The host keeps the last two Scenes, compares
them and does the drawing. Because it has two Scenes, the host can draw
smooth frames between steps at whatever rate the display runs, and your
game never has to think about frames.

Your game builds a new Scene from the Model at each step. It never changes
an old Scene, and it doesn't need to keep one.

## A first Scene

Pong's `view` draws six cubes, each with its own id, scale and tint. It
adds a Camera from the camera package, two Lights and its UI:

<!-- region: examples/pong/main.roc#view -->
```roc
box : U32, U64, Vec3, Vec3, Rgb -> Vocabulary.Draw
box = |mesh, id, pos, scale, tint| { ..Draw.default, id, mesh, pos, scale, tint }

view : Model -> Vocabulary.Scene
view = |m| {
	c = m.cube
	nodes = [
		Light(ambient),
		Light(sun),
		Draw(box(c, 10, { x: 0.0, y: -0.1, z: 0.0 }, { x: 2.0 * half_width, y: 0.1, z: 2.0 * half_depth }, { r: 0.01, g: 0.013, b: 0.02 })),
		Draw(box(c, 11, { x: 0.0, y: 0.1, z: -half_depth - 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white)),
		Draw(box(c, 12, { x: 0.0, y: 0.1, z: half_depth + 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white)),
		Draw(box(c, 0, { x: -paddle_x, y: 0.2, z: m.left }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 0.073, g: 0.448, b: 1.0 })),
		Draw(box(c, 1, { x: paddle_x, y: 0.2, z: m.right }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 1.0, g: 0.214, b: 0.073 })),
		Draw(box(c, m.ball.id, { x: m.ball.x, y: 0.2, z: m.ball.z }, { x: 2.0 * ball_half, y: 2.0 * ball_half, z: 2.0 * ball_half }, white)),
	]

	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 14.0, z: 7.0 }, { x: 0.0, y: 0.0, z: 0.0 }), nodes, ui: hud(m) }
}
```
<!-- endregion -->

Pong starts each Draw from `Draw.default` and its Scene from `Scene.empty`,
then sets only the fields it cares about. It keeps the default `queries`,
`environment` and `cursor`. Start your own records the same way.
[Defaults to start from](#defaults-to-start-from) lists every default
record.

A Scene is a Description: it says what should be true now, and the host
works out what to change. A [Command] is different, because it asks the
host to do one thing once.

## The fields

| Field | Holds | Page |
|---|---|---|
| `emitters` | host-simulated smoke, dust and sparks | [Particles](#particles) |
| `camera` | the [Camera] | this page |
| `nodes` | the root [Node]s of the 3D tree: Groups, Draws, Lights, Colliders and Speakers | this page |
| `environment` | the [Environment]: the sky id, the colour behind the 3D view, the tone map, the exposure, fog and bloom | this page and [Assets and Packs](assets.md) |
| `queries` | the [Query]s for the next step | [Collisions and Queries](collisions.md) |
| `cursor` | the [Cursor] | [Input](input.md) |
| `ui` | the root [Element]s of the UI tree over the 3D view | [The UI](ui.md) |

## Particles

Add sources to `Scene.emitters` to draw smoke, dust or sparks.
Start each source from `Emitter.default`.
Use a stable `id` for each source.
Set `rate` in particles per second.
Call `Emitter.burst(id, count)` from `init` or `step` for a single burst.
The host resolves bursts against the Scene from that same call.

The host simulates particles at the fixed step rate.
The source seed controls its random velocity offsets.
`velocity_spread` sets the uniform offset range for each velocity axis.
The host interpolates position, size and colour for each frame.
Size uses world units; colour uses linear HDR values.

Use `Alpha` for smoke and dust.
The host sorts Alpha sources with Blend Draws by source position.
Use `Add` for sparks.
The host draws Add sources after that sort.
Particles test opaque depth and write no depth.

Image id `0` selects the built-in soft round sprite.
A nonzero `image` id selects a Pack image.
If that image is missing or unloaded, the host omits those particles and logs once.
Particles keep no Pack reference.

Removing a source stops new emission.
Existing particles drain with its last settings.
Reusing a draining id keeps its random sequence.
A changed seed resets the sequence for future particles.
After a removed source drains, its id starts a new sequence.
Settings changes also affect particles already alive.

The host accepts 128 sources, including draining sources, and 8192 particles.
The first duplicate source id wins.
Sources keep their host slot until they drain.
New sources take the first free slot.
Continuous emission fills free particle slots in source slot order.
Bursts fill free particle slots in command order.
Bursts run before continuous emission.
Dropped emissions do not queue for later steps.
The first 128 distinct burst ids per step are accepted.
Repeated burst ids combine up to 8192 particles.

Run the `particles` example for smoke, a Pack-image dust source and additive sparks.
Press B for sparks, R to remove or restore sources, U to unload the image, and L to reload it.

## The tree of Nodes

`Scene.nodes` holds the 3D part of the Scene as a tree. A [Node] is one of
six tags, and your game writes the tags directly:

- `Draw(draw)`: a [Draw], a mesh to draw. See [Pairing by id](#pairing-by-id).
- `Light(light)`: a [Light]. See [Lights](#lights).
- `Collider(collider)`: a [Collider], a shape that Queries can test. See
  [Collisions and Queries](collisions.md).
- `Speaker(speaker)`: a [Speaker], a Sound that plays while the Scene holds
  it. See [Sound](sound.md#speakers).
- `Group({ id, pos, rot, selected }, children)`: a Group id, a Pose and a list of
  child Nodes. See [Groups](#groups).
- `Attach({ draw, joint }, children)`: a draw id, the name of a Joint in
  that Draw's Skin and a list of child Nodes. See
  [Attaching to a Joint](#attaching-to-a-joint).

A game with no Groups writes a flat list of leaves, such as
`[Light(Light.ambient(grey)), Draw(floor), Draw(player)]`. The order of the
list matters only for Lights. A Roc test can read the tree with a pattern,
such as `[Light(_), Light(_), Draw(d), ..]`.

## Groups

A Group holds the Nodes that belong to one thing, such as a player and the
drops it carries. It has a Group id and a Pose: a `pos` and a `rot`. The
Pose of each child is local to the Group, so a child at `pos` (0, 0, 1)
sits one unit in front of its Group and turns with it. Groups can nest.
A root Node's Pose is in the world.

A Group has no scale. The `scale` of a Draw acts on that Draw only.

Set `selected` to `Bool.False` for an ordinary Group.
Set it to `Bool.True` to include every descendant Draw in one Selection union.
Nested Groups inherit selection from any selected ancestor.
The current Scene supplies selection membership without interpolation.
The host supplies coverage and nearest selected depth, including geometry behind walls.
A Post shader compares selected depth with independent scene depth to choose its occlusion policy.
Blend materials cover their full shape, including alpha-zero glass.
Mask materials preserve their cutoff and deformation.
See [Runtime Post effects](../docs/POST-RUNTIME.md) for the shader inputs and example policies.

Group ids and draw ids are apart. A Group pairs only with a Group, so an
entity can use its own id for both its Group and its Draw. Keep a Group's
id the same from one step to the next, as you do for a Draw.

To draw a frame between two steps, the host pairs each Group with the
first Group of the same id in the previous Scene, in tree order. Then, for
each Node:

- If the Node has the same parent Group id in both Scenes, the host
  interpolates its local Pose and then composes it with the interpolated
  Pose of its parent. A drop on a turning player follows an arc, not a
  straight line between the two steps.
- If the parent changed, the host composes the world Pose in each Scene
  and interpolates between those. A Node that moves to a new Group does
  not jump.

If two Groups in a Scene share an id, both draw their children. The first
one pairs, and the host logs once. `Launch.capacity.groups`, 1024 by
default, is the number of Groups the host pairs in one Scene. Past it, the
host pairs the first Groups and logs once. See [Launch](launch.md).

A Light has no id. It takes the interpolated Pose of its Group, and its own
local values come from the current Scene. A Group moves and turns a Point
light, turns the `dir` of a Directional light and does not change an
Ambient light.

The host composes each Collider's world Pose from the current Scene, with
no interpolation, before it answers the Queries. Queries, Contacts,
RayHits and OverlapHits stay in world space.

When your game moves a Node to a new Group and wants it to stay where it
is, give it the local Pose that [`Pose.relative`][Pose.relative] returns.
[`Pose.compose`][Pose.compose] gives the world Pose of a local one, with
the rule the host uses. Both are in `packages/linalg`.

## Attaching to a Joint

An Attach puts its children on one Joint of a skinned Draw, such as a hat
on a head or a lantern in a hand. Name the Draw by its draw id and the
Joint by its node name in the .glb:

```roc
Attach({ draw: pip_id, joint: "head" }, [Draw(orb), Light(glow)])
```

Each child's Pose is local to the Joint. The host poses the Skin first and
then places the children in the same frame, so they follow the Clip with no
lag. The children take the Joint's position and rot, never its scale. To
size an attached mesh, set the `scale` of its own Draw.

The Attach can sit anywhere in the tree. Its parent Group does not move
it; only the Joint does. Draws, Lights, Colliders and Speakers under an
Attach all move with the Joint.

If no Draw has that id, the Draw's mesh has no Skin, or the Skin has no
Joint of that name, the host draws none of the children and logs once for
that draw id and joint. The log lists the Joint names of the Skin, so a
typo is easy to find. `examples/attach` shows an orb on Pip's head and a
lantern in Pip's hand.

## Pairing by id

The host draws frames at the rate of the display, not at the step rate. To
draw a frame that falls between two steps, it interpolates between the
previous Scene and the current one.

To do that, the host pairs each Draw in the current Scene with the Draw
that has the same `id` in the previous Scene. It interpolates `pos`,
`scale`, `rot` and `scale_rot` between the two, but not `mesh` or `tint`.
A Draw with no partner simply draws where it is.

The host blends the `pose` too. The `time` blends when the `clip` is the
same in both Scenes and the time did not go back. The `fade_time` blends
by the same rule with the `fade_clip`. The `fade` blends only when both
the `clip` and the `fade_clip` are the same. Anything else takes the
current value, so a looping time that wraps back to the start does not
play the Clip backwards for a frame.

So the ids matter. Follow these rules:

- Give each Draw an id that no other Draw in the Scene has.
- Keep the id of a thing the same from one step to the next.
- Give a new thing a new id, so that it does not slide from where an old
  thing was.
- Give fixed scenery ids that your entities never get.

If two Draws in a Scene have the same id, both draw, and the host logs the
id once. A Draw keeps its id when it moves to a new Group, so it pairs
with its previous self.

Pong gives the ball a new id at each serve. So the new ball appears at the
centre, and doesn't slide back across the court:

<!-- region: examples/pong/main.roc#serve -->
```roc
serve : Model, F32 -> Model
serve = |m, dir| {
	rng = next_rng(m.rng)
	serves = m.serves + 1
	ball = { id: ball_id_base + serves, x: 0.0, z: 0.0, vx: dir * serve_speed, vz: (unit(rng) - 0.5) * 6.0 }

	{ ..m, ball, serves, rng }
}
```
<!-- endregion -->

The entity game gives each entity an id from a counter that only goes up.
Its scenery ids count down from the top, so the two sets never meet:

<!-- region: examples/entity-game/main.roc#scenery-id -->
```roc
# Scenery ids count down from the top, so next_id never reaches them.
floor_id : U64
floor_id = U64.highest
```
<!-- endregion -->

## The camera

The [camera package][Camera package] makes a Camera. Add
`cam: "{{camera_url}}"` to the header of your app, then write
`import cam.Camera as Cam`. On GitHub, get the URL as
[Shipping a game](shipping.md#the-header) explains. Pong uses
[`Cam.look_at`][Camera.look_at] above. [`Cam.follow`][Camera.follow] keeps
the eye at an offset from a target, such as the player.

The host interpolates the `eye`, `target` and `up` of the Camera, but not
`fov_y`. If `up` is zero or points along the view, the host uses +y and
logs once.

## Lights

The host has no light of its own, so a Scene with no Lights draws black.
The [Light] type lists the kinds of Light. Put each one in `Scene.nodes`
with the `Light` tag.

Light colours are linear, and they carry the intensity, so a channel can go
above 1. The surface divides the diffuse light by pi. So a Directional
colour of 3.14 lights a white matte surface that faces it to about 1,
before the tone map.

Use [`Light.sun`][Light.sun] for the one light that casts a shadow. With
one cascade, the shadow map covers each Draw of the Scene. With more
cascades, set by `Launch.shadow_cascades`, the maps cover the first 150
metres of the view.

The host uses the first Ambient light.
It accepts four Directional lights, with the Sun first, and 1,024 Point lights in Scene order.
A late Sun replaces the last retained Directional when necessary.
The host divides the camera view into screen tiles and depth slices, called clusters.
Each cluster keeps up to 64 Point lights.
A full cluster keeps lights nearest its centre, with Scene order resolving ties.
The host logs each limit once per run.
Large floor meshes can receive lamps across their whole surface.
The `clustered-lights` example shows 200 moving lamps on one tiled floor Draw.

“First” follows a depth-first walk of the tree.
A Group's children come immediately after the Group, before the Nodes that follow it.
The first Directional light that sets `shadow` is the Sun.
Point lights cast no shadows.

A few rules to know:

- The host drops a Directional light with a zero `dir`, and a Point light
  with a `range` of 0 or less. It logs each reason once.
- Lights have no id, so the host does not interpolate them. A light that
  moves inside its Group jumps once each fixed step. A light moves smoothly
  when its Group does.

## Glow

A Draw's `glow` is the light that its surface gives off. The host adds it
after the lights, so a glowing surface shows in a Scene with no Light at
all. Like a light colour, a glow is linear and can go above 1. The glow
example's window keeps a dark tint and puts its brightness in the glow:

<!-- region: examples/glow/main.roc#window -->
```roc
window : Vocabulary.Draw
window = { ..Draw.default, id: 3, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: 1.4, z: -1.33 }, scale: { x: 1.4, y: 0.6, z: 0.06 }, tint: { r: 0.02, g: 0.018, b: 0.015 }, glow: { r: 3.2, g: 1.9, b: 0.6 } }
```
<!-- endregion -->

A glow lights nothing else. The floor under a glowing window stays dark.
So a thing that should light its surroundings also needs a Light. Put a
Draw with a glow and a Point Light side by side. The glow example's orbs
each pair a glowing sphere with a Point Light at its centre, in the same
colour:

<!-- region: examples/glow/main.roc#orb -->
```roc
orb : U64, Vec3, Rgb -> List(Vocabulary.Node)
orb = |id, pos, color| {
	lit = { r: color.r * 3.0, g: color.g * 3.0, b: color.b * 3.0 }
	sphere = { ..Draw.default, id, mesh: Mesh.primitive(Sphere), pos, scale: { x: 0.5, y: 0.5, z: 0.5 }, tint: color, glow: lit }
	[Draw(sphere), Light(Light.point(pos, lit, 4.0))]
}
```
<!-- endregion -->

Each Point counts toward the Scene's 1,024 Point limit.
A glTF mesh can also glow through its Material's emissive, and its Draw's glow adds to that.
See [Assets and Packs](assets.md).

A tint above 1 is no longer the way to make a surface glow. A tint
multiplies the lit colour, so it shows only where a Light reaches.

## Colours

Every colour is linear, not sRGB. The host multiplies the colour of the
mesh by the `tint` of the Draw. The fallback mesh ignores the tint and the
glow. The host adds the glow after the lights and before the tone map.

The host draws the 3D view in linear colour and turns it into screen
colour at the end of each frame, as [The environment](#the-environment)
explains. The UI draws after that, so it shows the colours you give it.

## The environment

`Scene.environment` sets the look of the whole 3D view: what shows behind
the meshes, how the linear colour becomes screen colour, the fog and the
bloom. Start from `Environment.default` and set only what you need. The
glow example sets its tone map and its bloom from its Model:

<!-- region: examples/glow/main.roc#environment -->
```roc
bloom_strength : F32
bloom_strength = 0.2

environment : Model -> Vocabulary.Environment
environment = |model| {
	strength = if (model.bloom) bloom_strength else 0.0
	{ ..Environment.default, tone_map: model.tone_map, bloom: { ..Environment.default.bloom, strength } }
}
```
<!-- endregion -->

The host takes the environment from the newest Scene each frame, with no
blend between two Scenes, so a change shows at once. None of it changes
the UI.

| Field | Default | Sets |
|---|---|---|
| `sky` | 0, no sky | the sky drawn behind the meshes |
| `clear` | black | the colour behind the meshes where no sky is |
| `tone_map` | `Aces` | how a bright colour rolls off to the screen |
| `exposure` | 1 | a multiplier on every colour before the tone map |
| `fog` | an `amount` of 0, which is off | a fade towards one colour with distance |
| `bloom` | a `strength` of 0, which is off | a soft halo around very bright surfaces |

### Sky and clear colour

Each frame starts from the `clear` colour. The meshes draw over it, and
then the sky fills every pixel that no mesh covers. A `sky` of 0, or an id
that the host does not know, draws no sky, so the `clear` colour shows
behind the meshes instead. [Assets and Packs](assets.md) shows how to load
a sky and get its id. Like every colour, `clear` is linear, and both it and
the sky go through the tone map.

### Tone map and exposure

The host multiplies the 3D view by `exposure`, then tone maps all of it
and encodes it to sRGB for the screen. Lit and unlit surfaces, the sky and
the `clear` colour all go through the tone map. Under the default `Aces`
tone map an unlit colour shows a little darker than its value. `Neutral`
keeps a colour closest to its value, and `AgX` keeps a bright colour from
shifting hue. The glow example cycles the three with T, so you can compare
them on one Scene.

`exposure` is a plain multiplier: 2 doubles every colour before the tone
map, and 0.5 halves it. Use it to brighten or darken the whole Scene
without changing each Light.

```roc
environment: { ..Environment.default, tone_map: AgX, exposure: 1.4 }
```

### Fog

Fog fades each mesh towards one colour as it gets further from the camera.
Up to `start` units away a surface draws as it would without fog. From
there the fog grows in a straight line until, at `end` units and beyond,
the surface is `amount` of the way to `color`. An `amount` of 1 hides a far
surface in the fog colour, and the default `amount` of 0 turns fog off.

```roc
environment: { ..Environment.default, fog: { color: { r: 0.32, g: 0.36, b: 0.45 }, start: 8.0, end: 40.0, amount: 1.0 } }
```

The distance is measured straight from the camera, so the fog stays put
when the camera turns on the spot. The fog mixes the whole colour of a
surface after its lights and its glow, so a far lamp or an unlit sign
fades too. The sky and the `clear` colour do not fog. Set the fog `color`
to the colour of the sky at its horizon, or to the `clear` colour when
there is no sky, so that far meshes melt into what is behind them instead
of showing as flat shapes against it. The fog colour is linear, like every
other colour, and goes through the tone map with the rest of the 3D view.

### Bloom

Bloom spreads the light of a very bright surface into a soft halo around
it, the way a lamp or a neon sign looks on a hazy night or through a
camera. It is off until you raise `strength`. The glow example above sets
only the strength, 0.2, and keeps the default threshold and knee. Press B
in the glow example to turn its bloom off and on.

The host keeps the light above `threshold`, blurs it at up to six sizes,
sums the blurs and adds `strength` times the result to the 3D view,
before the exposure and the tone map. `knee` softens the cut: the halo
fades in from `threshold - knee` and takes all the light above `threshold`
from `threshold + knee`. The threshold compares the brightest channel of
the colour before the exposure, so a change of exposure makes the halo
brighter or dimmer but does not change which surfaces bloom.

The default threshold of 2 suits a glow of about 3, like the glow
example's window, orbs and neon. It halos them but not a wall or a floor
that a Light makes a little brighter than 1. If a lit surface starts to
glow, raise the threshold. If a glow gets no halo, make the glow brighter
or lower the threshold. A strength of about 0.2 gives a clear halo, and a
strength near 1 washes the Scene out.

The blurs are sized in logical pixels, so the halo looks the same on a
Retina display and on a 1x display. The largest blur needs a window of at
least 512 logical pixels on its shorter side. A smaller window drops it
and shows a smaller, dimmer halo, so check the strength at the window size
your players use. Bloom adds up to eleven small passes to each frame, and
a strength of 0 runs none of them.

## Defaults to start from

The platform gives a default record for each large record. Start from it
with a record update, and set only the fields that you need.

| Record | Default | Use |
|---|---|---|
| Scene | [`Scene.empty`][Scene.empty] | the start of each Scene in `view` |
| Environment | [`Environment.default`][Environment.default] | the start of `Scene.environment`. Set `sky`, `tone_map`, `fog` or `bloom`. |
| Emitter | [`Emitter.default`][Emitter.default] | the start of each source. Set `id` and `rate`. |
| Draw | [`Draw.default`][Draw.default] | the start of each Draw. Set `id` and `mesh`. |
| Speaker | [`Speaker.default`][Speaker.default] | the start of each Speaker. Set `id` and `sound`. |
| Launch | [`Launch.default`][Launch.default] | the value of `launch`, or the start of it |
| PanelConfig | [`Ui.default_panel`][Ui.default_panel] | the config of each Panel in the UI |
| Text | [`Ui.default_text`][Ui.default_text] | the start of each Text in the UI. `Ui.label(str)` sets the string. |
| Config | [`Config.empty`][Config.empty] | the Config in a test |
| Input | [`Input.empty`][Input.empty] | the Input in a test |
| QueryResults | [`QueryResults.empty`][QueryResults.empty] | the QueryResults in a test |

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Camera]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Camera
[Draw]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Draw
[Light]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Light
[Node]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Node
[Collider]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Collider
[Speaker]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Speaker
[Query]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Query
[Cursor]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Cursor
[Element]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Element
[Scene.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Scene/#Scene.empty
[Environment]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Environment
[Environment.default]: https://pixelsprout.dev/projects/rocco/api/platform/Environment/#Environment.default
[Emitter.default]: https://pixelsprout.dev/projects/rocco/api/platform/Emitter/#Emitter.default
[Draw.default]: https://pixelsprout.dev/projects/rocco/api/platform/Draw/#Draw.default
[Speaker.default]: https://pixelsprout.dev/projects/rocco/api/platform/Speaker/#Speaker.default
[Launch.default]: https://pixelsprout.dev/projects/rocco/api/platform/Launch/#Launch.default
[Ui.default_panel]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_panel
[Ui.default_text]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_text
[Config.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Config/#Config.empty
[Input.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Input/#Input.empty
[QueryResults.empty]: https://pixelsprout.dev/projects/rocco/api/platform/QueryResults/#QueryResults.empty
[Light.sun]: https://pixelsprout.dev/projects/rocco/api/platform/Light/#Light.sun
[Pose.compose]: https://pixelsprout.dev/projects/rocco/api/linalg/Pose/#Pose.compose
[Pose.relative]: https://pixelsprout.dev/projects/rocco/api/linalg/Pose/#Pose.relative
[Camera package]: https://pixelsprout.dev/projects/rocco/api/camera/
[Camera.look_at]: https://pixelsprout.dev/projects/rocco/api/camera/#Camera.look_at
[Camera.follow]: https://pixelsprout.dev/projects/rocco/api/camera/#Camera.follow
