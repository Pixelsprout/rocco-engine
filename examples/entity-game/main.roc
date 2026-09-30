app [init, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-27-a3ce7f1", cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Config, Draw, Input, Scene, Vec3]
import pf.Key

# ---- Types only Roc reads. The host carries Model through untouched. -----

Kind : [Player, Pickup, Door({ open : Bool, lift : F32 }), Spark({ age : F32, phase : F32 })]

# pos and yaw are local to the parent. A parent precedes its children in the
# entity list: a child spawns later and append places it later. Reparenting to
# a younger entity is the one way to break that.
Entity : { id : U64, kind : Kind, parent : [Root, Child(U64)], pos : Vec3, vel : Vec3, yaw : F32, alive : Bool }

# The ids this game resolved from the manifest at init. Resolved once, kept
# in the Model, never looked up per step.
MeshIds : { cube : U32, sphere : U32, plane : U32, sprout : U32 }

# next_id only grows, so an id is never reused and the host never pairs a
# new entity with a dead one.
Model : { steps : U64, score : U64, next_id : U64, meshes : MeshIds, entities : List(Entity), orphans_logged : List(U64) }

# ---- init : Config -> Model ---------------------------------------------
#
# Config is the engine's: a seed and the mesh manifest, nothing about this
# game. How many pickups a round has, and which mesh is a pickup, is decided
# here.

init : Config -> Model
init = |config| new_game(resolve_meshes(config), 8)

resolve_meshes : Config -> MeshIds
resolve_meshes = |config| {
	cube: Mesh.primitive(config, Cube),
	sphere: Mesh.primitive(config, Sphere),
	plane: Mesh.primitive(config, Plane),
	sprout: Mesh.resolve(config, "sprout"),
}

new_game : MeshIds, U64 -> Model
new_game = |meshes, pickups| {
	player = { id: 0, kind: Player, parent: Root, pos: origin, vel: origin, yaw: 0.0, alive: Bool.True }
	door = { id: 1, kind: Door({ open: Bool.False, lift: 0.0 }), parent: Root, pos: { x: 0.0, y: 1.5, z: -8.0 }, vel: origin, yaw: 0.0, alive: Bool.True }

	var $pickups = List.with_capacity(pickups)
	var $i = 0
	while $i < pickups {
		angle = ($i.to_f32()) * 6.2832 / (pickups.to_f32())
		pos = { x: 4.0 * angle.cos(), y: 0.5, z: 4.0 * angle.sin() }
		$pickups = List.append($pickups, { id: 2 + $i, kind: Pickup, parent: Root, pos, vel: origin, yaw: 0.0, alive: Bool.True })
		$i = $i + 1
	}

	{ steps: 0, score: 0, next_id: 2 + pickups, meshes, entities: List.concat([player, door], $pickups), orphans_logged: [] }
}

# ---- step : Model, Input, F32 -> Model ---------------------------------
#
# The schedule is function composition. Each stage is Model -> Model and
# testable alone. Reorder the pipeline and you reorder the stages.

step : Model, Input, F32 -> Model
step = |model, input, dt|
	model
		|> steer(input)
		|> face(dt)
		|> integrate(dt)
		|> spin(dt)
		|> expire(dt)
		|> collect
		|> orbit
		|> open_door
		|> raise_door(dt)
		|> sweep
		|> log_orphans
		|> count_step

speed : F32
speed = 6.0

# The binding from keys to intent lives in the game, not the engine.
move_dir : Input -> Vec3
move_dir = |input| { x: Key.axis(input, A, D), y: 0.0, z: Key.axis(input, W, S) }

steer : Model, Input -> Model
steer = |m, input| map_entities(
	m,
	|e| match e.kind {
		Player => { ..e, vel: scale(move_dir(input), speed) }
		_ => e
	},
)

# Radians per second.
turn_speed : F32
turn_speed = 12.0

# The sprout's front is +z, so the yaw that faces (x, z) is the angle of (z, x).
face : Model, F32 -> Model
face = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Player if e.vel.x != 0.0 or e.vel.z != 0.0 => { ..e, yaw: turn_toward(e.yaw, F32.atan2({ x: e.vel.z, y: e.vel.x }), turn_speed * dt) }
		_ => e
	},
)

