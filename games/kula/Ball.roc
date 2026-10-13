import linalg.Quat
import World
import Grid

Ball := [].{
	Ball : { pose : World.Pose, motion : Motion, rot : Quat.Quat }

	# The pose commits when a move starts. from and t only serve View.
	Motion : [Still, Rolling({ from : World.Pose, t : F32 }), Turning({ from : World.Pose, t : F32 }), Jumping({ from : World.Pose, t : F32 })]

	Action : [Roll, TurnLeft, TurnRight, Jump]

	# In cells.
	radius : F32
	radius = 0.4

	start : World.Pose -> Ball.Ball
	start = |pose| { pose, motion: Still, rot: Quat.identity }

	roll : Set(World.Cell), World.Pose -> World.Pose
	roll = |blocks, pose| {
		ahead = Grid.add(pose.cell, pose.forward)
		if Grid.has_block(blocks, ahead) {
			{ cell: pose.cell, up: Grid.neg(pose.forward), forward: pose.up }
		} else if Grid.has_block(blocks, Grid.sub(ahead, pose.up)) {
			{ ..pose, cell: ahead }
		} else {
			{ cell: Grid.sub(ahead, pose.up), up: pose.forward, forward: Grid.neg(pose.up) }
		}
	}

	turn_left : World.Pose -> World.Pose
	turn_left = |pose| { ..pose, forward: Grid.cross(pose.up, pose.forward) }

	turn_right : World.Pose -> World.Pose
	turn_right = |pose| { ..pose, forward: Grid.cross(pose.forward, pose.up) }

	# A block ahead is checked before the floor two ahead, so a jump never passes through a wall.
	jump : Set(World.Cell), World.Pose -> [Land(World.Pose), Fall(World.Pose), Refused]
	jump = |blocks, pose| {
		ahead = Grid.add(pose.cell, pose.forward)
		two_ahead = Grid.add(ahead, pose.forward)
		on_ahead = Grid.add(ahead, pose.up)
		if Grid.has_block(blocks, Grid.add(pose.cell, pose.up)) {
			Refused
		} else if Grid.has_block(blocks, ahead) {
			if Grid.has_block(blocks, on_ahead) { Refused } else { Land({ ..pose, cell: on_ahead }) }
		} else if Grid.has_block(blocks, two_ahead) {
			Refused
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
			(Still, Roll) => { ..ball, pose: roll(blocks, from), motion: Rolling({ from, t: 0.0 }) }
			(Still, TurnLeft) => { ..ball, pose: turn_left(from), motion: Turning({ from, t: 0.0 }) }
			(Still, TurnRight) => { ..ball, pose: turn_right(from), motion: Turning({ from, t: 0.0 }) }
			(Still, Jump) => match jump(blocks, from) {
				Land(pose) => { ..ball, pose, motion: Jumping({ from, t: 0.0 }) }
				Fall(_) => ball
				Refused => ball
			}
			_ => ball
		}
	}

	advance : Ball.Ball, F32 -> Ball.Ball
	advance = |ball, dt| match ball.motion {
		Still => ball
		Rolling({ from, t }) => {
			next = progress(t, dt, roll_seconds)
			axis = Grid.to_vec3(Grid.cross(from.up, from.forward))
			spin = Quat.from_axis_angle(axis, (next - t) / radius)
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
	}
}

roll_seconds : F32
roll_seconds = 0.2

turn_seconds : F32
turn_seconds = 0.1

jump_seconds : F32
jump_seconds = 0.4

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

expect Ball.roll(blocks([cell(0, 0, 0), cell(0, 1, -1)]), on_origin) == { cell: y_up, up: cell(0, 0, 1), forward: y_up }
expect Ball.roll(blocks([cell(0, 0, 0), cell(0, 0, -1)]), on_origin) == { cell: cell(0, 1, -1), up: y_up, forward: north }

# Over the edge onto the block's -z side, then on round under it.
expect {
	floor = blocks([cell(0, 0, 0)])
	side = Ball.roll(floor, on_origin)
	under = Ball.roll(floor, side)
	side == { cell: cell(0, 0, -1), up: north, forward: cell(0, -1, 0) } and under == { cell: cell(0, -1, 0), up: cell(0, -1, 0), forward: cell(0, 0, 1) }
}

expect Ball.turn_left(on_origin) == { ..on_origin, forward: cell(-1, 0, 0) }
expect Ball.turn_right(on_origin) == { ..on_origin, forward: cell(1, 0, 0) }

expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 0, -2)]), on_origin) == Land({ ..on_origin, cell: cell(0, 1, -2) })
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -1)]), on_origin) == Land({ ..on_origin, cell: cell(0, 2, -1) })
expect Ball.jump(blocks([cell(0, 0, 0)]), on_origin) == Fall({ ..on_origin, cell: cell(0, 1, -2) })
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 0, -2), cell(0, 2, 0)]), on_origin) == Refused

expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -1), cell(0, 0, -2)]), on_origin) == Land({ ..on_origin, cell: cell(0, 2, -1) })

# A wall two high ahead has no top to land on, and a wall two ahead blocks the landing.
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -1), cell(0, 2, -1)]), on_origin) == Refused
expect Ball.jump(blocks([cell(0, 0, 0), cell(0, 1, -2)]), on_origin) == Refused

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

expect Ball.act(floor_ahead, still, TurnLeft).motion == Turning({ from: on_origin, t: 0.0 })
expect Ball.act(floor_ahead, still, Jump) == { ..still, pose: { ..on_origin, cell: cell(0, 1, -2) }, motion: Jumping({ from: on_origin, t: 0.0 }) }
expect Ball.act(blocks([cell(0, 0, 0)]), still, Jump) == still

# Input is read only when Still.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	Ball.act(floor_ahead, rolling, TurnLeft) == rolling
}

expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.1).motion == Rolling({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, Roll), 0.2).motion == Still
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.05).motion == Turning({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, TurnRight), 0.1).motion == Still
expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.2).motion == Jumping({ from: on_origin, t: 0.5 })
expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.4).motion == Still
expect Ball.advance(still, 1.0) == still

# Rolling along -z on +y turns about -x, 2.5 radians a cell, however the steps fall.
expect {
	rolling = Ball.act(floor_ahead, still, Roll)
	ball = [0.05, 0.05, 0.07, 0.07].fold(rolling, |b, dt| Ball.advance(b, dt))
	ball.motion == Still and near_quat(ball.rot, Quat.from_axis_angle({ x: -1.0, y: 0.0, z: 0.0 }, 2.5))
}

expect Ball.advance(Ball.act(floor_ahead, still, Jump), 0.4).rot == Quat.identity
