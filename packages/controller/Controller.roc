import collide.Ground
import collide.Solids
import linalg.Vec3 as V

## A third-person character that walks, jumps and glides over a Ground and
## around Solids, in the same step. Keep a Controller in the Model and step
## it each frame.
Controller := [].{

	## The character's state. `pos` is the foot. `vel` is in metres per
	## second, and its x/z part points along `heading`. `heading` is the
	## angle in x/z with 0 along `+z` and forward at `(sin heading, cos
	## heading)`. `coyote_left` and `jump_buffer_left` are the seconds left
	## of each window.
	Controller : {
		pos : V.Vec3,
		vel : V.Vec3,
		heading : F32,
		motion : Controller.Motion,
		coyote_left : F32,
		jump_buffer_left : F32,
		tuning : Controller.Tuning,
	}

	## On the Ground, falling or rising in the Air, or gliding.
	Motion : [Ground, Air, Glide]

	## What the player asks for this step. `move` is a world direction on
	## x/z: `x` is world `x` and `y` is world `z`, with a length up to 1.
	Intent : {
		move : { x : F32, y : F32 },
		jump_pressed : Bool,
		jump_held : Bool,
	}

	## How the character moves, in metres, seconds and radians. `walk` is the
	## speed at 70 % stick tilt and `gallop` at full tilt. `turn` is radians
	## per second, 60 % of it in the Air. `accel` speeds the character up,
	## half of it in the Air, and `decel` slows it when the stick asks for
	## less. `jump` is the jump height and `gravity` pulls it down.
	## `glide_speed` and `glide_fall` are the glide's forward and down
	## speeds. `coyote` and
	## `jump_buffer` are windows in seconds. `step_up` is the tallest box
	## the character walks onto. `slope_limit` is the steepest Ground it
	## stands on, in radians. `radius` and `height` size its capsule. A
	## zero `glide_fall`, `coyote`, `jump_buffer`, `step_up` or
	## `slope_limit` turns that feature off.
	Tuning : {
		walk : F32,
		gallop : F32,
		turn : F32,
		accel : F32,
		decel : F32,
		jump : F32,
		gravity : F32,
		glide_speed : F32,
		glide_fall : F32,
		coyote : F32,
		jump_buffer : F32,
		step_up : F32,
		slope_limit : F32,
		radius : F32,
		height : F32,
	}

	## The defaults, tuned by playing a 1.5 m character on a gamepad.
	default_tuning : Controller.Tuning
	default_tuning = {
		walk: 2.5,
		gallop: 8.0,
		turn: 6.2831855,
		accel: 12.0,
		decel: 24.0,
		jump: 1.6,
		gravity: 25.0,
		glide_speed: 9.0,
		glide_fall: 2.0,
		coyote: 0.1,
		jump_buffer: 0.1,
		step_up: 0.35,
		slope_limit: 0.87266463,
		radius: 0.45,
		height: 1.5,
	}

	## A character standing still at `pos`, facing `+z`.
	new : Controller.Tuning, V.Vec3 -> Controller.Controller
	new = |tuning, pos| {
		pos,
		vel: V.zero,
		heading: 0.0,
		motion: Ground,
		coyote_left: 0.0,
		jump_buffer_left: 0.0,
		tuning,
	}

	## Moves the character by one step of `dt` seconds. It stands on `ground`,
	## so give it the Ground with the tops of the Solids, as
	## `Ground.highest(terrain, Ground.tops(solids))`, and it walks around
	## `solids`. A press jumps from the Ground, within `coyote` after leaving
	## it, or up to `jump_buffer` before landing. Holding jump while falling
	## glides, and letting go while rising cuts the jump short.
	step : Controller.Controller, Controller.Intent, Ground.Ground, Solids, F32 -> Controller.Controller
	step = |state, intent, ground, solids, dt| {
		tuning = state.tuning
		tilt = F32.min(length_2d(intent.move), 1.0)
		heading = turned(state, { move: intent.move, tilt, dt })
		asked = intent.jump_pressed or state.jump_buffer_left > 0.0
		jumping = asked and (state.motion == Ground or (state.motion == Air and state.coyote_left > 0.0))
		speed = horizontal_speed(state, { tilt, dt })
		vy = vertical_speed(state, { intent, jumping, dt })
		motion = next_motion(state, { intent, jumping, vy })
		facing = { x: heading.sin(), z: heading.cos() }
		moved = slide({
			tuning,
			solids,
			motion,
			pos: state.pos,
			by: { x: facing.x * speed * dt, z: facing.z * speed * dt },
		})
		settled = settle({
			tuning,
			ground,
			solids,
			from: state.pos,
			pos: moved,
			vy,
			motion,
			reach_down: F32.max(tuning.step_up, speed * dt),
			dt,
		})
		{
			..state,
			pos: settled.pos,
			vel: { x: facing.x * speed, y: settled.vy, z: facing.z * speed },
			heading,
			motion: settled.motion,
			coyote_left: if (jumping) 0.0
			else if (settled.motion == Ground or state.motion == Ground) tuning.coyote
			else F32.max(0.0, state.coyote_left - dt),
			jump_buffer_left: if (jumping) 0.0
			else if (intent.jump_pressed) tuning.jump_buffer
			else F32.max(0.0, state.jump_buffer_left - dt),
		}
	}

	## True when `after`, the step that follows `before`, lands on the Ground.
	landed : Controller.Controller, Controller.Controller -> Bool
	landed = |before, after| before.motion != Ground and after.motion == Ground

	## True when `after`, the step that follows `before`, jumps.
	jumped : Controller.Controller, Controller.Controller -> Bool
	jumped = |before, after| after.vel.y > 0.0 and before.vel.y <= 0.0
}

