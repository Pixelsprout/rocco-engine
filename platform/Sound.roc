import Vocabulary

## Builds the Play Commands that your game returns from `init` or `step`.
Sound := [].{

	## Plays the Sound with this id once, at gain 1 and pitch 1, `Here` at the
	## Listener. For another gain, pitch or Place, write the `Play` tag
	## yourself, such as `Play({ sound: id, gain: 0.5, pitch: 1.0, at: Here })`.
	play : U32 -> Vocabulary.Command
	play = |id| Play({ sound: id, gain: 1.0, pitch: 1.0, at: Here })
}

expect Sound.play(3) == Play({ sound: 3, gain: 1.0, pitch: 1.0, at: Here })
