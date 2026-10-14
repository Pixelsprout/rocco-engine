import linalg.Quat
import World
import Grid

Ball := [].{
	# bob is the phase of the idle bob, in turns from 0 to 1.
	Ball : { pose : World.Pose, motion : Motion, turn : Turn, rot : Quat.Quat, bob : F32 }

	# The pose commits when a move starts. from, offset, over and t only serve View.
	# A jump from a roll starts offset cells along forward from from.cell.
	# A fall jumps to over, then drops straight down. Its seconds count from the jump start.
	# spin_rate is in radians a second. It plays the part of the original's rotX.
	Motion : [Still, Rolling({ from : World.Pose, t : F32 }), Jumping({ from : World.Pose, offset : F32, t : F32 }), JumpingInPlace({ t : F32 }), Falling({ from : World.Pose, offset : F32, over : World.Pose, drop : Drop, seconds : F32, spin_rate : F32 })]

	# Cells the ball drops below over. Off drops to 2 cells past the lowest block, then the level restarts.
	Drop : [Onto(I32), Off(I32)]

	# A turn runs while the ball is Still or JumpingInPlace, and can outlast the jump.
	# next holds a turn pressed during this one, as the original's startTurningLeftNextFrame.
	Turn : [Steady, Turning({ from : World.Pose, t : F32, next : NextTurn })]

	NextTurn : [Stay, TurnLeft, TurnRight]

	# Jump is a forward jump when Up is held or the ball rolls, else a jump in place.
	Action : [Roll, TurnLeft, TurnRight, Jump({ up_held : Bool })]

	# In cells. The original rests the ball centre 100 of 512 units above a face.
	radius : F32
	radius = 0.195

	start : World.Pose -> Ball.Ball
	start = |pose| { pose, motion: Still, turn: Steady, rot: Quat.identity, bob: 0.0 }

	# An edge roll needs an open end, as in the original.
	roll : Set(World.Cell), World.Pose -> Try(World.Pose, [ClosedEdge])
	roll = |blocks, pose| {
		ahead = Grid.add(pose.cell, pose.forward)
		standing_on = Grid.sub(pose.cell, pose.up)
		right = Grid.cross(pose.forward, pose.up)
		if Grid.has_block(blocks, ahead) {
			Ok({ cell: pose.cell, up: Grid.neg(pose.forward), forward: pose.up })
		} else if Grid.has_block(blocks, Grid.sub(ahead, pose.up)) {
			Ok({ ..pose, cell: ahead })
		} else if Grid.has_block(blocks, Grid.add(standing_on, right)) or Grid.has_block(blocks, Grid.sub(standing_on, right)) {
			Err(ClosedEdge)
		} else {
			Ok({ cell: Grid.sub(ahead, pose.up), up: pose.forward, forward: Grid.neg(pose.up) })
		}
	}

	RollKind : [Floor, Climb, Edge]

	roll_kind : World.Pose, World.Pose -> RollKind
	roll_kind = |from, to|
		if from.up == to.up {
			Floor
		} else if from.cell == to.cell {
			Climb
		} else {
			Edge
		}

	# The distance the ball centre travels. A climb rolls to the wall, then up it.
	# An edge roll adds a quarter circle round the edge.
	roll_length : RollKind -> F32
	roll_length = |kind| match kind {
		Floor => 1.0
		Climb => 2.0 * (0.5 - radius)
		Edge => 1.0 + quarter_turn * radius
	}

	turn_left : World.Pose -> World.Pose
	turn_left = |pose| { ..pose, forward: Grid.cross(pose.up, pose.forward) }

	turn_right : World.Pose -> World.Pose
	turn_right = |pose| { ..pose, forward: Grid.cross(pose.forward, pose.up) }

	# Always two cells ahead at the same level. A block in the path bounces the ball back.
	jump : Set(World.Cell), World.Pose -> [Land(World.Pose), Fall({ over : World.Pose, drop : Drop }), Bounce]
	jump = |blocks, pose| {
		ahead = Grid.add(pose.cell, pose.forward)
		two_ahead = Grid.add(ahead, pose.forward)
		if Grid.has_block(blocks, Grid.add(pose.cell, pose.up)) or Grid.has_block(blocks, ahead) or Grid.has_block(blocks, two_ahead) {
			Bounce
		} else if Grid.has_block(blocks, Grid.sub(two_ahead, pose.up)) {
			Land({ ..pose, cell: two_ahead })
		} else {
			over = { ..pose, cell: two_ahead }
			lowest = lowest_along(blocks, pose.up, Grid.dot(two_ahead, pose.up))
			Fall({ over, drop: drop_below(blocks, over, 1, lowest) })
		}
	}

	jump_lift : F32 -> F32
	jump_lift = |t| 4.0 * jump_height * t * (1.0 - t)

	fall_stage : F32 -> [Arc(F32), Dropped(F32)]
	fall_stage = |seconds| if seconds < jump_seconds { Arc(seconds / jump_seconds) } else { Dropped(drop_distance(seconds - jump_seconds)) }

	fell_off : Ball.Ball -> Bool
	fell_off = |ball| match ball.motion {
		Falling({ drop: Off(cells), seconds, .. }) => seconds >= fall_seconds(Off(cells))
		_ => False
	}

	# The original tests for a landing only in the last 11 of the jump's 27 frames.
	can_land : F32, F32 -> Bool
	can_land = |t, lift| t >= 16.0 / 27.0 and lift <= 0.0

	# A roll or a jump starts only from Still with no turn running. A floor roll,
	# or an edge roll before the edge, can also start a jump. A turn can start
	# during a jump in place.
	act : Set(World.Cell), Ball.Ball, Action -> Ball.Ball
	act = |blocks, ball, action| {
		from = ball.pose
		match (ball.motion, ball.turn, action) {
			(Still, Steady, Roll) => match roll(blocks, from) {
				Ok(pose) => { ..ball, pose, motion: Rolling({ from, t: 0.0 }) }
				Err(ClosedEdge) => ball
			}
			(Still, Steady, Jump({ up_held })) => if up_held { leap(blocks, ball, from, 0.0) } else { start_jump_in_place(blocks, ball) }
			# The jump starts from the cell the ball is nearest to.
			(Rolling({ from: roll_from, t }), _, Jump(_)) if roll_kind(roll_from, ball.pose) == Floor =>
				if t < 0.5 { leap(blocks, ball, roll_from, t) } else { leap(blocks, ball, ball.pose, t - 1.0) }
			# The original rolls up to the edge before it turns, so X still jumps there.
			(Rolling({ from: roll_from, t }), _, Jump(_)) if roll_kind(roll_from, ball.pose) == Edge and t * roll_length(Edge) < 0.5 =>
				leap(blocks, ball, roll_from, t * roll_length(Edge))
			(motion, _, TurnLeft) if can_turn(motion) => turn(ball, TurnLeft)
			(motion, _, TurnRight) if can_turn(motion) => turn(ball, TurnRight)
			_ => ball
		}
	}

	advance : Ball.Ball, F32 -> Ball.Ball
	advance = |ball, dt| move(ball, dt, Released)

	# With Up held, a roll or jump that ends this step starts the next roll in the
	# same step. The next roll gets the time left over, so the ball keeps its speed.
	advance_up_held : Set(World.Cell), Ball.Ball, F32 -> Ball.Ball
	advance_up_held = |blocks, ball, dt| {
		moved = move(ball, dt, Held)
		match (moved.motion, moved.turn) {
			(Still, Steady) if ball.motion != Still => {
				# One roll at most, so Rules.collect sees every committed cell.
				busy = seconds_left(ball)
				turning = turn_seconds_left(ball)
				left_over = dt - (if turning > busy { turning } else { busy })
				if left_over > 0.0 { move(act(blocks, moved, Roll), left_over, Held) } else { act(blocks, moved, Roll) }
			}
			_ => moved
		}
	}
}

