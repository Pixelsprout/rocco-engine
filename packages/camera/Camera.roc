## Builds the Camera that your game puts in `Scene.camera`. The `View` type
## has the same shape as `Vocabulary.Camera`.
Camera := [].{

	## A point or a direction in 3D. `+y` is up.
	Vec3 : { x : F32, y : F32, z : F32 }

	## Where the eye is, the point it looks at, the up direction and the
	## vertical field of view in radians.
	View : { eye : Vec3, target : Vec3, up : Vec3, fov_y : F32 }

	## 60 degrees, in radians.
	default_fov_y : F32
	default_fov_y = 1.047

	## `+y`, the `up` that `look_at` and `follow` give. To turn the camera over,
	## replace `up` with a record update.
	world_up : Vec3
	world_up = { x: 0.0, y: 1.0, z: 0.0 }

	## A View from `eye` that looks at `target`, with `world_up` and
	## `default_fov_y`.
	look_at : Vec3, Vec3 -> View
	look_at = |eye, target| { eye, target, up: world_up, fov_y: default_fov_y }

	## A View that looks at `target` from `target` plus `offset`. Give it the
	## player's position each step, and the camera follows the player.
	follow : Vec3, Vec3 -> View
	follow = |target, offset| {
		eye: { x: target.x + offset.x, y: target.y + offset.y, z: target.z + offset.z },
		target,
		up: world_up,
		fov_y: default_fov_y,
	}
}

expect {
	view = Camera.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 1.0, y: 0.0, z: 0.0 })
	view.eye.y == 8.0 and view.target.x == 1.0 and view.up == Camera.world_up and view.fov_y == Camera.default_fov_y
}

expect {
	view = Camera.follow({ x: 1.0, y: 0.0, z: -2.0 }, { x: 0.0, y: 8.0, z: 8.0 })
	view.eye.x == 1.0 and view.eye.y == 8.0 and view.eye.z == 6.0 and view.target.z == -2.0
}
