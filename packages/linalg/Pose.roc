import Vec3
import Quat

## A position and a rotation, such as a Group's in the Scene. The host composes
## Poses with the same rule as `compose`.
Pose := [].{

	## A position and a rotation. Without a parent they are in world space.
	Pose : { pos : Vec3.Vec3, rot : Quat.Quat }

	## At the origin, with no rotation.
	identity : Pose.Pose
	identity = { pos: Vec3.zero, rot: Quat.identity }

	## The world Pose of `local`, a Pose given in the space of `parent`. The
	## result turns by `local.rot` first, then by `parent.rot`.
	compose : Pose.Pose, Pose.Pose -> Pose.Pose
	compose = |parent, local| {
		pos: Vec3.add(parent.pos, Quat.rotate(local.pos, parent.rot)),
		rot: Quat.mul(parent.rot, local.rot),
	}

	## The Pose in the space of `parent` that `compose(parent, _)` sends to
	## `world`. Use it to keep a Node in place when it changes parent.
	## `parent.rot` must be unit length.
	relative : Pose.Pose, Pose.Pose -> Pose.Pose
	relative = |parent, world| {
		undo = Quat.conjugate(parent.rot)
		{
			pos: Quat.rotate(Vec3.sub(world.pos, parent.pos), undo),
			rot: Quat.mul(undo, world.rot),
		}
	}
}

pi : F32
pi = 3.1415927

near_vec : Vec3.Vec3, Vec3.Vec3 -> Bool
near_vec = |a, b| Vec3.length(Vec3.sub(a, b)) < 0.0001

# q and -q are the same turn.
near_rot : Quat.Quat, Quat.Quat -> Bool
near_rot = |a, b| {
	dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
	(dot.abs() - 1.0).abs() < 0.0001
}

near : Pose.Pose, Pose.Pose -> Bool
near = |a, b| near_vec(a.pos, b.pos) and near_rot(a.rot, b.rot)

parent : Pose.Pose
parent = { pos: { x: 1.0, y: 2.0, z: 3.0 }, rot: Quat.from_axis_angle({ x: 1.0, y: 2.0, z: 3.0 }, 0.8) }

local : Pose.Pose
local = { pos: { x: 0.3, y: -1.0, z: 2.0 }, rot: Quat.from_axis_angle({ x: -2.0, y: 0.5, z: 1.0 }, 1.3) }

expect near(Pose.compose(Pose.identity, local), local)

expect near(Pose.compose(parent, Pose.identity), parent)

# A parent a quarter turn about +y sends a child at local +z to world +x.
expect {
	turned = { pos: { x: 5.0, y: 0.0, z: 0.0 }, rot: Quat.from_yaw(pi / 2.0) }
	child = { pos: { x: 0.0, y: 1.0, z: 2.0 }, rot: Quat.identity }
	near(Pose.compose(turned, child), { pos: { x: 7.0, y: 1.0, z: 0.0 }, rot: Quat.from_yaw(pi / 2.0) })
}

# The child's rot turns first, then the parent's.
expect {
	world = Pose.compose(parent, local)
	v = { x: 0.0, y: 0.0, z: 1.0 }
	near_vec(Quat.rotate(v, world.rot), Quat.rotate(Quat.rotate(v, local.rot), parent.rot))
}

# A point in the child's space lands in the same place through the world Pose.
expect {
	world = Pose.compose(parent, local)
	p = { x: -0.4, y: 0.9, z: 1.7 }
	through_parent = Vec3.add(parent.pos, Quat.rotate(Vec3.add(local.pos, Quat.rotate(p, local.rot)), parent.rot))
	near_vec(Vec3.add(world.pos, Quat.rotate(p, world.rot)), through_parent)
}

expect near(Pose.relative(parent, Pose.compose(parent, local)), local)

expect {
	world = { pos: { x: -6.0, y: 0.5, z: 4.0 }, rot: Quat.from_yaw(2.2) }
	near(Pose.compose(parent, Pose.relative(parent, world)), world)
}

expect near(Pose.relative(parent, parent), Pose.identity)
