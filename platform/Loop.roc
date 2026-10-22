import Vocabulary

## Gives the Loop that your game starts a record update from.
Loop := [].{

	## Id 0, Sound 0, gain 1, pitch 1 and `Here` at the Listener. Sound 0
	## plays nothing. Set `sound` and `id`.
	default : Vocabulary.Loop
	default = {
		id: 0,
		sound: 0,
		gain: 1.0,
		pitch: 1.0,
		at: Here,
	}
}

expect Loop.default == { id: 0, sound: 0, gain: 1.0, pitch: 1.0, at: Here }
