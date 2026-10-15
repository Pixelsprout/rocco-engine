app [init, step, loaded, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-27-a3ce7f1", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", ui: "../../packages/ui/main.roc" }

import linalg.Quat
import linalg.Vec3
import pf.Vocabulary exposing [Command, Config, Contact, Draw, Input, Manifest, Rgb, Scene]
import pf.Key
import pf.Light
import World
import Grid
import Ball
import Rules
import View
import Theme
import Hud

Model : Rules.Model

init : Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = Rules.start(View.primitive_meshes, 1)
	{ model, commands: [Load({ pack: kula_pack, assets: View.assets }), load_theme(1)] }
}

# The kula pack holds what every Theme shares. It stays loaded for the whole game.
kula_pack : Str
kula_pack = "kula"

load_theme : U64 -> Command
load_theme = |level_number| {
	theme = Theme.of_level(level_number)
	Load({ pack: theme.pack, assets: theme.assets })
}

# The next level starts only when its Theme has loaded, so no level draws with the old Theme's ids.
loaded : Model, Str, Manifest -> Model
loaded = |model, pack, manifest| {
	current = Theme.of_level(model.level_number)
	next_theme = Theme.of_level(model.level_number + 1)
	if pack == kula_pack {
		{ ..model, meshes: View.kula_meshes(model.meshes, manifest) }
	} else if model.phase == Cleared and pack == next_theme.pack {
		next = Rules.next_level({ ..model, meshes: View.theme_meshes(model.meshes, manifest, next_theme.face, next_theme.sky) })
		{ ..next, unloads: [current.pack] }
	} else if model.phase != Cleared and pack == current.pack {
		{ ..model, meshes: View.theme_meshes(model.meshes, manifest, current.face, current.sky) }
	} else {
		model
	}
}

step : Model, Input, List(Contact), F32 -> { model : Model, commands : List(Command) }
step = |model, input, _contacts, dt| {
	stages = [Rules.count_down(dt), read_input(input), move_ball(input, dt), Rules.collect, Rules.exit, Rules.fall]
	after = stages.fold(model, |m, stage| stage(m))
	quit = if Key.pressed(input, Escape) {
		[Quit]
	} else {
		[]
	}
	load = if model.phase != Cleared and after.phase == Cleared {
		[load_theme(after.level_number + 1)]
	} else {
		[]
	}
	unloads = model.unloads.map(|pack| Unload(pack))
	{ model: { ..after, unloads: [] }, commands: quit.concat(load).concat(unloads) }
}

# Input is read before the ball moves. Ball.act ignores a key that cannot act on the current move.
read_input : Input -> (Model -> Model)
read_input = |input| |model| match (model.phase, action(input)) {
	(Playing, Ok(act)) => { ..model, ball: Ball.act(model.level.blocks, model.ball, act) }
	_ => model
}

move_ball : Input, F32 -> (Model -> Model)
move_ball = |input, dt| |model|
	if Key.held(input, Up) {
		{ ..model, ball: Ball.advance_up_held(model.level.blocks, model.ball, dt) }
	} else {
		{ ..model, ball: Ball.advance(model.ball, dt) }
	}

# Tank controls. Up rolls while held; the others act on press only. Space with Up
# held is a forward jump.
action : Input -> Try(Ball.Action, [NoAction])
action = |input|
	if Key.pressed(input, Space) {
		Ok(Jump({ up_held: Key.held(input, Up) }))
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
	theme = Theme.of_level(model.level_number)
	exits = model.level.items.keep_if(|entry| entry.item == Exit).map(|entry| below(entry.cell))
	exit_tint = if Rules.exit_open(model) {
		open_exit_tint
	} else {
		closed_exit_tint
	}
	camera = View.camera(model.ball)
	# Ids come before the near-plane filter, so a face keeps its id while others drop out.
	blocks = View.faces(model.level.blocks)
		.map_with_index(|face, i| { face, id: 1 + i.to_u64() })
		.keep_if(|entry| !View.cut_by_near_plane(entry.face, camera))
		.map(
			|entry| {
				tint = if exits.contains(entry.face.block) {
					exit_tint
				} else {
					face_tint
				}
				View.face_draw(entry.id, model.meshes.face, entry.face, tint)
			},
		)
	# Ids come before the collected filter too, so a key keeps its id.
	keys = model.level.items
		.keep_if(|entry| entry.item == Key)
		.map_with_index(|entry, i| { cell: entry.cell, id: key_ids + i.to_u64() })
		.keep_if(|key| !model.collected.contains(key.cell))
		.map(|key| cube(model.meshes, key.id, key.cell, 0.3, key_tint))
	ball_tint = if model.phase == Won {
		won_ball_tint
	} else {
		playing_ball_tint
	}
	ball = View.ball_draw(model.ball, model.meshes.ball, ball_tint)
	{ camera, draws: blocks.concat(keys).append(ball), colliders: [], lights: theme.lights, cursor: Free, sky: model.meshes.sky, ui: Hud.ui(model) }
}

