app [init, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47", cam: "../../packages/camera/main.roc" }

import cam.Camera as Cam

Vec3 : { x : F32, y : F32, z : F32 }

Rgb : { r : F32, g : F32, b : F32 }

Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }

Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }

Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }

Scene : { camera : Cam.View, draws : List(Draw) }

Ball : { id : U64, x : F32, z : F32, vx : F32, vz : F32 }

Score : { left : U64, right : U64 }

Model : { cube : U32, left : F32, right : F32, ball : Ball, score : Score, rng : U64, serves : U64 }

# Constants
half_width = 8.0 # F32
half_depth = 5.0 # F32
paddle_x = 7.0 # F32
paddle_half_len = 1.0 # F32
paddle_half_thick = 0.15 # F32
paddle_limit = half_depth - paddle_half_len # F32
paddle_speed = 9.0 # F32
ball_half = 0.2 # F32
ball_id_base = 1_000_000 # U64
wall_limit : F32
wall_limit = half_depth - ball_half
serve_speed : F32
serve_speed = 8.0

# key codes (sokol mapping)
key_w = 87
key_s = 83
key_up = 265
key_down = 264

manifest : Config
manifest = { seed: 0, meshes: [{ name: "cube", id: 1 }] }

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

init : Config -> Model
init = |config| {
	# Resolve cube from the manifest
	mesh = match List.find_first(config.meshes, |m| m.name == "cube") {
		Ok(m) => m.id
		Err(NotFound) => 0
	}

	model = {
		cube: mesh,
		left: 0.0,
		right: 0.0,
		ball: { id: ball_id_base, x: 0.0, z: 0.0, vx: 0.0, vz: 0.0 },
		score: { left: 0, right: 0 },
		rng: config.seed,
		serves: 0,
	}

	serve(model, 1.0)
}

step : Model, Input, F32 -> Model
step = |m, input, dt| {
	m
        |> move_paddles(input, dt)
        |> move_ball(dt)
        |> bounce_walls
        |> hit_paddles
        |> score_point
}

white : Rgb
white = { r: 0.95, g: 0.95, b: 0.95 }

box : U32, U64, Vec3, Vec3, Rgb -> Draw
box = |mesh, id, pos, scale, tint| { id, mesh, pos, scale, yaw: 0.0, tint }

