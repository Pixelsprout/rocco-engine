app [init, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Draw, Input, Manifest, Scene, Vec3]
import pf.Light
import pf.QueryResults

# The lower limit of the seam. It holds the same Model and returns the same
# Scene as bench/model-size, but step returns the Model unchanged. Keep spawn
# and view equal to bench/model-size, so only the simulation differs.
Entity : { id : U64, pos : Vec3, vel : Vec3 }

Model : { cube : U32, rng : U64, entities : List(Entity) }

draw_count = 100 # U64

half_extent = 20.0 # F32

max_speed = 4.0 # F32

no_args : Config
no_args = { seed: 0, assets: [], args: [] }

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

init : Config -> { model : Model, commands : List(Command) }
init = |config| match entity_count(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The empty-step bench game needs N, a positive integer, as its first Arg."
}

entity_count : List(Str) -> Try(U64, [BadCount])
entity_count = |args| match args.first() {
	Ok(word) =>
		match U64.from_str(word) {
			Ok(n) if n > 0 => Ok(n)
			_ => Err(BadCount)
		}
	Err(_) => Err(BadCount)
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, _dt| { model: m, commands: [] }

spawn : U64, U64 -> Model
spawn = |seed, n| spawn_help({ cube: Mesh.primitive(Cube), rng: seed, entities: List.with_capacity(n) }, n)

spawn_help : Model, U64 -> Model
spawn_help = |m, n| {
	if m.entities.len() >= n {
		m
	} else {
		r1 = next_rng(m.rng)
		r2 = next_rng(r1)
		r3 = next_rng(r2)
		r4 = next_rng(r3)
		entity = {
			id: m.entities.len(),
			pos: { x: spread(r1, half_extent), y: 0.0, z: spread(r2, half_extent) },
			vel: { x: spread(r3, max_speed), y: 0.0, z: spread(r4, max_speed) },
		}
		spawn_help({ ..m, rng: r4, entities: m.entities.append(entity) }, n)
	}
}

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

next_rng : U64 -> U64
next_rng = |s| s.times_wrap(6364136223846793005).plus_wrap(1)

spread : U64, F32 -> F32
spread = |s, limit| ((s.shr_zf_wrap(40) % 1000).to_f32() / 500.0 - 1.0) * limit

# =======================================
# Tests
# =======================================
with_n : U64 -> Config
with_n = |n| { ..no_args, args: [n.to_str()] }

counts_up : List(U64) -> Bool
counts_up = |ids| ids.map_with_index(|id, i| id == i).all(|ok| ok)

expect entity_count(["64"]) == Ok(64)
expect entity_count([]) == Err(BadCount)
expect entity_count(["0"]) == Err(BadCount)
expect entity_count(["many"]) == Err(BadCount)

expect init(with_n(64)).model.entities.len() == 64
expect init(with_n(8)).model != init({ ..with_n(8), seed: 7 }).model

expect {
	m = init(with_n(64)).model
	step(m, idle, QueryResults.empty, 1.0 / 120.0) == { model: m, commands: [] }
}

expect {
	draws = view(init(with_n(1000)).model).draws
	draws.len() == draw_count and counts_up(draws.map(|d| d.id))
}