# Face draw ids count up from 1, so the key ids start well past any level's faces.
key_ids : U64
key_ids = 100_000

closed_exit_tint : Rgb
closed_exit_tint = { r: 0.6, g: 0.15, b: 0.15 }

open_exit_tint : Rgb
open_exit_tint = { r: 1.0, g: 0.35, b: 0.3 }

# Each Theme's face texture carries its colour.
face_tint : Rgb
face_tint = { r: 1.0, g: 1.0, b: 1.0 }

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
cube = |meshes, id, cell, size, tint| { id, mesh: meshes.cube, pos: Grid.to_vec3(cell), scale: Vec3.scale(Vec3.one, size), rot: Quat.identity, scale_rot: Quat.identity, tint }

# The Model after init and both of its loads, as the first view sees it.
started : Model
started = {
	booted = init({ seed: 0, assets: ["ball", "haze_face", "sky/haze"] }).model
	loaded(loaded(booted, "kula", [{ name: "ball", id: 4 }]), "haze", [{ name: "haze_face", id: 5 }, { name: "sky/haze", id: 1 }])
}

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

expect init({ seed: 0, assets: [] }).commands == [Load({ pack: "kula", assets: ["ball"] }), Load({ pack: "haze", assets: ["haze_face", "sky/haze"] })]
expect init({ seed: 0, assets: [] }).model.meshes == { cube: 1, face: 0, ball: 0, sky: 0 }
expect started.meshes == { cube: 1, face: 5, ball: 4, sky: 1 }
expect view(started).sky == 1
expect started.ball == Ball.start(started.level.start)
expect started.level_number == 1 and started.phase == Playing

up_held : Input
up_held = { ..idle, held: [Key.code(Up)] }

expect step(started, up_held, [], 0.13).model.ball.motion == Rolling({ from: started.level.start, t: 0.5 })
expect step(started, { ..idle, pressed: [Key.code(Left)] }, [], 0.16).model.ball.turn == Turning({ from: started.level.start, t: 0.5, next: Stay })
expect step(started, { ..idle, held: [Key.code(Left)] }, [], 0.16).model.ball.turn == Steady

expect {
	model = [0.13, 0.13, 0.13, 0.13].fold(started, |m, dt| step(m, up_held, [], dt).model)
	model.ball.pose.cell == { x: 0, y: 1, z: 7 }
}
expect step(started, { ..idle, pressed: [Key.code(Escape)] }, [], 0.1).commands == [Quit]
expect step(started, idle, [], 0.1).commands == []

expect {
	draws = view(started).draws
	draws.len() == 49
}

expect {
	draws = view(started).draws
	exit_faces = draws.keep_if(|d| d.tint == closed_exit_tint)
	exit_faces.len() == 5 and exit_faces.all(|d| Vec3.length(d.pos) == 0.5)
}

expect {
	draws = view(started).draws
	keys = draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 1.0, z: 7.0 }, { x: 0.0, y: 2.0, z: 5.0 }] and keys.all(|d| d.scale.x == 0.3)
}

expect {
	model = started
	ball = view(model).draws.keep_if(|d| d.mesh == model.meshes.ball)
	ball.map(|d| d.pos) == [{ x: 0.0, y: 0.695, z: 9.0 }]
}

