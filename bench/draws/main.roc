app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc" }

import shared.Bench
import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Draw, Input, Manifest, Scene, Vec3]
import pf.Light
import pf.QueryResults
import pf.Launch
import pf.Pose

# The Draws bench game. view returns one primitive cube Draw per entity, lit by
# one Sun, so the Draw count is N and the rest of the Scene stays fixed.
Entity : { id : U64, pos : Vec3, vel : Vec3 }

Model : { cube : U32, rng : U64, entities : List(Entity) }

# The cubes stay inside a fixed square at every N, so the shadow box does not
# change with N.
half_extent = 20.0 # F32

max_speed = 4.0 # F32

cube_half = 0.25 # F32

# high_dpi off, so the numbers do not depend on the display. draws is N, so
# the pairing map and the uniform buffer match the workload.
launch : Config -> Vocabulary.Launch
launch = |config| {
	..Launch.default,
	window: { ..Launch.default.window, high_dpi: False },
	capacity: { ..Launch.default.capacity, draws: Bench.draws_for_n(config.args, Launch.default.capacity.draws) },
}

# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
# give a benchmark at the wrong size.
init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The draws bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, dt| { model: m |> move(dt) |> bounce, commands: [] }

spawn : U64, U64 -> Model
spawn = |seed, n| spawn_help({ cube: Mesh.primitive(Cube), rng: seed, entities: List.with_capacity(n) }, n)

spawn_help : Model, U64 -> Model
spawn_help = |m, n| {
	if m.entities.len() >= n {
		m
	} else {
		r1 = Bench.next_rng(m.rng)
		r2 = Bench.next_rng(r1)
		r3 = Bench.next_rng(r2)
		r4 = Bench.next_rng(r3)
		entity = {
			id: m.entities.len(),
			pos: { x: Bench.spread(r1, half_extent), y: cube_half, z: Bench.spread(r2, half_extent) },
			vel: { x: Bench.spread(r3, max_speed), y: 0.0, z: Bench.spread(r4, max_speed) },
		}
		spawn_help({ ..m, rng: r4, entities: m.entities.append(entity) }, n)
	}
}

move : Model, F32 -> Model
move = |m, dt| {
	moved = m.entities.map(|e| { ..e, pos: { x: e.pos.x + e.vel.x * dt, y: e.pos.y, z: e.pos.z + e.vel.z * dt } })
	{ ..m, entities: moved }
}

bounce : Model -> Model
bounce = |m| { ..m, entities: m.entities.map(bounce_entity) }

bounce_entity : Entity -> Entity
bounce_entity = |e| {
	vx = turn_back(e.pos.x, e.vel.x)
	vz = turn_back(e.pos.z, e.vel.z)
	{ ..e, vel: { ..e.vel, x: vx, z: vz } }
}

turn_back : F32, F32 -> F32
turn_back = |pos, vel| {
	if pos > half_extent and vel > 0.0 or pos < -half_extent and vel < 0.0 {
		-vel
	} else {
		vel
	}
}

# The entity id is the Draw id, so the Pairing finds each cube in the last Scene.
# The Sun, then one Draw per entity, in one list.
view : Model -> Scene
view = |m| {
	camera: Cam.look_at({ x: 0.0, y: 40.0, z: 30.0 }, { x: 0.0, y: 0.0, z: 0.0 }),
	nodes: List.fold(m.entities, List.with_capacity(m.entities.len() + 1).append(sun), |nodes, e| nodes.append(Draw(cube_draw(m.cube, e)))),
	cursor: Free,
	sky: 0,
	clear: { r: 0.0, g: 0.0, b: 0.0 },
	ui: [],
	queries: [],
}

cube_draw : U32, Entity -> Draw
cube_draw = |mesh, e| { id: e.id, mesh, pos: e.pos, scale: { x: cube_half, y: cube_half, z: cube_half }, rot: Quat.identity, scale_rot: Quat.identity, tint: { r: 0.8, g: 0.8, b: 0.8 }, pose: Pose.still(0, 0.0) }

sun : Vocabulary.Node
sun = Light(Light.sun({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 }))

draws_of : Scene -> List(Draw)
draws_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Draw(d) => Ok(d)
		_ => Err(NotADraw)
	},
)

expect launch(Bench.no_args).window.high_dpi == False
expect launch(Bench.with_n(20000)).capacity.draws == 20000
expect launch(Bench.no_args).capacity == Launch.default.capacity
expect init(Bench.with_n(64)).model.entities.len() == 64
expect init(Bench.with_n(64)).commands == []

# The Seed decides the cubes, so one Seed always gives the same run.
expect init(Bench.with_n(8)).model == init(Bench.with_n(8)).model
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

expect {
	m = spawn(3, 16)
	m.entities.all(|e| e.pos.x >= -half_extent and e.pos.x < half_extent and e.pos.z >= -half_extent and e.pos.z < half_extent and e.vel.x >= -max_speed and e.vel.x < max_speed)
}

expect {
	e = { id: 0, pos: { x: 1.0, y: cube_half, z: 2.0 }, vel: { x: 2.0, y: 0.0, z: -4.0 } }
	moved = move({ cube: 1, rng: 0, entities: [e] }, 0.5)
	moved.entities == [{ ..e, pos: { x: 2.0, y: cube_half, z: 0.0 } }]
}

expect {
	out = { id: 0, pos: { x: half_extent + 1.0, y: cube_half, z: -half_extent - 1.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	once = bounce({ cube: 1, rng: 0, entities: [out] })
	twice = bounce(once)
	once.entities.map(|e| e.vel) == [{ x: -2.0, y: 0.0, z: 3.0 }] and twice == once
}

expect {
	inside = { id: 0, pos: { x: 0.0, y: cube_half, z: 0.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	bounce({ cube: 1, rng: 0, entities: [inside] }).entities == [inside]
}

expect {
	m = init(Bench.with_n(64)).model
	after = step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0).model
	after.entities.len() == 64 and after != m
}

expect {
	small = draws_of(view(init(Bench.with_n(64)).model))
	large = draws_of(view(init(Bench.with_n(5000)).model))
	small.len() == 64 and large.len() == 5000 and Bench.counts_up(large.map(|d| d.id))
}

expect draws_of(view(init(Bench.with_n(16)).model)).all(|d| d.mesh == Mesh.primitive(Cube))

# Only the Draws change with N: one Sun with shadows on, no Colliders, UI or Queries.
expect {
	small = view(init(Bench.with_n(64)).model)
	large = view(init(Bench.with_n(1024)).model)
	small.nodes.first() == Ok(Light(Light.sun({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })))
		and small.nodes.len() == 65 and large.nodes.len() == 1025 and small.ui == [] and small.queries == []
}

expect [sun] == [Light(Directional({ dir: { x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, color: { r: 5.03, g: 5.03, b: 5.03 }, shadow: True }))]
