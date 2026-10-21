---
title: The Scene
summary: The Scene that view returns each step, how the host pairs Draws by id and interpolates them, and the records to start from.
order: 3
---

# The Scene

`view` returns a [Scene] each fixed step. The Scene tells what is on the
screen now and what can touch. Your game makes a new Scene from the Model
at each step. It never changes an old Scene. The host keeps the last two
Scenes, so your game keeps none.

A value of this kind is a Description. It tells what must be true now. The
host compares it with the last one and does the work. A [Command] is
different: it tells the host to do one thing one time.

## The fields

| Field | Holds | Page |
|---|---|---|
| `camera` | the [Camera] | this page |
| `draws` | the [Draw]s | this page |
| `lights` | the [Light]s | this page |
| `sky` | a sky id | [Assets and Packs](assets.md) |
| `colliders` | the [Collider]s | [Collisions and Queries](collisions.md) |
| `queries` | the [Query]s for the next step | [Collisions and Queries](collisions.md) |
| `cursor` | the [Cursor] | [Input](input.md) |
| `ui` | the [Element]s over the 3D view | [The UI](ui.md) |

## Start from the defaults

The platform gives a default record for each large record. Start from the
default with a record update. Set only the fields that you decide.

| Record | Default | Use |
|---|---|---|
| Scene | [`Scene.empty`][Scene.empty] | the start of each Scene in `view` |
| Draw | [`Draw.default`][Draw.default] | the start of each Draw. Set `id` and `mesh`. |
| Launch | [`Launch.default`][Launch.default] | the value of `launch`, or the start of it |
| Box | [`Ui.default_box`][Ui.default_box] | the start of each Box in the UI |
| Config | [`Config.empty`][Config.empty] | the Config in a test |
| Input | [`Input.empty`][Input.empty] | the Input in a test |
| QueryResults | [`QueryResults.empty`][QueryResults.empty] | the QueryResults in a test |

Pong starts each Draw from `Draw.default` and its Scene from `Scene.empty`:

<!-- region: examples/pong/main.roc#view -->
```roc
box : U32, U64, Vec3, Vec3, Rgb -> Vocabulary.Draw
box = |mesh, id, pos, scale, tint| { ..Draw.default, id, mesh, pos, scale, tint }

view : Model -> Vocabulary.Scene
view = |m| {
	c = m.cube
	fixed = [
		box(c, 10, { x: 0.0, y: -0.1, z: 0.0 }, { x: 2.0 * half_width, y: 0.1, z: 2.0 * half_depth }, { r: 0.01, g: 0.013, b: 0.02 }),
		box(c, 11, { x: 0.0, y: 0.1, z: -half_depth - 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white),
		box(c, 12, { x: 0.0, y: 0.1, z: half_depth + 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white),
		box(c, 0, { x: -paddle_x, y: 0.2, z: m.left }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 0.073, g: 0.448, b: 1.0 }),
		box(c, 1, { x: paddle_x, y: 0.2, z: m.right }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 1.0, g: 0.214, b: 0.073 }),
		box(c, m.ball.id, { x: m.ball.x, y: 0.2, z: m.ball.z }, { x: 2.0 * ball_half, y: 2.0 * ball_half, z: 2.0 * ball_half }, white),
	]

	ui = scoreboard(m.state, m.score).concat(banner(m.state, m.score)).concat(hints)

	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 14.0, z: 7.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws: fixed, lights, ui }
}
```
<!-- endregion -->

Pong draws six cubes, each with its own id, scale and tint. It adds a
Camera from the camera package, two Lights and its UI. It keeps the default
`colliders`, `queries`, `sky` and `cursor`.

## Pairing by id

The host draws frames at the rate of the display, not at the step rate. To
draw a frame between two steps, the host interpolates between the previous
Scene and the current Scene.

The host pairs each Draw in the current Scene with the Draw that has the
same `id` in the previous Scene. It interpolates `pos`, `scale`, `rot` and
`scale_rot` between the two. It does not interpolate `mesh` or `tint`. A
Draw with no partner draws where it is.

Obey these rules for draw ids:

- Give each Draw an id that no other Draw in the Scene has.
- Keep the id of a thing the same from one step to the next.
- Give a new thing a new id. Then it does not slide from the place of an
  old thing.
- Give fixed scenery ids that your entities never get.

If two Draws in a Scene have the same id, both draw, and the host logs the
id once.

Pong gives the ball a new id at each serve. So the new ball appears at the
centre, and does not slide back across the court:

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

The host interpolates the `eye`, `target` and `up` of the Camera. It does
not interpolate `fov_y`. If `up` is zero or points along the view, the host
uses +y and logs once.

The [camera package][Camera package] makes a Camera. Add
`cam: "{{camera_url}}"` to the header of your app. Then write
`import cam.Camera as Cam`. On GitHub, get the URL as
[Shipping a game](shipping.md#the-header) tells. Pong uses
[`Cam.look_at`][Camera.look_at] above. [`Cam.follow`][Camera.follow] keeps
the eye at an offset from a target, such as the player.

## Lights

The host has no light of its own. The [Light] type tells which Lights the
host uses.

- The host drops a Directional light with a zero `dir`, and a Point light
  with a `range` of 0 or less. It logs each reason to drop a light once.
- Lights have no id, so the host does not interpolate them. A light that
  moves jumps once each fixed step.

Light colours are linear and carry the intensity. The surface divides the
diffuse light by pi. So a Directional colour of 3.14 lights a white matte
surface that faces it to about 1, before the tone map.

Use [`Light.sun`][Light.sun] for the one light that casts a shadow. The
shadow map covers each Draw of the Scene.

## Colours

Each colour is linear, not sRGB. The host multiplies the colour of the mesh
by the `tint` of the Draw. The fallback mesh ignores the tint. The host
then tone maps the lit colour and encodes it to sRGB for the screen.

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Camera]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Camera
[Draw]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Draw
[Light]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Light
[Collider]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Collider
[Query]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Query
[Cursor]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Cursor
[Element]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Element
[Scene.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Scene/#Scene.empty
[Draw.default]: https://pixelsprout.dev/projects/rocco/api/platform/Draw/#Draw.default
[Launch.default]: https://pixelsprout.dev/projects/rocco/api/platform/Launch/#Launch.default
[Ui.default_box]: https://pixelsprout.dev/projects/rocco/api/ui/#Ui.default_box
[Config.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Config/#Config.empty
[Input.empty]: https://pixelsprout.dev/projects/rocco/api/platform/Input/#Input.empty
[QueryResults.empty]: https://pixelsprout.dev/projects/rocco/api/platform/QueryResults/#QueryResults.empty
[Light.sun]: https://pixelsprout.dev/projects/rocco/api/platform/Light/#Light.sun
[Camera package]: https://pixelsprout.dev/projects/rocco/api/camera/
[Camera.look_at]: https://pixelsprout.dev/projects/rocco/api/camera/#Camera.look_at
[Camera.follow]: https://pixelsprout.dev/projects/rocco/api/camera/#Camera.follow
