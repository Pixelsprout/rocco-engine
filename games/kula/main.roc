app [init, step, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../../platform/main.roc", linalg: "../../packages/linalg/main.roc" }

import linalg.Quat
import linalg.Vec3
import pf.Vocabulary exposing [Command, Config, Contact, Draw, Input, Rgb, Scene]
import pf.Key
import World
import Level

Model : World.Model

init : Config -> Model
init = |config| {
	level = parse_or_crash(Level.level1_text)
	{ level, ball: level.start, meshes: { cube: mesh_id(config, "primitive/cube"), sphere: mesh_id(config, "primitive/sphere") } }
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
step = |model, input, _contacts, _dt| {
	commands = if Key.pressed(input, Escape) { [Quit] } else { [] }
	{ model, commands }
}

view : Model -> Scene
view = |model| {
	exits = model.level.items.keep_if(|entry| entry.item == Exit).map(|entry| below(entry.cell))
	blocks = model.level.blocks.to_list().map_with_index(|block, i| {
		tint = if exits.contains(block) { exit_tint } else { block_tint }
		cube(model.meshes, 1 + i.to_u64(), block, 1.0, tint)
	})
	keys = model.level.items.keep_if(|entry| entry.item == Key).map_with_index(|entry, i| cube(model.meshes, key_ids + i.to_u64(), entry.cell, 0.3, key_tint))
	ball = { id: 0, mesh: model.meshes.sphere, pos: to_vec3(model.ball.cell), scale: Vec3.one, rot: Quat.identity, tint: ball_tint }
	{ camera, draws: blocks.concat(keys).append(ball), colliders: [], cursor: Free }
}

# Block draw ids count up from 1, so the key ids start well past any level's blocks.
key_ids : U64
key_ids = 100_000

camera : Vocabulary.Camera
camera = { eye: { x: 7.0, y: 8.0, z: 11.0 }, target: { x: 0.0, y: 0.5, z: 4.5 }, up: { x: 0.0, y: 1.0, z: 0.0 }, fov_y: 1.047 }

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

to_vec3 : World.Cell -> Vocabulary.Vec3
to_vec3 = |cell| { x: cell.x.to_f32(), y: cell.y.to_f32(), z: cell.z.to_f32() }

cube : World.Meshes, U64, World.Cell, F32, Rgb -> Draw
cube = |meshes, id, cell, size, tint| { id, mesh: meshes.cube, pos: to_vec3(cell), scale: Vec3.scale(Vec3.one, size), rot: Quat.identity, tint }

test_config : Config
test_config = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }] }

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

expect init(test_config).meshes == { cube: 1, sphere: 2 }
expect init(test_config).ball == init(test_config).level.start
expect step(init(test_config), { ..idle, pressed: [Key.code(Escape)] }, [], 0.1).commands == [Quit]
expect step(init(test_config), idle, [], 0.1).commands == []

expect {
	draws = view(init(test_config)).draws
	draws.len() == 14
}

expect {
	draws = view(init(test_config)).draws
	draws.keep_if(|d| d.tint == exit_tint).map(|d| d.pos) == [{ x: 0.0, y: 0.0, z: 0.0 }]
}

expect {
	draws = view(init(test_config)).draws
	keys = draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 1.0, z: 7.0 }, { x: 0.0, y: 2.0, z: 5.0 }] and keys.all(|d| d.scale.x == 0.3)
}

expect {
	model = init(test_config)
	ball = view(model).draws.keep_if(|d| d.mesh == model.meshes.sphere)
	ball.map(|d| d.pos) == [{ x: 0.0, y: 1.0, z: 9.0 }]
}
