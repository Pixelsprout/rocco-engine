import Vocabulary exposing [Vec3]

# Builds the Colliders a game returns in its Scene.
Collider := [].{
	# yaw turns the box in the ground plane.
	box : U64, Vec3, F32, Vec3 -> Vocabulary.Collider
	box = |id, pos, yaw, half| { id, pos, yaw, shape: Box(half) }

	sphere : U64, Vec3, F32 -> Vocabulary.Collider
	sphere = |id, pos, radius| { id, pos, yaw: 0.0, shape: Sphere(radius) }

	# A segment of half_height along y. The host does not test capsules yet.
	capsule : U64, Vec3, F32, F32, F32 -> Vocabulary.Collider
	capsule = |id, pos, yaw, radius, half_height| { id, pos, yaw, shape: Capsule({ radius, half_height }) }
}

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

expect Collider.box(7, origin, 0.5, { x: 0.3, y: 0.5, z: 0.3 }) == { id: 7, pos: origin, yaw: 0.5, shape: Box({ x: 0.3, y: 0.5, z: 0.3 }) }
expect Collider.sphere(3, origin, 0.4) == { id: 3, pos: origin, yaw: 0.0, shape: Sphere(0.4) }
expect Collider.capsule(4, origin, 0.0, 0.3, 0.6) == { id: 4, pos: origin, yaw: 0.0, shape: Capsule({ radius: 0.3, half_height: 0.6 }) }