leap : Set(World.Cell), Ball.Ball, World.Pose, F32 -> Ball.Ball
leap = |blocks, ball, from, offset| match Ball.jump(blocks, from) {
	Land(pose) => { ..ball, pose, motion: Jumping({ from, offset, t: 0.0 }) }
	Fall({ over, drop }) => { ..ball, pose: landing(over, drop), motion: Falling({ from, offset, over, drop, seconds: 0.0, spin_rate: top_spin }) }
	Bounce => ball
}

# The original drops until it leaves its fixed grid. The clone stops 2 cells past the lowest block.
drop_below : Set(World.Cell), World.Pose, I32, I32 -> Ball.Drop
drop_below = |blocks, over, depth, lowest| {
	below = Grid.sub(over.cell, Grid.scale(over.up, depth + 1))
	if Grid.dot(below, over.up) < lowest {
		Off(Grid.dot(over.cell, over.up) - lowest + 2)
	} else if Grid.has_block(blocks, below) {
		Onto(depth)
	} else {
		drop_below(blocks, over, depth + 1, lowest)
	}
}

lowest_along : Set(World.Cell), World.Cell, I32 -> I32
lowest_along = |blocks, up, start| blocks.to_list().fold(start, |low, block| {
	along = Grid.dot(block, up)
	if along < low { along } else { low }
})

