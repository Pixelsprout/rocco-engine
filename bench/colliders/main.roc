app [init, loaded, step, view] { cam: "../../packages/camera/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc" }

import shared.Bench
import cam.Camera as Cam
import pf.Collider
import pf.Query
import pf.Vocabulary exposing [Command, Config, Input, Manifest, Scene, Vec3]
import pf.QueryResults
import "colliders.golden" as golden_colliders : Str

# The Colliders bench game. step moves N Colliders and view asks a fixed set of
# Queries: 8 raycasts, 8 overlaps and one ContactsOf. The arena grows with N so
# that each Collider keeps the same space, and only the Collider count changes
# the work.
Body : { id : U64, pos : Vec3, vel : Vec3, yaw : F32 }

# answered counts the QueryResults of the last step, so step reads every answer.
Model : { rng : U64, half : F32, bodies : List(Body), answered : U64 }

# One raycast and one overlap per slot.
slots : List(U32)
slots = [0, 1, 2, 3, 4, 5, 6, 7]

max_speed = 4.0 # F32

radius = 0.5 # F32

probe_radius = 2.0 # F32

# The Queries carry this owner. No Collider has id 0, so no Query skips a Collider.
owner = 0 # U64

# ContactsOf asks about the first Body.
watched = 1 # U64

# N is the first Arg. A missing or bad N must stop the run, so a typo cannot
# give a benchmark at the wrong size.
init : Config -> { model : Model, commands : List(Command) }
init = |config| match Bench.n_arg(config.args) {
	Ok(n) => { model: spawn(config.seed, n), commands: [] }
	Err(BadCount) => crash "The colliders bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, results, dt| { model: m |> count_answers(results) |> move(dt) |> bounce, commands: [] }

# Each Collider gets 4 square units, so the arena half extent is sqrt(N).
spawn : U64, U64 -> Model
spawn = |seed, n| spawn_help({ rng: seed, half: n.to_f32().sqrt(), bodies: List.with_capacity(n), answered: 0 }, n)

spawn_help : Model, U64 -> Model
spawn_help = |m, n| {
	if m.bodies.len() >= n {
		m
	} else {
		r1 = Bench.next_rng(m.rng)
		r2 = Bench.next_rng(r1)
		r3 = Bench.next_rng(r2)
		r4 = Bench.next_rng(r3)
		r5 = Bench.next_rng(r4)
		body = {
			id: m.bodies.len() + 1,
			pos: { x: Bench.spread(r1, m.half), y: 0.0, z: Bench.spread(r2, m.half) },
			vel: { x: Bench.spread(r3, max_speed), y: 0.0, z: Bench.spread(r4, max_speed) },
			yaw: Bench.spread(r5, 3.0),
		}
		spawn_help({ ..m, rng: r5, bodies: m.bodies.append(body) }, n)
	}
}

# Stage: the answers to the last Queries.
count_answers : Model, Vocabulary.QueryResults -> Model
count_answers = |m, results| { ..m, answered: results.contacts.len() + results.rays.len() + results.overlaps.len() }

# Stage: each Body moves by its velocity.
move : Model, F32 -> Model
move = |m, dt| {
	moved = m.bodies.map(|b| { ..b, pos: { x: b.pos.x + b.vel.x * dt, y: b.pos.y, z: b.pos.z + b.vel.z * dt } })
	{ ..m, bodies: moved }
}

# Stage: a Body past the edge turns back inside.
bounce : Model -> Model
bounce = |m| { ..m, bodies: m.bodies.map(|b| bounce_body(b, m.half)) }

bounce_body : Body, F32 -> Body
bounce_body = |b, half| {
	vx = turn_back(b.pos.x, b.vel.x, half)
	vz = turn_back(b.pos.z, b.vel.z, half)
	{ ..b, vel: { ..b.vel, x: vx, z: vz } }
}

turn_back : F32, F32, F32 -> F32
turn_back = |pos, vel, half| {
	if pos > half and vel > 0.0 or pos < -half and vel < 0.0 {
		-vel
	} else {
		vel
	}
}

view : Model -> Scene
view = |m| {
	{
		camera: Cam.look_at({ x: 0.0, y: m.half * 2.0, z: m.half * 1.5 }, { x: 0.0, y: 0.0, z: 0.0 }),
		draws: [],
		colliders: m.bodies.map(to_collider),
		lights: [],
		cursor: Free,
		sky: 0,
		ui: [],
		queries: queries(m.half),
	}
}

# Even ids are spheres and odd ids are turned boxes, so both narrowphases run.
to_collider : Body -> Vocabulary.Collider
to_collider = |b| {
	if b.id % 2 == 0 {
		Collider.sphere(b.id, b.pos, radius)
	} else {
		Collider.box(b.id, b.pos, b.yaw, { x: radius, y: radius, z: radius })
	}
}

# Each raycast crosses the arena along x in its own lane. The overlaps sit on
# the diagonal through the lanes.
queries : F32 -> List(Vocabulary.Query)
queries = |half| {
	rays = slots.map(|k| Query.ray_slot(owner, k, { x: -half - 1.0, y: 0.0, z: lane(k, half) }, { x: 1.0, y: 0.0, z: 0.0 }, half * 2.0 + 2.0))
	overlaps = slots.map(|k| Query.overlap_slot(owner, k, Sphere(probe_radius), { x: lane(k, half), y: 0.0, z: lane(k, half) }))
	rays.concat(overlaps).append(Query.contacts_of(watched))
}

# The centre of lane k of the equal lanes across [-half, half].
lane : U32, F32 -> F32
lane = |k, half| ((2 * k + 1).to_f32() / slots.len().to_f32() - 1.0) * half

# =======================================
# Tests
# =======================================

expect init(Bench.with_n(64)).model.bodies.len() == 64
expect init(Bench.with_n(64)).commands == []
expect init(Bench.with_n(64)).model.half == 8.0

# The Seed decides the Bodies, so one Seed always gives the same run.
expect init(Bench.with_n(8)).model == init(Bench.with_n(8)).model
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

counts_from_one : List(U64) -> Bool
counts_from_one = |ids| ids.map_with_index(|id, i| id == i + 1).all(|ok| ok)

expect counts_from_one(init(Bench.with_n(32)).model.bodies.map(|b| b.id))

expect {
	m = spawn(3, 16)
	m.bodies.all(|b| b.pos.x >= -m.half and b.pos.x < m.half and b.vel.z >= -max_speed and b.vel.z < max_speed)
}

expect {
	b = { id: 1, pos: { x: 1.0, y: 0.0, z: 2.0 }, vel: { x: 2.0, y: 0.0, z: -4.0 }, yaw: 0.0 }
	moved = move({ rng: 0, half: 4.0, bodies: [b], answered: 0 }, 0.5)
	moved.bodies == [{ ..b, pos: { x: 2.0, y: 0.0, z: 0.0 } }]
}

expect {
	out = { id: 1, pos: { x: 5.0, y: 0.0, z: -5.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 }, yaw: 0.0 }
	once = bounce({ rng: 0, half: 4.0, bodies: [out], answered: 0 })
	twice = bounce(once)
	once.bodies.map(|b| b.vel) == [{ x: -2.0, y: 0.0, z: 3.0 }] and twice == once
}

expect {
	inside = { id: 1, pos: { x: 0.0, y: 0.0, z: 0.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 }, yaw: 0.0 }
	bounce({ rng: 0, half: 4.0, bodies: [inside], answered: 0 }).bodies == [inside]
}

expect {
	results = { ..QueryResults.empty, rays: [{ owner, slot: 0, id: 3, point: { x: 0.0, y: 0.0, z: 0.0 }, normal: { x: -1.0, y: 0.0, z: 0.0 }, distance: 1.0 }], overlaps: [{ owner, slot: 1, id: 4 }, { owner, slot: 1, id: 6 }] }
	count_answers(init(Bench.with_n(8)).model, results).answered == 3
}

expect {
	m = init(Bench.with_n(64)).model
	after = step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0).model
	after.bodies.len() == 64 and after != m
}

