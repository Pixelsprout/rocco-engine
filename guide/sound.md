---
title: Sound
summary: Why a sound that plays once is a Command and a sound that repeats is in the Scene, how Sounds load, where the Listener is, what happens when the voices run out, and a run with no audio device.
order: 10
---

# Sound

A sound lasts longer than a step. A jump sound plays for half a second,
which is 60 fixed steps, and music plays for minutes. But your game is pure
functions: `step` and `view` return values and keep nothing between calls.
So who remembers that a sound is still playing, and who stops it?

rocco splits sounds into two kinds, and the host keeps both playing between
steps:

- A sound that plays once, such as a jump or a pickup, is a **Play**. Your
  game returns it as a [Command], like `Load`. The host plays it to its
  end, and your game forgets it.
- A sound that repeats, such as music or the hum of a machine, is a
  **Loop**. Your game puts it in the `loops` field of the [Scene], like a
  Draw. It plays for as long as it stays in the Scene.

[Tutorial chapter 8](tutorial/08-sound.md) uses both: a blip when Pip
takes a pickup, music, and a hum at the door.

## Sounds are assets

A Sound is an asset in a Pack, like a mesh. Put `.wav` and `.ogg` files in
`assets/sound/`, next to your `main.roc`. A Sound takes the name `sound/`
and its file stem, so `assets/sound/blip.wav` is `sound/blip`.

Load Sounds with the `Load` Command, and keep their ids from the Manifest
in `loaded`. `Sound.resolve` finds a Sound id in the Manifest, as
`Mesh.resolve` finds a mesh id. Tutorial chapter 8 loads three Sounds in
the same Pack as its mesh:

<!-- region: examples/tutorial/08-sound/main.roc#load -->
```roc
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, sounds: { blip: 0, hum: 0, music: 0 }, pos: V.zero, yaw: 0.0, pickups: start_pickups, door_lift: 0.0, phase: Playing }
	{ model, commands: [Load({ pack: "pip", assets: ["pip", "sound/blip", "sound/hum", "sound/music"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	sounds = { blip: Sound.resolve(manifest, "sound/blip"), hum: Sound.resolve(manifest, "sound/hum"), music: Sound.resolve(manifest, "sound/music") }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), sounds }
}
```
<!-- endregion -->

A Sound id goes in a Play or a Loop. [Assets and Packs](assets.md) explains
Packs, the Manifest and `Config.assets`, which lists the Sound names after
the meshes and the skies.

The host decodes each Sound in full when it loads, and keeps the samples in
memory until the Pack unloads. It does not stream from disk. A minute of
stereo music takes about 23 MB, so load long music only while you need it.

When a Sound unloads with its Pack, the host first stops each Play and
Loop of it. If two files share a stem, such as `jump.ogg` and `jump.wav`, the
host loads the first one in sorted order, here `jump.ogg`, and logs once.

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
it. If you need to stop a sound, make it a Loop, even if it plays only
once: remove the Loop and the sound stops.

## Loops

A Loop is a Description, like a Draw. Your game says which sounds repeat
now, and the host works out what to start and stop. Start each Loop from
[`Loop.default`][Loop.default] and set its `id` and `sound`:

<!-- region: examples/tutorial/08-sound/main.roc#speakers -->
```roc
# The door's centre, as it rises.
door_at : Model -> Vec3
door_at = |model| { ..door_pos, y: door_pos.y + model.door_lift }

music_speaker_id : U64
music_speaker_id = 1

hum_speaker_id : U64
hum_speaker_id = 2

# Past this distance from the camera, the hum is silent.
hum_range : F32
hum_range = 10.0

# The hum fades as the door rises, and stops when the door is open.
speakers : Model -> List(Vocabulary.Node)
speakers = |model| {
	music = { ..Speaker.default, id: music_speaker_id, sound: model.sounds.music, gain: 0.5 }
	hum = { ..Speaker.default, id: hum_speaker_id, sound: model.sounds.hum, gain: 1.0 - model.door_lift / door_height, at: At({ pos: door_at(model), range: hum_range }) }
	if is_open(model) [Speaker(music)] else [Speaker(music), Speaker(hum)]
}
```
<!-- endregion -->

After each `view`, the host pairs each Loop with the Loop that had the same
`id` in the previous Scene:

- **A new id** starts the Sound from its start. The Loops of the first
  `view` start before the first `step`.
- **An id that stays** keeps playing. A changed `gain`, `pitch` or `at`
  applies on the next fixed step, and the Sound keeps its place.
- **A changed Sound id** stops the old Sound at once and starts the new one
  from its start.
- **An id that leaves the Scene** stops the Sound with a 5 millisecond fade.

Loop ids are any `U64`, and they are separate from Draw ids. Keep a Loop's
id the same for as long as it plays. If two Loops in one Scene share an id,
the first one plays, and the host logs once.

### Stopping and fading

The 5 millisecond fade keeps the speaker from clicking, but you hear it as
a cut, not a fade-out. To fade a Loop out, lower its `gain` over many
steps, then remove it. Tutorial chapter 8 fades its hum this way
while the door rises.

A Loop that leaves the Scene and comes back starts again from the start of
its Sound. There is no pause. To silence a Loop and keep its place, set its
`gain` to 0 and keep it in the Scene.