landing : World.Pose, Ball.Drop -> World.Pose
landing = |over, drop| match drop {
	Onto(depth) => { ..over, cell: Grid.sub(over.cell, Grid.scale(over.up, depth)) }
	Off(_) => over
}

start_jump_in_place : Set(World.Cell), Ball.Ball -> Ball.Ball
start_jump_in_place = |blocks, ball|
	if Grid.has_block(blocks, Grid.add(ball.pose.cell, ball.pose.up)) {
		ball
	} else {
		{ ..ball, motion: JumpingInPlace({ t: 0.0 }) }
	}

can_turn : Ball.Motion -> Bool
can_turn = |motion| match motion {
	Still => True
	JumpingInPlace(_) => True
	_ => False
}

# A press during a turn waits for that turn to end.
turn : Ball.Ball, Ball.NextTurn -> Ball.Ball
turn = |ball, side| match ball.turn {
	Steady => start_turn(ball, side)
	Turning(turning) => { ..ball, turn: Turning({ ..turning, next: side }) }
}

start_turn : Ball.Ball, Ball.NextTurn -> Ball.Ball
start_turn = |ball, side| {
	from = ball.pose
	match side {
		Stay => { ..ball, turn: Steady }
		TurnLeft => { ..ball, pose: Ball.turn_left(from), turn: Turning({ from, t: 0.0, next: Stay }) }
		TurnRight => { ..ball, pose: Ball.turn_right(from), turn: Turning({ from, t: 0.0, next: Stay }) }
	}
}

advance_turn : Ball.Ball, F32 -> Ball.Ball
advance_turn = |ball, dt| match ball.turn {
	Steady => ball
	Turning(turning) => {
		next = progress(turning.t, dt, turn_seconds)
		if next < 1.0 { { ..ball, turn: Turning({ ..turning, t: next }) } } else { start_turn(ball, turning.next) }
	}
}

move : Ball.Ball, F32, [Held, Released] -> Ball.Ball
move = |ball, dt, up| advance_turn(advance_motion(advance_bob(ball, dt), dt, up), dt)

# The original holds the bob in a forward jump and while the ball wraps an
# edge. A fall starts with a forward jump.
advance_bob : Ball.Ball, F32 -> Ball.Ball
advance_bob = |ball, dt| match ball.motion {
	Jumping(_) => ball
	Falling({ seconds, .. }) if seconds < jump_seconds => ball
	Rolling({ from, t }) if Ball.roll_kind(from, ball.pose) == Edge and wrapping(t * Ball.roll_length(Edge)) => ball
	_ => {
		next = ball.bob + bob_rate(full_clock) * dt
		{ ..ball, bob: if next >= 1.0 { next - 1.0 } else { next } }
	}
}

advance_motion : Ball.Ball, F32, [Held, Released] -> Ball.Ball
advance_motion = |ball, dt, up| match ball.motion {
	Still => ball
	Rolling({ from, t }) => {
		kind = Ball.roll_kind(from, ball.pose)
		next = progress(t, dt, roll_seconds(kind))
		{ ..ball, rot: spin_about(from, (next - t) * Ball.roll_length(kind) / Ball.radius, ball.rot), motion: if next < 1.0 { Rolling({ from, t: next }) } else { Still } }
	}
	# The landing cell always has a floor, so the ball lands back at rest height.
	Jumping(jumping) => {
		next = progress(jumping.t, dt, jump_seconds)
		rot = spin_about(jumping.from, (next - jumping.t) * jump_seconds * top_spin, ball.rot)
		{ ..ball, rot, motion: if Ball.can_land(next, Ball.jump_lift(next)) { Still } else { Jumping({ ..jumping, t: next }) } }
	}
	JumpingInPlace({ t }) => {
		next = progress(t, dt, jump_seconds)
		{ ..ball, motion: if Ball.can_land(next, Ball.jump_lift(next)) { Still } else { JumpingInPlace({ t: next }) } }
	}
	# An Off fall waits at its end for Rules to restart the level.
	Falling(falling) => {
		total = fall_seconds(falling.drop)
		next = if falling.seconds + dt > total { total } else { falling.seconds + dt }
		spun = fall_spin(falling.seconds, next, falling.spin_rate, up)
		rot = spin_about(falling.from, spun.angle, ball.rot)
		match falling.drop {
			Onto(_) if next >= total => { ..ball, rot, motion: Still }
			_ => { ..ball, rot, motion: Falling({ ..falling, seconds: next, spin_rate: spun.rate }) }
		}
	}
}