# How fast a released jump loses its rise, per second.
release_damping : F32
release_damping = 12.0

# The share of the turn rate the character keeps in the Air.
air_turn : F32
air_turn = 0.6

# The share of the accel the character keeps in the Air.
air_accel : F32
air_accel = 0.5

# A move along a slope or a push this small is not a rise.
rise_epsilon : F32
rise_epsilon = 0.0001

vertical_speed : Controller.Controller, { intent : Controller.Intent, jumping : Bool, dt : F32 } -> F32
vertical_speed = |state, { intent, jumping, dt }| {
	tuning = state.tuning
	fall = tuning.gravity * dt
	if jumping {
		(2.0 * tuning.gravity * tuning.jump).sqrt()
	} else {
		match state.motion {
			Ground => 0.0
			Air if !intent.jump_held and state.vel.y > 0.0 => state.vel.y * F32.max(0.0, 1.0 - release_damping * dt) - fall
			Air => state.vel.y - fall
			Glide => approach(state.vel.y, { to: -tuning.glide_fall, by: fall })
		}
	}
}

# A jump leaves the Ground. Holding jump while falling glides, and letting
# go ends the glide. Landing is for settle.
next_motion : Controller.Controller, { intent : Controller.Intent, jumping : Bool, vy : F32 } -> Controller.Motion
next_motion = |state, { intent, jumping, vy }|
	if jumping {
		Air
	} else {
		match state.motion {
			Air if intent.jump_held and vy < 0.0 and state.tuning.glide_fall > 0.0 => Glide
			Glide if !intent.jump_held => Air
			other => other
		}
	}

horizontal_speed : Controller.Controller, { tilt : F32, dt : F32 } -> F32
horizontal_speed = |state, { tilt, dt }| {
	tuning = state.tuning
	was = length_2d({ x: state.vel.x, y: state.vel.z })
	wanted = wanted_speed(tuning, tilt)
	match state.motion {
		Ground => approach(was, { to: wanted, by: (if (wanted < was) tuning.decel else tuning.accel) * dt })
		Air => approach(was, { to: F32.max(was, wanted), by: tuning.accel * air_accel * dt })
		Glide => approach(was, { to: tuning.glide_speed, by: tuning.accel * air_accel * dt })
	}
}

# Moves the foot along x/z in substeps no longer than the radius, out of
# the Solids. On the Ground the capsule is lifted by step_up, so a box no
# taller than that is left to the Ground; a push up onto a taller box is a
# wall there.
slide : Slide -> V.Vec3
slide = |{ tuning, solids, motion, pos, by }| {
	count =
		if tuning.radius <= 0.0 {
			1
		} else {
			(length_2d({ x: by.x, y: by.z }) / tuning.radius).div_floor_by(1.0).to_u64_wrap() + 1
		}
	part = { x: by.x / count.to_f32(), z: by.z / count.to_f32() }
	go = |at, left|
		if left == 0 {
			at
		} else {
			go(substep({ tuning, solids, motion, from: at, by: part, tries: wall_tries }), left - 1)
		}
	go(pos, count)
}

