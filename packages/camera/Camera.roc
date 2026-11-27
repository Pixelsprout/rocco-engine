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

	## A third-person camera that orbits a character. `yaw` is the angle the
	## camera looks along in x/z, with 0 along `+z` and forward at
	## `(sin yaw, cos yaw)`, as for a heading. `pitch` tilts the eye up above
	## the character. `look_y` is the height the camera looks at; it trails
	## the character so a jump does not shake the view.
	Orbit : {
		yaw : F32,
		pitch : F32,
		look_y : F32,
		tuning : Camera.OrbitTuning,
	}

	## How an Orbit moves. `distance` is metres from the look point to the
	## eye. `height` is how far above the character's position the camera
	## looks. `turn` and `tilt` are the right stick's yaw and pitch rates in
	## radians per second. While the right stick rests, the yaw swings toward
	## the heading at `follow` per second, scaled by speed up to
	## `swing_speed`. A zero `follow` turns the swing off.
	OrbitTuning : {
		distance : F32,
		height : F32,
		turn : F32,
		tilt : F32,
		follow : F32,
		swing_speed : F32,
	}

	## What `orbit_step` reads from the character each step. A game whose
	## character glides gives `Air` while it glides.
	Character : {
		pos : Camera.Vec3,
		heading : F32,
		speed : F32,
		footing : [Ground, Air],
	}

	## A gamepad stick or its world direction, each axis from -1 to 1.
	Stick : { x : F32, y : F32 }

	## A camera 7 metres back that swings fully behind a character at
	## 8 metres per second.
	default_orbit_tuning : Camera.OrbitTuning
	default_orbit_tuning = {
		distance: 7.0,
		height: 1.2,
		turn: 2.5,
		tilt: 1.2,
		follow: 2.5,
		swing_speed: 8.0,
	}

	## An Orbit behind a character at `pos` that faces `heading`, tilted a
	## little above it.
	orbit : Camera.OrbitTuning, { pos : Camera.Vec3, heading : F32 } -> Camera.Orbit
	orbit = |tuning, { pos, heading }| {
		yaw: heading,
		pitch: start_pitch,
		look_y: pos.y + tuning.height,
		tuning,
	}

	## Moves an Orbit by one step of `dt` seconds. The right stick `look`
	## turns it: `+x` turns the view right and `+y` lowers the eye. The
	## pitch stays between 0.05 and 1.1. The look height eases toward the
	## character at 5 per second on the Ground and 1.5 per second in the Air.
	orbit_step : Camera.Orbit, { character : Camera.Character, look : Camera.Stick, dt : F32 } -> Camera.Orbit
	orbit_step = |state, { character, look, dt }| {
		tuning = state.tuning
		swing =
			if look.x.abs() > stick_rest or tuning.follow <= 0.0 {
				0.0
			} else {
				pace = if (tuning.swing_speed <= 0.0) 1.0 else F32.min(character.speed / tuning.swing_speed, 1.0)
				F32.min(dt * tuning.follow * pace, 1.0)
			}
		yaw = wrap(state.yaw - look.x * tuning.turn * dt + wrap(character.heading - state.yaw) * swing)
		pitch = F32.max(lowest_pitch, F32.min(highest_pitch, state.pitch - look.y * tuning.tilt * dt))
		rate = match character.footing {
			Ground => ground_look_rate
			Air => air_look_rate
		}
		look_y = state.look_y + (character.pos.y + tuning.height - state.look_y) * F32.min(dt * rate, 1.0)
		{ ..state, yaw, pitch, look_y }
	}

	## The View of an Orbit around a character at `pos`. The eye stays at
	## least 0.4 above `y` 0.
	orbit_view : Camera.Orbit, Camera.Vec3 -> Camera.View
	orbit_view = |state, pos| {
		distance = state.tuning.distance
		target = { x: pos.x, y: state.look_y, z: pos.z }
		back = distance * state.pitch.cos()
		eye = {
			x: target.x - state.yaw.sin() * back,
			y: F32.max(target.y + distance * state.pitch.sin(), lowest_eye),
			z: target.z - state.yaw.cos() * back,
		}
		look_at(eye, target)
	}

	## Turns a stick relative to a camera with `yaw` into a world direction:
	## `x` is world `x` and `y` is world `z`, the shape of `Intent.move` in the
	## controller package. Stick `+y` moves along the view and stick `+x`
	## moves to the screen's right. The length stays the same.
	to_world : Camera.Stick, F32 -> Camera.Stick
	to_world = |stick, yaw| {
		x: yaw.sin() * stick.y - yaw.cos() * stick.x,
		y: yaw.cos() * stick.y + yaw.sin() * stick.x,
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

start_pitch : F32
start_pitch = 0.32

lowest_pitch : F32
lowest_pitch = 0.05

highest_pitch : F32
highest_pitch = 1.1

ground_look_rate : F32
ground_look_rate = 5.0

air_look_rate : F32
air_look_rate = 1.5

lowest_eye : F32
lowest_eye = 0.4

# A right stick tilted less than this along x lets the Orbit swing.
stick_rest : F32
stick_rest = 0.05

# The same angle in -pi to pi.
wrap : F32 -> F32
wrap = |angle| F32.atan2({ x: angle.cos(), y: angle.sin() })

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

## The right stick turns the yaw and leaves the pitch.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 })
	next = Camera.orbit_step(start, { character: standing, look: { x: 1.0, y: 0.0 }, dt: 0.1 })
	actual =
		\\yaw: ${Str.inspect(near_to(next.yaw, -0.25))}
		\\pitch: ${Str.inspect(next.pitch == start.pitch)}
	expected =
		\\yaw: True
		\\pitch: True
	actual == expected
}