# Both angles stay in (-pi, pi], so one wrap of the difference picks the short way.
turn_toward : F32, F32, F32 -> F32
turn_toward = |from, to, max_turn| {
	diff = wrap_angle(to - from)
	turn = if diff > max_turn {
		max_turn
	} else if diff < -max_turn {
		-max_turn
	} else {
		diff
	}
	wrap_angle(from + turn)
}

wrap_angle : F32 -> F32
wrap_angle = |a|
	if a > pi {
		a - 2.0 * pi
	} else if a <= -pi {
		a + 2.0 * pi
	} else {
		a
	}

integrate : Model, F32 -> Model
integrate = |m, dt| map_entities(m, |e| { ..e, pos: add(e.pos, scale(e.vel, dt)) })

spin : Model, F32 -> Model
spin = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Pickup => { ..e, yaw: e.yaw + 2.0 * dt }
		_ => e
	},
)

# Collision for a small game is a distance test over a list. When the host
# grows a broadphase, it passes contacts in as data and this stage reads them.
collect : Model -> Model
collect = |m| match player(m) {
	Err(NotFound) => m
	Ok(p) => {
		touched = |e| is_pickup(e) and e.alive and dist2(e.pos, p.pos) < 1.0
		gained = List.count_if(m.entities, touched)
		if gained == 0 {
			return m
		}
		entities = List.map(
			m.entities,
			|e| if touched(e) {
				{ ..e, alive: Bool.False }
			} else {
				e
			},
		)
		spawn_sparks({ ..m, score: m.score + gained, entities }, p.id, gained * sparks_per_pickup)
	}
}

sparks_per_pickup : U64
sparks_per_pickup = 6

# Seconds.
spark_life : F32
spark_life = 1.0

spawn_sparks : Model, U64, U64 -> Model
spawn_sparks = |m, parent, count| {
	var $entities = List.reserve(m.entities, count)
	var $i = 0
	while $i < count {
		phase = ($i % sparks_per_pickup).to_f32() * 2.0 * pi / sparks_per_pickup.to_f32()
		$entities = List.append($entities, { id: m.next_id + $i, kind: Spark({ age: 0.0, phase }), parent: Child(parent), pos: origin, vel: origin, yaw: 0.0, alive: Bool.True })
		$i = $i + 1
	}
	{ ..m, next_id: m.next_id + count, entities: $entities }
}

# A block arm that set age and alive together allocated on every step under
# --opt=dev, even with no sparks. The guard does not.
expire : Model, F32 -> Model
expire = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Spark(s) if s.age + dt >= spark_life => { ..e, alive: Bool.False }
		Spark(s) => { ..e, kind: Spark({ ..s, age: s.age + dt }) }
		_ => e
	},
)

orbit_radius : F32
orbit_radius = 0.8

orbit_height : F32
orbit_height = 0.9

# Radians per second.
orbit_speed : F32
orbit_speed = 4.0

orbit : Model -> Model
orbit = |m| map_entities(
	m,
	|e| match e.kind {
		Spark(s) => {
			angle = s.phase + orbit_speed * s.age
			{ ..e, pos: { x: orbit_radius * angle.cos(), y: orbit_height, z: orbit_radius * angle.sin() } }
		}
		_ => e
	},
)

open_door : Model -> Model
open_door = |m| {
	remaining = List.count_if(m.entities, |e| is_pickup(e) and e.alive)
	if remaining > 0 {
		m
	} else {
		map_entities(
			m,
			|e| match e.kind {
				Door(d) => { ..e, kind: Door({ ..d, open: Bool.True }) }
				_ => e
			},
		)
	}
}

# Units per second, and how far the door rises.
door_speed : F32
door_speed = 3.0

door_height : F32
door_height = 3.0

raise_door : Model, F32 -> Model
raise_door = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Door(d) if d.open and d.lift < door_height => { ..e, kind: Door({ ..d, lift: F32.min(d.lift + door_speed * dt, door_height) }) }
		_ => e
	},
)

