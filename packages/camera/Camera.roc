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

	## Where `point` lands in a window of `size`, in logical pixels: `x` from 0
	## at the left edge to `width`, `y` from 0 at the top edge to `height`. It
	## uses the host's lens, so `+y` is up and the aspect is `width / height`.
	## If `up` is zero or along the view, it uses `+y` like the host. A point
	## no more than 0.1 in front of the eye, the near plane, is `Behind`. A
	## point outside the window still projects, so clip it yourself.
	project : View, { width : F32, height : F32 }, Vec3 -> Try({ x : F32, y : F32 }, [Behind])
	project = |view, size, point| {
		view_dir = sub(view.target, view.eye)
		up = if length(cross(view_dir, view.up)) < up_epsilon world_up else view.up
		forward = normalize(view_dir)
		right = normalize(cross(forward, up))
		true_up = cross(right, forward)
		offset = sub(point, view.eye)
		depth = dot(forward, offset)
		if depth <= near {
			Err(Behind)
		} else {
			half = view.fov_y / 2.0
			focal = half.cos() / half.sin()
			ndc_x = focal / (size.width / size.height) * dot(right, offset) / depth
			ndc_y = focal * dot(true_up, offset) / depth
			Ok({ x: (ndc_x + 1.0) / 2.0 * size.width, y: (1.0 - ndc_y) / 2.0 * size.height })
		}
	}
}

# The host's SCENE_NEAR and UP_EPSILON in engine/frame_render.odin.
near : F32
near = 0.1

up_epsilon : F32
up_epsilon = 0.000001

# The camera package does not import linalg, so it keeps its own vector helpers.
sub : Camera.Vec3, Camera.Vec3 -> Camera.Vec3
sub = |a, b| { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }

dot : Camera.Vec3, Camera.Vec3 -> F32
dot = |a, b| a.x * b.x + a.y * b.y + a.z * b.z

cross : Camera.Vec3, Camera.Vec3 -> Camera.Vec3
cross = |a, b| {
	x: a.y * b.z - a.z * b.y,
	y: a.z * b.x - a.x * b.z,
	z: a.x * b.y - a.y * b.x,
}

length : Camera.Vec3 -> F32
length = |v| dot(v, v).sqrt()

# Zero stays zero, so an eye on its target gives a zero forward and Behind.
normalize : Camera.Vec3 -> Camera.Vec3
normalize = |v| {
	len = length(v)
	if len == 0.0 {
		v
	} else {
		{ x: v.x / len, y: v.y / len, z: v.z / len }
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

# A 90 degree lens at z 10 looking at the origin in a 1280 by 800 window.
test_view : Camera.View
test_view = { ..Camera.look_at({ x: 0.0, y: 0.0, z: 10.0 }, { x: 0.0, y: 0.0, z: 0.0 }), fov_y: 1.5707964 }

test_size : { width : F32, height : F32 }
test_size = { width: 1280.0, height: 800.0 }

# The target lands in the middle of the window.
expect {
	match Camera.project(test_view, test_size, { x: 0.0, y: 0.0, z: 0.0 }) {
		Ok(p) => (p.x - 640.0).abs() < 0.01 and (p.y - 400.0).abs() < 0.01
		Err(_) => Bool.False
	}
}

# +y is up: a point at the top of the frustum has y 0.
expect {
	match Camera.project(test_view, test_size, { x: 0.0, y: 10.0, z: 0.0 }) {
		Ok(p) => p.y.abs() < 0.01
		Err(_) => Bool.False
	}
}

# The aspect widens x: 16 units right at distance 10 is the right edge at 1.6 aspect.
expect {
	match Camera.project(test_view, test_size, { x: 16.0, y: 0.0, z: 0.0 }) {
		Ok(p) => (p.x - 1280.0).abs() < 0.01
		Err(_) => Bool.False
	}
}

# A point behind the eye is Behind.
expect Camera.project(test_view, test_size, { x: 0.0, y: 0.0, z: 20.0 }) == Err(Behind)

# A point past the window still projects, so the caller can clip.
expect {
	match Camera.project(test_view, test_size, { x: 32.0, y: 0.0, z: 0.0 }) {
		Ok(p) => p.x > 1280.0
		Err(_) => Bool.False
	}
}

# An up along the view falls back to +y, as the host does.
expect {
	view = { ..test_view, up: { x: 0.0, y: 0.0, z: 1.0 } }
	match Camera.project(view, test_size, { x: 0.0, y: 10.0, z: 0.0 }) {
		Ok(p) => p.y.abs() < 0.01 and (p.x - 640.0).abs() < 0.01
		Err(_) => Bool.False
	}
}

# An eye on its target sees nothing.
expect {
	view = { ..test_view, target: test_view.eye }
	Camera.project(view, test_size, { x: 0.0, y: 0.0, z: 0.0 }) == Err(Behind)
}
