app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", shared: "../shared/main.roc", ui: "../../packages/ui/main.roc" }

import shared.Bench
import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Quat
import ui.Ui
import pf.Collider
import pf.Light
import pf.Query
import pf.Vocabulary exposing [Command, Config, Draw, Element, Input, Manifest, Rgba, Scene, Vec3]
import pf.QueryResults
import pf.Launch
import pf.Pose

# The mixed bench game. One N scales every axis together: each entity has one
# Draw and one Collider, and every 10 entities add one UI element. The Queries
# stay at 8 raycasts, 8 overlaps and one ContactsOf, and there are 4 Lights.
# The arena grows with N, so each entity keeps 4 square units.
Entity : { id : U64, pos : Vec3, vel : Vec3, yaw : F32 }

# labels holds the Text of each UI cell, built once, so view copies no text.
# answered counts the QueryResults of the last step, so step reads every answer.
Model : { cube : U32, sphere : U32, rng : U64, half : F32, entities : List(Entity), labels : List(Str), lit : U64, answered : U64 }

entities_per_ui_element = 10 # U64

# One raycast and one overlap per slot.
slots : List(U32)
slots = [0, 1, 2, 3, 4, 5, 6, 7]

max_speed = 4.0 # F32

radius = 0.5 # F32

probe_radius = 2.0 # F32

# The Queries carry this owner. No Collider has id 0, so no Query skips a Collider.
owner = 0 # U64

# ContactsOf asks about the first entity.
watched = 1 # U64

cell_box : Ui.BoxConfig
cell_box = { ..Ui.default_box, width: Fixed(120.0), height: Fixed(16.0), pad: { left: 4.0, right: 4.0, top: 0.0, bottom: 0.0 }, background: { r: 0.15, g: 0.15, b: 0.2, a: 1.0 } }

lit_background : Rgba
lit_background = { r: 0.8, g: 0.5, b: 0.1, a: 1.0 }

root_box : Ui.BoxConfig
root_box = { ..Ui.default_box, direction: Col, gap: 2.0, pad: Ui.pad_all(8.0) }

label : Str -> Ui.Text
label = |str| { ..Ui.label(str), size: 12.0, wrap: None }

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
	Err(BadCount) => crash "The mixed bench game needs N, a positive integer, as its first Arg."
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, _input, results, dt| { model: m |> count_answers(results) |> move(dt) |> bounce |> move_light, commands: [] }

