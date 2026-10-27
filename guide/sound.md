---
title: Sound
summary: Why a sound your game fires and forgets is a Command and a sound it controls is a Speaker in the Scene, how Sounds load, Loop and Once, where the Listener is, what happens when the voices run out, and a run with no audio device.
order: 10
---

# Sound

A sound lasts longer than a step. A jump sound plays for half a second,
which is 60 fixed steps, and music plays for minutes. But your game is pure
functions: `step` and `view` return values and keep nothing between calls.
So who remembers that a sound is still playing, and who stops it?

rocco splits sounds into two kinds, and the host keeps both playing between
steps:

- A sound that your game fires and forgets, such as a jump or a pickup, is
  a **Play**. Your game returns it as a [Command], like `Load`. The host
  plays it to its end, and your game forgets it.
- A sound that your game controls, such as music, the hum of a machine or
  the creak of a door, is a **Speaker**. It is a Node in the `nodes` of the
  [Scene], like a Draw. It plays for as long as it stays in the Scene, and
  it repeats or plays once.

[Tutorial chapter 8](tutorial/08-sound.md) uses both: a blip when Pip
takes a pickup, music, a hum at the door, and a creak while the door rises.

## Sounds are assets

A Sound is an asset in a Pack, like a mesh. Put `.wav` and `.ogg` files in
`assets/sound/`, next to your `main.roc`. A Sound takes the name `sound/`
and its file stem, so `assets/sound/blip.wav` is `sound/blip`.

Load Sounds with the `Load` Command, and keep their ids from the Manifest
in `loaded`. `Sound.resolve` finds a Sound id in the Manifest, as
`Mesh.resolve` finds a mesh id. Tutorial chapter 8 loads four Sounds in
the same Pack as its mesh:

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

A Sound id goes in a Play or a Speaker. [Assets and Packs](assets.md)
explains Packs, the Manifest and `Config.assets`, which lists the Sound names
after the meshes and the skies.

The Manifest also gives each Sound's length. `Sound.duration(manifest,
name)` gives it in seconds, at pitch 1. See [Loop and Once](#loop-and-once).

The host decodes each Sound in full when it loads, and keeps the samples in
memory until the Pack unloads. It does not stream from disk. A minute of
stereo music takes about 23 MB, so load long music only while you need it.

When a Sound unloads with its Pack, the host first stops each Play and
Speaker of it. If two files share a stem, such as `jump.ogg` and `jump.wav`,
the host loads the first one in sorted order, here `jump.ogg`, and logs once.

## Play a sound once

`Sound.play(id)` gives a Play of the Sound at its recorded gain and pitch,
`Here` at the Listener. Return it from `init` or `step`, and the host starts
the sound in the same fixed step, right after `view` moves the Listener.
Tutorial chapter 8 plays a blip when Pip takes a pickup:

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

For another gain, pitch or place, write the `Play` yourself:

```roc
Play({ sound: model.sounds.blip, gain: 0.5, pitch: 1.5, at: At({ pos: model.pos, range: 8.0 }) })
```

A Play plays to its end, or until its Pack unloads. Your game can't stop
it, and it stays at the place it started at. If a sound must stop early or
follow a moving object, make it a Speaker.

## Speakers

A Speaker is a Description, like a Draw. Your game says which sounds play
now, and the host works out what to start and stop. Start each Speaker from
[`Speaker.default`][Speaker.default], which repeats its Sound `Here` at gain
1 and pitch 1, and set its `id` and `sound`. Tutorial chapter 8 plays its
music this way:

<!-- region: examples/tutorial/08-sound/main.roc#music -->
```roc
music_speaker_id : U64
music_speaker_id = 1