## At rest the yaw swings toward the heading, scaled by speed up to
## swing_speed.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 })
	swung = |speed| {
		character = { ..standing, heading: 1.0, speed }
		Camera.orbit_step(start, { character, look: rest, dt: 0.1 }).yaw
	}
	actual =
		\\full: ${Str.inspect(near_to(swung(8.0), 0.25))}
		\\faster: ${Str.inspect(near_to(swung(20.0), 0.25))}
		\\half: ${Str.inspect(near_to(swung(4.0), 0.125))}
		\\standing: ${Str.inspect(swung(0.0) == 0.0)}
	expected =
		\\full: True
		\\faster: True
		\\half: True
		\\standing: True
	actual == expected
}

## The swing takes the short way across the turn from pi to -pi.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 3.0 })
	character = { ..standing, heading: -3.0, speed: 8.0 }
	next = Camera.orbit_step(start, { character, look: rest, dt: 0.1 })
	(next.yaw - 3.0708).abs() < 0.001
}

## The right stick stops the swing.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 })
	character = { ..standing, heading: 1.0, speed: 8.0 }
	next = Camera.orbit_step(start, { character, look: { x: 0.5, y: 0.0 }, dt: 0.1 })
	near_to(next.yaw, -0.125)
}

## A zero follow turns the swing off.
expect {
	start = Camera.orbit({ ..Camera.default_orbit_tuning, follow: 0.0 }, { pos: origin, heading: 0.0 })
	character = { ..standing, heading: 1.0, speed: 8.0 }
	Camera.orbit_step(start, { character, look: rest, dt: 0.1 }).yaw == 0.0
}

## The pitch stays between 0.05 and 1.1.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 })
	low = Camera.orbit_step(start, { character: standing, look: { x: 0.0, y: 1.0 }, dt: 1.0 })
	high = Camera.orbit_step(start, { character: standing, look: { x: 0.0, y: -1.0 }, dt: 1.0 })
	actual =
		\\low: ${Str.inspect(low.pitch)}
		\\high: ${Str.inspect(high.pitch)}
	expected =
		\\low: 0.05
		\\high: 1.1
	actual == expected
}

## The look height eases toward 1.2 above the character, faster on the
## Ground than in the Air, and never past it.
expect {
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 })
	eased = |footing, dt| {
		character = { ..standing, pos: { x: 0.0, y: 2.0, z: 0.0 }, footing }
		Camera.orbit_step(start, { character, look: rest, dt }).look_y
	}
	actual =
		\\ground: ${Str.inspect(near_to(eased(Ground, 0.1), 2.2))}
		\\air: ${Str.inspect(near_to(eased(Air, 0.1), 1.5))}
		\\long: ${Str.inspect(near_to(eased(Ground, 1.0), 3.2))}
	expected =
		\\ground: True
		\\air: True
		\\long: True
	actual == expected
}