spawn : U64, U64 -> Model
spawn = |seed, n| {
	empty = {
		cube: Mesh.primitive(Cube),
		sphere: Mesh.primitive(Sphere),
		rng: seed,
		half: n.to_f32().sqrt(),
		entities: List.with_capacity(n),
		labels: ui_labels(n // entities_per_ui_element),
		lit: 0,
		answered: 0,
	}
	spawn_help(empty, n)
}

spawn_help : Model, U64 -> Model
spawn_help = |m, n| {
	if m.entities.len() >= n {
		m
	} else {
		r1 = Bench.next_rng(m.rng)
		r2 = Bench.next_rng(r1)
		r3 = Bench.next_rng(r2)
		r4 = Bench.next_rng(r3)
		r5 = Bench.next_rng(r4)
		entity = {
			id: m.entities.len() + 1,
			pos: { x: Bench.spread(r1, m.half), y: radius, z: Bench.spread(r2, m.half) },
			vel: { x: Bench.spread(r3, max_speed), y: 0.0, z: Bench.spread(r4, max_speed) },
			yaw: Bench.spread(r5, 3.0),
		}
		spawn_help({ ..m, rng: r5, entities: m.entities.append(entity) }, n)
	}
}

# The UI holds count Box and Text elements, counted as the UI bench game counts
# them: count / 2 cells of one Box and one Text, and one empty Box when count is
# odd. An empty label marks that Box.
ui_labels : U64 -> List(Str)
ui_labels = |count| {
	labels = add_labels(List.with_capacity(count // 2 + 1), count // 2)
	if count % 2 == 1 labels.append("") else labels
}

add_labels : List(Str), U64 -> List(Str)
add_labels = |labels, count| {
	if labels.len() >= count {
		labels
	} else {
		add_labels(labels.append("Group ${labels.len().to_str()}"), count)
	}
}

count_answers : Model, Vocabulary.QueryResults -> Model
count_answers = |m, results| { ..m, answered: results.contacts.len() + results.rays.len() + results.overlaps.len() }

move : Model, F32 -> Model
move = |m, dt| {
	moved = m.entities.map(|e| { ..e, pos: { x: e.pos.x + e.vel.x * dt, y: e.pos.y, z: e.pos.z + e.vel.z * dt } })
	{ ..m, entities: moved }
}

bounce : Model -> Model
bounce = |m| { ..m, entities: m.entities.map(|e| bounce_entity(e, m.half)) }

bounce_entity : Entity, F32 -> Entity
bounce_entity = |e, half| {
	vx = turn_back(e.pos.x, e.vel.x, half)
	vz = turn_back(e.pos.z, e.vel.z, half)
	{ ..e, vel: { ..e.vel, x: vx, z: vz } }
}

turn_back : F32, F32, F32 -> F32
turn_back = |pos, vel, half| {
	if pos > half and vel > 0.0 or pos < -half and vel < 0.0 {
		-vel
	} else {
		vel
	}
}

move_light : Model -> Model
move_light = |m| if m.labels.is_empty() m else { ..m, lit: (m.lit + 1) % m.labels.len() }

view : Model -> Scene
view = |m| {
	camera: Cam.look_at({ x: 0.0, y: m.half * 2.0, z: m.half * 1.5 }, { x: 0.0, y: 0.0, z: 0.0 }),
	nodes: nodes_of(m),
	cursor: Free,
	sky: 0,
	ui: elements(m),
	queries: queries(m.half),
}

# The 4 Lights, then each entity's Draw and Collider, in one list.
nodes_of : Model -> List(Vocabulary.Node)
nodes_of = |m| {
	first = List.with_capacity(4 + 2 * m.entities.len()) |> with_lights(m.half)
	m.entities.fold(first, |nodes, e| nodes.append(Draw(to_draw(m, e))).append(Collider(to_collider(e))))
}

# Even ids are spheres and odd ids are turned boxes, so both narrowphases run.
is_sphere : Entity -> Bool
is_sphere = |e| e.id % 2 == 0

to_draw : Model, Entity -> Draw
to_draw = |m, e| {
	(mesh, rot) = if is_sphere(e) (m.sphere, Quat.identity) else (m.cube, Quat.from_yaw(e.yaw))
	{ id: e.id, mesh, pos: e.pos, scale: { x: radius, y: radius, z: radius }, rot, scale_rot: Quat.identity, tint: { r: 0.8, g: 0.8, b: 0.8 }, pose: Pose.still(0, 0.0) }
}

to_collider : Entity -> Vocabulary.Collider
to_collider = |e| {
	if is_sphere(e) {
		Collider.sphere(e.id, e.pos, radius)
	} else {
		Collider.box(e.id, e.pos, Quat.from_yaw(e.yaw), { x: radius, y: radius, z: radius })
	}
}

# One Ambient, one Sun with shadows and two Points over opposite corners.
with_lights : List(Vocabulary.Node), F32 -> List(Vocabulary.Node)
with_lights = |nodes, half| nodes
	.append(Light(Light.ambient({ r: 0.05, g: 0.05, b: 0.05 })))
	.append(Light(Light.sun({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })))
	.append(Light(Light.point({ x: -half / 2.0, y: 4.0, z: -half / 2.0 }, { r: 3.0, g: 2.0, b: 1.0 }, half)))
	.append(Light(Light.point({ x: half / 2.0, y: 4.0, z: half / 2.0 }, { r: 1.0, g: 2.0, b: 3.0 }, half)))

# Each raycast crosses the arena along x in its own lane. The overlaps sit on
# the diagonal through the lanes.
queries : F32 -> List(Vocabulary.Query)
queries = |half| {
	rays = slots.map(|k| Query.ray_slot(owner, k, { x: -half - 1.0, y: radius, z: lane(k, half) }, { x: 1.0, y: 0.0, z: 0.0 }, half * 2.0 + 2.0))
	overlaps = slots.map(|k| Query.overlap_slot(owner, k, Sphere(probe_radius), { x: lane(k, half), y: radius, z: lane(k, half) }))
	rays.concat(overlaps).append(Query.contacts_of(watched))
}

# The centre of lane k of the equal lanes across [-half, half].
lane : U32, F32 -> F32
lane = |k, half| ((2 * k + 1).to_f32() / slots.len().to_f32() - 1.0) * half

elements : Model -> List(Element)
elements = |m| {
	if m.labels.is_empty() {
		[]
	} else {
		[Box(root_box, m.labels.map_with_index(|text, i| cell(text, i == m.lit)))]
	}
}

cell : Str, Bool -> Element
cell = |text, lit| {
	config = if lit { ..cell_box, background: lit_background } else cell_box
	children = if text == "" [] else [Text(label(text))]
	Box(config, children)
}

scene_of : U64 -> Scene
scene_of = |n| view(init(Bench.with_n(n)).model)

draws_of : Scene -> List(Draw)
draws_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Draw(d) => Ok(d)
		_ => Err(NotADraw)
	},
)

colliders_of : Scene -> List(Vocabulary.Collider)
colliders_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Collider(c) => Ok(c)
		_ => Err(NotACollider)
	},
)

