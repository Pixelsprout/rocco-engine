app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

# The guide pages copy the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Element, Manifest, Rgb, Rgba, Vec3]
import pf.Config
import pf.Draw
import pf.Input
import pf.Launch
import pf.Scene
import pf.Key
import pf.Light
import pf.QueryResults

Ball : { id : U64, x : F32, z : F32, vx : F32, vz : F32 }

Score : { left : U64, right : U64 }

GameState : [Running, Paused, EndGame]

Model : { state : GameState, cube : U32, left : F32, right : F32, ball : Ball, score : Score, rng : U64, serves : U64 }

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

max_score = 7

# region: launch
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "pong" } }

# endregion

# region: calls
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| {
	model = {
		state: Running,
		cube: Mesh.primitive(Cube),
		left: 0.0,
		right: 0.0,
		ball: { id: ball_id_base, x: 0.0, z: 0.0, vx: 0.0, vz: 0.0 },
		score: { left: 0, right: 0 },
		rng: config.seed,
		serves: 0,
	}

	{ model: serve(model, 1.0), commands: [] }
}

# Pong draws only the cube primitive, so it loads no pack.
loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, input, _results, dt| { model: update(m, input, dt), commands: [] }

# endregion

update : Model, Vocabulary.Input, F32 -> Model
update = |m, input, dt| {
	next = game_state(m, input)
	if next.state == Running {
		next
			|> move_paddles(input, dt)
			|> move_ball(dt)
			|> bounce_walls
			|> hit_paddles
			|> score_point
	} else {
		next
	}
}

white : Rgb
white = { r: 0.89, g: 0.89, b: 0.89 }

white_text : Rgba
white_text = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }

green_text : Rgba
green_text = { r: 0.033, g: 0.787, b: 0.073, a: 1.0 }

red_text : Rgba
red_text = { r: 0.787, g: 0.033, b: 0.033, a: 1.0 }

# region: ui
centred : Ui.BoxConfig
centred = { ..Ui.default_box, child_align: { x: Center, y: Center } }

score_color : GameState, U64, U64 -> Rgba
score_color = |state, own, other| {
	if state == EndGame {
		if own > other {
			green_text
		} else {
			red_text
		}
	} else {
		white_text
	}
}

# Fixed cells keep the colon still when a score gains a digit.
scoreboard : GameState, Score -> Element
scoreboard = |state, score| {
	cell = |own, other| Box({ ..centred, width: Fixed(48.0) }, [Text({ ..Ui.label(own.to_str()), color: score_color(state, own, other) })])
	Box(
		{ ..Ui.panel(CenterTop, { x: 0.0, y: 16.0 }), gap: 8.0, child_align: { x: Center, y: Center } },
		[cell(score.left, score.right), Text(Ui.label(":")), cell(score.right, score.left)],
	)
}

banner : GameState, Score -> List(Element)
banner = |state, score| match state {
	Running => []
	Paused => [banner_box("Paused", white_text, "Space to resume")]
	EndGame => {
		winner = if score.left > score.right "Left" else "Right"
		[banner_box("${winner} wins", green_text, "Space to play again")]
	}
}

# Percent sizes the banner against the window. Grow stretches each row across
# the banner, so the text centres and the hint wraps inside it.
banner_box : Str, Rgba, Str -> Element
banner_box = |title, color, hint| {
	row = |child| Box({ ..centred, width: Grow({ min: 0.0, max: 0.0 }) }, [child])
	Box(
		{ ..Ui.panel(CenterCenter, { x: 0.0, y: 0.0 }), width: Percent(0.3), direction: Col, gap: 8.0, pad: Ui.pad_all(16.0) },
		[row(Text({ ..Ui.label(title), size: 40.0, color })), row(Text(Ui.label(hint)))],
	)
}

# The engine adds the offset at the same corner of the window and the box, so
# a bottom or right corner needs a negative offset.
hints : List(Element)
hints = [
	Box(Ui.panel(LeftBottom, { x: 16.0, y: -16.0 }), [Text(Ui.label("W / S"))]),
	Box(Ui.panel(RightBottom, { x: -16.0, y: -16.0 }), [Text(Ui.label("Up / Down"))]),
]

hud : Model -> List(Element)
hud = |m| [scoreboard(m.state, m.score)].concat(banner(m.state, m.score)).concat(hints)

# endregion

ambient : Vocabulary.Light
ambient = Light.ambient({ r: 0.2, g: 0.2, b: 0.2 })

# The BRDF divides diffuse light by pi, so 5.03 (1.6 pi) lights a white surface facing it to 1.6.
sun : Vocabulary.Light
sun = Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })

# region: view
box : U32, U64, Vec3, Vec3, Rgb -> Vocabulary.Draw
box = |mesh, id, pos, scale, tint| { ..Draw.default, id, mesh, pos, scale, tint }