Slide : {
	tuning : Controller.Tuning,
	solids : Solids,
	motion : Controller.Motion,
	pos : V.Vec3,
	by : { x : F32, z : F32 },
}

# Halvings of a substep that ends inside a wall, so the character closes the
# gap to it.
wall_tries : U64
wall_tries = 4

Substep : {
	tuning : Controller.Tuning,
	solids : Solids,
	motion : Controller.Motion,
	from : V.Vec3,
	by : { x : F32, z : F32 },
	tries : U64,
}

substep : Substep -> V.Vec3
substep = |{ tuning, solids, motion, from, by, tries }| {
	to = { x: from.x + by.x, y: from.y, z: from.z + by.z }
	lift = if (motion == Ground) tuning.step_up else 0.0
	foot = { ..to, y: to.y + lift }
	capsule = { foot, radius: tuning.radius, height: F32.max(tuning.height - lift, 2.0 * tuning.radius) }
	match Solids.push_out(solids, capsule) {
		Clear => to
		Pushed(pushed) if motion != Ground => pushed.foot
		Pushed(pushed) if pushed.foot.y <= foot.y + rise_epsilon => { ..pushed.foot, y: to.y }
		Pushed(_) if tries == 0 => from
		Pushed(_) => substep({ tuning, solids, motion, from, by: { x: by.x / 2.0, z: by.z / 2.0 }, tries: tries - 1 })
	}
}

Settle : {
	tuning : Controller.Tuning,
	ground : Ground.Ground,
	solids : Solids,
	from : V.Vec3,
	pos : V.Vec3,
	vy : F32,
	motion : Controller.Motion,
	reach_down : F32,
	dt : F32,
}

Settled : { pos : V.Vec3, vy : F32, motion : Controller.Motion }

# Puts the foot on the Ground, or moves it through the Air and lands it. A
# rise into a Solid ends there. A move up a steep surface goes back to `from`.
settle : Settle -> Settled
settle = |{ tuning, ground, solids, from, pos, vy, motion, reach_down, dt }| {
	on_steep = |hit|
		if hit.y > from.y + rise_epsilon {
			{ pos: from, vy: 0.0, motion: Air }
		} else {
			fall = F32.max(-vy, 0.0) * dt
			x = pos.x + hit.normal.x * fall
			z = pos.z + hit.normal.z * fall
			y = match ground(x, z, hit.y) {
				Hit(below) => below.y
				Miss => hit.y
			}
			{ pos: { x, y, z }, vy: F32.min(vy, 0.0), motion: Air }
		}
	if motion == Ground {
		match ground(pos.x, pos.z, pos.y + tuning.step_up) {
			Hit(hit) if hit.y >= pos.y - reach_down and is_steep(tuning, hit.normal) => on_steep(hit)
			Hit(hit) if hit.y >= pos.y - reach_down => { pos: { ..pos, y: hit.y }, vy: 0.0, motion: Ground }
			_ => { pos, vy: 0.0, motion: Air }
		}
	} else if vy > 0.0 {
		risen = { ..pos, y: pos.y + vy * dt }
		match Solids.push_out(solids, { foot: risen, radius: tuning.radius, height: tuning.height }) {
			Pushed(pushed) if pushed.foot.y < risen.y => { pos: pushed.foot, vy: 0.0, motion }
			Pushed(pushed) => { pos: pushed.foot, vy, motion }
			Clear => { pos: risen, vy, motion }
		}
	} else {
		to = pos.y + vy * dt
		match Ground.sweep(ground, { x: pos.x, z: pos.z, from: pos.y, to }) {
			Hit(hit) if is_steep(tuning, hit.normal) => on_steep(hit)
			Hit(hit) => { pos: { ..pos, y: hit.y }, vy: 0.0, motion: Ground }
			Miss => { pos: { ..pos, y: to }, vy, motion }
		}
	}
}

is_steep : Controller.Tuning, V.Vec3 -> Bool
is_steep = |tuning, normal| tuning.slope_limit > 0.0 and normal.y < tuning.slope_limit.cos()

# A stick tilted less than this rests.
stick_rest : F32
stick_rest = 0.05

