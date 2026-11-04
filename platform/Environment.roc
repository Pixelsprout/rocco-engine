import Vocabulary

## Gives the Environment that `Scene.empty` holds.
Environment := [].{

	## No sky, a black clear colour, the `Aces` tone map and an exposure of 1.
	## Fog and bloom are off: the fog `amount` and the bloom `strength` are 0.
	## Raise one to turn it on, as in
	## `fog: { ..Environment.default.fog, amount: 1.0 }`. The other numbers
	## are a starting point: grey fog from 10 to 50 units, and bloom above 2
	## with a knee of 0.5. That threshold halos a glow of about 3 and leaves
	## a lit surface a little above 1 without a halo. A bloom `strength` near
	## 0.2 is a good start.
	default : Vocabulary.Environment
	default = {
		sky: 0,
		clear: { r: 0.0, g: 0.0, b: 0.0 },
		tone_map: Aces,
		exposure: 1.0,
		fog: { color: { r: 0.5, g: 0.5, b: 0.5 }, start: 10.0, end: 50.0, amount: 0.0 },
		bloom: { strength: 0.0, threshold: 2.0, knee: 0.5 },
	}
}

expect Environment.default == { sky: 0, clear: { r: 0.0, g: 0.0, b: 0.0 }, tone_map: Aces, exposure: 1.0, fog: { color: { r: 0.5, g: 0.5, b: 0.5 }, start: 10.0, end: 50.0, amount: 0.0 }, bloom: { strength: 0.0, threshold: 2.0, knee: 0.5 } }
