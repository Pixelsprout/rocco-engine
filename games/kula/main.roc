app [init, step, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../../platform/main.roc", linalg: "../../packages/linalg/main.roc" }

import linalg.Quat
import linalg.Vec3
import pf.Vocabulary exposing [Command, Config, Contact, Draw, Input, Rgb, Scene]
import pf.Key
import World
import Grid
import Level
import Ball
import View

Model : { level : World.Level, ball : Ball.Ball, meshes : World.Meshes }

init : Config -> Model
init = |config| {
	level = parse_or_crash(Level.level1_text)
	{ level, ball: Ball.start(level.start), meshes: { cube: mesh_id(config, "primitive/cube"), sphere: mesh_id(config, "primitive/sphere"), plane: mesh_id(config, "primitive/plane") } }
}

parse_or_crash : Str -> World.Level
parse_or_crash = |text| match Level.parse(text) {
	Ok(level) => level
	Err(err) => crash "The level does not parse: ${Str.inspect(err)}"
}

# A name the engine did not load gets 0, the fallback mesh.
mesh_id : Config, Str -> U32
mesh_id = |config, name| match List.find_first(config.meshes, |m| m.name == name) {
	Ok(m) => m.id
	Err(NotFound) => 0
}

step : Model, Input, List(Contact), F32 -> { model : Model, commands : List(Command) }
step = |model, input, _contacts, dt| {
	stages = [read_input(input), move_ball(dt)]
	commands = if Key.pressed(input, Escape) { [Quit] } else { [] }
	{ model: stages.fold(model, |m, stage| stage(m)), commands }
}

# Input is read before the ball moves, so a key acts only on a step that starts Still.
read_input : Input -> (Model -> Model)
read_input = |input| |model| match action(input) {
	Ok(act) => { ..model, ball: Ball.act(model.level.blocks, model.ball, act) }
	Err(NoAction) => model
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
	blocks = View.faces(model.level.blocks).map_with_index(|face, i| {
		tint = if exits.contains(face.block) { exit_tint } else { block_tint }
		View.face_draw(1 + i.to_u64(), model.meshes.plane, face, tint)
	})
	keys = model.level.items.keep_if(|entry| entry.item == Key).map_with_index(|entry, i| cube(model.meshes, key_ids + i.to_u64(), entry.cell, 0.3, key_tint))
	ball = View.ball_draw(model.ball, model.meshes.sphere, ball_tint)
	{ camera: View.camera(model.ball), draws: blocks.concat(keys).append(ball), colliders: [], cursor: Free }
}

# Face draw ids count up from 1, so the key ids start well past any level's faces.
key_ids : U64
key_ids = 100_000

block_tint : Rgb
block_tint = { r: 0.45, g: 0.5, b: 0.6 }

exit_tint : Rgb
exit_tint = { r: 0.6, g: 0.15, b: 0.15 }

key_tint : Rgb
key_tint = { r: 1.0, g: 0.787, b: 0.033 }

ball_tint : Rgb
ball_tint = { r: 0.9, g: 0.9, b: 0.95 }

below : World.Cell -> World.Cell
below = |cell| { ..cell, y: cell.y - 1 }

cube : World.Meshes, U64, World.Cell, F32, Rgb -> Draw
cube = |meshes, id, cell, size, tint| { id, mesh: meshes.cube, pos: Grid.to_vec3(cell), scale: Vec3.scale(Vec3.one, size), rot: Quat.identity, tint }

test_config : Config
test_config = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }, { name: "primitive/plane", id: 3 }] }

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

expect init(test_config).meshes == { cube: 1, sphere: 2, plane: 3 }
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
	exit_faces = draws.keep_if(|d| d.tint == exit_tint)
	exit_faces.len() == 5 and exit_faces.all(|d| Vec3.length(d.pos) == 0.5)
}

expect {
	draws = view(init(test_config)).draws
	keys = draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 1.0, z: 7.0 }, { x: 0.0, y: 2.0, z: 5.0 }] and keys.all(|d| d.scale.x == 0.3)
}

expect {
	model = init(test_config)
	ball = view(model).draws.keep_if(|d| d.mesh == model.meshes.sphere)
	ball.map(|d| d.pos) == [{ x: 0.0, y: 0.695, z: 9.0 }]
}