# The stick tilt where the walk ends and the gallop begins.
walk_tilt : F32
walk_tilt = 0.7

wanted_speed : Controller.Tuning, F32 -> F32
wanted_speed = |tuning, tilt|
	if (tilt < stick_rest) 0.0
	else if (tilt < walk_tilt) tuning.walk * tilt / walk_tilt
	else tuning.walk + (tuning.gallop - tuning.walk) * (tilt - walk_tilt) / (1.0 - walk_tilt)

turned : Controller.Controller, { move : { x : F32, y : F32 }, tilt : F32, dt : F32 } -> F32
turned = |state, { move, tilt, dt }|
	if tilt < stick_rest {
		state.heading
	} else {
		reach = state.tuning.turn * dt * (if (state.motion == Ground) 1.0 else air_turn)
		gap = wrap(F32.atan2({ x: move.y, y: move.x }) - state.heading)
		wrap(state.heading + F32.max(-reach, F32.min(reach, gap)))
	}

approach : F32, { to : F32, by : F32 } -> F32
approach = |value, { to, by }|
	if (value < to) F32.min(to, value + by) else F32.max(to, value - by)

# The same angle in -pi to pi.
wrap : F32 -> F32
wrap = |angle| F32.atan2({ x: angle.cos(), y: angle.sin() })

length_2d : { x : F32, y : F32 } -> F32
length_2d = |v| (v.x * v.x + v.y * v.y).sqrt()

## Full stick forward on flat ground speeds the character up at accel along
## its heading.
expect {
	start = Controller.new(Controller.default_tuning, V.zero)
	next = Controller.step(start, forward, floor, no_solids, 0.1)
	actual =
		\\speed: ${Str.inspect(near_to(next.vel.z, 1.2))}
		\\moved: ${Str.inspect(near_to(next.pos.z, 0.12))}
		\\motion: ${Str.inspect(next.motion)}
	expected =
		\\speed: True
		\\moved: True
		\\motion: Ground
	actual == expected
}

forward : Controller.Intent
forward = { ..still, move: { x: 0.0, y: 1.0 } }

still : Controller.Intent
still = {
	move: { x: 0.0, y: 0.0 },
	jump_pressed: Bool.False,
	jump_held: Bool.False,
}

jump : Controller.Intent
jump = { ..still, jump_pressed: Bool.True }

# Steps `count` times at 60 per second with the same Intent. The press is
# only on the first step.
run : Controller.Controller, { intent : Controller.Intent, ground : Ground.Ground, solids : Solids, count : U64 } -> { last : Controller.Controller, peak : F32 }
run = |start, { intent, ground, solids, count }| {
	go = |sofar, now, left|
		if left == 0 {
			sofar
		} else {
			next = Controller.step(sofar.last, now, ground, solids, 1.0 / 60.0)
			go({ last: next, peak: F32.max(sofar.peak, next.pos.y) }, { ..now, jump_pressed: Bool.False }, left - 1)
		}
	go({ last: start, peak: start.pos.y }, intent, count)
}

floor : Ground.Ground
floor = Ground.flat(0.0)

# Level ground for x below 0 and nothing past it.
ledge : Ground.Ground
ledge = |x, _z, _from| if (x < 0.0) Hit({ y: 0.0, normal: { x: 0.0, y: 1.0, z: 0.0 } }) else Miss

# A box from z 1 to 3, `top` high, across the character's path.
box_ahead : F32 -> Solids.Solid
box_ahead = |top| Box({
	center: { x: 0.0, y: top / 2.0, z: 2.0 },
	half_extents: { x: 2.0, y: top / 2.0, z: 1.0 },
	yaw: 0.0,
})

# The floor and the tops of the Solids, as a game builds its Ground.
standing_on : Solids -> Ground.Ground
standing_on = |solids| Ground.highest(floor, Ground.tops(solids))

# A plane through the origin that rises `rise` metres for each metre along +z.
ramp : F32 -> Ground.Ground
ramp = |rise| |_x, z, _from| Hit({ y: rise * z, normal: V.normalize({ x: 0.0, y: 1.0, z: -rise }) })

# A character in the Air at `pos` moving at `vel`.
airborne : Controller.Tuning, { pos : V.Vec3, vel : V.Vec3 } -> Controller.Controller
airborne = |tuning, { pos, vel }| { ..Controller.new(tuning, pos), motion: Air, vel }