# In the climb at the level1 wall, the eye passes down through the old floor.
# Only as it passes does that face drop out, and the rest keep their ids.
expect {
	rest = view(started).draws
	at_wall = [0.13, 0.13, 0.13, 0.13].fold(started, |m, dt| step(m, up_held, [], dt).model)
	faces_at = |dt| {
		climbing = step(at_wall, up_held, [], dt).model
		view(climbing).draws.keep_if(|d| d.mesh == climbing.meshes.face)
	}
	passing = faces_at(0.152)
	faces_at(0.14).len() == 46 and passing.len() < 46 and passing.all(|d| rest.any(|r| r.id == d.id and r.pos == d.pos))
}

# Rolling from S over the first key collects it.
expect {
	model = [0.13, 0.13, 0.13, 0.13].fold(started, |m, dt| step(m, up_held, [], dt).model)
	model.keys_left == 1 and model.collected.contains({ x: 0, y: 1, z: 7 })
}

at_pose : Model, World.Pose -> Model
at_pose = |model, pose| { ..model, ball: Ball.start(pose) }

before_exit : World.Pose
before_exit = { cell: { x: 0, y: 1, z: 1 }, up: { x: 0, y: 1, z: 0 }, forward: { x: 0, y: 0, z: -1 } }

expect step(at_pose(started, before_exit), up_held, [], 0.1).model.phase == Playing

# In Won the ball ignores input, and Escape still quits.
expect {
	won = { ..started, phase: Won }
	after = step(won, up_held, [], 0.1)
	{ ..after.model.ball, bob: won.ball.bob } == won.ball and step(won, { ..idle, pressed: [Key.code(Escape)] }, [], 0.1).commands == [Quit]
}

# A jump off the side from S falls, then the level restarts.
expect {
	space = { ..idle, held: [Key.code(Up)], pressed: [Key.code(Space)] }
	facing_out = { ..at_pose(started, { ..started.level.start, forward: { x: -1, y: 0, z: 0 } }), keys_left: 1 }
	jumped = step(facing_out, space, [], 0.25).model
	still_falling = step(jumped, idle, [], 0.25).model
	landed = step(still_falling, idle, [], 0.5).model
	fell = match jumped.ball.motion {
		Falling({ from, offset, over, drop, seconds, .. }) => from == facing_out.ball.pose and offset == 0.0 and over == { ..facing_out.ball.pose, cell: { x: -2, y: 1, z: 9 } } and drop == Off(3) and seconds == 0.25
		_ => False
	}
	fell and still_falling.ball.pose == jumped.ball.pose and landed == started
}

expect {
	collected = [0.13, 0.13, 0.13, 0.13].fold(started, |m, dt| step(m, up_held, [], dt).model)
	keys = view(collected).draws.keep_if(|d| d.tint == key_tint)
	keys.map(|d| d.pos) == [{ x: 0.0, y: 2.0, z: 5.0 }] and keys.map(|d| d.id) == [key_ids + 1]
}

expect {
	draws = view({ ..started, keys_left: 0 }).draws
	draws.keep_if(|d| d.tint == open_exit_tint).len() == 5 and !draws.any(|d| d.tint == closed_exit_tint)
}

expect {
	won = { ..started, phase: Won }
	view(won).draws.keep_if(|d| d.mesh == won.meshes.ball).map(|d| d.tint) == [won_ball_tint]
}

space : Input
space = { ..idle, pressed: [Key.code(Space)] }

expect step(started, space, [], 0.27).model.ball.motion == JumpingInPlace({ t: 0.5 })

# Up and Space jump the level1 gap from the cell before it.
expect {
	before_gap = at_pose(started, { ..started.level.start, cell: { x: 0, y: 1, z: 4 } })
	jumped = step(before_gap, { ..space, held: [Key.code(Up)] }, [], 0.1).model
	jumped.ball.pose.cell == { x: 0, y: 1, z: 2 } and jumped.ball.motion == Jumping({ from: before_gap.ball.pose, offset: 0.0, t: 0.1 / 0.54 })
}

# A key in the roll's target cell is collected, though the jump starts from the cell behind it.
expect {
	on_layer1 = at_pose(started, { ..started.level.start, cell: { x: 0, y: 2, z: 6 } })
	rolling = step(on_layer1, up_held, [], 0.05).model
	jumped = step(rolling, space, [], 0.01).model
	jumped.collected.contains({ x: 0, y: 2, z: 5 }) and jumped.keys_left == 1 and match jumped.ball.motion {
		Falling({ from, .. }) => from.cell == { x: 0, y: 2, z: 6 }
		_ => False
	}
}