# The fold allocates even when it keeps everything, so skip it on a quiet step.
# A parent precedes its children, so one pass in list order drops every
# descendant of a dead entity.
sweep : Model -> Model
sweep = |m|
	if List.all(m.entities, |e| e.alive) {
		m
	} else {
		start = { kept: List.with_capacity(List.len(m.entities)), dropped: [] }
		swept = List.fold(
			m.entities,
			start,
			|acc, e| {
				orphaned = match e.parent {
					Root => Bool.False
					Child(parent) => List.contains(acc.dropped, parent)
				}
				if e.alive and !orphaned {
					{ ..acc, kept: acc.kept.append(e) }
				} else {
					{ ..acc, dropped: acc.dropped.append(e.id) }
				}
			},
		)
		{ ..m, entities: swept.kept }
	}

# view cannot remember what it logged, so this stage logs each orphan once.
log_orphans : Model -> Model
log_orphans = |m| {
	found = List.fold(
		m.entities,
		{ index: 0, logged: m.orphans_logged },
		|acc, e| {
			orphan = match e.parent {
				Root => Bool.False
				Child(parent) => match List.find_first_index(m.entities, |p| p.id == parent) {
					Ok(j) => j >= acc.index
					Err(_) => Bool.True
				}
			}
			logged = if orphan and !List.contains(acc.logged, e.id) {
				dbg e.id
				acc.logged.append(e.id)
			} else {
				acc.logged
			}
			{ index: acc.index + 1, logged }
		},
	)
	{ ..m, orphans_logged: found.logged }
}

count_step : Model -> Model
count_step = |m| { ..m, steps: m.steps + 1 }

# ---- view : Model -> Scene -------------------------------------------------
#
# Runs once per fixed step, after step. It sees one Model and no alpha. The
# host holds this Scene and the previous one and interpolates between draws
# with the same id when it draws a frame. That keeps the Model's refcount at one,
# so step mutates in place and nothing is copied to remember the past.

# Scenery ids count down from the top, so next_id never reaches them.
floor_id : U64
floor_id = U64.highest

camera_offset : Vec3
camera_offset = { x: 0.0, y: 1.5, z: 3.5 }

view : Model -> Scene
view = |curr| {
	floor = { id: floor_id, mesh: curr.meshes.plane, pos: origin, scale: { x: 20.0, y: 1.0, z: 20.0 }, yaw: 0.0, tint: { r: 0.051, g: 0.051, b: 0.064 } }

	# One allocation for every draw. List.concat would allocate twice.
	# A parent precedes its child, so the parent's Draw is already in acc.
	first = List.with_capacity(List.len(curr.entities) + 1).append(floor)
	draws = List.fold(
		curr.entities,
		first,
		|acc, e| {
			world = match e.parent {
				Root => { pos: e.pos, yaw: e.yaw }
				Child(parent) => match List.find_first(acc, |d| d.id == parent) {
					Ok(p) => { pos: add(p.pos, rotate_y(e.pos, p.yaw)), yaw: p.yaw + e.yaw }
					Err(NotFound) => { pos: e.pos, yaw: e.yaw }
				}
			}
			acc.append(draw(curr.meshes, e, world))
		},
	)

	target = match player(curr) {
		Ok(p) => p.pos
		Err(NotFound) => origin
	}

	{ camera: Cam.follow(target, camera_offset), draws }
}

draw : MeshIds, Entity, { pos : Vec3, yaw : F32 } -> Draw
draw = |meshes, e, world| {
	pos = world.pos
	yaw = world.yaw
	match e.kind {
		Player => { id: e.id, mesh: meshes.sprout, pos, scale: one, yaw, tint: { r: 1.0, g: 1.0, b: 1.0 } }
		Pickup => { id: e.id, mesh: meshes.cube, pos, scale: scale(one, 0.4), yaw, tint: { r: 0.033, g: 0.787, b: 0.133 } }
		Spark(_) => { id: e.id, mesh: meshes.sphere, pos, scale: scale(one, 0.12), yaw, tint: { r: 1.0, g: 0.527, b: 0.051 } }
		Door(d) => {
			lifted = { ..pos, y: pos.y + d.lift }
			{ id: e.id, mesh: meshes.cube, pos: lifted, scale: { x: 3.0, y: 3.0, z: 0.3 }, yaw, tint: { r: 0.214, g: 0.073, b: 0.604 } }
		}
	}
}

