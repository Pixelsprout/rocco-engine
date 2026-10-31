app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc" }

import shared.Bench
import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import pf.Vocabulary exposing [Command, Config, Draw, Input, Manifest, Rgb, Scene, Vec3]
import pf.Light
import pf.QueryResults
import pf.Launch
import pf.Pose

# The Lights bench game. N orbs drift over a fixed floor of tiles. Each orb is
# a glowing sphere Draw with a Point Light at its centre, so the Point Light
# count is N and the floor stays the same at every N.
Orb : { id : U64, pos : Vec3, vel : Vec3 }

Model : { tile : U32, orb : U32, rng : U64, orbs : List(Orb) }

# Tiles per side of the floor.
side = 32 # U64

tile_count = 1024 # U64

# The orbs stay inside this square, so the shadow box does not change with N.
half_extent = 15.0 # F32

max_speed = 2.0 # F32

orb_height = 1.0 # F32

orb_radius = 0.2 # F32

orb_range = 3.0 # F32

orb_color : Rgb
orb_color = { r: 4.0, g: 2.5, b: 1.0 }

# high_dpi off, so the numbers do not depend on the display. draws is the
# floor plus N, so the pairing map and the uniform buffer match the workload.
launch : Config -> Vocabulary.Launch
launch = |config| {
	..Launch.default,
	window: { ..Launch.default.window, high_dpi: False },
	capacity: { ..Launch.default.capacity, draws: draws_for(config.args) },
}

draws_for : List(Str) -> U32
draws_for = |args| match Bench.n_arg(args) {
	Ok(n) =>
		match (tile_count + n).to_u32_try() {
			Ok(draws) => draws
			Err(_) => Launch.default.capacity.draws
		}
	Err(BadCount) => Launch.default.capacity.draws
}

# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
# give a benchmark at the wrong size.
init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The lights bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, _results, dt| { model: m |> move(dt) |> bounce, commands: [] }

spawn : U64, U64 -> Model
spawn = |seed, n| spawn_help({ tile: Mesh.primitive(Cube), orb: Mesh.primitive(Sphere), rng: seed, orbs: List.with_capacity(n) }, n)

spawn_help : Model, U64 -> Model
spawn_help = |m, n| {
	if m.orbs.len() >= n {
		m
	} else {
		r1 = Bench.next_rng(m.rng)
		r2 = Bench.next_rng(r1)
		r3 = Bench.next_rng(r2)
		r4 = Bench.next_rng(r3)
		orb = {
			id: tile_count + m.orbs.len(),
			pos: { x: Bench.spread(r1, half_extent), y: orb_height, z: Bench.spread(r2, half_extent) },
			vel: { x: Bench.spread(r3, max_speed), y: 0.0, z: Bench.spread(r4, max_speed) },
		}
		spawn_help({ ..m, rng: r4, orbs: m.orbs.append(orb) }, n)
	}
}

move : Model, F32 -> Model
move = |m, dt| {
	moved = m.orbs.map(|o| { ..o, pos: { x: o.pos.x + o.vel.x * dt, y: o.pos.y, z: o.pos.z + o.vel.z * dt } })
	{ ..m, orbs: moved }
}

bounce : Model -> Model
bounce = |m| { ..m, orbs: m.orbs.map(bounce_orb) }

bounce_orb : Orb -> Orb
bounce_orb = |o| {
	vx = turn_back(o.pos.x, o.vel.x)
	vz = turn_back(o.pos.z, o.vel.z)
	{ ..o, vel: { ..o.vel, x: vx, z: vz } }
}

turn_back : F32, F32 -> F32
turn_back = |pos, vel| {
	if pos > half_extent and vel > 0.0 or pos < -half_extent and vel < 0.0 {
		-vel
	} else {
		vel
	}
}

# The Ambient and the Sun, the tiles, the orb Draws, then the Point Lights.
view : Model -> Scene
view = |m| {
	lit = List.with_capacity(2 + tile_count + 2 * m.orbs.len()).append(Light(ambient)).append(Light(sun))
	tiled = add_tiles(lit, m.tile, 0)
	drawn = List.fold(m.orbs, tiled, |nodes, o| nodes.append(Draw(orb_draw(m.orb, o))))
	{
		camera: Cam.look_at({ x: 0.0, y: 28.0, z: 22.0 }, { x: 0.0, y: 0.0, z: 0.0 }),
		nodes: List.fold(m.orbs, drawn, |nodes, o| nodes.append(Light(Light.point(o.pos, orb_color, orb_range)))),
		cursor: Free,
		sky: 0,
		clear: { r: 0.0, g: 0.0, b: 0.0 },
		ui: [],
		queries: [],
	}
}