lights_of : Scene -> List(Vocabulary.Light)
lights_of = |scene| scene.nodes.keep_oks(
	|node| match node {
		Light(l) => Ok(l)
		_ => Err(NotALight)
	},
)

boxes : List(Element) -> U64
boxes = |ui| ui.fold(
	0,
	|n, e| match e {
		Box(_, children) => n + 1 + boxes(children)
		Text(_) => n
	},
)

texts : List(Element) -> U64
texts = |ui| ui.fold(
	0,
	|n, e| match e {
		Box(_, children) => n + texts(children)
		Text(_) => n + 1
	},
)

# The root Box is not one of the UI elements.
ui_element_count : List(Element) -> U64
ui_element_count = |ui| match ui {
	[Box(_, cells)] => boxes(cells) + texts(cells)
	_ => 0
}

query_kinds : List(Vocabulary.Query) -> List([Ray, Overlap, Contacts, Listen])
query_kinds = |qs| qs.map(
	|q| match q {
		Raycast(_) => Ray
		Overlap(_) => Overlap
		ContactsOf(_) => Contacts
		Listen(_) => Listen
	},
)

expect launch(Bench.no_args).window.high_dpi == False
expect launch(Bench.with_n(20000)).capacity.draws == 20000
expect launch(Bench.no_args).capacity == Launch.default.capacity
expect init(Bench.with_n(64)).model.entities.len() == 64
expect init(Bench.with_n(64)).commands == []
expect init(Bench.with_n(64)).model.half == 8.0

# The Seed decides the entities, so one Seed always gives the same run.
expect init(Bench.with_n(8)).model == init(Bench.with_n(8)).model
expect init(Bench.with_n(8)).model != init({ ..Bench.with_n(8), seed: 7 }).model

expect {
	m = spawn(3, 16)
	m.entities.all(|e| e.pos.x >= -m.half and e.pos.x < m.half and e.pos.z >= -m.half and e.pos.z < m.half and e.vel.x >= -max_speed and e.vel.x < max_speed)
}

# One N scales the Draws, the Colliders and the UI at the stated ratio.
expect {
	scene = scene_of(64)
	draws_of(scene).len() == 64 and colliders_of(scene).len() == 64 and ui_element_count(scene.ui) == 6
}

