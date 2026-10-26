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
`sky` and `cursor`. Start your own records the same way.
[Defaults to start from](#defaults-to-start-from) lists every default
record.

A Scene is a Description: it says what should be true now, and the host
works out what to change. A [Command] is different, because it asks the
host to do one thing once.

## The fields

| Field | Holds | Page |
|---|---|---|
| `camera` | the [Camera] | this page |
| `nodes` | the root [Node]s of the 3D tree: Groups, Draws, Lights, Colliders and Speakers | this page |
| `sky` | a sky id | [Assets and Packs](assets.md) |
| `queries` | the [Query]s for the next step | [Collisions and Queries](collisions.md) |
| `cursor` | the [Cursor] | [Input](input.md) |
| `ui` | the root [Element]s of the UI tree over the 3D view | [The UI](ui.md) |

## The tree of Nodes

`Scene.nodes` holds the 3D part of the Scene as a tree. A [Node] is one of
four tags, and your game writes the tags directly:

- `Draw(draw)`: a [Draw], a mesh to draw. See [Pairing by id](#pairing-by-id).
- `Light(light)`: a [Light]. See [Lights](#lights).
- `Collider(collider)`: a [Collider], a shape that Queries can test. See
  [Collisions and Queries](collisions.md).
- `Group({ id, pos, rot }, children)`: a Group id, a Pose and a list of
  child Nodes. See [Groups](#groups).

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

Use [`Light.sun`][Light.sun] for the one light that casts a shadow. The
shadow map covers each Draw of the Scene.

The host uses the first Ambient light, and the first 8 Directional and
Point lights. "First" is the order of a depth-first walk of the tree: a
Group's children come right after the Group, before the Nodes that follow
it. The first Directional light that sets `shadow` is the Sun.

A few rules to know:

- The host drops a Directional light with a zero `dir`, and a Point light
  with a `range` of 0 or less. It logs each reason once.
- Lights have no id, so the host does not interpolate them. A light that
  moves inside its Group jumps once each fixed step. A light moves smoothly
  when its Group does.

## Colours

Every colour is linear, not sRGB. The host multiplies the colour of the
mesh by the `tint` of the Draw. The fallback mesh ignores the tint. Then the
host tone maps the lit colour and encodes it to sRGB for the screen.

## Defaults to start from

The platform gives a default record for each large record. Start from it
with a record update, and set only the fields that you need.

| Record | Default | Use |
|---|---|---|
| Scene | [`Scene.empty`][Scene.empty] | the start of each Scene in `view` |
| Draw | [`Draw.default`][Draw.default] | the start of each Draw. Set `id` and `mesh`. |
| Speaker | [`Speaker.default`][Speaker.default] | the start of each Speaker. Set `id` and `sound`. |
| Launch | [`Launch.default`][Launch.default] | the value of `launch`, or the start of it |
| BoxConfig | [`Ui.default_box`][Ui.default_box] | the config of each Box in the UI |
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
[Query]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Query
[Cursor]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Cursor
[Element]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Element
[Scene.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Scene/#Scene.empty
[Draw.default]: https://pixelsprout.dev/projects/rocco/api/platform/Draw/#Draw.default
[Speaker.default]: https://pixelsprout.dev/projects/rocco/api/platform/Speaker/#Speaker.default
[Launch.default]: https://pixelsprout.dev/projects/rocco/api/platform/Launch/#Launch.default
[Ui.default_box]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_box
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