spin_about : World.Pose, F32, Quat.Quat -> Quat.Quat
spin_about = |from, angle, rot| Quat.mul(Quat.from_axis_angle(Grid.to_vec3(Grid.cross(from.up, from.forward)), angle), rot)

# The arc keeps its spin. The drop builds it to top_spin with Up held, else runs it down to 0.
fall_spin : F32, F32, F32, [Held, Released] -> { rate : F32, angle : F32 }
fall_spin = |from_seconds, to_seconds, rate, up| {
	arc_end = if to_seconds < jump_seconds { to_seconds } else { jump_seconds }
	arc = if arc_end > from_seconds { arc_end - from_seconds } else { 0.0 }
	drop = to_seconds - from_seconds - arc
	dropped = match up {
		Held => spin_toward(rate, top_spin, spin_gain, drop)
		Released => spin_toward(rate, 0.0, spin_loss, drop)
	}
	{ rate: dropped.rate, angle: rate * arc + dropped.angle }
}

# The rate changes linearly and stops at target, so the angle does not depend on the step size.
spin_toward : F32, F32, F32, F32 -> { rate : F32, angle : F32 }
spin_toward = |rate, target, change, seconds| {
	to_target = (target - rate).abs() / change
	if seconds <= to_target {
		next = if target > rate { rate + change * seconds } else { rate - change * seconds }
		{ rate: next, angle: (rate + next) / 2.0 * seconds }
	} else {
		{ rate: target, angle: (rate + target) / 2.0 * to_target + target * (seconds - to_target) }
	}
}

turn_seconds_left : Ball.Ball -> F32
turn_seconds_left = |ball| match ball.turn {
	Steady => 0.0
	Turning({ t, .. }) => (1.0 - t) * turn_seconds
}

seconds_left : Ball.Ball -> F32
seconds_left = |ball| match ball.motion {
	Still => 0.0
	Rolling({ from, t }) => (1.0 - t) * roll_seconds(Ball.roll_kind(from, ball.pose))
	Jumping({ t, .. }) => (1.0 - t) * jump_seconds
	JumpingInPlace({ t }) => (1.0 - t) * jump_seconds
	Falling({ drop, seconds, .. }) => fall_seconds(drop) - seconds
}

# PAL frame counts from the original, at 0.02 s a frame. See SPEC.md.
# An edge roll is half a cell at top speed, the 4-frame wrap, then half a cell.
roll_seconds : Ball.RollKind -> F32
roll_seconds = |kind| match kind {
	Floor => 0.26
	Climb => 0.28
	Edge => 0.34
}

quarter_turn : F32
quarter_turn = 1.5707963

turn_seconds : F32
turn_seconds = 0.32

jump_seconds : F32
jump_seconds = 0.54

jump_height : F32
jump_height = 0.5

# The wrap is the quarter circle between the two half cells of an edge roll.
wrapping : F32 -> Bool
wrapping = |cells| cells >= 0.5 and cells < 0.5 + quarter_turn * Ball.radius

# The clone has no level clock yet, so the bob runs at the rate for a full one.
full_clock : F32
full_clock = 100.0

# Turns a second, for clock seconds left. Each frame the original adds 165 - 1.25 * clock, in 4096ths of a turn.
bob_rate : F32 -> F32
bob_rate = |clock| (165.0 - 1.25 * clock) / 4096.0 / 0.02

# Radians a second at the top roll speed.
top_spin : F32
top_spin = 1.0 / roll_seconds(Floor) / Ball.radius

# A fall adds 6 to rotX a frame with Up held, else takes 1 away. The top rotX is 40.
spin_gain : F32
spin_gain = top_spin * 6.0 / 40.0 / 0.02
spin_loss : F32
spin_loss = top_spin / 40.0 / 0.02

# The original adds 6 units a frame to the fall speed, up to 80 units a frame.
gravity : F32
gravity = 6.0 / 512.0 / (0.02 * 0.02)

top_fall_speed : F32
top_fall_speed = 80.0 / 512.0 / 0.02

# The drop starts at the speed the jump arc ends with.
drop_start_speed : F32
drop_start_speed = 4.0 * jump_height / jump_seconds

seconds_to_top_speed : F32
seconds_to_top_speed = (top_fall_speed - drop_start_speed) / gravity

distance_to_top_speed : F32
distance_to_top_speed = (drop_start_speed + top_fall_speed) / 2.0 * seconds_to_top_speed

drop_distance : F32 -> F32
drop_distance = |seconds|
	if seconds <= seconds_to_top_speed {
		drop_start_speed * seconds + 0.5 * gravity * seconds * seconds
	} else {
		distance_to_top_speed + top_fall_speed * (seconds - seconds_to_top_speed)
	}