add_tiles : List(Vocabulary.Node), U32, U64 -> List(Vocabulary.Node)
add_tiles = |nodes, mesh, id| {
	if id >= tile_count {
		nodes
	} else {
		add_tiles(nodes.append(Draw(tile_draw(mesh, id))), mesh, id + 1)
	}
}

# The primitive cube is 1 unit wide, so a tile leaves a 0.05 gap to the next.
tile_draw : U32, U64 -> Draw
tile_draw = |mesh, id| {
	centre = (side - 1).to_f32() / 2.0
	x = (id % side).to_f32() - centre
	z = (id // side).to_f32() - centre
	{ id, mesh, pos: { x, y: 0.0, z }, scale: { x: 0.95, y: 0.05, z: 0.95 }, rot: Quat.identity, scale_rot: Quat.identity, tint: { r: 0.5, g: 0.5, b: 0.5 }, glow: { r: 0.0, g: 0.0, b: 0.0 }, pose: Pose.still(0, 0.0) }
}

# The primitive sphere has a diameter of 1.
orb_draw : U32, Orb -> Draw
orb_draw = |mesh, o| {
	size = 2.0 * orb_radius
	{ id: o.id, mesh, pos: o.pos, scale: { x: size, y: size, z: size }, rot: Quat.identity, scale_rot: Quat.identity, tint: { r: 1.0, g: 0.6, b: 0.25 }, glow: orb_color, pose: Pose.still(0, 0.0) }
}

ambient : Vocabulary.Light
ambient = Light.ambient({ r: 0.02, g: 0.02, b: 0.02 })

sun : Vocabulary.Light
sun = Light.sun({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 0.3, g: 0.3, b: 0.3 })

draws_of : Scene -> List(Draw)
draws_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Draw(d) => Ok(d)
		_ => Err(NotADraw)
	},
)

lights_of : Scene -> List(Vocabulary.Light)
lights_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Light(l) => Ok(l)
		_ => Err(NotALight)
	},
)

run_steps : Model, U64 -> Model
run_steps = |m, count| {
	if count == 0 {
		m
	} else {
		run_steps(step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0).model, count - 1)
	}
}

expect launch(Bench.no_args).window.high_dpi == False
expect launch(Bench.with_n(40)).capacity.draws == 1064
expect launch(Bench.no_args).capacity == Launch.default.capacity
expect init(Bench.with_n(40)).model.orbs.len() == 40
expect init(Bench.with_n(40)).commands == []

# The Seed decides the orbs, so one Seed always gives the same run.
expect init(Bench.with_n(8)).model == init(Bench.with_n(8)).model
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

# The floor is fixed: 1,024 tiles with ids 0 to 1,023 at every N.
expect {
	small = draws_of(view(init(Bench.with_n(8)).model))
	large = draws_of(view(init(Bench.with_n(512)).model))
	small.len() == 1032 and large.len() == 1536 and Bench.counts_up(large.map(|d| d.id))
}

# One Point light per orb, at the orb, plus the Ambient and the Sun.
expect {
	m = init(Bench.with_n(40)).model
	scene = view(m)
	points = lights_of(scene).keep_if(
		|l| match l {
			Point(_) => Bool.True
			_ => Bool.False
		},
	)
	lights_of(scene).len() == 42 and points == m.orbs.map(|o| Light.point(o.pos, orb_color, orb_range))
}

# Each orb glows, and each tile does not.
expect {
	draws = draws_of(view(init(Bench.with_n(8)).model))
	draws.keep_if(|d| d.glow == orb_color).len() == 8 and draws.keep_if(|d| d.mesh == Mesh.primitive(Sphere)).len() == 8
}

# The orbs move, and stay inside the floor after a bounce.
expect {
	m = init(Bench.with_n(64)).model
	after = run_steps(m, 600)
	after != m and after.orbs.all(|o| o.pos.x >= -half_extent - 1.0 and o.pos.x <= half_extent + 1.0 and o.pos.z >= -half_extent - 1.0 and o.pos.z <= half_extent + 1.0)
}
