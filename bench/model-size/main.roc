app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc" }

import shared.Bench
import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Draw, Input, Manifest, Scene, Vec3]
import pf.Light
import pf.QueryResults
import pf.Launch
import "positions.golden" as golden_positions : Str
import "model.golden" as golden_model : Str

# The idiomatic Model size bench game. step moves N entities with ordinary Roc
# list code. view always returns draw_count Draws, so the render cost stays
# fixed while N grows.
Entity : { id : U64, pos : Vec3, vel : Vec3 }

Model : { cube : U32, rng : U64, entities : List(Entity) }

draw_count = 100 # U64

half_extent = 20.0 # F32

max_speed = 4.0 # F32

# high_dpi off, so the numbers do not depend on the display.
launch : Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, high_dpi: False } }

# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
# give a benchmark at the wrong size.
init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The model-size bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, dt| { model: update(m, dt), commands: [] }

update : Model, F32 -> Model
update = |m, dt| m |> move(dt) |> bounce

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
			pos: { x: Bench.spread(r1, half_extent), y: 0.0, z: Bench.spread(r2, half_extent) },
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

# Draw id i shows entity i * N / draw_count, so N below draw_count repeats
# entities under fresh ids.
view : Model -> Scene
view = |m| {
	n = m.entities.len()
	draws = List.with_capacity(draw_count) |> add_draws(m, n, 0)
	{
		camera: Cam.look_at({ x: 0.0, y: 40.0, z: 30.0 }, { x: 0.0, y: 0.0, z: 0.0 }),
		draws,
		colliders: [],
		lights,
		cursor: Free,
		sky: 0,
		ui: [],
		queries: [],
	}
}

add_draws : List(Draw), Model, U64, U64 -> List(Draw)
add_draws = |draws, m, n, i| {
	if i >= draw_count {
		draws
	} else {
		next = match m.entities.get(i * n // draw_count) {
			Ok(e) => draws.append(cube_draw(m.cube, i, e.pos))
			Err(_) => draws
		}
		add_draws(next, m, n, i + 1)
	}
}

cube_draw : U32, U64, Vec3 -> Draw
cube_draw = |mesh, id, pos| { id, mesh, pos, scale: { x: 0.5, y: 0.5, z: 0.5 }, rot: Quat.identity, scale_rot: Quat.identity, tint: { r: 0.8, g: 0.8, b: 0.8 } }

lights : List(Vocabulary.Light)
lights = [
	Light.ambient({ r: 0.2, g: 0.2, b: 0.2 }),
	Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 }),
]

expect launch(Bench.no_args).window.high_dpi == False
expect init(Bench.with_n(64)).model.entities.len() == 64
expect init(Bench.with_n(64)).commands == []

# The Seed decides the entities, so one Seed always gives the same run.
expect init(Bench.with_n(8)).model == init(Bench.with_n(8)).model
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

expect Bench.counts_up(init(Bench.with_n(32)).model.entities.map(|e| e.id))

expect {
	m = spawn(3, 16)
	m.entities.all(|e| e.pos.x >= -half_extent and e.pos.x < half_extent and e.vel.z >= -max_speed and e.vel.z < max_speed)
}

expect {
	e = { id: 0, pos: { x: 1.0, y: 0.0, z: 2.0 }, vel: { x: 2.0, y: 0.0, z: -4.0 } }
	moved = move({ cube: 1, rng: 0, entities: [e] }, 0.5)
	moved.entities == [{ ..e, pos: { x: 2.0, y: 0.0, z: 0.0 } }]
}

expect {
	out = { id: 0, pos: { x: half_extent + 1.0, y: 0.0, z: -half_extent - 1.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	once = bounce({ cube: 1, rng: 0, entities: [out] })
	twice = bounce(once)
	once.entities.map(|e| e.vel) == [{ x: -2.0, y: 0.0, z: 3.0 }] and twice == once
}

expect {
	inside = { id: 0, pos: { x: 0.0, y: 0.0, z: 0.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	bounce({ cube: 1, rng: 0, entities: [inside] }).entities == [inside]
}

expect {
	m = init(Bench.with_n(64)).model
	after = step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0).model
	after.entities.len() == 64 and after != m
}

# view gives draw_count Draws with distinct ids at every N.
expect {
	small = view(init(Bench.with_n(64)).model).draws
	large = view(init(Bench.with_n(1000)).model).draws
	small.len() == draw_count and large.len() == draw_count and Bench.counts_up(small.map(|d| d.id)) and Bench.counts_up(large.map(|d| d.id))
}

expect view(init(Bench.with_n(1000)).model).draws.first().map_ok(|d| d.mesh) == Ok(Mesh.primitive(Cube))

# bench/model-size-twin checks its positions against the same file, so the
# twin and this game agree for one Seed and N after the same steps.
run_steps : Model, U64 -> Model
run_steps = |m, count| if count == 0 m else run_steps(update(m, 1.0 / 120.0), count - 1)

positions_text : List(Draw) -> Str
positions_text = |draws| Str.join_with(draws.map(|d| "${d.pos.x.to_bits().to_str()} ${d.pos.z.to_bits().to_str()}\n"), "")

expect {
	m = run_steps(init({ ..Bench.with_n(100), seed: 7 }).model, 600)
	positions_text(view(m).draws) == golden_positions
}

# bench/model-size-tuned checks its Model against the same file, so both
# versions give the same Model for one Seed and N after the same steps.
f32_text : F32 -> Str
f32_text = |f| f.to_bits().to_str()

model_text : Model -> Str
model_text = |m| {
	entity_lines = m.entities.map(|e| "${e.id.to_str()} ${f32_text(e.pos.x)} ${f32_text(e.pos.y)} ${f32_text(e.pos.z)} ${f32_text(e.vel.x)} ${f32_text(e.vel.y)} ${f32_text(e.vel.z)}\n")
	Str.join_with(List.concat(["${m.cube.to_str()} ${m.rng.to_str()}\n"], entity_lines), "")
}

expect model_text(run_steps(init({ ..Bench.with_n(100), seed: 7 }).model, 600)) == golden_model
