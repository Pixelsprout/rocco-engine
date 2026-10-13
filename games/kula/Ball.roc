import linalg.Quat
import World
import Grid

Ball := [].{
	Ball : { pose : World.Pose, motion : Motion, rot : Quat.Quat }

	# The pose commits when a move starts. from and t only serve View.
	Motion : [Still, Rolling({ from : World.Pose, t : F32 }), Turning({ from : World.Pose, t : F32 }), Jumping({ from : World.Pose, t : F32 }), Falling({ from : World.Pose, t : F32 })]

	Action : [Roll, TurnLeft, TurnRight, Jump]

	# In cells. The original rests the ball centre 100 of 512 units above a face.
	radius : F32
	radius = 0.195

	start : World.Pose -> Ball.Ball
	start = |pose| { pose, motion: Still, rot: Quat.identity }

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
	jump : Set(World.Cell), World.Pose -> [Land(World.Pose), Fall(World.Pose), Bounce]
	jump = |blocks, pose| {
		ahead = Grid.add(pose.cell, pose.forward)
		two_ahead = Grid.add(ahead, pose.forward)
		if Grid.has_block(blocks, Grid.add(pose.cell, pose.up)) or Grid.has_block(blocks, ahead) or Grid.has_block(blocks, two_ahead) {
			Bounce
		} else if Grid.has_block(blocks, Grid.sub(two_ahead, pose.up)) {
			Land({ ..pose, cell: two_ahead })
		} else {
			Fall({ ..pose, cell: two_ahead })
		}
	}

	# Starts a move from Still. A moving ball ignores the action.
	act : Set(World.Cell), Ball.Ball, Action -> Ball.Ball
	act = |blocks, ball, action| {
		from = ball.pose
		match (ball.motion, action) {
			(Still, Roll) => match roll(blocks, from) {
				Ok(pose) => { ..ball, pose, motion: Rolling({ from, t: 0.0 }) }
				Err(ClosedEdge) => ball
			}
			(Still, TurnLeft) => { ..ball, pose: turn_left(from), motion: Turning({ from, t: 0.0 }) }
			(Still, TurnRight) => { ..ball, pose: turn_right(from), motion: Turning({ from, t: 0.0 }) }
			(Still, Jump) => match jump(blocks, from) {
				Land(pose) => { ..ball, pose, motion: Jumping({ from, t: 0.0 }) }
				Fall(pose) => { ..ball, pose, motion: Falling({ from, t: 0.0 }) }
				Bounce => ball
			}
			_ => ball
		}
	}

	advance : Ball.Ball, F32 -> Ball.Ball
	advance = |ball, dt| match ball.motion {
		Still => ball
		Rolling({ from, t }) => {
			kind = roll_kind(from, ball.pose)
			next = progress(t, dt, roll_seconds(kind))
			axis = Grid.to_vec3(Grid.cross(from.up, from.forward))
			spin = Quat.from_axis_angle(axis, (next - t) * roll_length(kind) / radius)
			{ ..ball, rot: Quat.mul(spin, ball.rot), motion: if next < 1.0 { Rolling({ from, t: next }) } else { Still } }
		}
		Turning({ from, t }) => {
			next = progress(t, dt, turn_seconds)
			{ ..ball, motion: if next < 1.0 { Turning({ from, t: next }) } else { Still } }
		}
		Jumping({ from, t }) => {
			next = progress(t, dt, jump_seconds)
			{ ..ball, motion: if next < 1.0 { Jumping({ from, t: next }) } else { Still } }
		}
		# A fall never ends Still. Rules restarts the level when t reaches 1.
		Falling({ from, t }) => { ..ball, motion: Falling({ from, t: progress(t, dt, fall_seconds) }) }
	}
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

fall_seconds : F32
fall_seconds = 0.5

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
expect Ball.jump(blocks([cell(0, 0, 0)]), on_origin) == Fall({ ..on_origin, cell: cell(0, 1, -2) })
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -1), cell(0, 0, -2)]), on_origin) == Bounce
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -2), cell(0, 0, -2)]), on_origin) == Bounce
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 0, -2), cell(0, 2, 0)]), on_origin) == Bounce

floor_ahead : Set(World.Cell)
floor_ahead = blocks([cell(0, 0, 0), cell(0, 0, -1), cell(0, 0, -2)])

still : Ball.Ball
still = Ball.start(on_origin)

near_quat : Quat.Quat, Quat.Quat -> Bool
near_quat = |a, b| (a.x - b.x).abs() < 0.0001 and (a.y - b.y).abs() < 0.0001 and (a.z - b.z).abs() < 0.0001 and (a.w - b.w).abs() < 0.0001

expect {
	ball = Ball.act(floor_ahead, still, Roll)
	ball.pose.cell == cell(0, 1, -1) and ball.motion == Rolling({ from: on_origin, t: 0.0 })
}

expect Ball.act(blocks([cell(0, 0, 0), cell(1, 0, 0)]), still, Roll) == still
expect Ball.act(floor_ahead, still, TurnLeft).motion == Turning({ from: on_origin, t: 0.0 })
expect Ball.act(floor_ahead, still, Jump) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Jumping({ from: on_origin, t: 0.0 }) }
expect Ball.act(blocks([cell(0, 0, 0)]), still, Jump) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Falling({ from: on_origin, t: 0.0 }) }
expect Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, Jump) == still

# Input is read only when Still.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	Ball.act(floor_ahead, rolling, TurnLeft) == rolling
}

expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.13).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.26).motion == Still
expect Ball.advance(Ball.act(blocks([cell(0, 0, 0), cell(0, 1, -1)]), still, Roll), 0.14).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(blocks([cell(0, 0, 0)]), still, Roll), 0.17).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.16).motion == Turning({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.32).motion == Still
expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.27).motion == Jumping({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.54).motion == Still
expect Ball.advance(still, 1.0) == still
expect Ball.advance(Ball.act(blocks([cell(0, 0, 0)]), still, Jump), 0.25).motion == Falling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.advance(Ball.act(blocks([cell(0, 0, 0)]), still, Jump), 0.5), 0.5).motion == Falling({ from: on_origin, t: 1.0 })

# Rolling along -z on +y turns about -x, one cell over the radius, however the steps fall.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	ball = [0.06, 0.07, 0.06, 0.07, 0.05].fold(rolling, |b, dt| Ball.advance(b, dt))
	ball.motion == Still and near_quat(ball.rot, Quat.from_axis_angle({ x: -1.0, y: 0.0, z: 0.0 }, 1.0 / Ball.radius))
}

expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.54).rot == Quat.identity
