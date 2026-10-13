app [init, step, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../../platform/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc" }

import linalg.Quat
import linalg.Vec3
import pf.Vocabulary exposing [Command, Config, Contact, Draw, Input, Rgb, Scene]
import pf.Key
import World
import Grid
import Ball
import Rules
import View

Model : Rules.Model

init : Config -> Model
init = |config| Rules.start(View.meshes(config))

step : Model, Input, List(Contact), F32 -> { model : Model, commands : List(Command) }
step = |model, input, _contacts, dt| {
	stages = [read_input(input), move_ball(dt), Rules.collect, Rules.exit, Rules.fall]
	commands = if Key.pressed(input, Escape) { [Quit] } else { [] }
	{ model: stages.fold(model, |m, stage| stage(m)), commands }
}

# Input is read before the ball moves, so a key acts only on a step that starts Still.
read_input : Input -> (Model -> Model)
read_input = |input| |model| match (model.phase, action(input)) {
	(Playing, Ok(act)) => { ..model, ball: Ball.act(model.level.blocks, model.ball, act) }
	_ => model
}

move_ball : F32 -> (Model -> Model)
move_ball = |dt| |model| { ..model, ball: Ball.advance(model.ball, dt) }

# Tank controls. Up rolls while held; the others act on press only.
action : Input -> Try(Ball.Action, [NoAction])
action = |input|
	if Key.pressed(input, Space) {
		Ok(Jump)
	} else if Key.pressed(input, Left) {
		Ok(TurnLeft)
	} else if Key.pressed(input, Right) {
		Ok(TurnRight)
	} else if Key.held(input, Up) {
		Ok(Roll)
	} else {
		Err(NoAction)
	}

view : Model -> Scene
view = |model| {
	exits = model.level.items.keep_if(|entry| entry.item == Exit).map(|entry| below(entry.cell))
	exit_tint = if Rules.exit_open(model) { open_exit_tint } else { closed_exit_tint }
	camera = View.camera(model.ball)
	# Ids come before the near-eye filter, so a face keeps its id while others drop out.
	blocks = View.faces(model.level.blocks)
		.map_with_index(|face, i| { face, id: 1 + i.to_u64() })
		.keep_if(|entry| !View.near_eye(entry.face, camera.eye))
		.map(|entry| {
			tint = if exits.contains(entry.face.block) { exit_tint } else { block_tint }
			View.face_draw(entry.id, model.meshes.face, entry.face, tint)
		})
	# Ids come before the collected filter too, so a key keeps its id.
	keys = model.level.items
		.keep_if(|entry| entry.item == Key)
		.map_with_index(|entry, i| { cell: entry.cell, id: key_ids + i.to_u64() })
		.keep_if(|key| !model.collected.contains(key.cell))
		.map(|key| cube(model.meshes, key.id, key.cell, 0.3, key_tint))
	ball_tint = match model.phase {
		Playing => playing_ball_tint
		Won => won_ball_tint
	}
	ball = View.ball_draw(model.ball, model.meshes.ball, ball_tint)
	{ camera, draws: blocks.concat(keys).append(ball), colliders: [], cursor: Free }
}

# Face draw ids count up from 1, so the key ids start well past any level's faces.
key_ids : U64
key_ids = 100_000

block_tint : Rgb
block_tint = { r: 0.45, g: 0.5, b: 0.6 }

closed_exit_tint : Rgb
closed_exit_tint = { r: 0.6, g: 0.15, b: 0.15 }

open_exit_tint : Rgb
open_exit_tint = { r: 1.0, g: 0.35, b: 0.3 }

key_tint : Rgb
key_tint = { r: 1.0, g: 0.787, b: 0.033 }

# ball.glb carries its own colours.
playing_ball_tint : Rgb
playing_ball_tint = { r: 1.0, g: 1.0, b: 1.0 }

won_ball_tint : Rgb
won_ball_tint = { r: 1.0, g: 0.85, b: 0.2 }

below : World.Cell -> World.Cell
below = |cell| { ..cell, y: cell.y - 1 }

cube : World.Meshes, U64, World.Cell, F32, Rgb -> Draw
cube = |meshes, id, cell, size, tint| { id, mesh: meshes.cube, pos: Grid.to_vec3(cell), scale: Vec3.scale(Vec3.one, size), rot: Quat.identity, tint }

test_config : Config
test_config = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }, { name: "primitive/plane", id: 3 }, { name: "ball", id: 4 }, { name: "face", id: 5 }] }

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

expect init(test_config).meshes == { cube: 1, face: 5, ball: 4 }
expect init(test_config).ball == Ball.start(init(test_config).level.start)

up_held : Input
up_held = { ..idle, held: [Key.code(Up)] }