view : Model -> Scene
view = |m| {
	c = m.cube
	fixed = [
		box(c, 10, { x: 0.0, y: -0.1, z: 0.0 }, { x: 2.0 * half_width, y: 0.1, z: 2.0 * half_depth }, { r: 0.1, g: 0.12, b: 0.15 }),
		box(c, 11, { x: 0.0, y: 0.1, z: -half_depth - 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white),
		box(c, 12, { x: 0.0, y: 0.1, z: half_depth + 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white),
		box(c, 0, { x: -paddle_x, y: 0.2, z: m.left }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 0.3, g: 0.7, b: 1.0 }),
		box(c, 1, { x: paddle_x, y: 0.2, z: m.right }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 1.0, g: 0.5, b: 0.3 }),
		box(c, m.ball.id, { x: m.ball.x, y: 0.2, z: m.ball.z }, { x: 2.0 * ball_half, y: 2.0 * ball_half, z: 2.0 * ball_half }, white),
	]

	draws = fixed
	    |> pips(c, m.score.left, 1000, -1.0)
	    |> pips(c, m.score.right, 2000, 1.0)

	{ camera: Cam.look_at({ x: 0.0, y: 14.0, z: 7.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws }
}

pips : List(Draw), U32, U64, U64, F32 -> List(Draw)
pips = |draws, mesh, count, id_base, side| {
	var $out = draws
	var $i = 0
	while $i < count {
		pos = { x: side * (1.0 + $i.to_f32() * 0.6), y: 0.2, z: -half_depth - 1.0 }
		$out = List.append($out, box(mesh, id_base + $i, pos, { x: 0.3, y: 0.3, z: 0.3 }, white))
		$i = $i + 1
	}
	$out
}

serve : Model, F32 -> Model
serve = |m, dir| {
    rng = next_rng(m.rng)
    serves = m.serves + 1
    ball = { id: ball_id_base + serves, x: 0.0, z: 0.0, vx: dir * serve_speed, vz: (unit(rng) - 0.5) * 6.0 }

    { ..m, ball, serves, rng }
}

score_point : Model -> Model
score_point = |m| {
    if m.ball.x > half_width {
        serve({ ..m, score: { ..m.score, left: m.score.left + 1 } }, -1.0)
    } else if m.ball.x < -half_width {
        serve({ ..m, score: { ..m.score, right: m.score.right + 1 } }, 1.0)
    } else m
}

move_paddles : Model, Input, F32 -> Model
move_paddles = |m, input, dt| {
	left = clamp(-paddle_limit, paddle_limit, m.left + axis(input, key_w, key_s) * paddle_speed * dt)
	right = clamp(-paddle_limit, paddle_limit, m.right + axis(input, key_up, key_down) * paddle_speed * dt)
	{ ..m, left, right }
}

move_ball : Model, F32 -> Model
move_ball = |m, dt| {
	ball = { ..m.ball, x: m.ball.x + m.ball.vx * dt, z: m.ball.z + m.ball.vz * dt }
	{ ..m, ball }
}

bounce_walls : Model -> Model
bounce_walls = |m| {
	b = m.ball
	outward = b.z > wall_limit and b.vz > 0.0 or b.z < -wall_limit and b.vz < 0.0

	if outward {
		{ ..m, ball: { ..b, vz: -b.vz } }
	} else {
		m
	}
}

touches : Ball, F32, F32 -> Bool
touches = |b, px, pz| {
    (b.x - px).abs() < ball_half + paddle_half_thick
        and (b.z - pz).abs() < ball_half + paddle_half_len
}

return_ball : Ball, F32 -> Ball
return_ball = |b, pz| {
    { ..b, vx: -b.vx * 1.05, vz: b.vz + (b.z - pz) * 3.0 }
}

hit_paddles : Model -> Model
hit_paddles = |m| {
	b = m.ball
	if b.vx < 0.0 and touches(b, -paddle_x, m.left) {
		{ ..m, ball: return_ball(b, m.left) }
	} else if b.vx > 0.0 and touches(b, paddle_x, m.right) {
		{ ..m, ball: return_ball(b, m.right) }
	} else {
		m
	}
}

axis : Input, U16, U16 -> F32
axis = |input, neg, pos| {
	n = if List.contains(input.held, neg) {
		1.0
	} else {
		0.0
	}
	p = if List.contains(input.held, pos) {
		1.0
	} else {
		0.0
	}
	p - n
}

clamp : F32, F32, F32 -> F32
clamp = |lo, hi, v| {
	v.max(lo).min(hi)
}

next_rng : U64 -> U64
next_rng = |s| s.times_wrap(6364136223846793005).plus_wrap(1)

unit : U64 -> F32
unit = |s| (s.shr_zf_wrap(40) % 1000).to_f32() / 1000.0


# =======================================
# Tests
# =======================================
# Paddle movement, wall and paddle bounces, scoring and serve state.
# The manifest names a cube, so init resolves its mesh id.
expect init(manifest).cube == 1

# A fresh scene draws the floor, two walls, two paddles and the ball.
expect List.len(view(init(manifest)).draws) == 6

# clamp caps above the top and below the bottom.
expect clamp(1.0, 2.0, 2.1) == 2.0
expect clamp(1.0, 2.0, 0.5) == 1.0

# Holding W for a long step drives the left paddle to its limit, the right stays put.
expect {
	m = step(init(manifest), { ..idle, held: [key_w] }, 10.0)
	m.left == -paddle_limit and m.right == 0.0
}

# A ball past the top wall moving outward bounces once, and a second call is a no-op.
expect {
    m = init(manifest)
    going_out = { ..m, ball: { ..m.ball, z: wall_limit + 0.01, vz: 2.0 }}
    once = bounce_walls(going_out)
    twice = bounce_walls(once)
    once.ball.vz == -2.0 and twice.ball.vz == -2.0
}

# The same for the bottom wall, which needs the opposite sign on vz.
expect {
    m = init(manifest)
    going_out = { ..m, ball: { ..m.ball, z: -wall_limit - 0.01, vz: -2.0 }}
    once = bounce_walls(going_out)
    twice = bounce_walls(once)
    once.ball.vz == 2.0 and twice.ball.vz == 2.0
}

# A ball reaching the right paddle is returned faster and angled by where it hit.
expect {
    m = init(manifest)
    at_right = { ..m, ball: {..m.ball, x: paddle_x - 0.2, z: 0.5, vx: 8.0, vz: 0.0 } }
    once = hit_paddles(at_right)
    twice = hit_paddles(once)
    once.ball.vx == -8.4 and once.ball.vz == 1.5 and twice.ball.vx == -8.4
}

# A ball past the right wall scores for the left and is served again with a new id.
expect {
	m = init(manifest)
	past_right = { ..m, ball: { ..m.ball, x: half_width + 0.1 } }
	after = score_point(past_right)
	after.score.left == 1 and after.ball.x == 0.0 and after.ball.id == m.ball.id + 1
}

# The seed picks the serve angle, and the first serve id is one past the base.
expect {
	a = init(manifest)
	b = init({ ..manifest, seed: 7 })
	a.ball.vz != b.ball.vz and a.ball.id == ball_id_base + 1
}

# Each scored point adds one pip, so 3 + 2 pips join the six fixed draws.
expect {
	m = init(manifest)
	scored = { ..m, score: { left: 3, right: 2 } }
	List.len(view(scored).draws) == 11
}