## The eye sits distance back along the yaw and up along the pitch, and looks
## at the look height above the character.
expect {
	state = { ..Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.0 }), pitch: 0.5235988 }
	view = Camera.orbit_view(state, { x: 1.0, y: 0.0, z: 2.0 })
	actual =
		\\eye: ${Str.inspect(near_to(view.eye.x, 1.0) and near_to(view.eye.y, 4.7) and near_to(view.eye.z, -4.0622))}
		\\target: ${Str.inspect(view.target == { x: 1.0, y: 1.2, z: 2.0 })}
		\\up: ${Str.inspect(view.up == Camera.world_up)}
	expected =
		\\eye: True
		\\target: True
		\\up: True
	actual == expected
}

## Looking along +x from a low point, the eye stays at least 0.4 high.
expect {
	low = { x: 0.0, y: -3.2, z: 0.0 }
	start = Camera.orbit(Camera.default_orbit_tuning, { pos: low, heading: 1.5707964 })
	view = Camera.orbit_view({ ..start, pitch: 0.05 }, low)
	actual =
		\\y: ${Str.inspect(view.eye.y)}
		\\x: ${Str.inspect(near_to(view.eye.x, -6.9913))}
		\\z: ${Str.inspect(near_to(view.eye.z, 0.0))}
	expected =
		\\y: 0.4
		\\x: True
		\\z: True
	actual == expected
}

## Stick up moves along the view and stick right moves to the screen's right.
## Looking along +z, screen right is -x. Looking along +x, it is +z.
expect {
	quarter = 1.5707964
	actual =
		\\up at 0: ${Str.inspect(stick_near(Camera.to_world({ x: 0.0, y: 1.0 }, 0.0), { x: 0.0, y: 1.0 }))}
		\\right at 0: ${Str.inspect(stick_near(Camera.to_world({ x: 1.0, y: 0.0 }, 0.0), { x: -1.0, y: 0.0 }))}
		\\up at quarter: ${Str.inspect(stick_near(Camera.to_world({ x: 0.0, y: 1.0 }, quarter), { x: 1.0, y: 0.0 }))}
		\\right at quarter: ${Str.inspect(stick_near(Camera.to_world({ x: 1.0, y: 0.0 }, quarter), { x: 0.0, y: 1.0 }))}
		\\mixed at quarter: ${Str.inspect(stick_near(Camera.to_world({ x: 0.3, y: 0.4 }, quarter), { x: 0.4, y: 0.3 }))}
	expected =
		\\up at 0: True
		\\right at 0: True
		\\up at quarter: True
		\\right at quarter: True
		\\mixed at quarter: True
	actual == expected
}

## A stick pushed right moves a point right on the screen of the Orbit's View.
expect {
	state = Camera.orbit(Camera.default_orbit_tuning, { pos: origin, heading: 0.7 })
	view = Camera.orbit_view(state, origin)
	move = Camera.to_world({ x: 1.0, y: 0.0 }, state.yaw)
	here = Camera.project(view, test_size, { x: 0.0, y: 1.2, z: 0.0 })
	there = Camera.project(view, test_size, { x: move.x, y: 1.2, z: move.y })
	match (here, there) {
		(Ok(a), Ok(b)) => b.x > a.x + 1.0 and (b.y - a.y).abs() < 1.0
		_ => Bool.False
	}
}

origin : Camera.Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

rest : Camera.Stick
rest = { x: 0.0, y: 0.0 }

standing : Camera.Character
standing = { pos: origin, heading: 0.0, speed: 0.0, footing: Ground }

near_to : F32, F32 -> Bool
near_to = |a, b| (a - b).abs() < 0.001

stick_near : Camera.Stick, Camera.Stick -> Bool
stick_near = |a, b| near_to(a.x, b.x) and near_to(a.y, b.y)