expect step(init(test_config), up_held, [], 0.13).model.ball.motion == Rolling({ from: init(test_config).level.start, t: 0.5 })
expect step(init(test_config), { ..idle, pressed: [Key.code(Left)] }, [], 0.16).model.ball.motion == Turning({ from: init(test_config).level.start, t: 0.5 })
expect step(init(test_config), { ..idle, held: [Key.code(Left)] }, [], 0.16).model.ball.motion == Still

expect {
	model = [0.13, 0.13, 0.13, 0.13].fold(init(test_config), |m, dt| step(m, up_held, [], dt).model)
	model.ball.pose.cell == { x: 0, y: 1, z: 7 }
}
expect step(init(test_config), { ..idle, pressed: [Key.code(Escape)] }, [], 0.1).commands == [Quit]
expect step(init(test_config), idle, [], 0.1).commands == []

expect {
	draws = view(init(test_config)).draws
	draws.len() == 49
}

expect {
	draws = view(init(test_config)).draws
	exit_faces = draws.keep_if(|d| d.tint == closed_exit_tint)
	exit_faces.len() == 5 and exit_faces.all(|d| Vec3.length(d.pos) == 0.5)
}

expect {
	draws = view(init(test_config)).draws
	keys = draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 1.0, z: 7.0 }, { x: 0.0, y: 2.0, z: 5.0 }] and keys.all(|d| d.scale.x == 0.3)
}

expect {
	model = init(test_config)
	ball = view(model).draws.keep_if(|d| d.mesh == model.meshes.ball)
	ball.map(|d| d.pos) == [{ x: 0.0, y: 0.695, z: 9.0 }]
}

# Halfway through the climb at the level1 wall, the eye is near the old floor.
# Faces near it drop out, and the rest keep the ids they have at rest.
expect {
	rest = view(init(test_config)).draws
	at_wall = [0.13, 0.13, 0.13, 0.13].fold(init(test_config), |m, dt| step(m, up_held, [], dt).model)
	mid_climb = step(at_wall, up_held, [], 0.14).model
	faces = view(mid_climb).draws.keep_if(|d| d.mesh == mid_climb.meshes.face)
	faces.len() < 46 and faces.all(|d| rest.any(|r| r.id == d.id and r.pos == d.pos))
}

# Rolling from S over the first key collects it.
expect {
	model = [0.13, 0.13, 0.13, 0.13].fold(init(test_config), |m, dt| step(m, up_held, [], dt).model)
	model.keys_left == 1 and model.collected.contains({ x: 0, y: 1, z: 7 })
}

at_pose : Model, World.Pose -> Model
at_pose = |model, pose| { ..model, ball: Ball.start(pose) }

before_exit : World.Pose
before_exit = { cell: { x: 0, y: 1, z: 1 }, up: { x: 0, y: 1, z: 0 }, forward: { x: 0, y: 0, z: -1 } }

expect step(at_pose(init(test_config), before_exit), up_held, [], 0.1).model.phase == Playing

expect {
	open = { ..at_pose(init(test_config), before_exit), keys_left: 0 }
	step(open, up_held, [], 0.1).model.phase == Won
}

# In Won the ball ignores input, and Escape still quits.
expect {
	won = { ..init(test_config), phase: Won }
	after = step(won, up_held, [], 0.1)
	after.model.ball == won.ball and step(won, { ..idle, pressed: [Key.code(Escape)] }, [], 0.1).commands == [Quit]
}

# A jump off the side from S falls, then the level restarts.
expect {
	space = { ..idle, pressed: [Key.code(Space)] }
	facing_out = { ..at_pose(init(test_config), { ..init(test_config).level.start, forward: { x: -1, y: 0, z: 0 } }), keys_left: 1 }
	jumped = step(facing_out, space, [], 0.25).model
	landed = step(jumped, idle, [], 0.25).model
	jumped.ball.motion == Falling({ from: facing_out.ball.pose, t: 0.5 }) and landed == init(test_config)
}

expect {
	collected = [0.13, 0.13, 0.13, 0.13].fold(init(test_config), |m, dt| step(m, up_held, [], dt).model)
	keys = view(collected).draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 2.0, z: 5.0 }] and keys.map(|d| d.id) == [key_ids + 1]
}

expect {
	draws = view({ ..init(test_config), keys_left: 0 }).draws
	draws.keep_if(|d| d.tint == open_exit_tint).len() == 5 and !draws.any(|d| d.tint == closed_exit_tint)
}

expect {
	won = { ..init(test_config), phase: Won }
	view(won).draws.keep_if(|d| d.mesh == won.meshes.ball).map(|d| d.tint) == [won_ball_tint]
}