no_solids : Solids
no_solids = Solids.build([], 4.0)

# Within a small gap of the near side of box_ahead, at z 1 less the radius.
is_against_box : Controller.Controller -> Bool
is_against_box = |state| state.pos.z > 0.5 and state.pos.z <= 0.551

near_to : F32, F32 -> Bool
near_to = |a, b| (a - b).abs() < 0.001

## A resting stick slows the character at decel.
expect {
	running = { ..Controller.new(Controller.default_tuning, V.zero), vel: { x: 0.0, y: 0.0, z: 8.0 } }
	next = Controller.step(running, still, floor, no_solids, 0.1)
	near_to(next.vel.z, 5.6)
}

## The heading turns toward the stick at no more than turn per second.
expect {
	start = Controller.new(Controller.default_tuning, V.zero)
	right = { ..still, move: { x: 1.0, y: 0.0 } }
	actual =
		\\short: ${Str.inspect(near_to(Controller.step(start, right, floor, no_solids, 0.1).heading, 0.62832))}
		\\long: ${Str.inspect(near_to(Controller.step(start, right, floor, no_solids, 1.0).heading, 1.5708))}
	expected =
		\\short: True
		\\long: True
	actual == expected
}

## Half the walk tilt asks for half the walk speed.
expect {
	start = Controller.new({ ..Controller.default_tuning, accel: 100.0 }, V.zero)
	half_walk = { ..still, move: { x: 0.0, y: 0.35 } }
	near_to(Controller.step(start, half_walk, floor, no_solids, 0.1).vel.z, 1.25)
}

## A press on the Ground jumps at sqrt(2 gravity jump), and jumped sees it.
expect {
	start = Controller.new(Controller.default_tuning, V.zero)
	next = Controller.step(start, jump, floor, no_solids, 0.1)
	actual =
		\\vy: ${Str.inspect(near_to(next.vel.y, 8.9443))}
		\\y: ${Str.inspect(near_to(next.pos.y, 0.89443))}
		\\motion: ${Str.inspect(next.motion)}
		\\jumped: ${Str.inspect(Controller.jumped(start, next))}
	expected =
		\\vy: True
		\\y: True
		\\motion: Air
		\\jumped: True
	actual == expected
}

## A held jump peaks at the jump height, within one step's rise, and lands
## back on the Ground when the glide is off.
expect {
	start = Controller.new({ ..Controller.default_tuning, glide_fall: 0.0 }, V.zero)
	arc = run(start, { intent: { ..jump, jump_held: Bool.True }, ground: floor, solids: no_solids, count: 60 })
	actual =
		\\peak: ${Str.inspect((arc.peak - 1.6).abs() < 0.1)}
		\\motion: ${Str.inspect(arc.last.motion)}
		\\y: ${Str.inspect(arc.last.pos.y)}
	expected =
		\\peak: True
		\\motion: Ground
		\\y: 0
	actual == expected
}

## A fall that would pass the Ground in one step lands on it, and landed
## sees it.
expect {
	falling = airborne(Controller.default_tuning, { pos: { x: 0.0, y: 0.5, z: 0.0 }, vel: { x: 0.0, y: -5.0, z: 0.0 } })
	next = Controller.step(falling, still, floor, no_solids, 0.1)
	actual =
		\\y: ${Str.inspect(next.pos.y)}
		\\vy: ${Str.inspect(next.vel.y)}
		\\motion: ${Str.inspect(next.motion)}
		\\landed: ${Str.inspect(Controller.landed(falling, next))}
		\\jumped: ${Str.inspect(Controller.jumped(falling, next))}
	expected =
		\\y: 0
		\\vy: 0
		\\motion: Ground
		\\landed: True
		\\jumped: False
	actual == expected
}

## Letting go of jump while rising cuts the rise short.
expect {
	rising = airborne(Controller.default_tuning, { pos: { x: 0.0, y: 1.0, z: 0.0 }, vel: { x: 0.0, y: 8.0, z: 0.0 } })
	actual =
		\\held: ${Str.inspect(near_to(Controller.step(rising, { ..still, jump_held: Bool.True }, floor, no_solids, 0.05).vel.y, 6.75))}
		\\released: ${Str.inspect(near_to(Controller.step(rising, still, floor, no_solids, 0.05).vel.y, 1.95))}
	expected =
		\\held: True
		\\released: True
	actual == expected
}