drop_seconds : F32 -> F32
drop_seconds = |cells|
	if cells <= distance_to_top_speed {
		((drop_start_speed * drop_start_speed + 2.0 * gravity * cells).sqrt() - drop_start_speed) / gravity
	} else {
		seconds_to_top_speed + (cells - distance_to_top_speed) / top_fall_speed
	}

fall_seconds : Ball.Drop -> F32
fall_seconds = |drop| {
	cells = match drop {
		Onto(depth) => depth
		Off(depth) => depth
	}
	jump_seconds + drop_seconds(cells.to_f32())
}

# Clamped to 1, so the last step of a roll spins only the remaining distance.
progress : F32, F32, F32 -> F32
progress = |t, dt, seconds| {
	next = t + dt / seconds
	if next > 1.0 { 1.0 } else { next }
}

cell : I32, I32, I32 -> World.Cell
cell = |x, y, z| { x, y, z }

y_up : World.Cell
y_up = cell(0, 1, 0)

north : World.Cell
north = cell(0, 0, -1)

# The ball stands on the block at the origin, facing -z.
on_origin : World.Pose
on_origin = { cell: y_up, up: y_up, forward: north }

blocks : List(World.Cell) -> Set(World.Cell)
blocks = |cells| Set.from_list(cells)

expect Ball.roll(blocks([cell(0, 0, 0), cell(0, 1, -1)]), on_origin) == Ok({ cell: y_up, up: cell(0, 0, 1), forward: y_up })
expect Ball.roll(blocks([cell(0, 0, 0), cell(0, 0, -1)]), on_origin) == Ok({ cell: cell(0, 1, -1), up: y_up, forward: north })

# Over the edge onto the block's -z side, then on round under it.
expect {
	floor = blocks([cell(0, 0, 0)])
	side = Ball.roll(floor, on_origin) ?? on_origin
	under = Ball.roll(floor, side) ?? side
	side == { cell: cell(0, 0, -1), up: north, forward: cell(0, -1, 0) } and under == { cell: cell(0, -1, 0), up: cell(0, -1, 0), forward: cell(0, 0, 1) }
}

# An edge roll needs an open end: no block beside the one the ball stands on.
expect Ball.roll(blocks([cell(0, 0, 0), cell(1, 0, 0)]), on_origin) == Err(ClosedEdge)
expect Ball.roll(blocks([cell(0, 0, 0), cell(-1, 0, 0)]), on_origin) == Err(ClosedEdge)

expect Ball.turn_left(on_origin) == { ..on_origin, forward: cell(-1, 0, 0) }
expect Ball.turn_right(on_origin) == { ..on_origin, forward: cell(1, 0, 0) }

expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 0, -2)]), on_origin) == Land({ ..on_origin, cell: cell(0, 1, -2) })
expect Ball.jump(blocks([cell(0, 0, 0)]), on_origin) == Fall({ over: { ..on_origin, cell: cell(0, 1, -2) }, drop: Off(3) })

# A jump with no floor two ahead falls onto the first block below the target.
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, -1, -2)]), on_origin) == Fall({ over: { ..on_origin, cell: cell(0, 1, -2) }, drop: Onto(1) })

# On a wall the search runs along -x.
expect {
	on_wall = { cell: cell(1, 0, 0), up: cell(1, 0, 0), forward: north }
	over = { ..on_wall, cell: cell(1, 0, -2) }
	Ball.jump(blocks([cell(0, 0, 0), cell(-1, 0, -2)]), on_wall) == Fall({ over, drop: Onto(1) }) and Ball.jump(blocks([cell(0, 0, 0)]), on_wall) == Fall({ over, drop: Off(3) })
}
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -1), cell(0, 0, -2)]), on_origin) == Bounce
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -2), cell(0, 0, -2)]), on_origin) == Bounce
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 0, -2), cell(0, 2, 0)]), on_origin) == Bounce

floor_ahead : Set(World.Cell)
floor_ahead = blocks([cell(0, 0, 0), cell(0, 0, -1), cell(0, 0, -2)])

still : Ball.Ball
still = Ball.start(on_origin)

forward_jump : Ball.Action
forward_jump = Jump({ up_held: True })

near_quat : Quat.Quat, Quat.Quat -> Bool
near_quat = |a, b| (a.x - b.x).abs() < 0.0001 and (a.y - b.y).abs() < 0.0001 and (a.z - b.z).abs() < 0.0001 and (a.w - b.w).abs() < 0.0001

