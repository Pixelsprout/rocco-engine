import Vocabulary

## A seeded source of host-simulated billboards.
Emitter := [].{

	## A stationary, soft round Alpha source. Set an id and rate before use.
	default : Vocabulary.Emitter
	default = { id: 0, position: { x: 0, y: 0, z: 0 }, rate: 0, lifetime: 1, start_size: 0.2, end_size: 1, start_colour: { r: 1, g: 1, b: 1, a: 0.5 }, end_colour: { r: 1, g: 1, b: 1, a: 0 }, velocity: { x: 0, y: 1, z: 0 }, velocity_spread: { x: 0.2, y: 0.2, z: 0.2 }, drag: 0, seed: 1, image: 0, blend: Alpha }

	## Emit once after this step's view. The source must be in that Scene.
	burst : U64, U32 -> Vocabulary.Command
	burst = |emitter, count| Burst({ emitter, count })
}
