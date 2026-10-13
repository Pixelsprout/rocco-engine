import linalg.Quat
import linalg.Vec3
import pf.Vocabulary exposing [Camera, Draw, Rgb]
import World
import Grid
import Ball

View := [].{
	Placement : { pos : Vec3.Vec3, up : Vec3.Vec3, forward : Vec3.Vec3 }

	interpolated : Ball.Ball -> Placement
	interpolated = |ball| match ball.motion {
		Still => placement_of(ball.pose)
		Rolling({ from, t }) => between(from, ball.pose, t)
		Turning({ from, t }) => between(from, ball.pose, t)
		Jumping({ from, t }) => {
			placed = between(from, ball.pose, t)
			{ ..placed, pos: Vec3.add(placed.pos, Vec3.scale(placed.up, 4.0 * jump_height * t * (1.0 - t))) }
		}
	}

	# The centre sinks from the middle of the cell so the ball rests on the face below.
	ball_draw : Ball.Ball, U32, Rgb -> Draw
	ball_draw = |ball, mesh, tint| {
		placed = interpolated(ball)
		sink = 0.5 - Ball.radius
		{ id: 0, mesh, pos: Vec3.sub(placed.pos, Vec3.scale(placed.up, sink)), scale: Vec3.scale(Vec3.one, 2.0 * Ball.radius), rot: ball.rot, tint }
	}

	# The camera has no clipping test. It stays less than half a cell behind the
	# ball, so after a climb it never reaches into the floor the ball left.
	camera : Ball.Ball -> Camera
	camera = |ball| {
		placed = interpolated(ball)
		eye = Vec3.add(Vec3.sub(placed.pos, Vec3.scale(placed.forward, camera_back)), Vec3.scale(placed.up, camera_height))
		target = Vec3.add(placed.pos, Vec3.scale(placed.forward, camera_lead))
		{ eye, target, up: placed.up, fov_y: 1.047 }
	}
}

camera_back : F32
camera_back = 0.4

camera_height : F32
camera_height = 2.5

# The camera looks one cell ahead, so the ball sits low in the view.
camera_lead : F32
camera_lead = 1.0

jump_height : F32
jump_height = 0.5

placement_of : World.Pose -> View.Placement
placement_of = |pose| { pos: Grid.to_vec3(pose.cell), up: Grid.to_vec3(pose.up), forward: Grid.to_vec3(pose.forward) }

between : World.Pose, World.Pose, F32 -> View.Placement
between = |from, to, t| {
	a = placement_of(from)
	b = placement_of(to)
	{ pos: Vec3.lerp(a.pos, b.pos, t), up: Vec3.normalize(Vec3.lerp(a.up, b.up, t)), forward: Vec3.normalize(Vec3.lerp(a.forward, b.forward, t)) }
}

cell : I32, I32, I32 -> World.Cell
cell = |x, y, z| { x, y, z }

on_origin : World.Pose
on_origin = { cell: cell(0, 1, 0), up: cell(0, 1, 0), forward: cell(0, 0, -1) }

floor : Set(World.Cell)
floor = Set.from_list([cell(0, 0, 0), cell(0, 0, -1), cell(0, 0, -2)])

near : Vec3.Vec3, Vec3.Vec3 -> Bool
near = |a, b| Vec3.length(Vec3.sub(a, b)) < 0.0001

white : Rgb
white = { r: 1.0, g: 1.0, b: 1.0 }

expect View.interpolated(Ball.start(on_origin)) == { pos: { x: 0.0, y: 1.0, z: 0.0 }, up: { x: 0.0, y: 1.0, z: 0.0 }, forward: { x: 0.0, y: 0.0, z: -1.0 } }

expect {
	half = Ball.advance(Ball.act(floor, Ball.start(on_origin), Roll), 0.1)
	View.interpolated(half).pos == { x: 0.0, y: 1.0, z: -0.5 }
}

# Halfway round an edge, up and forward are each a unit diagonal.
expect {
	edge = Set.from_list([cell(0, 0, 0)])
	placed = View.interpolated(Ball.advance(Ball.act(edge, Ball.start(on_origin), Roll), 0.1))
	s = 0.70710678
	near(placed.pos, { x: 0.0, y: 0.5, z: -0.5 }) and near(placed.up, { x: 0.0, y: s, z: -s }) and near(placed.forward, { x: 0.0, y: -s, z: -s })
}

# A jump peaks half a cell above the straight line at its midpoint.
expect {
	placed = View.interpolated(Ball.advance(Ball.act(floor, Ball.start(on_origin), Jump), 0.2))
	near(placed.pos, { x: 0.0, y: 1.5, z: -1.0 })
}

expect {
	draw = View.ball_draw(Ball.start(on_origin), 2, white)
	near(draw.pos, { x: 0.0, y: 0.9, z: 0.0 }) and draw.scale == Vec3.scale(Vec3.one, 0.8) and draw.rot == Quat.identity and draw.mesh == 2
}

expect {
	cam = View.camera(Ball.start(on_origin))
	near(cam.eye, { x: 0.0, y: 3.5, z: 0.4 }) and cam.target == { x: 0.0, y: 1.0, z: -1.0 } and cam.up == { x: 0.0, y: 1.0, z: 0.0 }
}

inside_block : Set(World.Cell), Vec3.Vec3 -> Bool
inside_block = |blocks, v| blocks.to_list().any(|b| {
	c = Grid.to_vec3(b)
	(v.x - c.x).abs() < 0.5 and (v.y - c.y).abs() < 0.5 and (v.z - c.z).abs() < 0.5
})

# After a climb, behind the ball is down through the floor it left.
expect {
	behind = Set.from_list([cell(0, 0, 0), cell(0, 0, 1), cell(0, 0, 2), cell(0, 0, 3), cell(0, 1, -1)])
	climbed = Ball.advance(Ball.act(behind, Ball.start(on_origin), Roll), 0.2)
	cam = View.camera(climbed)
	climbed.pose.up == cell(0, 0, 1) and near(cam.eye, { x: 0.0, y: 0.6, z: 2.5 }) and !inside_block(behind, cam.eye)
}