# ---- helpers -------------------------------------------------------------

# A List.update loop, because List.map copies the list under --opt=dev.
# The fallback must not name $entities: a second reference makes each update
# copy the list. The index is always in range, so [] is never used.
map_entities : Model, (Entity -> Entity) -> Model
map_entities = |m, f| {
	var $entities = m.entities
	var $i = 0
	while $i < List.len($entities) {
		$entities = List.update($entities, $i, f) ?? []
		$i = $i + 1
	}
	{ ..m, entities: $entities }
}

player : Model -> Try(Entity, [NotFound])
player = |m| List.find_first(
	m.entities,
	|e| match e.kind {
		Player => Bool.True
		_ => Bool.False
	},
)

is_pickup : Entity -> Bool
is_pickup = |e| match e.kind {
	Pickup => Bool.True
	_ => Bool.False
}

door_open : Model -> Bool
door_open = |m| List.any(
	m.entities,
	|e| match e.kind {
		Door(d) => d.open
		_ => Bool.False
	},
)

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

one : Vec3
one = { x: 1.0, y: 1.0, z: 1.0 }

add : Vec3, Vec3 -> Vec3
add = |a, b| { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }

# Turns v about +y by yaw, the way the host turns a Draw, so +z goes to (sin, 0, cos).
rotate_y : Vec3, F32 -> Vec3
rotate_y = |v, yaw| {
	c = yaw.cos()
	s = yaw.sin()
	{ x: v.x * c + v.z * s, y: v.y, z: v.z * c - v.x * s }
}

scale : Vec3, F32 -> Vec3
scale = |v, s| { x: v.x * s, y: v.y * s, z: v.z * s }

pi : F32
pi = 3.1415927

dist2 : Vec3, Vec3 -> F32
dist2 = |a, b| {
	d = { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }
	d.x * d.x + d.y * d.y + d.z * d.z
}

# ---- tests. `roc test main.roc` runs these with no engine. ----------------

# What the engine would hand init on this machine.
manifest : Config
manifest = { seed: 0, meshes: [{ name: "primitive/fallback", id: 0 }, { name: "primitive/cube", id: 1 }, { name: "primitive/sphere", id: 2 }, { name: "primitive/plane", id: 3 }, { name: "sprout", id: 4 }] }

test_meshes : MeshIds
test_meshes = resolve_meshes(manifest)

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

right : Input
right = { ..idle, held: [Key.code(D)] }

expect {
	m = new_game(test_meshes, 3)
	List.len(m.entities) == 5 and m.score == 0
}

expect {
	# A plane floor, a sprout player, a cube door and cube pickups.
	scene = view(new_game(test_meshes, 1))
	mesh_of = |id| List.find_first(scene.draws, |d| d.id == id).map_ok(|d| d.mesh) ?? 0
	mesh_of(floor_id) == test_meshes.plane and mesh_of(0) == test_meshes.sprout and mesh_of(1) == test_meshes.cube and mesh_of(2) == test_meshes.cube
}

expect {
	# The sprout carries its own colours, so its tint is white.
	scene = view(new_game(test_meshes, 1))
	match List.find_first(scene.draws, |d| d.id == 0) {
		Ok(d) => d.tint == { r: 1.0, g: 1.0, b: 1.0 }
		Err(_) => Bool.False
	}
}

yaw_of : Model -> F32
yaw_of = |m| player(m).map_ok(|p| p.yaw) ?? -100.0

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

run_steps : Model, Input, U64, F32 -> Model
run_steps = |m, input, n, dt| {
	var $m = m
	var $i = 0
	while $i < n {
		$m = step($m, input, dt)
		$i = $i + 1
	}
	$m
}

