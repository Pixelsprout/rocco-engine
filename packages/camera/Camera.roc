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
	## point outside the window still projects, so clip it yourself. A view
	## with no right direction, such as straight down with no other `up`, sees
	## nothing, so every point is `Behind`.
	project : View, { width : F32, height : F32 }, Vec3 -> Try({ x : F32, y : F32 }, [Behind])
	project = |view, size, point| match basis(view) {
		Ok({ forward, right, true_up }) => {
			offset = sub(point, view.eye)
			depth = dot(forward, offset)
			if depth <= near {
				Err(Behind)
			} else {
				f = focal(view.fov_y)
				ndc_x = f / (size.width / size.height) * dot(right, offset) / depth
				ndc_y = f * dot(true_up, offset) / depth
				Ok({ x: (ndc_x + 1.0) / 2.0 * size.width, y: (1.0 - ndc_y) / 2.0 * size.height })
			}
		}
		Err(NoRight) => Err(Behind)
	}

	## A line from `origin` along the unit direction `dir`.
	Ray : { origin : Vec3, dir : Vec3 }

	## The world ray under a window position, the inverse of `project`. The
	## position and `size` are in logical pixels, as in `Input.pointer` and
	## `Input.window`. The ray starts at the eye. Send it as a Raycast Query to
	## find the Collider under the pointer; the answer comes the next step. A
	## view that sees nothing, as in `project`, is `SeesNothing`.
	unproject : View, { width : F32, height : F32 }, { x : F32, y : F32 } -> Try(Ray, [SeesNothing])
	unproject = |view, size, position| match basis(view) {
		Ok({ forward, right, true_up }) => {
			f = focal(view.fov_y)
			ndc_x = position.x / size.width * 2.0 - 1.0
			ndc_y = 1.0 - position.y / size.height * 2.0
			side = ndc_x * (size.width / size.height) / f
			lift = ndc_y / f
			dir = normalize({
				x: forward.x + right.x * side + true_up.x * lift,
				y: forward.y + right.y * side + true_up.y * lift,
				z: forward.z + right.z * side + true_up.z * lift,
			})
			Ok({ origin: view.eye, dir })
		}
		Err(NoRight) => Err(SeesNothing)
	}
}

# The host's SCENE_NEAR and UP_EPSILON in engine/frame_render.odin.
near : F32
near = 0.1

up_epsilon : F32
up_epsilon = 0.000001

# The host's camera axes. An up along the view falls back to +y, as the host
# does. A view with no right direction sees nothing.
basis : Camera.View -> Try({ forward : Camera.Vec3, right : Camera.Vec3, true_up : Camera.Vec3 }, [NoRight])
basis = |view| {
	view_dir = sub(view.target, view.eye)
	up = if (length(cross(view_dir, view.up)) < up_epsilon) Camera.world_up else view.up
	forward = normalize(view_dir)
	right = normalize(cross(forward, up))
	if dot(right, right) == 0.0 {
		Err(NoRight)
	} else {
		Ok({ forward, right, true_up: cross(right, forward) })
	}
}

focal : F32 -> F32
focal = |fov_y| {
	half = fov_y / 2.0
	half.cos() / half.sin()
}

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

# A 60 degree lens, off axis with a tilted up. The want comes from
# mat4_perspective_reversed_infinite times mat4_look_at in engine/math.odin.
expect {
	view = {
		eye: { x: 3.0, y: 5.0, z: 8.0 },
		target: { x: -1.0, y: 0.5, z: 0.0 },
		up: { x: 0.2, y: 1.0, z: 0.1 },
		fov_y: 1.047,
	}
	match Camera.project(view, test_size, { x: 1.0, y: 2.0, z: -1.0 }) {
		Ok(p) => (p.x - 787.527).abs() < 0.05 and (p.y - 274.871).abs() < 0.05
		Err(_) => Bool.False
	}
}

# A point in front of the eye but nearer than the near plane is Behind.
expect Camera.project(test_view, test_size, { x: 0.0, y: 0.0, z: 9.95 }) == Err(Behind)

# Straight down with +y up has no right direction, so it sees nothing.
expect {
	view = Camera.look_at({ x: 0.0, y: 10.0, z: 0.0 }, { x: 0.0, y: 0.0, z: 0.0 })
	Camera.project(view, test_size, { x: 0.0, y: 0.0, z: 0.0 }) == Err(Behind)
}

# A ray through the middle of the window points along the view.
expect {
	match Camera.unproject(test_view, test_size, { x: 640.0, y: 400.0 }) {
		Ok(ray) => ray.origin == test_view.eye and ray.dir.x.abs() < 0.0001 and ray.dir.y.abs() < 0.0001 and (ray.dir.z + 1.0).abs() < 0.0001
		Err(_) => Bool.False
	}
}

# A point along the ray projects back to the pointer, for a corner and an
# off-centre pointer on a tilted view.
expect {
	view = {
		eye: { x: 3.0, y: 5.0, z: 8.0 },
		target: { x: -1.0, y: 0.5, z: 0.0 },
		up: { x: 0.2, y: 1.0, z: 0.1 },
		fov_y: 1.047,
	}
	round_trips = |pointer|
		match Camera.unproject(view, test_size, pointer) {
			Ok(ray) => {
				along = { x: ray.origin.x + ray.dir.x * 7.0, y: ray.origin.y + ray.dir.y * 7.0, z: ray.origin.z + ray.dir.z * 7.0 }
				match Camera.project(view, test_size, along) {
					Ok(p) => (p.x - pointer.x).abs() < 0.05 and (p.y - pointer.y).abs() < 0.05
					Err(_) => Bool.False
				}
			}
			Err(_) => Bool.False
		}
	round_trips({ x: 0.0, y: 0.0 }) and round_trips({ x: 1280.0, y: 800.0 }) and round_trips({ x: 213.0, y: 611.0 })
}

# The ray's direction has unit length.
expect {
	match Camera.unproject(test_view, test_size, { x: 0.0, y: 800.0 }) {
		Ok(ray) => ((ray.dir.x * ray.dir.x + ray.dir.y * ray.dir.y + ray.dir.z * ray.dir.z) - 1.0).abs() < 0.0001
		Err(_) => Bool.False
	}
}

# Straight down with +y up has no right direction, so it gives no ray.
expect {
	view = Camera.look_at({ x: 0.0, y: 10.0, z: 0.0 }, { x: 0.0, y: 0.0, z: 0.0 })
	Camera.unproject(view, test_size, { x: 640.0, y: 400.0 }) == Err(SeesNothing)
}

# On a tilted view, the ray through the middle of the window points at the target.
expect {
	view = {
		eye: { x: 3.0, y: 5.0, z: 8.0 },
		target: { x: -1.0, y: 0.5, z: 0.0 },
		up: { x: 0.2, y: 1.0, z: 0.1 },
		fov_y: 1.047,
	}
	want = { x: -4.0 / 10.0125, y: -4.5 / 10.0125, z: -8.0 / 10.0125 }
	match Camera.unproject(view, test_size, { x: 640.0, y: 400.0 }) {
		Ok(ray) => (ray.dir.x - want.x).abs() < 0.0001 and (ray.dir.y - want.y).abs() < 0.0001 and (ray.dir.z - want.z).abs() < 0.0001
		Err(_) => Bool.False
	}
}
