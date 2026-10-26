import Vocabulary

## Finds Sound ids in a Manifest, and builds the Play Commands that your game
## returns from `init` or `step`.
Sound := [].{

	## The Sound id of a name in the Manifest, such as `sound/jump`. Call it
	## once, in `loaded`, and keep the id in your Model. A name that is not in
	## the Manifest gives 0, which plays nothing.
	resolve : Vocabulary.Manifest, Str -> U32
	resolve = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.id
		Err(NotFound) => 0
	}

	## The length in seconds at pitch 1 of the Sound with this name, such as
	## `sound/creak`. A Speaker at pitch 2 ends in half this time. A name that
	## is not in the Manifest, a mesh or a sky gives 0.
	duration : Vocabulary.Manifest, Str -> F32
	duration = |manifest, name| match List.find_first(manifest, |m| m.name == name) {
		Ok(m) => m.duration
		Err(NotFound) => 0
	}

	## Plays the Sound with this id once, at gain 1 and pitch 1, `Here` at the
	## Listener. For another gain, pitch or Place, write the `Play` tag
	## yourself, such as `Play({ sound: id, gain: 0.5, pitch: 1.0, at: Here })`.
	play : U32 -> Vocabulary.Command
	play = |id| Play({ sound: id, gain: 1.0, pitch: 1.0, at: Here })
}

expect Sound.resolve([{ name: "pip", id: 4, duration: 0.0, clips: [] }, { name: "sound/jump", id: 65541, duration: 0.0, clips: [] }], "sound/jump") == 65541
expect Sound.resolve([{ name: "sound/jump", id: 0, duration: 0.0, clips: [] }], "sound/jump") == 0
expect Sound.resolve([{ name: "sound/jump", id: 5, duration: 0.0, clips: [] }], "sound/jmup") == 0
expect Sound.duration([{ name: "pip", id: 4, duration: 0.0, clips: [] }, { name: "sound/creak", id: 65541, duration: 1.5, clips: [] }], "sound/creak") == 1.5
expect Sound.duration([{ name: "sound/creak", id: 65541, duration: 1.5, clips: [] }], "sound/crek") == 0.0
expect Sound.play(3) == Play({ sound: 3, gain: 1.0, pitch: 1.0, at: Here })
