---
title: "8. Sound"
summary: Play a blip when Pip takes a pickup with the Play Command, and add music, a hum and a creak with Speakers, the door's two in its Group.
order: 8
---

# 8. Sound

The game works, and the HUD tells the player what is going on, but the game
is silent. In this chapter, you add four sounds:

- a blip when Pip takes a pickup, with the `Play` Command,
- music that plays all the time, with a Speaker in the Scene,
- a hum at the door that gets louder as Pip comes closer, with a Speaker
  in the door's Group,
- a creak that plays once while the door rises, and stops when Pip walks
  through.

![Pip walks toward the door, with "Pickups: 1 / 5" at the top left](../images/tutorial-08-sound.png)

This chapter starts from your app from [7. A HUD](07-hud.md). The full app
is
[`examples/tutorial/08-sound/main.roc`](../../examples/tutorial/08-sound/main.roc).
To see every change, compare the two chapter apps:

```sh
git diff --no-index examples/tutorial/07-hud/main.roc examples/tutorial/08-sound/main.roc
```

The header and `pip.glb` stay the same.

## Get the sound files

A Sound is an asset, like Pip's mesh. The host reads `.wav` and `.ogg`
files from `assets/sound/`.

1. Make the folder `pip/assets/sound/`.
2. Download
   [`blip.wav`](../../examples/tutorial/08-sound/assets/sound/blip.wav?raw=true),
   [`creak.wav`](../../examples/tutorial/08-sound/assets/sound/creak.wav?raw=true),
   [`hum.wav`](../../examples/tutorial/08-sound/assets/sound/hum.wav?raw=true)
   and
   [`music.wav`](../../examples/tutorial/08-sound/assets/sound/music.wav?raw=true).
3. Put them in `pip/assets/sound/`.

A Sound takes the name `sound/` and its file stem, so `blip.wav` is
`sound/blip`.

The four files come from a Python script,
[`examples/tutorial/source/make_sounds.py`](../../examples/tutorial/source/make_sounds.py).
It builds each sound from sine waves, so you can change a note and run it
again.

## The imports

Import `pf.Sound` and `pf.Speaker`:

<!-- region: examples/tutorial/08-sound/main.roc#imports -->
```roc
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Contact, Element, Manifest, Vec3]
import pf.Collider
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Query
import pf.QueryResults
import pf.Scene
import pf.Sound
import pf.Speaker
```
<!-- endregion -->

## The Model

A Sound id works like a mesh id. The host gives it to you in the Manifest,
and you keep it in your Model. Add the four Sound ids:

<!-- region: examples/tutorial/08-sound/main.roc#model -->
```roc
# A Sound id of 0 plays nothing.
Sounds : { blip : U32, creak : U32, hum : U32, music : U32 }

# pip is 0, the fallback mesh, and each Sound id is 0 until loaded gives the ids.
# yaw turns Pip about +y. At 0, Pip faces +z.
# door_lift goes from 0, shut, to door_height, open.
Model : { cube : U32, sphere : U32, pip : U32, sounds : Sounds, pos : Vec3, yaw : F32, pickups : List(Pickup), door_lift : F32, phase : Phase }
```
<!-- endregion -->

## Load the Sounds

Add the four Sound names to the `Load` of the `pip` Pack, and keep their
ids in `loaded`:

<!-- region: examples/tutorial/08-sound/main.roc#load -->
```roc
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, sounds: { blip: 0, creak: 0, hum: 0, music: 0 }, pos: V.zero, yaw: 0.0, pickups: start_pickups, door_lift: 0.0, phase: Playing }
	{ model, commands: [Load({ pack: "pip", assets: ["pip", "sound/blip", "sound/creak", "sound/hum", "sound/music"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	sounds = { blip: Sound.resolve(manifest, "sound/blip"), creak: Sound.resolve(manifest, "sound/creak"), hum: Sound.resolve(manifest, "sound/hum"), music: Sound.resolve(manifest, "sound/music") }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), sounds }
}
```
<!-- endregion -->

