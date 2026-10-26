import Vocabulary

## Gives the Speaker that your game starts a record update from.
Speaker := [].{

	## Id 0, Sound 0, gain 1, pitch 1, `Here` at the Listener and `Loop`.
	## Sound 0 plays nothing. Set `sound` and `id`.
	default : Vocabulary.Speaker
	default = {
		id: 0,
		sound: 0,
		gain: 1.0,
		pitch: 1.0,
		at: Here,
		repeat: Loop,
	}
}

expect Speaker.default == { id: 0, sound: 0, gain: 1.0, pitch: 1.0, at: Here, repeat: Loop }
