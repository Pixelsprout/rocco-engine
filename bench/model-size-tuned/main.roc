app [init, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc" }

import shared.Bench
import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Draw, Input, Manifest, Scene, Vec3]
import pf.Light
import pf.QueryResults
import "../model-size/model.golden" as golden_model : Str

# The tuned Model size bench game. It has the behaviour of bench/model-size,
# but step keeps the entity list unique and walks it once.
Entity : { id : U64, pos : Vec3, vel : Vec3 }

Model : { cube : U32, rng : U64, entities : List(Entity) }

draw_count = 100 # U64

half_extent = 20.0 # F32

max_speed = 4.0 # F32

init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The model-size-tuned bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, dt| { model: update(m, dt), commands: [] }

# The record is taken apart so the list has one reference and map can write it
# in place. One pass runs both Stages on each entity.
update : Model, F32 -> Model
update = |m, dt| {
	{ cube, rng, entities } = m
	{ cube, rng, entities: entities.map(|e| bounce(move(e, dt))) }
}

spawn : U64, U64 -> Model
spawn = |seed, n| {
	var $rng = seed
	var $entities = List.with_capacity(n)
	while List.len($entities) < n {
		r1 = Bench.next_rng($rng)
		r2 = Bench.next_rng(r1)
		r3 = Bench.next_rng(r2)
		r4 = Bench.next_rng(r3)
		$entities = List.append(
			$entities,
			{
				id: List.len($entities),
				pos: { x: Bench.spread(r1, half_extent), y: 0.0, z: Bench.spread(r2, half_extent) },
				vel: { x: Bench.spread(r3, max_speed), y: 0.0, z: Bench.spread(r4, max_speed) },
			},
		)
		$rng = r4
	}
	{ cube: Mesh.primitive(Cube), rng: $rng, entities: $entities }
}

# Stage: the entity moves by its velocity.
move : Entity, F32 -> Entity
move = |e, dt| { ..e, pos: { x: e.pos.x + e.vel.x * dt, y: e.pos.y, z: e.pos.z + e.vel.z * dt } }

# Stage: an entity past the edge turns back inside.
bounce : Entity -> Entity
bounce = |e| {
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

# =======================================
# Tests
# =======================================

expect init(Bench.with_n(64)).model.entities.len() == 64
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

expect {
	e = { id: 0, pos: { x: 1.0, y: 0.0, z: 2.0 }, vel: { x: 2.0, y: 0.0, z: -4.0 } }
	move(e, 0.5) == { ..e, pos: { x: 2.0, y: 0.0, z: 0.0 } }
}

expect {
	out = { id: 0, pos: { x: half_extent + 1.0, y: 0.0, z: -half_extent - 1.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	once = bounce(out)
	once.vel == { x: -2.0, y: 0.0, z: 3.0 } and bounce(once) == once
}

expect {
	inside = { id: 0, pos: { x: 0.0, y: 0.0, z: 0.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 } }
	bounce(inside) == inside
}

expect {
	small = view(init(Bench.with_n(64)).model).draws
	large = view(init(Bench.with_n(1000)).model).draws
	small.len() == draw_count and large.len() == draw_count
}

# bench/model-size checks its Model against the same file, so both versions
# give the same Model for one Seed and N after the same steps.
run_steps : Model, U64 -> Model
run_steps = |m, count| if count == 0 m else run_steps(update(m, 1.0 / 120.0), count - 1)

f32_text : F32 -> Str
f32_text = |f| f.to_bits().to_str()

model_text : Model -> Str
model_text = |m| {
	entity_lines = m.entities.map(|e| "${e.id.to_str()} ${f32_text(e.pos.x)} ${f32_text(e.pos.y)} ${f32_text(e.pos.z)} ${f32_text(e.vel.x)} ${f32_text(e.vel.y)} ${f32_text(e.vel.z)}\n")
	Str.join_with(List.concat(["${m.cube.to_str()} ${m.rng.to_str()}\n"], entity_lines), "")
}

expect model_text(run_steps(init({ ..Bench.with_n(100), seed: 7 }).model, 600)) == golden_model