The Sounds load with Pip, so one Manifest holds all five ids.
`Sound.resolve` finds a Sound id in it, as `Mesh.resolve` finds Pip's mesh
id. If a name is not on disk, it gets id 0 and the host logs it once. A
Sound id of 0 plays nothing, so a missing file leaves the game silent but
running.

## Play the blip

A sound that plays once is a Command, like `Load` or `Quit`. Return it from
`step`, and the host starts the sound in the same fixed step:

<!-- region: examples/tutorial/08-sound/main.roc#step -->
```roc
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| {
	contacts = results.contacts
	next = match model.phase {
		Playing => collect(model, contacts) |> push_out(contacts) |> walk(input, dt) |> raise_door(dt) |> win(contacts)
		Won => spin(model, dt)
	}
	{ model: next, commands: quit_on_escape(input).concat(blip(model, next)) }
}

# A blip plays once when Pip collects a pickup. Two pickups in one step make one blip.
blip : Model, Model -> List(Command)
blip = |before, after|
	if List.len(after.pickups) < List.len(before.pickups) {
		[Sound.play(after.sounds.blip)]
	} else {
		[]
	}
```
<!-- endregion -->

- `blip` compares the pickups before and after the step. If Pip collected
  one, it returns a Play of the blip.
- `Sound.play(id)` gives a `Play` at gain 1 and pitch 1, `Here`: the blip
  sounds the same in both ears, wherever Pip is. To play it louder, softer
  or at another pitch, write the `Play` record yourself, as
  [Sound](../sound.md#play-a-sound-once) shows.

Once a Play starts, it plays to its end. Your game can't stop it, and it
doesn't need to remember it.

## The music

A sound that the game controls is a Speaker. A Speaker is not a Command:
it is a Node, like a Draw, so it goes in `nodes`. The Sound plays for as
long as its Speaker stays in the Scene, and `Speaker.default` repeats it.
Add the music's Speaker:

<!-- region: examples/tutorial/08-sound/main.roc#music -->
```roc
music_speaker_id : U64
music_speaker_id = 1

music : Model -> Vocabulary.Speaker
music = |model| { ..Speaker.default, id: music_speaker_id, sound: model.sounds.music, gain: 0.5 }
```
<!-- endregion -->

The host pairs each Speaker with the Speaker that had the same `id` in
the previous Scene, as it pairs Draws:

- A new id starts the Sound from its start.
- An id that stays keeps the Sound playing. If its gain, pitch or place
  changed, the change applies on the next fixed step.
- An id that leaves the Scene stops the Sound.

Speaker ids are separate from Draw ids, so the music can be 1 while the
ground is Draw 1. Keep each Speaker's id the same from step to step.

The music plays `Here`, at half its recorded gain. `Here` is the default
place: the music sounds the same in both ears, wherever the camera is.

## The hum and the creak

The hum and the creak come from the door. Add their Speakers:

<!-- region: examples/tutorial/08-sound/main.roc#door -->
```roc
hum_speaker_id : U64
hum_speaker_id = 2

creak_speaker_id : U64
creak_speaker_id = 3

# Past this distance from the camera, the door's Speakers are silent.
door_range : F32
door_range = 10.0

# The door's Speakers sit at the centre of its Group, so they rise with it.
door_speakers : Model -> List(Vocabulary.Node)
door_speakers = |model| {
	at = At({ pos: V.zero, range: door_range })
	hum = { ..Speaker.default, id: hum_speaker_id, sound: model.sounds.hum, gain: 1.0 - model.door_lift / door_height, at }
	creak = { ..Speaker.default, id: creak_speaker_id, sound: model.sounds.creak, at, repeat: Once }
	match model.phase {
		Playing if is_open(model) => [Speaker(creak)]
		Playing if model.door_lift > 0.0 => [Speaker(hum), Speaker(creak)]
		Playing => [Speaker(hum)]
		Won => []
	}
}
```
<!-- endregion -->

Both Speakers play `At` a place, with a `range` of 10. They are loudest at
that place, get quieter with distance, and are silent 10 units away. They
also come from the side they are on: if the door is on your left, you hear
them in your left ear.

Their place is `V.zero`, not the door's position. In the next section, they
go in a Group with the door's Draw, and a Speaker's `pos` in a Group is
local to that Group, as a Draw's `pos` is. So `V.zero` is the centre of the
door, and the Speakers rise with it.

When the door opens, the hum stops. Why not take it out of the list at
once? A Speaker that leaves the Scene stops in 5 milliseconds. That is
fast enough to sound like a cut, but it keeps the sound from clicking. To fade
a sound out, lower its gain over many steps instead. So the hum's gain goes
from 1 down to 0 as the door rises, and the Speaker leaves the list only when
the door is open and the hum is already silent.

The creak is a `Once` Speaker: `repeat: Once` plays its Sound one time, and
then the Speaker stays silent. It joins the door's Group when the door starts
to rise, so the creak starts then. The creak is 4 seconds long, and the door
opens in under a second and a half. When Pip walks through, the game wins,
`door_speakers` returns no Speakers, and the creak stops before its end.
Here you want that cut: the creak stops when Pip leaves the room.

## The door's Group

In chapter 7, the door's Draw rose by its own `pos`. Now the door is a Group
that holds its Draw and its Speakers. The Group rises, and everything in it
rises too:

<!-- region: examples/tutorial/08-sound/main.roc#view -->
```roc
camera_offset : Vec3
camera_offset = { x: 0.0, y: 3.6, z: 4.5 }

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw) }
	door = { ..Draw.default, id: door_id, mesh: model.cube, scale: V.scale(door_half, 2.0), tint: { r: 0.45, g: 0.12, b: 0.05 } }
	door_group = Group({ id: door_group_id, pos: { ..door_pos, y: door_pos.y + model.door_lift }, rot: Quat.identity }, [Draw(door)].concat(door_speakers(model)))
	pickups = model.pickups.map(|p| Draw(pickup(model.sphere, p)))
	# The camera is the Listener, so it follows Pip to let you hear the door come closer.
	camera = Cam.follow({ ..model.pos, z: model.pos.z + 0.3 }, camera_offset)
	# The box's centre is half its height up, so it stands on Pip's feet.
	pip_box = Collider.box(pip_id, { ..model.pos, y: pip_half.y }, Quat.from_yaw(model.yaw), pip_half)
	# The doorway keeps its Collider while the door rises.
	door_box = Collider.box(door_id, door_pos, Quat.identity, door_half)
	colliders = [Collider(pip_box), Collider(door_box)].concat(model.pickups.map(|p| Collider(Collider.sphere(p.id, p.pos, pickup_radius))))
	queries = [Query.contacts_of(pip_id)]
	nodes = [Light(sky_light), Light(sunlight), Speaker(music(model)), Draw(ground), Draw(pip), door_group].concat(pickups).concat(colliders)
	{ ..Scene.empty, camera, nodes, queries, ui: hud(model) }
}
```
<!-- endregion -->

- The Group's `pos` is the door's centre, raised by `door_lift`. The door's
  Draw keeps the default `pos`, the origin, so it sits at the centre of the
  Group.
- A Group id is separate from Draw ids, so the door's Group can be 1 while
  the ground is Draw 1.
- The doorway's Collider stays outside the Group, at `door_pos`. It keeps
  blocking the doorway while the door rises.
- The music goes in `nodes` outside the Group. A `Here` Speaker would
  ignore a Group anyway.

## The Listener follows Pip

Who hears the hum? In rocco, the Listener is the camera of the Scene. A
Speaker `At` the door is loud when the camera is close to the door.

In chapter 7, the camera stands still, so the hum would sound the same
wherever Pip went. In `view`, make the camera follow Pip with `Cam.follow`,
as the `view` above does.

At the start, the camera is where it was in chapter 7. As Pip walks, the
camera keeps the same offset behind Pip, and so does the Listener. Walk
toward the door, and the hum gets louder. Walk to the left, and the hum
moves to your right ear.

## Test the sounds

A Play is a value, like `Quit`, and the Speakers are part of the Scene. So
you test them without the host. `speakers_of` picks the root Speakers out of
the Nodes, and `door_of` finds the door's Group and the Speakers in it. Add
these tests below the tests from chapter 7:

<!-- region: examples/tutorial/08-sound/main.roc#tests -->
```roc
# The root Speakers of a Scene, in list order.
speakers_of : Vocabulary.Scene -> List(Vocabulary.Speaker)
speakers_of = |scene| List.keep_oks(
	scene.nodes,
	|node| match node {
		Speaker(s) => Ok(s)
		_ => Err(NotSpeaker)
	},
)

# The door's Group, and the Speakers in it.
door_of : Vocabulary.Scene -> { pos : Vec3, speakers : List(Vocabulary.Speaker) }
door_of = |scene| {
	groups = List.keep_oks(
		scene.nodes,
		|node| match node {
			Group(g, children) if g.id == door_group_id => Ok({ pos: g.pos, speakers: speakers_of({ ..scene, nodes: children }) })
			_ => Err(NotDoor)
		},
	)
	match List.first(groups) {
		Ok(door) => door
		Err(_) => { pos: V.zero, speakers: [] }
	}
}

with_sounds : Model
with_sounds = { ..start, sounds: { blip: 7, creak: 6, hum: 8, music: 9 } }

rising : Model
rising = { ..with_sounds, pickups: [], door_lift: 0.5 * door_height }

# Pip collects a pickup, and the step plays the blip once.
expect step(with_sounds, Input.empty, contact_with(12), 0.1).commands == [Sound.play(7)]

# With no pickup collected, nothing plays.
expect step(with_sounds, Input.empty, QueryResults.empty, 0.1).commands == []

# The music plays Here, outside the door's Group.
expect {
	root = speakers_of(view(with_sounds))
	root.map(|s| s.id) == [music_speaker_id] and root.map(|s| s.sound) == [9] and root.map(|s| s.at) == [Here]
}

# While the door is shut, its Group holds the hum at its centre, and no creak.
expect {
	door = door_of(view(with_sounds))
	ids = door.speakers.map(|s| s.id)
	places = door.speakers.map(|s| s.at)
	door.pos == door_pos and ids == [hum_speaker_id] and places == [At({ pos: V.zero, range: door_range })]
}

# Halfway up, the Group has risen, the hum plays at half gain and the creak plays once.
expect {
	door = door_of(view(rising))
	ids = door.speakers.map(|s| s.id)
	gains = door.speakers.map(|s| s.gain)
	repeats = door.speakers.map(|s| s.repeat)
	door.pos == { ..door_pos, y: door_pos.y + 0.5 * door_height } and ids == [hum_speaker_id, creak_speaker_id] and gains == [0.5, 1.0] and repeats == [Loop, Once]
}

# Once the door is open, the hum has gone and the creak plays on.
expect door_of(view({ ..rising, door_lift: door_height })).speakers.map(|s| s.id) == [creak_speaker_id]

# When Pip walks through, the creak leaves the Scene, so it stops.
expect {
	door = door_of(view({ ..rising, door_lift: door_height, phase: Won }))
	door.pos == { ..door_pos, y: door_pos.y + door_height } and door.speakers == []
}
```
<!-- endregion -->

Run the tests:

```sh
roc test main.roc
```

## Play the game

In `pip/`, run:

```sh
roc main.roc
```

The music starts at once, and the hum is quiet. Walk toward the door and
listen to the hum grow. Each pickup blips. When you take the last one, the
door creaks as it rises, and the hum rises with it and fades away. Walk
through the open door before the creak ends, and the creak stops. Press
Escape to quit.

If you hear nothing, read the log. If the host can't open the audio device,
it says so once, and the game runs with no sound. If a name in the `Load`
is wrong, the log names it.

You have made a whole game: a character that you load from a file, moves
with the keys, collects pickups and wins, with lights, a shadow, a HUD and
sound. Next, read [9. A gamepad](09-gamepad.md). It walks Pip with the
stick of a gamepad.

The guide pages explain each part in more detail. Start with
[Sound](../sound.md), [Collisions and Queries](../collisions.md) and
[The UI](../ui.md), or read [Shipping a game](../shipping.md) to build your
game for other people.
