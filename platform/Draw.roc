import Vocabulary exposing [Quat]

## Gives the Draw that your game starts a record update from.
Draw := [].{

	## Id 0, mesh 0, at the origin, scale 1, no rotation, a white tint, no
	## glow and a Pose of all zeros, which draws the bind pose. Mesh 0 draws
	## the Fallback mesh. Set `mesh` and `id`.
	default : Vocabulary.Draw
	default = {
		id: 0,
		mesh: 0,
		pos: { x: 0.0, y: 0.0, z: 0.0 },
		scale: { x: 1.0, y: 1.0, z: 1.0 },
		rot: identity,
		scale_rot: identity,
		tint: { r: 1.0, g: 1.0, b: 1.0 },
		glow: { r: 0.0, g: 0.0, b: 0.0 },
		pose: { clip: 0, time: 0.0, fade_clip: 0, fade_time: 0.0, fade: 0.0 },
	}
}

identity : Quat
identity = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }

expect Draw.default == { id: 0, mesh: 0, pos: { x: 0.0, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.0 }, rot: identity, scale_rot: identity, tint: { r: 1.0, g: 1.0, b: 1.0 }, glow: { r: 0.0, g: 0.0, b: 0.0 }, pose: { clip: 0, time: 0.0, fade_clip: 0, fade_time: 0.0, fade: 0.0 } }
