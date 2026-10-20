import Vocabulary exposing [Quat]

# The Draw a game starts a record update from.
Draw := [].{
	# Mesh 0 draws the Fallback mesh.
	default : Vocabulary.Draw
	default = {
		id: 0,
		mesh: 0,
		pos: { x: 0.0, y: 0.0, z: 0.0 },
		scale: { x: 1.0, y: 1.0, z: 1.0 },
		rot: identity,
		scale_rot: identity,
		tint: { r: 1.0, g: 1.0, b: 1.0 },
	}
}

identity : Quat
identity = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }

expect Draw.default == { id: 0, mesh: 0, pos: { x: 0.0, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.0 }, rot: identity, scale_rot: identity, tint: { r: 1.0, g: 1.0, b: 1.0 } }
