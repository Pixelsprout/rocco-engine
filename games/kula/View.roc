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

	ball_draw : Ball.Ball, U32, Rgb -> Draw
	ball_draw = |ball, mesh, tint| {
		{ id: 0, mesh, pos: centre(ball), scale: Vec3.scale(Vec3.one, 2.0 * Ball.radius), rot: ball.rot, tint }
	}

	# Rigid in the ball's frame, with no smoothing and no clipping test, as in the
	# original. After a climb the eye sits inside the floor the ball left. That
	# floor does not hide the ball only because blocks draw as one-sided faces.
	camera : Ball.Ball -> Camera
	camera = |ball| {
		placed = interpolated(ball)
		cam_forward = Vec3.sub(Vec3.scale(placed.forward, camera_pitch.cos()), Vec3.scale(placed.up, camera_pitch.sin()))
		cam_up = Vec3.add(Vec3.scale(placed.forward, camera_pitch.sin()), Vec3.scale(placed.up, camera_pitch.cos()))
		eye = Vec3.add(Vec3.sub(centre(ball), Vec3.scale(cam_forward, camera_depth)), Vec3.scale(cam_up, camera_drop))
		{ eye, target: Vec3.add(eye, cam_forward), up: cam_up, fov_y: camera_fov_y }
	}

	Face : { block : World.Cell, normal : World.Cell }

	# One face for each side of a block that borders an empty cell, as the original builds its level.
	faces : Set(World.Cell) -> List(Face)
	faces = |blocks| blocks.to_list().join_map(|block|
		normals.keep_if(|normal| !Grid.has_block(blocks, Grid.add(block, normal))).map(|normal| { block, normal }))

	# A guess at the original's near-polygon handling, which is undecompiled: a
	# face this close to the eye is not drawn, so the floor left behind in a
	# climb vanishes and is not sliced by the near plane. See SPEC.md.
	near_eye : Face, Vec3.Vec3 -> Bool
	near_eye = |face, eye| {
		centre_of_face = Vec3.add(Grid.to_vec3(face.block), Vec3.scale(Grid.to_vec3(face.normal), 0.5))
		n = Grid.to_vec3(face.normal)
		closest = |e, c, axis_normal| if axis_normal != 0.0 { c } else { clamp(e, c - 0.5, c + 0.5) }
		nearest = {
			x: closest(eye.x, centre_of_face.x, n.x),
			y: closest(eye.y, centre_of_face.y, n.y),
			z: closest(eye.z, centre_of_face.z, n.z),
		}
		Vec3.length(Vec3.sub(eye, nearest)) < near_face_distance
	}

	# The primitive plane faces +y and is one-sided.
	face_draw : U64, U32, Face, Rgb -> Draw
	face_draw = |id, mesh, face, tint| {
		pos = Vec3.add(Grid.to_vec3(face.block), Vec3.scale(Grid.to_vec3(face.normal), 0.5))
		{ id, mesh, pos, scale: Vec3.one, rot: face_rot(face.normal), tint }
	}
}

# The original's view space puts the ball centre 250 units below the screen
# centre at a depth of 800, with the basis pitched down 250 of 4096. See SPEC.md.
camera_pitch : F32
camera_pitch = 250.0 / 4096.0 * 2.0 * pi

camera_depth : F32
camera_depth = 800.0 / 512.0

camera_drop : F32
camera_drop = 250.0 / 512.0

# 73.7 degrees, from the original's 90 degree horizontal view on 4:3.
camera_fov_y : F32
camera_fov_y = 1.286

near_face_distance : F32
near_face_distance = 1.12

clamp : F32, F32, F32 -> F32
clamp = |v, lo, hi| if v < lo { lo } else if v > hi { hi } else { v }

pi : F32
pi = 3.1415927

jump_height : F32
jump_height = 0.5