facing : Model, F32 -> Model
facing = |m, yaw| map_entities(
	m,
	|e| match e.kind {
		Player => { ..e, yaw }
		_ => e
	},
)

expect {
	# One short step turns the player part of the way, at turn_speed.
	moved = step(new_game(test_meshes, 0), right, 0.05)
	near(yaw_of(moved), turn_speed * 0.05)
}

expect {
	# Given time, the player faces where it moves, and keeps that yaw when it stops.
	moved = run_steps(new_game(test_meshes, 0), right, 20, 0.05)
	stopped = run_steps(moved, idle, 5, 0.05)
	back = run_steps(stopped, { ..idle, held: [Key.code(W)] }, 20, 0.05)
	near(yaw_of(moved), pi / 2.0) and near(yaw_of(stopped), pi / 2.0) and near(yaw_of(back), pi)
}

expect {
	# From 3/4 pi toward -3/4 pi, the short way is up through pi.
	m = facing(new_game(test_meshes, 0), 0.75 * pi)
	turned = step(m, { ..idle, held: [Key.code(W), Key.code(A)] }, 0.05)
	yaw_of(turned) > 0.75 * pi
}

expect {
	# Standing on every pickup collects every pickup and opens the door in one step.
	m = new_game(test_meshes, 2)
	on_top = map_entities(
		m,
		|e| if is_pickup(e) {
			{ ..e, pos: origin }
		} else {
			e
		},
	)
	after = step(on_top, idle, 1.0 / 120.0)
	after.score == 2 and door_open(after) and List.len(after.entities) == 2 + 2 * sparks_per_pickup
}

is_spark : Entity -> Bool
is_spark = |e| match e.kind {
	Spark(_) => Bool.True
	_ => Bool.False
}

spark_count : Model -> U64
spark_count = |m| List.count_if(m.entities, is_spark)

expect {
	# Each collected pickup spawns its sparks, and the pickup is swept.
	m = new_game(test_meshes, 3)
	on_one = map_entities(
		m,
		|e| if e.id == 2 {
			{ ..e, pos: origin }
		} else {
			e
		},
	)
	after = step(on_one, idle, 1.0 / 120.0)
	spark_count(after) == sparks_per_pickup and List.count_if(after.entities, is_pickup) == 2
}

expect {
	# New ids start past the last pickup, only grow, and are never reused.
	m = new_game(test_meshes, 2)
	after = step(on_every_pickup(m), idle, 1.0 / 120.0)
	spark_ids = List.keep_if(after.entities, is_spark).map(|e| e.id)
	fresh = List.all(spark_ids, |id| id >= m.next_id and id < after.next_id)
	distinct = List.all(spark_ids, |id| List.count_if(spark_ids, |other| other == id) == 1)
	m.next_id == 4 and after.next_id == m.next_id + 2 * sparks_per_pickup and fresh and distinct
}

expect {
	# A spark lives for spark_life seconds, then sweep drops it.
	sparked = step(on_every_pickup(new_game(test_meshes, 1)), idle, 0.1)
	before = run_steps(sparked, idle, 8, 0.1)
	after = run_steps(before, idle, 3, 0.1)
	spark_count(sparked) == sparks_per_pickup and spark_count(before) == sparks_per_pickup and spark_count(after) == 0
}

expect {
	# Pickups are cubes so the spin shows. Sparks are small spheres.
	sparked = step(on_every_pickup(new_game(test_meshes, 2)), idle, 1.0 / 120.0)
	scene = view(sparked)
	pickup_mesh = List.find_first(view(new_game(test_meshes, 1)).draws, |d| d.id == 2).map_ok(|d| d.mesh) ?? 0
	spark_draws = List.keep_if(scene.draws, |d| d.id >= 4 and d.id < sparked.next_id)
	pickup_mesh == test_meshes.cube and List.len(spark_draws) == 2 * sparks_per_pickup and List.all(spark_draws, |d| d.mesh == test_meshes.sphere)
}