expect {
	ball = Ball.act(floor_ahead, still, Roll)
	ball.pose.cell == cell(0, 1, -1) and ball.motion == Rolling({ from: on_origin, t: 0.0 })
}

expect Ball.act(blocks([cell(0, 0, 0), cell(1, 0, 0)]), still, Roll) == still
expect Ball.act(floor_ahead, still, TurnLeft).turn == Turning({ from: on_origin, t: 0.0, next: Stay })
expect Ball.act(floor_ahead, still, forward_jump) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Jumping({ from: on_origin, offset: 0.0, t: 0.0 }) }
expect Ball.act(blocks([cell(0, 0, 0)]), still, forward_jump) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Falling({ from: on_origin, offset: 0.0, over: { ..on_origin, cell: cell(0, 1, -2) }, drop: Off(3), seconds: 0.0, spin_rate: top_spin }) }
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, forward_jump) == still

# Input is read only when Still.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	Ball.act(floor_ahead, rolling, TurnLeft) == rolling
}

expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.13).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.26).motion == Still
expect Ball.advance(Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, Roll), 0.14).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(blocks([cell(0, 0, 0)]), still, Roll), 0.17).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.16).turn == Turning({ from: on_origin, t: 0.5, next: Stay })
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.32).turn == Steady
expect Ball.advance(Ball.act(floor_ahead, still, forward_jump), 0.27).motion == Jumping({ from: on_origin, offset: 0.0, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, forward_jump), 0.54).motion == Still
expect { ..Ball.advance(still, 1.0), bob: 0.0 } == still

# A 1-cell drop lands between 0.70 and 0.71 s after the jump starts.
expect {
	falling = Ball.act(blocks([cell(0, 0, 0), cell(0, -1, -2)]), still, forward_jump)
	landed = Ball.advance(falling, 0.71)
	falling.pose.cell == cell(0, 0, -2) and Ball.advance(falling, 0.70).motion != Still and landed.motion == Still and landed.pose.cell == cell(0, 0, -2)
}

# Rolling along -z on +y turns about -x, one cell over the radius, however the steps fall.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	ball = [0.06, 0.07, 0.06, 0.07, 0.05].fold(rolling, |b, dt| Ball.advance(b, dt))
	ball.motion == Still and near_quat(ball.rot, x_axis_spin(1.0 / Ball.radius))
}

x_axis_spin : F32 -> Quat.Quat
x_axis_spin = |angle| Quat.from_axis_angle({ x: -1.0, y: 0.0, z: 0.0 }, angle)

# A forward jump spins at the top roll rate from its first frame.
expect near_quat(Ball.advance(Ball.act(floor_ahead, still, forward_jump), 0.27).rot, x_axis_spin(0.27 * top_spin))
expect near_quat(Ball.advance(Ball.act(floor_ahead, still, forward_jump), 0.54).rot, x_axis_spin(0.54 * top_spin))

# The spin carries on into the next roll with no jump in angle.
expect {
	jumping = Ball.act(long_floor, still, forward_jump)
	ball = Ball.advance_up_held(long_floor, jumping, 0.67)
	near_quat(ball.rot, x_axis_spin(0.54 * top_spin + 0.5 / Ball.radius))
}

# 13 cells to fall, so the ball is still falling after 2 s.
deep_drop : Set(World.Cell)
deep_drop = blocks([cell(0, 0, 0), cell(5, -10, 5)])

fall_spin_rate : Ball.Ball -> F32
fall_spin_rate = |ball| match ball.motion {
	Falling({ spin_rate, .. }) => spin_rate
	_ => -1.0
}

expect Ball.act(deep_drop, still, forward_jump).motion == Falling({ from: on_origin, offset: 0.0, over: { ..on_origin, cell: cell(0, 1, -2) }, drop: Off(13), seconds: 0.0, spin_rate: top_spin })

# The arc keeps the top rate. Without Up, the drop then stops the spin in 0.8 s.
expect {
	falling = Ball.act(deep_drop, still, forward_jump)
	ball = Ball.advance(falling, 2.0)
	near(fall_spin_rate(Ball.advance(falling, 0.94)), 0.5 * top_spin) and fall_spin_rate(ball) == 0.0 and near_quat(ball.rot, x_axis_spin((0.54 + 0.4) * top_spin))
}

# With Up held, the drop keeps the top rate.
expect {
	falling = Ball.act(deep_drop, still, forward_jump)
	near_quat(Ball.advance_up_held(deep_drop, falling, 1.54).rot, x_axis_spin(1.54 * top_spin))
}