# The centre rests one radius above the face. Round an edge it follows the
# original's path: half a cell to the edge, a quarter circle of one radius
# about the edge line, then half a cell down the side.
centre : Ball.Ball -> Vec3.Vec3
centre = |ball| match ball.motion {
	Rolling({ from, t }) if Ball.roll_kind(from, ball.pose) == Edge => edge_centre(from, t)
	_ => {
		placed = View.interpolated(ball)
		Vec3.sub(placed.pos, Vec3.scale(placed.up, 0.5 - Ball.radius))
	}
}

edge_centre : World.Pose, F32 -> Vec3.Vec3
edge_centre = |from, t| {
	up = Grid.to_vec3(from.up)
	forward = Grid.to_vec3(from.forward)
	r = Ball.radius
	edge = Vec3.add(Grid.to_vec3(Grid.sub(from.cell, from.up)), Vec3.scale(Vec3.add(up, forward), 0.5))
	arc = pi / 2.0 * r
	s = t * Ball.roll_length(Edge)
	if s < 0.5 {
		Vec3.add(edge, Vec3.add(Vec3.scale(up, r), Vec3.scale(forward, s - 0.5)))
	} else if s < 0.5 + arc {
		a = (s - 0.5) / r
		Vec3.add(edge, Vec3.add(Vec3.scale(up, r * a.cos()), Vec3.scale(forward, r * a.sin())))
	} else {
		Vec3.sub(Vec3.add(edge, Vec3.scale(forward, r)), Vec3.scale(up, s - 0.5 - arc))
	}
}

normals : List(World.Cell)
normals = [{ x: 0, y: 1, z: 0 }, { x: 0, y: -1, z: 0 }, { x: 1, y: 0, z: 0 }, { x: -1, y: 0, z: 0 }, { x: 0, y: 0, z: 1 }, { x: 0, y: 0, z: -1 }]

face_rot : World.Cell -> Quat.Quat
face_rot = |normal| {
	x_axis = { x: 1.0, y: 0.0, z: 0.0 }
	z_axis = { x: 0.0, y: 0.0, z: 1.0 }
	if normal.y == 1 {
		Quat.identity
	} else if normal.y == -1 {
		Quat.from_axis_angle(x_axis, pi)
	} else if normal.x == 1 {
		Quat.from_axis_angle(z_axis, -pi / 2.0)
	} else if normal.x == -1 {
		Quat.from_axis_angle(z_axis, pi / 2.0)
	} else if normal.z == 1 {
		Quat.from_axis_angle(x_axis, pi / 2.0)
	} else {
		Quat.from_axis_angle(x_axis, -pi / 2.0)
	}
}

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
	half = Ball.advance(Ball.act(floor, Ball.start(on_origin), Roll), 0.13)
	View.interpolated(half).pos == { x: 0.0, y: 1.0, z: -0.5 }
}

# Halfway round an edge, up and forward are each a unit diagonal.
expect {
	edge = Set.from_list([cell(0, 0, 0)])
	placed = View.interpolated(Ball.advance(Ball.act(edge, Ball.start(on_origin), Roll), 0.17))
	s = 0.70710678
	near(placed.pos, { x: 0.0, y: 0.5, z: -0.5 }) and near(placed.up, { x: 0.0, y: s, z: -s }) and near(placed.forward, { x: 0.0, y: -s, z: -s })
}

# A jump peaks half a cell above the straight line at its midpoint.
expect {
	placed = View.interpolated(Ball.advance(Ball.act(floor, Ball.start(on_origin), Jump), 0.27))
	near(placed.pos, { x: 0.0, y: 1.5, z: -1.0 })
}

expect {
	draw = View.ball_draw(Ball.start(on_origin), 2, white)
	near(draw.pos, { x: 0.0, y: 0.695, z: 0.0 }) and draw.scale == Vec3.scale(Vec3.one, 0.39) and draw.rot == Quat.identity and draw.mesh == 2
}

# SPEC.md: the eye is 1.27 cells behind the ball centre and 1.04 above it.
expect {
	cam = View.camera(Ball.start(on_origin))
	(cam.eye.x).abs() < 0.001 and (cam.eye.y - (0.695 + 1.0375)).abs() < 0.001 and (cam.eye.z - 1.2663).abs() < 0.001
}

