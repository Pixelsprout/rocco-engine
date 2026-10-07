import Vocabulary exposing [Vec3]

# Builds the Colliders a game returns in its Scene. Games call these and never
# write a kind number. A new kind is a host branch, not a vocabulary change.
Collider := [Box, Sphere, Capsule].{
    kind : Collider -> U8
    kind = |shape| match shape {
        Box => 0
        Sphere => 1
        Capsule => 2
    }

    # yaw turns the box in the ground plane.
    box : U64, Vec3, F32, Vec3 -> Vocabulary.Collider
    box = |id, pos, yaw, half| { id, kind: kind(Box), pos, yaw, extent: half }

    sphere : U64, Vec3, F32 -> Vocabulary.Collider
    sphere = |id, pos, radius| { id, kind: kind(Sphere), pos, yaw: 0.0, extent: { x: radius, y: 0.0, z: 0.0 } }

    # A segment of half_height along y. The host does not test capsules yet.
    capsule : U64, Vec3, F32, F32, F32 -> Vocabulary.Collider
    capsule = |id, pos, yaw, radius, half_height| { id, kind: kind(Capsule), pos, yaw, extent: { x: radius, y: half_height, z: 0.0 } }
}

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

expect Collider.kind(Box) == 0
expect Collider.kind(Sphere) == 1
expect Collider.kind(Capsule) == 2
expect Collider.box(7, origin, 0.5, { x: 0.3, y: 0.5, z: 0.3 }) == { id: 7, kind: 0, pos: origin, yaw: 0.5, extent: { x: 0.3, y: 0.5, z: 0.3 } }
expect Collider.sphere(3, origin, 0.4) == { id: 3, kind: 1, pos: origin, yaw: 0.0, extent: { x: 0.4, y: 0.0, z: 0.0 } }
expect Collider.capsule(4, origin, 0.0, 0.3, 0.6) == { id: 4, kind: 2, pos: origin, yaw: 0.0, extent: { x: 0.3, y: 0.6, z: 0.0 } }