# With Up held again, the rate climbs back to the top.
expect {
	slowed = Ball.advance(Ball.act(deep_drop, still, forward_jump), 0.94)
	near(fall_spin_rate(Ball.advance_up_held(deep_drop, slowed, 0.04)), 0.8 * top_spin) and fall_spin_rate(Ball.advance_up_held(deep_drop, slowed, 0.1)) == top_spin
}

# The fall spin does not depend on how the steps fall, also across the arc's end.
expect {
	falling = Ball.act(deep_drop, still, forward_jump)
	stepped = [0.3, 0.3, 0.3, 0.3, 0.34].fold(falling, |b, dt| Ball.advance(b, dt))
	near_quat(stepped.rot, Ball.advance(falling, 1.54).rot)
}

# A ball that lands from a fall keeps the angle it spun to.
expect {
	landed = Ball.advance(Ball.act(blocks([cell(0, 0, 0), cell(0, -1, -2)]), still, forward_jump), 0.71)
	drop = drop_seconds(1.0)
	landed.motion == Still and near_quat(landed.rot, x_axis_spin(top_spin * (0.54 + drop - 0.5 * 1.25 * drop * drop)))
}

in_place : Ball.Action
in_place = Jump({ up_held: False })

long_floor : Set(World.Cell)
long_floor = blocks([cell(0, 0, 0), cell(0, 0, -1), cell(0, 0, -2), cell(0, 0, -3)])

rolling_at : F32 -> Ball.Ball
rolling_at = |t| { ..Ball.act(long_floor, still, Roll), motion: Rolling({ from: on_origin, t }) }

# A jump from a roll spins at the top rate too.
expect near_quat(Ball.advance(Ball.act(long_floor, rolling_at(0.25), forward_jump), 0.27).rot, x_axis_spin(0.27 * top_spin))

expect Ball.act(floor_ahead, still, in_place) == { ..still, motion: JumpingInPlace({ t: 0.0 }) }
expect Ball.advance(Ball.act(floor_ahead, still, in_place), 0.27).motion == JumpingInPlace({ t: 0.5 })
expect { ..Ball.advance(Ball.act(floor_ahead, still, in_place), 0.54), bob: 0.0 } == still

# A jump in place does not spin.
expect Ball.advance(Ball.act(floor_ahead, still, in_place), 0.27).rot == Quat.identity

# Only a block above bounces a jump in place. A block ahead does not.
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 2, 0)]), still, in_place) == still
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, in_place).motion == JumpingInPlace({ t: 0.0 })

# A jump from a roll lands two cells past the cell the ball is nearest to.
expect Ball.act(long_floor, rolling_at(0.25), in_place) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Jumping({ from: on_origin, offset: 0.25, t: 0.0 }) }
expect Ball.act(long_floor, rolling_at(0.75), in_place) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -3) }, motion: Jumping({ from: { ..on_origin, cell: cell(0, 1, -1) }, offset: -0.25, t: 0.0 }) }

# A block in the path bounces a jump from a roll. The ball rolls on.
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 0, -1), cell(0, 0, -2), cell(0, 1, -2)]), rolling_at(0.25), in_place) == rolling_at(0.25)

# Climbs and turns cannot start a jump. An edge roll can, until the ball reaches the edge.
expect {
	climbing = { ..Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, Roll), motion: Rolling({ from: on_origin, t: 0.75 }) }
	Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), climbing, forward_jump) == climbing
}
expect {
	gap = blocks([cell(0, 0, 0), cell(0, 0, -2)])
	approaching = { ..Ball.act(gap, still, Roll), motion: Rolling({ from: on_origin, t: 0.2 }) }
	jumped = Ball.act(gap, approaching, in_place)
	jumped.pose == { ..on_origin, cell: cell(0, 1, -2) } and match jumped.motion {
		Jumping({ from, offset, t }) => from == on_origin and near(offset, 0.2 * Ball.roll_length(Edge)) and t == 0.0
		_ => False
	}
}
expect {
	gap = blocks([cell(0, 0, 0), cell(0, 0, -2)])
	wrapping = { ..Ball.act(gap, still, Roll), motion: Rolling({ from: on_origin, t: 0.5 }) }
	Ball.act(gap, wrapping, forward_jump) == wrapping
}
expect {
	turning = Ball.act(floor_ahead, still, TurnLeft)
	Ball.act(floor_ahead, turning, forward_jump) == turning and Ball.act(floor_ahead, turning, in_place) == turning
}

# No input acts during a forward jump.
expect {
	jumping = Ball.act(floor_ahead, still, forward_jump)
	[TurnLeft, TurnRight, Roll, forward_jump, in_place].all(|action| Ball.act(floor_ahead, jumping, action) == jumping)
}