music : Model -> Vocabulary.Speaker
music = |model| { ..Speaker.default, id: music_speaker_id, sound: model.sounds.music, gain: 0.5 }
```
<!-- endregion -->

A Speaker goes in `nodes`, at the root or inside a Group. After each
`view`, the host pairs each Speaker with the Speaker that had the same `id`
anywhere in the previous Scene:

- **A new id** starts the Sound from its start. The Speakers of the first
  `view` start before the first `step`.
- **An id that stays** keeps playing, even if the Speaker moved to another
  Group. A changed `gain`, `pitch` or `at` applies on the next fixed step,
  and the Sound keeps its place.
- **A changed Sound id** stops the old Sound at once and starts the new one
  from its start.
- **An id that leaves the Scene** stops the Sound with a 5 millisecond fade.

Speaker ids are any `U64`, and they are separate from Draw ids and Group
ids. Keep a Speaker's id the same for as long as it plays. If two Speakers
in one Scene share an id, the first one in the tree plays, and the host logs
once. The host walks the tree depth first: a Group's children come before
the Node after the Group.

### Loop and Once

A Speaker's `repeat` says what happens at the end of its Sound:

- **`Loop`**, the default, starts the Sound again from its start. Use it
  for music and for the hum of a machine.
- **`Once`** plays the Sound one time. Then the Speaker stays paired and
  silent, and it gives its voice back. It does not play again while it stays
  in the Scene.

Tutorial chapter 8 has one of each at its door. The hum is a `Loop`, and
the creak is a `Once`:

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

The creak joins the Scene when the door starts to rise, so it starts then.
When Pip walks through the door, the creak leaves the Scene, so it stops,
even if its Sound has not ended. If Pip waits, the creak ends by itself, and
the silent Speaker stays until Pip walks through.

To play a `Once` Speaker again, give it a new id, or leave it out of the
Scene for one step.

A changed `repeat` applies to the Sound that plays. A `Loop` that changes to
`Once` stops at the end of the current pass. A `Once` that changes to `Loop`
keeps repeating. A `Once` that has ended does not start again.

The host does not tell your game when a `Once` ends. If your game needs to
know, read the Sound's length with `Sound.duration` in `loaded`, keep it in
your Model, and count the time in `step`. The length is at pitch 1, so
divide it by the Speaker's pitch. At pitch 2, a Sound of 4 seconds ends
after 2 seconds:

```roc
creak_seconds = Sound.duration(manifest, "sound/creak") / creak_pitch
```

### Stopping and fading

The 5 millisecond fade keeps the speaker from clicking, but you hear it as
a cut, not a fade-out. To fade a Speaker out, lower its `gain` over many
steps, then remove it. Tutorial chapter 8 fades its hum this way while the
door rises.

A Speaker that leaves the Scene and comes back starts again from the start
of its Sound. There is no pause. To silence a `Loop` Speaker and keep its
place, set its `gain` to 0 and keep it in the Scene.

To switch from one piece of music to another smoothly, give each piece its
own Speaker id. Lower the gain of the old Speaker while you raise the gain
of the new one, then remove the old Speaker. A changed Sound id on one
Speaker cuts with no fade, and the jump in level can click.

### A sound that outlives its object

A Speaker in a Group leaves the Scene when its Group leaves, and its Sound
stops. For the creak of a door that the player walks through, that is what
you want. But a rocket that your game removes when it hits a wall still
needs its explosion to play to the end. Make that sound a `Play` at the
rocket's last `pos`, not a Speaker in the rocket's Group. The Play does not
need the rocket to stay in the Scene.

### Make a Sound that loops cleanly

The host repeats a `Loop` Speaker's samples from the last one straight back
to the first, with no crossfade. If the last sample does not lead into the
first, you hear a click each time the Sound repeats. Cut a loop at a point
where the wave crosses zero, or make each tone a whole number of periods
long.

[`make_sounds.py`](../examples/tutorial/source/make_sounds.py) builds the
tutorial's Sounds this way. The hum is one second of tones at whole
frequencies, such as 100 Hz and 150 Hz. Each note of the music fades to
zero before the next one starts. The creak plays once, so it only fades to
zero at its end.

## Gain and pitch

`gain` is linear. 1 plays the Sound as recorded, 0.5 plays it at half the
amplitude, and 0 is silent. A gain above 1 is louder than the recording and
can clip. A negative gain plays as 0.

`pitch` is the playback rate. 1 plays the Sound as recorded. 2 plays it an
octave higher and twice as fast, and 0.5 an octave lower and twice as
long. A pitch of 0 or less plays at 1, and the host logs once.

A Speaker's gain or pitch changes in one step. A small change each step
sounds smooth, but a big jump in the gain of a `Here` Speaker can click.
Change it over a few steps.

## The Listener and the place

The Listener is the ear that hears a placed sound. In rocco, the Listener is
the camera of the current Scene. The host moves it once per fixed step, at
the camera's `eye`, facing its `target`, with its `up`. It does not move
between steps, and the debug camera does not move it.

The `at` field of a Play or a Speaker says where it sounds:

- **`Here`** plays at the Listener, with no direction. The Sound is as loud
  in each ear as its gain says, wherever the camera is. Use it for music,
  the HUD and the player's own sounds. A `Here` Speaker ignores its Group.
- **`At({ pos, range })`** plays at `pos`. Its gain falls off linearly with
  the distance from the Listener, from full at the Listener to zero at
  `range`, like a Point Light. Past `range` it is silent. A `range` of 0 or
  less is silent.

A placed sound also pans to the side it is on. To the right of the
Listener, the right ear gets the full gain and the left ear gets a fifth of
it. Straight ahead, each ear gets half. So a placed sound right
in front of the camera is quieter than the same sound `Here`. Raise the
gain of placed sounds if they sound too soft next to the others.

A Play's `pos` is in the world, and the Play stays where it started. A
Speaker's `pos` is in the space of its Group, as a Draw's `pos` is. A root
Speaker's `pos` is in the world.

So to place a sound on an object that moves, put its Speaker in the
object's Group. The Speaker moves with the Group, and your game gives it no
`pos` from the Model. Tutorial chapter 8 puts the hum and the creak at
`V.zero` in the door's Group, the centre of the door, so they rise with the
door. The host takes a Speaker's place from the current Scene once per fixed
step, as it moves the Listener. It does not interpolate it.

If your camera stands still, every placed sound keeps the same level and
side. Tutorial chapter 8 makes its camera follow Pip, so the hum grows as
Pip walks to the door.

## Voices

Each Play and each Speaker that sounds takes a voice. `capacity.voices` in
the [Launch](launch.md) sets how many voices there are, 64 by default. A
Play gives its voice back when it ends, and so does a `Once` Speaker. A
`Loop` Speaker holds its voice for as long as it is in the Scene, even at
gain 0 or out of range. A Speaker that leaves holds its voice until its fade
ends.

When every voice is in use:

- A new Play takes the voice of the oldest Play, which stops. If Speakers
  hold every voice, the Play plays nothing.
- A new Speaker waits silent. It starts when a voice frees, if it is still
  in the Scene. Waiting Speakers start in the order of the tree.

A Play never takes a Speaker's voice, and a Speaker never takes a Play's
voice. Each of these cases logs once per run.

`capacity.sounds` sets how many Sounds can be loaded at once, 64 by
default. When the table is full, a `Load` gives the new name id 0, and the
host logs once.

## Bad Sound ids

A Sound id of 0, an id from a Pack that has unloaded, or an id the host
never gave plays nothing. The host logs each id once. There is no fallback
sound, as there is a fallback mesh, so a misspelt name is silent. Read the
log.

A Speaker with a bad id tries again each step, so it starts as soon as you
give it a good id. If you unload the Pack of a Speaker's Sound and load it
again, the Sound gets a new id. Put the new id in the Speaker to start it
again. The new id is a changed Sound id, so a `Once` that has ended plays
again.

## With no audio device

At startup, the host opens the default audio device. If it can't, it logs
once and runs the game with no sound:

```
the audio device did not open: <the reason>. The run has no sound.
```

A Headless run never opens a device. Everything else works the same with
no device. Your game gets the same calls, the host still runs each Play and
Speaker, and a Play or a `Once` Speaker still ends after its length. So
tests and CI run on a machine with no sound card.

## Sound and the Bridge

The [Bridge](bridge.md) shows each Play in the `commands` of a `step`
reply, and each Speaker in the `scene` reply, in its place in the tree. So
a check can find the sound that a step played without a speaker.
`scripts/bridge_check.py` walks Pip into a pickup in chapter 8, and checks
that the `step` reply holds the Play of the blip:

```
{"op":"step","n":30,"held":["W"]}
{"ok":true,"steps":30,"commands":[{"Play":{"sound":1,"gain":1,"pitch":1,"at":"Here"}}],"alloc":{...}}
```

Then it takes the other pickups, and checks that the creak is in the
children of the door's Group:

```
{"Speaker":{"id":3,"sound":2,"gain":1,"pitch":1,"at":{"At":{"pos":{"x":0,"y":0,"z":0},"range":10}},"repeat":"Once"}}
```

While the Bridge pauses the run, the sounds play on. A Play or a `Once`
Speaker plays to its end, and the `Loop` Speakers keep repeating. Nothing
changes until the next step.

## Limits

- No master volume, mute or pause. Scale the gains that your game returns.
- A Play can't stop. Use a Speaker for a sound that must stop.
- The host does not tell your game when a `Once` Speaker ends. Use
  `Sound.duration`.
- No streaming. Each Sound is decoded in full when it loads.
- `.wav` and `.ogg` only. No `.flac` or `.mp3`.
- One Listener, the camera.

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Speaker.default]: https://pixelsprout.dev/projects/rocco/api/platform/Speaker/#Speaker.default