expect view(init(Bench.with_n(64)).model).colliders.len() == 64
expect view(init(Bench.with_n(1000)).model).colliders.len() == 1000

expect view(init(Bench.with_n(64)).model).colliders.map(|c| c.id) == init(Bench.with_n(64)).model.bodies.map(|b| b.id)

expect {
	colliders = view(init(Bench.with_n(4)).model).colliders
	colliders.map(|c| c.shape) == [Box({ x: radius, y: radius, z: radius }), Sphere(radius), Box({ x: radius, y: radius, z: radius }), Sphere(radius)]
}

# The Queries stay the same at every N.
query_kinds : List(Vocabulary.Query) -> List([Ray, Overlap, Contacts])
query_kinds = |qs| qs.map(
	|q| match q {
		Raycast(_) => Ray
		Overlap(_) => Overlap
		ContactsOf(_) => Contacts
	},
)

expect {
	small = view(init(Bench.with_n(64)).model).queries
	large = view(init(Bench.with_n(4096)).model).queries
	kinds = List.repeat(Ray, slots.len()).concat(List.repeat(Overlap, slots.len())).append(Contacts)
	query_kinds(small) == kinds and query_kinds(large) == kinds
}

expect view(init(Bench.with_n(64)).model).queries.last() == Ok(ContactsOf(watched))

expect lane(0, 8.0) == -7.0
expect lane(7, 8.0) == 7.0

# Every raycast starts outside the arena and reaches its far side.
expect {
	half = 8.0
	queries(half).all(
		|q| match q {
			Raycast(r) => r.origin.x < -half and r.origin.x + r.max_distance > half
			_ => Bool.True
		},
	)
}

# bench/colliders-twin checks its Colliders against the same file, so the twin
# and this game agree for one Seed and N after the same steps.
run_steps : Model, U64 -> Model
run_steps = |m, count| if count == 0 m else run_steps(step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0).model, count - 1)

bits_text : F32 -> Str
bits_text = |f| f.to_bits().to_str()

shape_text : [Box(Vec3), Sphere(F32), Capsule({ radius : F32, half_height : F32 })] -> Str
shape_text = |shape| match shape {
	Box(h) => "box ${bits_text(h.x)} ${bits_text(h.y)} ${bits_text(h.z)}"
	Sphere(r) => "sphere ${bits_text(r)}"
	Capsule(_) => "capsule"
}

colliders_text : List(Vocabulary.Collider) -> Str
colliders_text = |colliders| Str.join_with(colliders.map(|c| "${c.id.to_str()} ${shape_text(c.shape)} ${bits_text(c.pos.x)} ${bits_text(c.pos.y)} ${bits_text(c.pos.z)} ${bits_text(c.yaw)}\n"), "")

expect colliders_text(view(run_steps(init({ ..Bench.with_n(100), seed: 7 }).model, 600)).colliders) == golden_colliders