To switch from one piece of music to another smoothly, give each piece its
own Loop id. Lower the gain of the old Loop while you raise the gain of the
new one, then remove the old Loop. A changed Sound id on one Loop cuts with
no fade, and the jump in level can click.

### Make a Sound that loops cleanly

The host repeats a Loop's samples from the last one straight back to the
first, with no crossfade. If the last sample does not lead into the first,
you hear a click each time the Sound repeats. Cut a loop at a point where
the wave crosses zero, or make each tone a whole number of periods long.

[`make_sounds.py`](../examples/tutorial/source/make_sounds.py) builds the
tutorial's Sounds this way. The hum is one second of tones at whole
frequencies, such as 100 Hz and 150 Hz. Each note of the music fades to
zero before the next one starts.

## Gain and pitch

`gain` is linear. 1 plays the Sound as recorded, 0.5 plays it at half the
amplitude, and 0 is silent. A gain above 1 is louder than the recording and
can clip. A negative gain plays as 0.

`pitch` is the playback rate. 1 plays the Sound as recorded. 2 plays it an
octave higher and twice as fast, and 0.5 an octave lower and twice as
long. A pitch of 0 or less plays at 1, and the host logs once.

A Loop's gain or pitch changes in one step. A small change each step sounds
smooth, but a big jump in the gain of a `Here` Loop can click. Change it
over a few steps.

## The Listener and the place

The Listener is the ear that hears a placed sound. In rocco, the Listener is
the camera of the current Scene. The host moves it once per fixed step, at
the camera's `eye`, facing its `target`, with its `up`. It does not move
between steps, and the debug camera does not move it.

The `at` field of a Play or a Loop says where it sounds:

- **`Here`** plays at the Listener, with no direction. The Sound is as loud
  in each ear as its gain says, wherever the camera is. Use it for music,
  the HUD and the player's own sounds.
- **`At({ pos, range })`** plays at `pos` in the world. Its gain falls off
  linearly with the distance from the Listener, from full at the Listener
  to zero at `range`, like a Point Light. Past `range` it is silent. A
  `range` of 0 or less is silent.

A placed sound also pans to the side it is on. To the right of the
Listener, the right ear gets the full gain and the left ear gets a fifth of
it. Straight ahead, each ear gets half. So a placed sound right
in front of the camera is quieter than the same sound `Here`. Raise the
gain of placed sounds if they sound too soft next to the others.

A sound placed on an object that moves needs its new `pos` each step. For
a Loop, set `at` from the Model in `view`, as tutorial chapter 8 does with
the door. A Play keeps the place it started at.

If your camera stands still, every placed sound keeps the same level and
side. Tutorial chapter 8 makes its camera follow Pip, so the hum grows as
Pip walks to the door.

## Voices

Each Play and each Loop that sounds takes a voice. `capacity.voices` in the
[Launch](launch.md) sets how many voices there are, 64 by default. A Play
gives its voice back when it ends. A Loop holds its voice for as long as it
is in the Scene, even at gain 0 or out of range. A Loop that leaves holds
its voice until its fade ends.

When every voice is in use:

- A new Play takes the voice of the oldest Play, which stops. If Loops hold
  every voice, the Play plays nothing.
- A new Loop waits silent. It starts when a voice frees, if it is still in
  the Scene. Waiting Loops start in Scene order.

A Play never takes a Loop's voice, and a Loop never takes a Play's voice.
Each of these cases logs once per run.

`capacity.sounds` sets how many Sounds can be loaded at once, 64 by
default. When the table is full, a `Load` gives the new name id 0, and the
host logs once.

## Bad Sound ids

A Sound id of 0, an id from a Pack that has unloaded, or an id the host
never gave plays nothing. The host logs each id once. There is no fallback
sound, as there is a fallback mesh, so a misspelt name is silent. Read the
log.

A Loop with a bad id tries again each step, so it starts as soon as you
give it a good id. If you unload the Pack of a Loop's Sound and load it
again, the Sound gets a new id. Put the new id in the Loop to start it
again.

## With no audio device

At startup, the host opens the default audio device. If it can't, it logs
once and runs the game with no sound:

```
the audio device did not open: <the reason>. The run has no sound.
```

A Headless run never opens a device. Everything else works the same with
no device. Your game gets the same calls, the host still runs each Play and
Loop, and a Play still ends after its length. So tests and CI run on a
machine with no sound card.

## Sound and the Bridge

The [Bridge](bridge.md) shows each Play in the `commands` of a `step`
reply, and the Loops in the `scene` reply. So a check can find the sound
that a step played without a speaker. `scripts/bridge_check.py` walks Pip
into a pickup in chapter 8, and checks that the `step` reply holds the
Play of the blip:

```
{"op":"step","n":30,"held":["W"]}
{"ok":true,"steps":30,"commands":[{"Play":{"sound":1,"gain":1,"pitch":1,"at":"Here"}}],"alloc":{...}}
```

While the Bridge pauses the run, the sounds play on. A Play plays to its
end, and the Loops keep repeating. Nothing changes until the next step.

## Limits

- No master volume, mute or pause. Scale the gains that your game returns.
- A Play can't stop. Use a Loop for a sound that must stop.
- No streaming. Each Sound is decoded in full when it loads.
- `.wav` and `.ogg` only. No `.flac` or `.mp3`.
- One Listener, the camera.

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Loop.default]: https://pixelsprout.dev/projects/rocco/api/platform/Loop/#Loop.default