## Holding jump while falling glides: the fall slows to glide_fall and the
## speed rises to glide_speed. Letting go falls again.
expect {
	falling = airborne(Controller.default_tuning, { pos: { x: 0.0, y: 20.0, z: 0.0 }, vel: { x: 0.0, y: -1.0, z: 8.0 } })
	hold = { ..forward, jump_held: Bool.True }
	glide = run(falling, { intent: hold, ground: floor, solids: no_solids, count: 60 }).last
	dropped = Controller.step(glide, forward, floor, no_solids, 1.0 / 60.0)
	actual =
		\\motion: ${Str.inspect(glide.motion)}
		\\fall: ${Str.inspect(near_to(glide.vel.y, -2.0))}
		\\speed: ${Str.inspect(near_to(glide.vel.z, 9.0))}
		\\released: ${Str.inspect(dropped.motion)}
	expected =
		\\motion: Glide
		\\fall: True
		\\speed: True
		\\released: Air
	actual == expected
}

## A zero glide_fall turns the glide off.
expect {
	tuning = { ..Controller.default_tuning, glide_fall: 0.0 }
	falling = airborne(tuning, { pos: { x: 0.0, y: 20.0, z: 0.0 }, vel: { x: 0.0, y: -1.0, z: 0.0 } })
	Controller.step(falling, { ..still, jump_held: Bool.True }, floor, no_solids, 0.1).motion == Air
}

## Just after walking off a ledge, a press still jumps. A zero coyote turns
## that off.
expect {
	off_ledge = |tuning| {
		walking = {
			..Controller.new(tuning, { x: -0.05, y: 0.0, z: 0.0 }),
			heading: 1.5707964,
			vel: { x: 8.0, y: 0.0, z: 0.0 },
		}
		walked_off = Controller.step(walking, { ..still, move: { x: 1.0, y: 0.0 } }, ledge, no_solids, 1.0 / 60.0)
		pressed = Controller.step(walked_off, jump, ledge, no_solids, 1.0 / 60.0)
		{ walked_off: walked_off.motion, jumped: Controller.jumped(walked_off, pressed) }
	}
	actual =
		\\coyote: ${Str.inspect(off_ledge(Controller.default_tuning))}
		\\off: ${Str.inspect(off_ledge({ ..Controller.default_tuning, coyote: 0.0 }))}
	expected =
		\\coyote: { jumped: True, walked_off: Air }
		\\off: { jumped: False, walked_off: Air }
	actual == expected
}

## A press just before landing jumps on the step after the landing. A zero
## jump_buffer turns that off.
expect {
	early = |tuning| {
		falling = airborne(tuning, { pos: { x: 0.0, y: 0.05, z: 0.0 }, vel: { x: 0.0, y: -5.0, z: 0.0 } })
		landing = Controller.step(falling, jump, floor, no_solids, 1.0 / 60.0)
		after = Controller.step(landing, still, floor, no_solids, 1.0 / 60.0)
		{ landed: Controller.landed(falling, landing), jumped: Controller.jumped(landing, after) }
	}
	actual =
		\\buffer: ${Str.inspect(early(Controller.default_tuning))}
		\\off: ${Str.inspect(early({ ..Controller.default_tuning, jump_buffer: 0.0 }))}
	expected =
		\\buffer: { jumped: True, landed: True }
		\\off: { jumped: False, landed: True }
	actual == expected
}

## A box taller than step_up stops the character at its side, and it stays
## on the Ground.
expect {
	wall = Solids.build([box_ahead(2.0)], 4.0)
	stopped = run(Controller.new(Controller.default_tuning, V.zero), { intent: forward, ground: standing_on(wall), solids: wall, count: 60 }).last
	actual =
		\\against: ${Str.inspect(is_against_box(stopped))}
		\\y: ${Str.inspect(stopped.pos.y)}
		\\motion: ${Str.inspect(stopped.motion)}
	expected =
		\\against: True
		\\y: 0
		\\motion: Ground
	actual == expected
}