door_lift : Model -> F32
door_lift = |m| List.fold(
	m.entities,
	-1.0,
	|acc, e| match e.kind {
		Door(d) => d.lift
		_ => acc
	},
)

door_draw_y : Model -> F32
door_draw_y = |m| List.find_first(view(m).draws, |d| d.id == 1).map_ok(|d| d.pos.y) ?? -1.0

on_every_pickup : Model -> Model
on_every_pickup = |m| map_entities(
	m,
	|e| if is_pickup(e) {
		{ ..e, pos: origin }
	} else {
		e
	},
)

expect {
	# The door starts to rise on the step it opens, at door_speed.
	after = step(on_every_pickup(new_game(test_meshes, 2)), idle, 0.1)
	near(door_lift(after), door_speed * 0.1) and near(door_draw_y(after), 1.5 + door_speed * 0.1)
}

expect {
	# Given time, the door stops at door_height.
	after = run_steps(on_every_pickup(new_game(test_meshes, 2)), idle, 30, 0.1)
	near(door_lift(after), door_height) and near(door_draw_y(after), 1.5 + door_height)
}

expect {
	# A shut door does not rise.
	after = run_steps(new_game(test_meshes, 2), idle, 30, 0.1)
	door_lift(after) == 0.0 and near(door_draw_y(after), 1.5)
}

expect {
	# Nothing touched: the door stays shut and nothing is swept.
	after = step(new_game(test_meshes, 4), idle, 1.0 / 120.0)
	after.score == 0 and !door_open(after) and List.len(after.entities) == 6
}

expect {
	# step is pure. The same Model and Input give the same step count and score,
	# which is what makes a recorded input log a replay.
	m = new_game(test_meshes, 4)
	a = step(m, right, 0.5)
	b = step(m, right, 0.5)
	a.steps == b.steps and a.score == b.score
}

expect {
	# view carries the entity id onto its draw, so the host can pair this
	# step's draw with the last one. The floor's id never collides.
	m = new_game(test_meshes, 1)
	scene = view(step(m, right, 1.0))
	player_draw = List.find_first(scene.draws, |d| d.id == 0)
	ids_unique = List.len(scene.draws) == 4 and List.count_if(scene.draws, |d| d.id == floor_id) == 1
	match player_draw {
		Ok(d) => d.pos.x == 6.0 and ids_unique
		Err(_) => Bool.False
	}
}

expect {
	# The camera follows the player from a fixed offset.
	scene = view(step(new_game(test_meshes, 1), right, 1.0))
	scene.camera.target.x == 6.0 and scene.camera.eye.x == 6.0 and scene.camera.eye.y == 1.5
}

# A Pickup draws at its world pos and yaw with no offset.
entity_at : U64, [Root, Child(U64)], Vec3, F32 -> Entity
entity_at = |id, parent, pos, yaw| { id, kind: Pickup, parent, pos, vel: origin, yaw, alive: Bool.True }

with_entities : List(Entity) -> Model
with_entities = |entities| { ..new_game(test_meshes, 0), entities }

draw_of : Scene, U64 -> Try(Draw, [NotFound])
draw_of = |scene, id| List.find_first(scene.draws, |d| d.id == id)

near_vec : Vec3, Vec3 -> Bool
near_vec = |a, b| near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z)

expect {
	# A child's world pos is its local pos turned by the parent yaw, plus the
	# parent pos. Yaws add. Depth is unbounded.
	scene = view(
		with_entities(
			[
				entity_at(10, Root, { x: 1.0, y: 0.0, z: 0.0 }, pi / 2.0),
				entity_at(11, Child(10), { x: 0.0, y: 2.0, z: 1.0 }, 0.5),
				entity_at(12, Child(11), { x: 0.0, y: 0.0, z: 1.0 }, 0.0),
			],
		),
	)
	match (draw_of(scene, 11), draw_of(scene, 12)) {
		(Ok(child), Ok(grandchild)) => {
			turned = pi / 2.0 + 0.5
			want = { x: 2.0 + turned.sin(), y: 2.0, z: turned.cos() }
			near_vec(child.pos, { x: 2.0, y: 2.0, z: 0.0 }) and near(child.yaw, turned) and near_vec(grandchild.pos, want)
		}
		_ => Bool.False
	}
}