expect {
	scene = scene_of(16384)
	draws_of(scene).len() == 16384 and colliders_of(scene).len() == 16384 and ui_element_count(scene.ui) == 1638 and texts(scene.ui) == 819
}

expect ui_element_count(scene_of(30).ui) == 3 and texts(scene_of(30).ui) == 1
expect scene_of(9).ui == []

# Each entity's Draw and Collider share its id and position.
expect {
	scene = scene_of(32)
	draws_of(scene).map(|d| (d.id, d.pos)) == colliders_of(scene).map(|c| (c.id, c.pos))
}

expect {
	scene = scene_of(4)
	colliders_of(scene).map(|c| c.shape) == [Box({ x: radius, y: radius, z: radius }), Sphere(radius), Box({ x: radius, y: radius, z: radius }), Sphere(radius)]
		and draws_of(scene).map(|d| d.mesh) == [Mesh.primitive(Cube), Mesh.primitive(Sphere), Mesh.primitive(Cube), Mesh.primitive(Sphere)]
}

# The Queries and the Light count stay the same at every N.
expect {
	kinds = List.repeat(Ray, slots.len()).concat(List.repeat(Overlap, slots.len())).append(Contacts)
	query_kinds(scene_of(64).queries) == kinds and query_kinds(scene_of(4096).queries) == kinds
}

expect scene_of(64).queries.last() == Ok(ContactsOf(watched))
expect lights_of(scene_of(64)).len() == 4 and lights_of(scene_of(4096)).len() == 4
expect scene_of(64).nodes.take_first(4) == with_lights([], 8.0)
expect lights_of(scene_of(64)).count_if(
	|l| match l {
		Directional(d) => d.shadow
		_ => Bool.False
	},
) == 1

expect lane(0, 8.0) == -7.0
expect lane(7, 8.0) == 7.0

expect {
	e = { id: 1, pos: { x: 1.0, y: radius, z: 2.0 }, vel: { x: 2.0, y: 0.0, z: -4.0 }, yaw: 0.0 }
	moved = move({ ..init(Bench.with_n(1)).model, entities: [e] }, 0.5)
	moved.entities == [{ ..e, pos: { x: 2.0, y: radius, z: 0.0 } }]
}

expect {
	out = { id: 1, pos: { x: 5.0, y: radius, z: -5.0 }, vel: { x: 2.0, y: 0.0, z: -3.0 }, yaw: 0.0 }
	m = { ..init(Bench.with_n(16)).model, entities: [out] }
	once = bounce(m)
	once.entities.map(|e| e.vel) == [{ x: -2.0, y: 0.0, z: 3.0 }] and bounce(once) == once
}

expect {
	results = { ..QueryResults.empty, rays: [{ owner, slot: 0, id: 3, point: { x: 0.0, y: 0.0, z: 0.0 }, normal: { x: -1.0, y: 0.0, z: 0.0 }, distance: 1.0 }], overlaps: [{ owner, slot: 1, id: 4 }, { owner, slot: 1, id: 6 }] }
	count_answers(init(Bench.with_n(8)).model, results).answered == 3
}

expect {
	m = init(Bench.with_n(60)).model
	[1, 2, 0] == [move_light(m), move_light(move_light(m)), move_light(move_light(move_light(m)))].map(|x| x.lit)
}

expect move_light(init(Bench.with_n(9)).model).lit == 0

# A step moves the entities and the lit cell, and keeps every count.
expect {
	m = init(Bench.with_n(64)).model
	after = step(m, Bench.idle, QueryResults.empty, 1.0 / 120.0)
	before_scene = view(m)
	after_scene = view(after.model)
	after.commands == [] and after.model.entities != m.entities and after.model.lit == 1 and before_scene.ui != after_scene.ui and before_scene.ui.len() == after_scene.ui.len()
}
