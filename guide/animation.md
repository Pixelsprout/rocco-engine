---
title: Animation
summary: Play the Clips of a skinned mesh, fade from one Clip to another, keep two Clips at the same phase with Mesh.synced_time, and keep the feet out of the ground with Grounding.
order: 5
---

# Animation

A skinned mesh carries Clips: named sets of keys for the Joints of its
Skin, such as Idle, Walk or Run. A Draw plays them through its `pose`.
This page explains how a game finds its Clips, keeps their times, fades
from one Clip to another, keeps two Clips in step and keeps the feet on
the ground while it fades.

[Tutorial chapter 10](tutorial/10-animation.md) builds the first steps one
at a time: Pip fades between Idle and Walk. This page uses
`examples/animation`, where Pip walks on the spot and Space fades it into
Run and back. To run it, build it with `roc scripts/build.roc game
animation`.

[Skinned meshes](assets.md#skinned-meshes) lists what a `.glb` must hold to
load as a skinned mesh.

## Clips and their ids

When a Pack loads, the host gives each Clip an id. The Manifest entry of
the mesh lists its Clips, each with a name, an id and a duration in
seconds. As with mesh ids, the game keeps the ids it needs in its Model:

<!-- region: examples/animation/main.roc#model -->
```roc
# A Clip id of 0 is no Clip. walk_duration is 0 and manifest is empty until
# loaded gives them.
Clips : { walk : U32, run : U32, walk_duration : F32, manifest : Manifest }

# Each time is in seconds, wrapped into its Clip. run_time follows Walk's
# phase, so both Clips put the same foot down together. fade goes from 0, all
# Walk, to 1, all Run.
Animation : { walk_time : F32, run_time : F32, fade : F32 }

# pip is 0, the fallback mesh, until loaded gives its id. running is the Clip
# that the fade moves toward.
Model : { pip : U32, clips : Clips, animation : Animation, running : Bool }
```
<!-- endregion -->

Clip id 0 is no Clip, and a Draw with no Clip draws its mesh in the bind
pose. So the game starts with zeros, and `loaded` looks the Clips up by the
name of the mesh and the name of the Clip:

<!-- region: examples/animation/main.roc#loaded -->
```roc
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	clips = { walk: 0, run: 0, walk_duration: 0.0, manifest: [] }
	animation = { walk_time: 0.0, run_time: 0.0, fade: 0.0 }
	{ model: { pip: 0, clips, animation, running: Bool.False }, commands: [Load({ pack: "pip", assets: ["pip"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	walk = Mesh.clip(manifest, "pip", "Walk")
	run = Mesh.clip(manifest, "pip", "Run")
	clips = { walk, run, walk_duration: Mesh.clip_duration(manifest, walk), manifest }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), clips }
}
```
<!-- endregion -->

- `Mesh.clip(manifest, "pip", "Run")` gives the id of the Run Clip of the
  mesh `pip`, or 0 if the mesh or the Clip is not in the Manifest. It
  prints nothing, so a misspelt name shows up only as a mesh that does not
  move.
- `Mesh.clip_duration(manifest, id)` gives the duration of a Clip, or 0
  for an id that the Manifest does not hold.

This example keeps the whole Manifest in its Model, because
`Mesh.synced_time` reads the durations from it at each step.

## The Pose of a Draw

A Draw's `pose` has five fields:

- `clip` and `time`: the main Clip and the time in it, in seconds.
- `fade_clip` and `fade_time`: the fade Clip and the time in it.
- `fade`: how much of the fade Clip to show, from 0, all main Clip, to 1,
  all fade Clip.

<!-- region: examples/animation/main.roc#pose -->
```roc
pip_pose : Model -> Vocabulary.Pose
pip_pose = |model| {
	c = model.clips
	a = model.animation
	{ clip: c.walk, time: a.walk_time, fade_clip: c.run, fade_time: a.run_time, fade: a.fade }
}
```
<!-- endregion -->

`Draw.default` has a Pose of all zeros, so it draws the bind pose. For one
Clip with no fade, use `Pose.still(clip, time)`.

The host has no clock for a Clip. The Model moves each time at each step,
and the Pose tells the host which moment to draw. So `step` stays pure,
and a test can put the mesh at any moment of any Clip.

The host never wraps a time either. A time past the end of a Clip holds
the last key, so a Clip that plays once just keeps its time and stops on
its last frame. For a Clip that repeats, wrap the time yourself with
`Pose.loop(time, duration)`. It gives a time from 0 up to the duration,
and 0 while the duration is 0, as it is before `loaded`. Wrap at each
step, so the time stays small enough for an `F32` to keep it exact.

Between two steps, the host blends the Pose with the rest of the Draw.
A time blends only when its Clip is the same in both Scenes and the time
did not go back, so a time that wraps does not play the Clip backwards for
a frame. See [Pairing by id](scene.md#pairing-by-id).

## Fades

To fade from one Clip to another, move the `fade` toward 1 a little at each
step, and back toward 0 to fade back. In `examples/animation`, Space picks
the Clip that the fade moves toward, and the fade takes half a second to go
all the way:

<!-- region: examples/animation/main.roc#animate -->
```roc
# Walk plays at its own pace and Run keeps Walk's phase. The fade moves toward
# the Clip that running names.
animate : Model, F32 -> Model
animate = |model, dt| {
	c = model.clips
	a = model.animation
	step_fade = dt / fade_seconds
	fade = if (model.running) F32.min(a.fade + step_fade, 1.0) else F32.max(a.fade - step_fade, 0.0)
	walk_time = Pose.loop(a.walk_time + dt, c.walk_duration)
	run_time = Mesh.synced_time(c.manifest, c.walk, walk_time, c.run)
	{ ..model, animation: { walk_time, run_time, fade } }
}
```
<!-- endregion -->

You do not mix the Clips yourself. The host samples both Clips at their
own times, and mixes the rotation, position and scale of each Joint by the
fade. Halfway through, the mesh is half in one Clip and half in the other.

A Joint-by-Joint mix works well for two Clips that hold the body in a
similar way, such as Idle and Walk. It has two weak points when two Clips
move the legs in different ways, such as Walk and Run:

- If the two Clips are at different points of their stride, the legs
  scissor: one Clip has the left foot forward while the other has the right.
  Phase sync fixes that.
- Even at the same point of the stride, the mix of two bent legs is a
  shorter leg, and the feet sink into the ground. Grounding fixes that.

## Phase sync with Mesh.synced_time

Walk and Run are each one full stride, but they are not the same length:
Pip's Walk is 1 s and its Run is 0.75 s. If each Clip keeps its own time,
the two drift apart, and a fade can catch them with opposite feet forward.

`Mesh.synced_time(manifest, main_clip, time, fade_clip)` gives the time in
the fade Clip that is at the same phase as `time` in the main Clip. A
quarter of the way into Walk, at 0.25 s, is a quarter of the way into Run,
at 0.1875 s. So both Clips put the same foot down at the same moment.
`animate` above gives Run its time this way, from Walk's time at each step.
If either Clip is not in the Manifest, or the main Clip has a duration of
0, it gives 0.

Because Run's time follows Walk's, Run plays over Walk's period of 1 s, not
its own 0.75 s, even after the fade reaches 1. Pip's run is a little slower
than the Clip was keyed at. That is the cost of the simplest form of phase
sync.

The tests in the example check the phase at the wrap and at half a
stride:

<!-- region: examples/animation/main.roc#phase-tests -->
```roc
# Walk wraps at its duration, and Run sits at the same phase of its own.
expect {
	late = { ..animated, animation: { walk_time: 0.95, run_time: 0.7125, fade: 0.0 } }
	a = step(late, Input.empty, QueryResults.empty, 0.1).model.animation
	near(a.walk_time, 0.05) and near(a.run_time, 0.0375)
}

# Half of Walk is half of Run.
expect {
	a = step(animated, Input.empty, QueryResults.empty, 0.5).model.animation
	near(a.walk_time, 0.5) and near(a.run_time, 0.375)
}
```
<!-- endregion -->

## Grounding

A fade between two Clips mixes each Joint on its own. When the two Clips
bend the legs differently, the mix shortens the legs, and the feet sink
into the ground for the length of the fade. Phase sync does not stop that.
Grounding does. Name the foot Joints of a skinned Draw in `ground.feet`:

<!-- region: examples/animation/main.roc#view -->
```roc
view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	# Grounding lifts Pip out of the sink of the half fade.
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, rot: Quat.from_yaw(1.2), pose: pip_pose(model), ground: { feet: ["lower_leg.L", "lower_leg.R"] } }
	nodes = [
		Light(Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })),
		Light(Light.sun({ x: -0.5, y: -0.75, z: -0.45 }, { r: 3.0, g: 2.7, b: 2.3 })),
		Draw(ground),
		Draw(pip),
	]
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 0.8, z: 2.4 }, { x: 0.0, y: 0.45, z: 0.0 }), nodes }
}
```
<!-- endregion -->

After the host mixes the Clips, it compares each named foot Joint's height
in the mesh's own space with its height in the bind pose. If a foot is
below its bind height, the host lifts the whole Draw by the depth of the
lowest foot. It never lowers the Draw, so a jump or the airborne part of a
run keeps its height. The lift applies at every step, not only in a fade.

The lift is in the mesh's units, before the Draw's `scale`. Attach children
and the Draw's shadow follow it. The rig must bind with its feet on the
ground, because the bind pose is the height the host lifts back to.

An empty list, the default in `Draw.default`, turns Grounding off. A name
that is not a Joint of the Skin logs once for that draw id and name and is
skipped. The names are the node names in the `.glb`, as for an
[Attach](scene.md#attaching-to-a-joint).

Grounding only lifts. It does not stop a foot from sliding on the ground
in a fade.

## Rules for Clips

- **Clips are in place.** The host poses the Joints, but it never moves the
  Draw, except for the lift of Grounding. The Model moves the Draw.
- **A Clip belongs to one mesh.** A Draw that names a Clip of another mesh
  draws its bind pose, and the host logs it once.
- **No non-uniform Joint scale.** The host turns the normals with the same
  matrix that moves each vertex, so a Joint that scales more along one axis
  than another lights the mesh wrong.

See [Rules for Clips](tutorial/10-animation.md#rules-for-clips) in the
tutorial and [Skinned meshes](assets.md#skinned-meshes) for the full list.