expect {
	# Scale is not inherited.
	scene = view(with_entities([entity_at(10, Root, origin, 0.0), entity_at(11, Child(10), origin, 0.0)]))
	match (draw_of(scene, 10), draw_of(scene, 11)) {
		(Ok(parent), Ok(child)) => parent.scale == child.scale
		_ => Bool.False
	}
}

expect {
	# A child whose parent is missing, or later in the list, draws at its local values.
	local = { x: 3.0, y: 1.0, z: 2.0 }
	scene = view(
		with_entities(
			[
				entity_at(10, Child(99), local, 0.25),
				entity_at(11, Child(12), local, 0.25),
				entity_at(12, Root, { x: 5.0, y: 0.0, z: 0.0 }, 1.0),
			],
		),
	)
	at_local = |id| draw_of(scene, id).map_ok(|d| d.pos == local and d.yaw == 0.25) ?? Bool.False
	at_local(10) and at_local(11)
}

expect {
	# log_orphans records each orphan id once, however many steps it lives.
	m = with_entities([entity_at(10, Child(99), origin, 0.0), entity_at(11, Child(12), origin, 0.0), entity_at(12, Root, origin, 0.0), entity_at(13, Child(13), origin, 0.0)])
	after = run_steps(m, idle, 3, 0.1)
	after.orphans_logged == [10, 11, 13]
}

expect {
	# A child of the door lifts with the slab, because it composes from the door's Draw.
	opened = run_steps(on_every_pickup(new_game(test_meshes, 1)), idle, 30, 0.1)
	with_child = { ..opened, entities: List.append(opened.entities, entity_at(50, Child(1), { x: 0.0, y: 2.0, z: 0.0 }, 0.0)) }
	draw_of(view(with_child), 50).map_ok(|d| near(d.pos.y, 1.5 + door_height + 2.0)) ?? Bool.False
}

expect {
	# Sweep drops a dead entity, then every descendant of it in the same pass.
	dead = { ..entity_at(10, Root, origin, 0.0), alive: Bool.False }
	swept = sweep(
		with_entities(
			[
				dead,
				entity_at(11, Child(10), origin, 0.0),
				entity_at(12, Child(11), origin, 0.0),
				entity_at(13, Root, origin, 0.0),
				entity_at(14, Child(13), origin, 0.0),
			],
		),
	)
	swept.entities.map(|e| e.id) == [13, 14]
}

expect {
	# Sparks orbit the player at orbit_radius and orbit_height, and turn with it.
	sparked = step(on_every_pickup(new_game(test_meshes, 1)), idle, 1.0 / 120.0)
	offsets = |m| {
		scene = view(m)
		p = draw_of(scene, 0).map_ok(|d| d.pos) ?? origin
		List.keep_if(scene.draws, |d| d.id >= 3 and d.id < m.next_id).map(|d| { x: d.pos.x - p.x, y: d.pos.y - p.y, z: d.pos.z - p.z })
	}
	on_orbit = |o| near(o.x * o.x + o.z * o.z, orbit_radius * orbit_radius) and near(o.y, orbit_height)
	still = offsets(sparked)
	turned = offsets(facing(sparked, pi / 2.0))
	rotated = List.map2(still, turned, |a, b| near_vec(b, { x: a.z, y: a.y, z: -a.x }))
	List.len(still) == sparks_per_pickup and List.all(still, on_orbit) and List.all(rotated, |ok| ok)
}

expect {
	# A spark moves round its orbit at orbit_speed.
	sparked = step(on_every_pickup(new_game(test_meshes, 1)), idle, 1.0 / 120.0)
	later = step(sparked, idle, 0.1)
	angle_of = |m| List.find_first(m.entities, |e| e.id == 3).map_ok(|e| F32.atan2({ x: e.pos.x, y: e.pos.z })) ?? -100.0
	near(wrap_angle(angle_of(later) - angle_of(sparked)), orbit_speed * 0.1)
}