# The jump from the raised block lands on the floor one cell below its target.
expect {
	on_layer1 = at_pose(started, { ..started.level.start, cell: { x: 0, y: 2, z: 6 } })
	rolling = step(on_layer1, up_held, [], 0.05).model
	jumped = step(rolling, space, [], 0.01).model
	landed = step(jumped, idle, [], 1.0).model
	landed.ball.motion == Still and landed.ball.pose.cell == { x: 0, y: 1, z: 4 }
}

# Held Up rolls on through the cell with no step at rest.
expect {
	model = [0.13, 0.13].fold(started, |m, dt| step(m, up_held, [], dt).model)
	model.ball.pose.cell == { x: 0, y: 1, z: 7 } and model.ball.motion != Still
}

# Held Up runs the ball to the level1 gap. Space on the approach to the edge clears it.
expect {
	two_before = at_pose(started, { ..started.level.start, cell: { x: 0, y: 1, z: 5 } })
	at_edge = step(two_before, up_held, [], 0.26).model
	jumped = step(at_edge, { ..space, held: [Key.code(Up)] }, [], 0.06).model
	jumped.ball.pose.cell == { x: 0, y: 1, z: 2 } and match jumped.ball.motion {
		Jumping({ from, .. }) => from.cell == { x: 0, y: 1, z: 4 }
		_ => False
	}
}

expect {
	open = { ..at_pose(started, before_exit), keys_left: 0 }
	finished = step(open, up_held, [], 0.1)
	switched = loaded(finished.model, "inca", [{ name: "inca_face", id: 7 }, { name: "sky/inca", id: 2 }])
	after = step(switched, idle, [], 0.1)
	finished.commands == [Load({ pack: "inca", assets: ["inca_face", "sky/inca"] })]
		and finished.model.phase == Cleared
			and switched.meshes == { cube: 1, face: 7, ball: 4, sky: 2 }
				and switched.level_number == 2
					and switched.phase == Starting(Rules.start_pause)
						and after.commands == [Unload("haze")]
							and step(after.model, idle, [], 0.1).commands == []
}

# A Cleared level sends its Load once.
expect {
	open = { ..at_pose(started, before_exit), keys_left: 0 }
	finished = step(open, up_held, [], 0.1).model
	step(finished, idle, [], 0.1).commands == []
}

# A loaded for a pack Kula did not ask for changes nothing.
expect loaded(started, "inca", [{ name: "inca_face", id: 7 }]) == started

# During the pause the ball ignores input. After it, the level plays.
expect {
	starting = { ..on_level(2), phase: Starting(1.0) }
	paused = step(starting, up_held, [], 0.5).model
	playing = step(paused, idle, [], 0.6).model
	paused.ball.motion == Still and playing.phase == Playing and step(playing, up_held, [], 0.1).model.ball.motion != Still
}

expect view(on_level(2)).lights == Theme.of_level(2).lights

Move : [Roll, Left, Right, Leap]

# Each move starts with a short step that presses its keys. A long idle step then finishes it.
play : Model, List(Move) -> Model
play = |model, moves| moves.fold(
	model,
	|m, move| {
		keys = match move {
			Roll => { ..idle, held: [Key.code(Up)] }
			Left => { ..idle, pressed: [Key.code(Left)] }
			Right => { ..idle, pressed: [Key.code(Right)] }
			Leap => { ..idle, held: [Key.code(Up)], pressed: [Key.code(Space)] }
		}
		step(step(m, keys, [], 0.01).model, idle, [], 1.0).model
	},
)

on_level : U64 -> Model
on_level = |number| Rules.start(started.meshes, number)

expect {
	played = play(on_level(2), [Roll, Roll, Right, Roll, Roll, Roll, Roll, Left, Leap, Roll, Roll, Roll])
	played.keys_left == 0 and played.phase == Cleared
}

expect {
	played = play(on_level(3), [Roll, Roll, Roll, Roll, Roll, Roll, Roll, Roll, Roll, Leap, Roll, Roll])
	played.keys_left == 0 and played.phase == Won
}

expect {
	open = { ..at_pose(on_level(3), before_exit), keys_left: 0 }
	finished = step(open, up_held, [], 0.1)
	finished.model.phase == Won and finished.commands == []
}
