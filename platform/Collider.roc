import Vocabulary exposing [Quat, Vec3]

## Builds the Colliders that your game puts in `Scene.nodes` with the
## `Collider` tag. The `id` is the draw id of the Collider. `pos` and `rot`
## are local to the Collider's Group.
Collider := [].{

	## A box at `pos` with half extents `half`, turned by `rot`.
	box : U64, Vec3, Quat, Vec3 -> Vocabulary.Collider
	box = |id, pos, rot, half| { id, pos, rot, shape: Box(half) }

	## A sphere at `pos` with a radius. It has no turn.
	sphere : U64, Vec3, F32 -> Vocabulary.Collider
	sphere = |id, pos, radius| { id, pos, rot: identity, shape: Sphere(radius) }

	## A capsule at `pos`: a radius around a segment of `half_height` along its
	## own `y`, turned by `rot`. The host does not test capsules yet.
	capsule : U64, Vec3, Quat, F32, F32 -> Vocabulary.Collider
	capsule = |id, pos, rot, radius, half_height| { id, pos, rot, shape: Capsule({ radius, half_height }) }
}

identity : Quat
identity = { x: 0.0, y: 0.0, z: 0.0, w: 1.0 }

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

pitched : Quat
pitched = { x: 0.3826834, y: 0.0, z: 0.0, w: 0.9238795 }

expect Collider.box(7, origin, pitched, { x: 0.3, y: 0.5, z: 0.3 }) == { id: 7, pos: origin, rot: pitched, shape: Box({ x: 0.3, y: 0.5, z: 0.3 }) }
expect Collider.sphere(3, origin, 0.4) == { id: 3, pos: origin, rot: identity, shape: Sphere(0.4) }
expect Collider.capsule(4, origin, pitched, 0.3, 0.6) == { id: 4, pos: origin, rot: pitched, shape: Capsule({ radius: 0.3, half_height: 0.6 }) }