## A box no taller than step_up is a step. A zero step_up makes it a wall.
expect {
	low = Solids.build([box_ahead(0.3)], 4.0)
	walk = |tuning| run(Controller.new(tuning, V.zero), { intent: forward, ground: standing_on(low), solids: low, count: 30 }).last
	up = walk(Controller.default_tuning)
	off = walk({ ..Controller.default_tuning, step_up: 0.0 })
	actual =
		\\step y: ${Str.inspect(up.pos.y)}
		\\step on box: ${Str.inspect(up.pos.z > 1.0)}
		\\step motion: ${Str.inspect(up.motion)}
		\\off y: ${Str.inspect(off.pos.y)}
		\\off against: ${Str.inspect(is_against_box(off))}
	expected =
		\\step y: 0.3
		\\step on box: True
		\\step motion: Ground
		\\off y: 0
		\\off against: True
	actual == expected
}

## A box a little taller than step_up is a wall, and the character closes
## the gap to it.
expect {
	ledge_box = Solids.build([box_ahead(0.5)], 4.0)
	stopped = run(Controller.new(Controller.default_tuning, V.zero), { intent: forward, ground: standing_on(ledge_box), solids: ledge_box, count: 60 }).last
	actual =
		\\y: ${Str.inspect(stopped.pos.y)}
		\\against: ${Str.inspect(is_against_box(stopped))}
	expected =
		\\y: 0
		\\against: True
	actual == expected
}

## A box overhead stops a jump: the head stays under it and the rise ends.
expect {
	roof_box = Box({
		center: { x: 0.0, y: 3.0, z: 0.0 },
		half_extents: { x: 2.0, y: 0.5, z: 2.0 },
		yaw: 0.0,
	})
	roof = Solids.build([roof_box], 4.0)
	start = Controller.new({ ..Controller.default_tuning, glide_fall: 0.0 }, V.zero)
	arc = run(start, { intent: { ..jump, jump_held: Bool.True }, ground: floor, solids: roof, count: 60 })
	actual =
		\\under: ${Str.inspect(arc.peak <= 1.001)}
		\\motion: ${Str.inspect(arc.last.motion)}
	expected =
		\\under: True
		\\motion: Ground
	actual == expected
}

## Running down a slope under the slope_limit keeps the foot on the Ground.
expect {
	down = ramp(-0.5)
	last = run(Controller.new(Controller.default_tuning, V.zero), { intent: forward, ground: down, solids: no_solids, count: 60 }).last
	actual =
		\\motion: ${Str.inspect(last.motion)}
		\\on slope: ${Str.inspect(near_to(last.pos.y, -0.5 * last.pos.z))}
		\\ran: ${Str.inspect(last.pos.z > 2.0)}
	expected =
		\\motion: Ground
		\\on slope: True
		\\ran: True
	actual == expected
}

## Ground steeper than the slope_limit puts the character in the Air. A zero
## slope_limit turns that off.
expect {
	steep = ramp(-1.5)
	on_slope = |tuning| Controller.step(Controller.new(tuning, V.zero), still, steep, no_solids, 1.0 / 60.0).motion
	actual =
		\\limit: ${Str.inspect(on_slope(Controller.default_tuning))}
		\\off: ${Str.inspect(on_slope({ ..Controller.default_tuning, slope_limit: 0.0 }))}
	expected =
		\\limit: Air
		\\off: Ground
	actual == expected
}

## The character cannot run up a slope steeper than the slope_limit.
expect {
	last = run(Controller.new(Controller.default_tuning, V.zero), { intent: forward, ground: ramp(1.5), solids: no_solids, count: 60 }).last
	actual =
		\\z: ${Str.inspect(last.pos.z < 0.1)}
		\\y: ${Str.inspect(last.pos.y < 0.15)}
	expected =
		\\z: True
		\\y: True
	actual == expected
}

## On Ground steeper than the slope_limit the character slides down it.
expect {
	dropped = airborne(Controller.default_tuning, { pos: { x: 0.0, y: 3.0, z: 0.0 }, vel: V.zero })
	last = run(dropped, { intent: still, ground: ramp(-1.5), solids: no_solids, count: 60 }).last
	actual =
		\\downhill: ${Str.inspect(last.pos.z > 0.5)}
		\\on slope: ${Str.inspect(near_to(last.pos.y, -1.5 * last.pos.z))}
		\\motion: ${Str.inspect(last.motion)}
	expected =
		\\downhill: True
		\\on slope: True
		\\motion: Air
	actual == expected
}
