app [init, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-27-a3ce7f1", cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Config, Draw, Input, Scene, Vec3]
import pf.Key

# ---- Types only Roc reads. The host carries Model through untouched. -----

Kind : [Player, Pickup, Door({ open : Bool, lift : F32 }), Spark({ age : F32, phase : F32 })]

Entity : { id : U64, kind : Kind, pos : Vec3, vel : Vec3, yaw : F32, alive : Bool }

# The ids this game resolved from the manifest at init. Resolved once, kept
# in the Model, never looked up per step.
MeshIds : { cube : U32, sphere : U32, plane : U32, sprout : U32 }

# next_id only grows, so an id is never reused and the host never pairs a
# new entity with a dead one.
Model : { steps : U64, score : U64, next_id : U64, meshes : MeshIds, entities : List(Entity) }

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
	player = { id: 0, kind: Player, pos: origin, vel: origin, yaw: 0.0, alive: Bool.True }
	door = { id: 1, kind: Door({ open: Bool.False, lift: 0.0 }), pos: { x: 0.0, y: 1.5, z: -8.0 }, vel: origin, yaw: 0.0, alive: Bool.True }

	var $pickups = List.with_capacity(pickups)
	var $i = 0
	while $i < pickups {
		angle = ($i.to_f32()) * 6.2832 / (pickups.to_f32())
		pos = { x: 4.0 * angle.cos(), y: 0.5, z: 4.0 * angle.sin() }
		$pickups = List.append($pickups, { id: 2 + $i, kind: Pickup, pos, vel: origin, yaw: 0.0, alive: Bool.True })
		$i = $i + 1
	}

	{ steps: 0, score: 0, next_id: 2 + pickups, meshes, entities: List.concat([player, door], $pickups) }
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
		|> open_door
		|> raise_door(dt)
		|> sweep
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
		spawn_sparks({ ..m, score: m.score + gained, entities }, p.pos, gained * sparks_per_pickup)
	}
}

sparks_per_pickup : U64
sparks_per_pickup = 6

# Seconds.
spark_life : F32
spark_life = 1.0

spawn_sparks : Model, Vec3, U64 -> Model
spawn_sparks = |m, at, count| {
	var $entities = List.reserve(m.entities, count)
	var $i = 0
	while $i < count {
		phase = ($i % sparks_per_pickup).to_f32() * 2.0 * pi / sparks_per_pickup.to_f32()
		$entities = List.append($entities, { id: m.next_id + $i, kind: Spark({ age: 0.0, phase }), pos: at, vel: origin, yaw: 0.0, alive: Bool.True })
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

# keep_if allocates even when it keeps everything, so skip it on a quiet step.
sweep : Model -> Model
sweep = |m|
	if List.all(m.entities, |e| e.alive) {
		m
	} else {
		{ ..m, entities: List.keep_if(m.entities, |e| e.alive) }
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
	first = List.with_capacity(List.len(curr.entities) + 1).append(floor)
	draws = List.fold(curr.entities, first, |acc, e| acc.append(draw(curr.meshes, e)))

	target = match player(curr) {
		Ok(p) => p.pos
		Err(NotFound) => origin
	}

	{ camera: Cam.follow(target, camera_offset), draws }
}

draw : MeshIds, Entity -> Draw
draw = |meshes, e| {
	pos = e.pos
	yaw = e.yaw
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
