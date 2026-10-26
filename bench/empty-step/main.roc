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

# The lower limit of the seam. It holds the same Model and returns the same
# Scene as bench/model-size, but step returns the Model unchanged. Keep spawn
# and view equal to bench/model-size, so only the simulation differs.
Entity : { id : U64, pos : Vec3, vel : Vec3 }

Model : { cube : U32, rng : U64, entities : List(Entity) }

draw_count = 100 # U64

half_extent = 20.0 # F32

max_speed = 4.0 # F32

# high_dpi off, so the numbers do not depend on the display.
launch : Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, high_dpi: False } }

init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The empty-step bench game needs N, a positive integer, as its first Arg."
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

view : Model -> Scene
view = |m| {
	n = m.entities.len()
	# The Draws, then the Lights, in one list. With the Lights first, add_draws
	# grew the list again from a small size: 6 reallocs a step.
	nodes = List.with_capacity(draw_count + 2) |> add_draws(m, n, 0) |> with_lights
	{
		camera: Cam.look_at({ x: 0.0, y: 40.0, z: 30.0 }, { x: 0.0, y: 0.0, z: 0.0 }),
		nodes,
		cursor: Free,
		sky: 0,
		ui: [],
		queries: [],
	}
}

add_draws : List(Vocabulary.Node), Model, U64, U64 -> List(Vocabulary.Node)
add_draws = |nodes, m, n, i| {
	if i >= draw_count {
		nodes
	} else {
		next = match m.entities.get(i * n // draw_count) {
			Ok(e) => nodes.append(Draw(cube_draw(m.cube, i, e.pos)))
			Err(_) => nodes
		}
		add_draws(next, m, n, i + 1)
	}
}

cube_draw : U32, U64, Vec3 -> Draw
cube_draw = |mesh, id, pos| { id, mesh, pos, scale: { x: 0.5, y: 0.5, z: 0.5 }, rot: Quat.identity, scale_rot: Quat.identity, tint: { r: 0.8, g: 0.8, b: 0.8 }, pose: Pose.still(0, 0.0) }

with_lights : List(Vocabulary.Node) -> List(Vocabulary.Node)
with_lights = |nodes| nodes
	.append(Light(Light.ambient({ r: 0.2, g: 0.2, b: 0.2 })))
	.append(Light(Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })))

draws_of : Scene -> List(Draw)
draws_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Draw(d) => Ok(d)
		_ => Err(NotADraw)
	},
)

expect launch(Bench.no_args).window.high_dpi == False
expect init(Bench.with_n(64)).model.entities.len() == 64
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

expect {
	m = init(Bench.with_n(64)).model
	step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0) == { model: m, commands: [] }
}

expect {
	draws = draws_of(view(init(Bench.with_n(1000)).model))
	draws.len() == draw_count and Bench.counts_up(draws.map(|d| d.id))
}