# The ball centre sits 250 units below the view axis at a depth of 800.
expect {
	cam = View.camera(Ball.start(on_origin))
	to_ball = Vec3.sub({ x: 0.0, y: 0.695, z: 0.0 }, cam.eye)
	view_dir = Vec3.sub(cam.target, cam.eye)
	(Vec3.dot(to_ball, view_dir) - 800.0 / 512.0).abs() < 0.001 and (Vec3.dot(to_ball, cam.up) + 250.0 / 512.0).abs() < 0.001
}

inside_block : Set(World.Cell), Vec3.Vec3 -> Bool
inside_block = |blocks, v| blocks.to_list().any(|b| {
	c = Grid.to_vec3(b)
	(v.x - c.x).abs() < 0.5 and (v.y - c.y).abs() < 0.5 and (v.z - c.z).abs() < 0.5
})

# After a climb the eye is inside the floor block behind the ball, as in the original.
expect {
	behind = Set.from_list([cell(0, 0, 0), cell(0, 0, 1), cell(0, 0, 2), cell(0, 0, 3), cell(0, 1, -1)])
	climbed = Ball.advance(Ball.act(behind, Ball.start(on_origin), Roll), 0.28)
	cam = View.camera(climbed)
	climbed.pose.up == cell(0, 0, 1) and inside_block(Set.from_list([cell(0, 0, 1)]), cam.eye)
}

expect View.faces(Set.from_list([cell(0, 0, 0)])).len() == 6

# Two stacked blocks draw no face between them.
expect {
	found = View.faces(Set.from_list([cell(0, 0, 0), cell(0, 1, 0)]))
	found.len() == 10 and !found.contains({ block: cell(0, 0, 0), normal: cell(0, 1, 0) }) and !found.contains({ block: cell(0, 1, 0), normal: cell(0, -1, 0) })
}

# Each face turns the plane's +y onto its normal and sits on the block's surface.
expect {
	up = { x: 0.0, y: 1.0, z: 0.0 }
	View.faces(Set.from_list([cell(2, 0, 0)])).all(|face| {
		draw = View.face_draw(1, 3, face, white)
		n = Grid.to_vec3(face.normal)
		near(Quat.rotate(up, draw.rot), n) and near(draw.pos, Vec3.add({ x: 2.0, y: 0.0, z: 0.0 }, Vec3.scale(n, 0.5)))
	})
}

# Distance from a point to the surface of the unit block at the origin, 0 inside.
outside_origin_block : Vec3.Vec3 -> F32
outside_origin_block = |v| {
	gap = |c| if c.abs() > 0.5 { c.abs() - 0.5 } else { 0.0 }
	Vec3.length({ x: gap(v.x), y: gap(v.y), z: gap(v.z) })
}

# Round an edge, the ball wraps the corner and never enters the block.
expect {
	edge = Set.from_list([cell(0, 0, 0)])
	rolling = Ball.act(edge, Ball.start(on_origin), Roll)
	steps = [0.0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.12, 0.14, 0.16, 0.17, 0.18, 0.2, 0.22, 0.24, 0.26, 0.28, 0.3, 0.32, 0.34]
	steps.all(|dt| outside_origin_block(View.ball_draw(Ball.advance(rolling, dt), 2, white).pos) >= Ball.radius - 0.001)
}

# Halfway round, the centre sits one radius out from the edge at 45 degrees.
expect {
	edge = Set.from_list([cell(0, 0, 0)])
	half = Ball.advance(Ball.act(edge, Ball.start(on_origin), Roll), 0.17)
	d = Ball.radius * 0.70710678
	near(View.ball_draw(half, 2, white).pos, { x: 0.0, y: 0.5 + d, z: -0.5 - d })
}

expect {
	face = { block: cell(0, 0, 0), normal: cell(0, 1, 0) }
	View.near_eye(face, { x: 0.2, y: 1.5, z: -0.4 }) and !View.near_eye(face, { x: 0.0, y: 1.7, z: 0.0 }) and !View.near_eye(face, { x: 1.7, y: 0.5, z: 0.0 })
}