view : Model -> Vocabulary.Scene
view = |m| {
	c = m.cube
	nodes = [
		Light(ambient),
		Light(sun),
		Draw(box(c, 10, { x: 0.0, y: -0.1, z: 0.0 }, { x: 2.0 * half_width, y: 0.1, z: 2.0 * half_depth }, { r: 0.01, g: 0.013, b: 0.02 })),
		Draw(box(c, 11, { x: 0.0, y: 0.1, z: -half_depth - 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white)),
		Draw(box(c, 12, { x: 0.0, y: 0.1, z: half_depth + 0.15 }, { x: 2.0 * half_width, y: 0.3, z: 0.3 }, white)),
		Draw(box(c, 0, { x: -paddle_x, y: 0.2, z: m.left }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 0.073, g: 0.448, b: 1.0 })),
		Draw(box(c, 1, { x: paddle_x, y: 0.2, z: m.right }, { x: 2.0 * paddle_half_thick, y: 0.4, z: 2.0 * paddle_half_len }, { r: 1.0, g: 0.214, b: 0.073 })),
		Draw(box(c, m.ball.id, { x: m.ball.x, y: 0.2, z: m.ball.z }, { x: 2.0 * ball_half, y: 2.0 * ball_half, z: 2.0 * ball_half }, white)),
	]

	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 14.0, z: 7.0 }, { x: 0.0, y: 0.0, z: 0.0 }), nodes, ui: hud(m) }
}

# endregion

game_state : Model, Vocabulary.Input -> Model
game_state = |m, input| {
	if Key.pressed(input, Space) {
		match m.state {
			Paused => { ..m, state: Running }
			EndGame => reset(m)
			_ => { ..m, state: Paused }
		}
	} else if m.score.left >= max_score or m.score.right >= max_score {
		{ ..m, state: EndGame }
	} else {
		m
	}
}

reset : Model -> Model
reset = |m| {
	cleared = { ..m, state: Running, left: 0.0, right: 0.0, score: { left: 0, right: 0 } }
	serve(cleared, 1.0)
}

# region: serve
serve : Model, F32 -> Model
serve = |m, dir| {
	rng = next_rng(m.rng)
	serves = m.serves + 1
	ball = { id: ball_id_base + serves, x: 0.0, z: 0.0, vx: dir * serve_speed, vz: (unit(rng) - 0.5) * 6.0 }

	{ ..m, ball, serves, rng }
}

# endregion

end_game : Model -> Model
end_game = |m| {
	if m.score.left >= max_score or m.score.right >= max_score {
		m
	} else m
}

score_point : Model -> Model
score_point = |m| {
	if m.ball.x > half_width {
		serve({ ..m, score: { ..m.score, left: m.score.left + 1 } }, -1.0)
	} else if m.ball.x < -half_width {
		serve({ ..m, score: { ..m.score, right: m.score.right + 1 } }, 1.0)
	} else m
}