# During a jump in place, Left and Right turn the ball. The turn can outlast the jump.
expect {
	jumping_in_place = Ball.advance(Ball.act(floor_ahead, still, in_place), 0.4)
	turning = Ball.act(floor_ahead, jumping_in_place, TurnLeft)
	landed = Ball.advance(turning, 0.2)
	turning.motion == JumpingInPlace({ t: 0.4 / 0.54 }) and turning.turn == Turning({ from: on_origin, t: 0.0, next: Stay }) and landed.motion == Still and landed.turn != Steady
}

# A turn pressed during a turn starts when the current one ends.
expect {
	turning = Ball.act(floor_ahead, Ball.act(floor_ahead, still, in_place), TurnLeft)
	queued = Ball.act(floor_ahead, turning, TurnLeft)
	after = Ball.advance(queued, 0.32)
	queued.pose == turning.pose and after.turn == Turning({ from: Ball.turn_left(on_origin), t: 0.0, next: Stay }) and after.pose == Ball.turn_left(Ball.turn_left(on_origin))
}

# The original tests for a landing only in the last 11 of 27 frames.
expect !Ball.can_land(15.0 / 27.0, 0.0) and Ball.can_land(16.0 / 27.0, 0.0) and !Ball.can_land(0.9, 0.01)
expect {
	jumping = Ball.act(floor_ahead, still, forward_jump)
	Ball.advance(jumping, 0.53).motion != Still and Ball.advance(jumping, 0.54).motion == Still
}

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

# With Up held, the next roll starts in the step the last one ends, with the time left over.
expect {
	ball = Ball.advance_up_held(long_floor, rolling_at(0.5), 0.26)
	ball.pose.cell == cell(0, 1, -2) and match ball.motion {
		Rolling({ from, t }) => from.cell == cell(0, 1, -1) and near(t, 0.5)
		_ => False
	}
}

expect {
	jumping = Ball.act(long_floor, still, forward_jump)
	ball = Ball.advance_up_held(long_floor, jumping, 0.54)
	ball.pose.cell == cell(0, 1, -3) and match ball.motion {
		Rolling({ t, .. }) => near(t, 0.0)
		_ => False
	}
}

# A turn that outlasts the jump in place holds the roll back.
expect {
	turning = Ball.act(floor_ahead, Ball.advance(Ball.act(floor_ahead, still, in_place), 0.4), TurnLeft)
	Ball.advance_up_held(floor_ahead, turning, 0.2).motion == Still
}

expect Ball.advance(rolling_at(0.5), 0.26).motion == Still

# A block above bounces a forward jump too. A block two ahead does not bounce a jump in place.
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 0, -2), cell(0, 2, 0)]), still, forward_jump) == still
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -2)]), still, in_place).motion == JumpingInPlace({ t: 0.0 })

# The next roll gets the time after the later of the jump's end and the turn's end.
expect {
	west = blocks([cell(0, 0, 0), cell(-1, 0, 0)])
	turning = Ball.act(west, Ball.advance(Ball.act(west, still, in_place), 0.4), TurnLeft)
	ball = Ball.advance_up_held(west, turning, 0.52)
	ball.pose.cell == cell(-1, 1, 0) and match ball.motion {
		Rolling({ t, .. }) => near(t, 0.2 / roll_seconds(Floor))
		_ => False
	}
}

expect near(Ball.advance(still, 0.512).bob, 0.25)
expect near(Ball.advance(Ball.advance(still, 1.0), 1.048).bob, 0.0)

# The bob runs in a roll and a jump in place.
expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.1).bob > 0.0
expect Ball.advance(Ball.act(floor_ahead, still, Jump({ up_held: False })), 0.1).bob > 0.0

# A forward jump holds the bob, as does the arc of a fall.
expect {
	bobbing = { ..still, bob: 0.3 }
	Ball.advance(Ball.act(floor_ahead, bobbing, forward_jump), 0.27).bob == 0.3
}

expect {
	bobbing = { ..still, bob: 0.3 }
	falling = Ball.act(blocks([cell(0, 0, 0), cell(0, -3, -2)]), bobbing, forward_jump)
	in_arc = Ball.advance(falling, 0.5)
	in_arc.bob == 0.3 and Ball.advance(Ball.advance(in_arc, 0.1), 0.1).bob > 0.3
}

# The bob holds while the ball wraps an edge, and runs on the way to it.
expect {
	rolling = Ball.act(blocks([cell(0, 0, 0)]), still, Roll)
	wrapping = Ball.advance(rolling, 0.14)
	Ball.advance(rolling, 0.02).bob > 0.0 and Ball.advance(wrapping, 0.02).bob == wrapping.bob
}
