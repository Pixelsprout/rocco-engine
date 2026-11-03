import Vocabulary

## Gives the Environment that `Scene.empty` holds, and a Bloom to start from.
Environment := [].{

	## No sky, a black clear colour, the `Aces` tone map, an exposure of 1, no
	## fog and no bloom.
	default : Vocabulary.Environment
	default = {
		sky: 0,
		clear: { r: 0.0, g: 0.0, b: 0.0 },
		tone_map: Aces,
		exposure: 1.0,
		fog: None,
		bloom: None,
	}

	## A Bloom to start from: strength 0.5, threshold 1 and knee 0.5. Set it
	## with `{ ..Environment.default, bloom: Environment.bloom }`.
	bloom : [None, Bloom({ strength : F32, threshold : F32, knee : F32 })]
	bloom = Bloom({ strength: 0.5, threshold: 1.0, knee: 0.5 })
}

expect Environment.default == { sky: 0, clear: { r: 0.0, g: 0.0, b: 0.0 }, tone_map: Aces, exposure: 1.0, fog: None, bloom: None }
expect Environment.bloom == Bloom({ strength: 0.5, threshold: 1.0, knee: 0.5 })