move_paddles : Model, Vocabulary.Input, F32 -> Model
move_paddles = |m, input, dt| {
	left = clamp(-paddle_limit, paddle_limit, m.left + Key.axis(input, W, S) * paddle_speed * dt)
	right = clamp(-paddle_limit, paddle_limit, m.right + Key.axis(input, Up, Down) * paddle_speed * dt)
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
expect launch(Config.empty) == { ..Launch.default, window: { ..Launch.default.window, title: "pong" } }
expect init(Config.empty).commands == []
expect loaded(init(Config.empty).model, "pong", [{ name: "cube", id: 9 }]).cube == Mesh.primitive(Cube)

# A fresh scene draws the floor, two walls, two paddles and the ball.
expect draw_count(view(init(Config.empty).model)) == 6

draw_count : Vocabulary.Scene -> U64
draw_count = |scene| List.count_if(
	scene.nodes,
	|node| match node {
		Draw(_) => Bool.True
		_ => Bool.False
	},
)

# clamp caps above the top and below the bottom.
expect clamp(1.0, 2.0, 2.1) == 2.0
expect clamp(1.0, 2.0, 0.5) == 1.0

# region: input-test
# Holding W for a long step drives the left paddle to its limit, the right stays put.
expect {
	stepped = step(init(Config.empty).model, { ..Input.empty, held: [Key.code(W)] }, QueryResults.empty, 10.0)
	m = stepped.model
	stepped.commands == [] and m.left == -paddle_limit and m.right == 0.0
}
# endregion

# A ball past the top wall moving outward bounces once, and a second call is a no-op.
expect {
	m = init(Config.empty).model
	going_out = { ..m, ball: { ..m.ball, z: wall_limit + 0.01, vz: 2.0 } }
	once = bounce_walls(going_out)
	twice = bounce_walls(once)
	once.ball.vz == -2.0 and twice.ball.vz == -2.0
}

# The same for the bottom wall, which needs the opposite sign on vz.
expect {
	m = init(Config.empty).model
	going_out = { ..m, ball: { ..m.ball, z: -wall_limit - 0.01, vz: -2.0 } }
	once = bounce_walls(going_out)
	twice = bounce_walls(once)
	once.ball.vz == 2.0 and twice.ball.vz == 2.0
}

# A ball reaching the right paddle is returned faster and angled by where it hit.
expect {
	m = init(Config.empty).model
	at_right = { ..m, ball: { ..m.ball, x: paddle_x - 0.2, z: 0.5, vx: 8.0, vz: 0.0 } }
	once = hit_paddles(at_right)
	twice = hit_paddles(once)
	once.ball.vx == -8.4 and once.ball.vz == 1.5 and twice.ball.vx == -8.4
}

# A ball past the right wall scores for the left and is served again with a new id.
expect {
	m = init(Config.empty).model
	past_right = { ..m, ball: { ..m.ball, x: half_width + 0.1 } }
	after = score_point(past_right)
	after.score.left == 1 and after.ball.x == 0.0 and after.ball.id == m.ball.id + 1
}

# The seed picks the serve angle, and the first serve id is one past the base.
expect {
	a = init(Config.empty).model
	b = init({ ..Config.empty, seed: 7 }).model
	a.ball.vz != b.ball.vz and a.ball.id == ball_id_base + 1
}

# The scoreboard shows the score, so scoring adds no draws.
expect {
	m = init(Config.empty).model
	scored = { ..m, score: { left: 3, right: 2 } }
	draw_count(view(scored)) == 6
}

# Space pauses a running game and resumes it without touching the score.
expect {
	m = init(Config.empty).model
	press = { ..Input.empty, pressed: [Key.code(Space)] }
	paused = game_state(m, press)
	resumed = game_state(paused, press)
	paused.state == Paused and resumed.state == Running and resumed.score == m.score
}

# A score of 7 ends the game, and the paddles and ball freeze there.
expect {
	m = init(Config.empty).model
	ended = { ..m, score: { left: max_score, right: 0 } }
	after = step(ended, { ..Input.empty, held: [Key.code(W)] }, QueryResults.empty, 1.0).model
	after.state == EndGame and after.left == ended.left and after.ball.x == ended.ball.x
}

# Space on an ended game starts a fresh one: score cleared, ball served again.
expect {
	m = init(Config.empty).model
	ended = { ..m, state: EndGame, score: { left: max_score, right: 0 } }
	after = game_state(ended, { ..Input.empty, pressed: [Key.code(Space)] })
	after.state == Running and after.score == { left: 0, right: 0 } and after.ball.x == 0.0 and after.ball.id == ended.ball.id + 1
}

shows : List(Element), Str, Rgba -> Bool
shows = |ui, str, color| ui.any(
	|e| match e {
		Text(t) => t.str == str and t.color == color
		Box(_, children) => shows(children, str, color)
	},
)

floats_at : List(Element), Ui.AttachPoint -> Bool
floats_at = |ui, point| ui.any(
	|e| match e {
		Box({ floating: Float({ attach, .. }), .. }, _) => attach == point
		_ => Bool.False
	},
)

# region: ui-test
# The scoreboard is a panel of a cell, a colon and a cell, and each cell holds
# one Text.
expect
	match scoreboard(Running, { left: 3, right: 0 }) {
		Box(_, [Box(_, [Text(left)]), Text(colon), Box(_, [Text(right)])]) => left.str == "3" and colon.str == ":" and right.str == "0"
		_ => Bool.False
	}

# endregion

expect floats_at([scoreboard(Running, { left: 0, right: 0 })], CenterTop)
expect floats_at(banner(Paused, { left: 0, right: 0 }), CenterCenter)
expect floats_at(hints, LeftBottom) and floats_at(hints, RightBottom)

expect {
	ui = [scoreboard(Running, { left: 3, right: 2 })]
	shows(ui, "3", white_text) and shows(ui, "2", white_text) and shows(ui, ":", white_text)
}

expect {
	ui = [scoreboard(EndGame, { left: 2, right: max_score })]
	shows(ui, max_score.to_str(), green_text) and shows(ui, "2", red_text)
}

expect banner(Running, { left: 0, right: 0 }) == []

expect {
	ui = banner(Paused, { left: 1, right: 0 })
	shows(ui, "Paused", white_text) and shows(ui, "Space to resume", white_text)
}

expect shows(banner(EndGame, { left: max_score, right: 2 }), "Left wins", green_text)
expect {
	ui = banner(EndGame, { left: 2, right: max_score })
	shows(ui, "Right wins", green_text) and shows(ui, "Space to play again", white_text)
}

expect shows(hints, "W / S", white_text) and shows(hints, "Up / Down", white_text)

expect {
	m = init(Config.empty).model
	running = view(m).ui
	paused = view({ ..m, state: Paused }).ui
	running.len() == 3 and shows(running, "W / S", white_text) and !shows(running, "Paused", white_text) and shows(paused, "Paused", white_text)
}
