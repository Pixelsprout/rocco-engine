---
title: A third-person character
summary: Walk, jump and glide a character over Ground and around Solids in the same step with the collide, controller and camera packages, and the order to call them in.
order: 8
---

# A third-person character

A character has to know where the ground is in the same step that it
moves. The host answers a [Query][Collisions] one step late, so a
character that waited for a ray down would sink into the ground or float
above it for a step. The collide and controller packages do the work in
Roc instead, inside your `step`. They need nothing from the host.

- The [collide package][Collide] describes the world: a `Ground` gives the
  height under a point, and `Solids` holds the static boxes and spheres
  that a character walks around.
- The [controller package][Controller] moves a character over them. It
  walks, gallops, jumps, glides, steps up onto low boxes and slides off
  steep slopes.
- The [camera package][Camera] has an `Orbit` that follows the character,
  and `to_world`, which turns a stick into a world direction.

`examples/third-person` uses all three. Build it and play it:

```sh
roc scripts/build.roc game third-person
cd examples/third-person && ./third-person.bin
```

WASD or the left stick moves, Space or the bottom face button jumps, and
holding it while you fall glides. The arrow keys or the right stick turn
the camera.

## The level

The level is built once, as top-level values. `Ground.heights` makes a
terrain from a grid of heights, and `Ground.highest` joins two of them.
`Solids.build` files the boxes and the sphere in a grid so that a step
only tests the Solids near the character. The character stands on the
tops of the Solids too, so the Ground that it gets joins the terrain with
`Ground.tops(solids)`:

<!-- region: examples/third-person/main.roc#level -->
```roc
# A flat field with a slope up to a plateau on +x, then a gap and a far field.
terrain : Ground.Ground
terrain = Ground.highest(
	Ground.heights({ origin: { x: -12.0, z: -8.0 }, cell: 4.0, columns: 9, rows: 5, heights: List.join(List.repeat(field_row, 5)) }),
	Ground.heights({ origin: { x: -12.0, z: far_z }, cell: 4.0, columns: 9, rows: 4, heights: List.repeat(0.0, 36) }),
)

# One row of heights along +x: level to x 8, up the slope to 2 at x 12, then the plateau.
field_row : List(F32)
field_row = [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 2.0]

solid_list : List(Solids.Solid)
solid_list = [
	step_box,
	Box({ center: { x: -8.0, y: 1.0, z: -4.0 }, half_extents: { x: 1.5, y: 1.0, z: 1.5 }, yaw: 0.0 }),
	Box({ center: { x: 4.0, y: 0.6, z: -4.0 }, half_extents: { x: 1.5, y: 0.6, z: 1.0 }, yaw: 0.7 }),
	thin_platform,
	Sphere({ center: { x: -5.0, y: 0.0, z: 5.0 }, radius: 1.2 }),
	cliff(8.0 - cliff_depth),
	cliff(far_z),
]

solids : Solids
solids = Solids.build(solid_list, 4.0)

# The character stands on the terrain and on the tops of the Solids.
ground : Ground.Ground
ground = Ground.highest(terrain, Ground.tops(solids))
```
<!-- endregion -->

A Solid never moves. Keep anything that moves, such as a door, out of
`Solids`.

## The Intent

The controller does not read Input. Each step your game gives it an
Intent: a direction to move in, in world `x` and `z`, and the state of the
jump button. That keeps the controller free of keys and pads, and lets a
game drive a character from a script or an AI the same way.

The example builds the Intent from the keys and the left stick. It adds
them, clamps the sum to length 1, and turns it by the camera's yaw with
`Cam.to_world`, so pushing up moves the character away from the camera:

<!-- region: examples/third-person/main.roc#intent -->
```roc
# WASD and the left stick move along the view. Space and South jump and glide.
intent : Vocabulary.Input, F32 -> Controller.Intent
intent = |input, yaw| {
	keys = { x: Key.axis(input, A, D), y: Key.axis(input, S, W) }
	stick = input.gamepads.fold(keys, |sum, pad| { x: sum.x + pad.left_stick.x, y: sum.y + pad.left_stick.y })
	{
		move: Cam.to_world(clamp_to_disc(stick), yaw),
		jump_pressed: Key.pressed(input, Space) or GamepadButton.pressed_any(input, South),
		jump_held: Key.held(input, Space) or GamepadButton.held_any(input, South),
	}
}
```
<!-- endregion -->

Up to 70 % tilt the character walks. Past that the speed rises to a
gallop at full tilt. A key gives a full tilt, so the keys always gallop.

## The step order

The order of the calls in `step` matters:

<!-- region: examples/third-person/main.roc#step -->
```roc
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	# The Intent turns the stick by the camera yaw of the frame the player saw.
	player = Controller.step(model.player, intent(input, model.orbit.yaw), ground, solids, dt)
	orbit = Cam.orbit_step(model.orbit, { character: character(player), look: look(input), dt })
	next = if (player.pos.y < fall_limit) { ..model, player: start_over.player, orbit: start_over.orbit } else { ..model, player, orbit }
	{ model: next, commands: if (Key.pressed(input, Escape)) [Quit] else [] }
}

# The camera reads a glide as Air, so it trails a glide the way it trails a jump.
character : Controller.Controller -> Cam.Character
character = |player| {
	pos: player.pos,
	heading: player.heading,
	speed: (player.vel.x * player.vel.x + player.vel.z * player.vel.z).sqrt(),
	footing: if (player.motion == Ground) Ground else Air,
}
```
<!-- endregion -->

1. Build the Intent with the camera yaw from the model. That is the yaw
   of the frame that the player saw when they pushed the stick.
2. Step the Controller with the Intent, the Ground, the Solids and `dt`.
3. Step the Orbit with the moved character, so the camera follows where
   the character is now.
4. In `view`, place the camera with `Cam.orbit_view(model.orbit,
   model.player.pos)`.

The Orbit knows only `Ground` and `Air` footing. The example reports a
glide as `Air`, so the camera trails a glide the way it trails a jump.

## Events

The controller has no event list. To play a sound on a landing or a jump,
compare the Controller before and after the step:

```roc
sounds = if (Controller.landed(model.player, player)) [Sound.play(model.thud)] else []
```

`Controller.jumped` works the same way. To react to a glide, compare
`motion` yourself.

## Tuning

`Controller.default_tuning` holds numbers tuned for a 1.5 m character on
a gamepad. Change a field with a record update. A zero `glide_fall`,
`coyote`, `jump_buffer`, `step_up` or `slope_limit` turns that feature
off:

```roc
tuning = { ..Controller.default_tuning, glide_fall: 0.0, jump: 2.0 }
player = Controller.new(tuning, spawn)
```

`step_up` is the tallest box that the character walks onto. The low box in
the example is 0.3 m tall, under the default 0.35 m, so the character
walks up it. `slope_limit` is the steepest ground it stands on. On steeper
ground it is in the Air and slides down.

## Ground that is solid all the way down

A Ground from `Ground.heights` or `Ground.flat` answers from any height,
because terrain is solid all the way down. A character that falls into a
hole and drifts under the edge of the terrain would rise onto it. The
example puts a box under each edge of its gap, so the boxes push a falling
character back into the gap.

[Collisions]: collisions.md
[Collide]: https://pixelsprout.dev/projects/rocco/api/collide/
[Controller]: https://pixelsprout.dev/projects/rocco/api/controller/
[Camera]: https://pixelsprout.dev/projects/rocco/api/camera/
