app [init, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-27-a3ce7f1", cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Config, Contact, Draw, Input, Scene, Vec3]
import pf.Collider
import pf.Key

# ---- Types only Roc reads. The host carries Model through untouched. -----

Kind : [Player, Pickup, Door({ open : Bool, lift : F32 }), Drop({ age : F32, phase : F32, delay : F32 })]

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

# ---- step : Model, Input, List(Contact), F32 -> Model -------------------
#
# The schedule is function composition. Each stage is Model -> Model and
# testable alone. Reorder the pipeline and you reorder the stages.

step : Model, Input, List(Contact), F32 -> Model
step = |model, input, contacts, dt|
	model
		|> steer(input)
		|> face(dt)
		|> block(contacts)
		|> integrate(dt)
		|> spin(dt)
		|> expire(dt)
		|> collect(contacts)
		|> fall
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

# Contacts come from the last Scene, so block runs before integrate moves the
# player. The host orders a contact by id, so the player can be a or b.
block : Model, List(Contact) -> Model
block = |m, contacts|
	if List.is_empty(contacts) {
		m
	} else {
		match player(m) {
			Err(NotFound) => m
			Ok(p) => {
				is_door_id = |id| List.any(m.entities, |e| e.id == id and is_door(e))
				moved = List.fold(contacts, p, |acc, c| push_out(acc, c, is_door_id))
				map_entities(
					m,
					|e| if e.id == p.id {
						moved
					} else {
						e
					},
				)
			}
		}
	}

push_out : Entity, Contact, (U64 -> Bool) -> Entity
push_out = |e, c, is_door_id| match seen_from(c, e.id) {
	Ok(side) if is_door_id(side.other) => {
		away = scale(side.normal, -1.0)
		into = dot(e.vel, away)
		vel = if into < 0.0 {
			add(e.vel, scale(away, -into))
		} else {
			e.vel
		}
		{ ..e, pos: add(e.pos, scale(away, c.depth)), vel }
	}
	_ => e
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

collect : Model, List(Contact) -> Model
collect = |m, contacts|
	if List.is_empty(contacts) {
		m
	} else {
		match player(m) {
			Err(NotFound) => m
			Ok(p) => {
				touched = |e| is_pickup(e) and e.alive and List.any(contacts, |c| seen_from(c, p.id).map_ok(|side| side.other == e.id) ?? Bool.False)
				gained = List.count_if(m.entities, touched)
				if gained == 0 {
					return m
				}
				gone = map_entities(
					m,
					|e| if touched(e) {
						{ ..e, alive: Bool.False }
					} else {
						e
					},
				)
				spawn_drops({ ..gone, score: m.score + gained }, p.id, gained * drops_per_pickup)
			}
		}
	}

drops_per_pickup : U64
drops_per_pickup = 6

# Seconds.
drop_life : F32
drop_life = 1.0

# Seconds each drop waits before it falls, out of ring order so the drops do
# not fall round the ring in turn.
drop_delays : List(F32)
drop_delays = [0.0, 0.32, 0.12, 0.45, 0.22, 0.38]

spawn_drops : Model, U64, U64 -> Model
spawn_drops = |m, parent, count| {
	var $entities = List.reserve(m.entities, count)
	var $i = 0
	while $i < count {
		slot = $i % drops_per_pickup
		phase = slot.to_f32() * 2.0 * pi / drops_per_pickup.to_f32()
		delay = List.get(drop_delays, slot) ?? 0.0
		$entities = List.append($entities, { id: m.next_id + $i, kind: Drop({ age: 0.0, phase, delay }), parent: Child(parent), pos: origin, vel: origin, yaw: 0.0, alive: Bool.True })
		$i = $i + 1
	}
	{ ..m, next_id: m.next_id + count, entities: $entities }
}

# A block arm that set age and alive together allocated on every step under
# --opt=dev, even with no drops. The guard does not.
expire : Model, F32 -> Model
expire = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Drop(s) if s.age + dt >= s.delay + drop_life => { ..e, alive: Bool.False }
		Drop(s) => { ..e, kind: Drop({ ..s, age: s.age + dt }) }
		_ => e
	},
)

# Drops start in a ring above the sprout's crown and land on the soil in its pot.
drop_start_radius : F32
drop_start_radius = 0.35

drop_start_height : F32
drop_start_height = 1.6

drop_land_radius : F32
drop_land_radius = 0.1

drop_land_height : F32
drop_land_height = 0.52

fall : Model -> Model
fall = |m| map_entities(
	m,
	|e| match e.kind {
		Drop(d) => { ..e, pos: drop_offset(d.phase, F32.max(d.age - d.delay, 0.0)) }
		_ => e
	},
)

# The height falls with the square of time, as under gravity.
drop_offset : F32, F32 -> Vec3
drop_offset = |phase, age| {
	t = age / drop_life
	radius = drop_start_radius + (drop_land_radius - drop_start_radius) * t
	{ x: radius * phase.cos(), y: drop_start_height - (drop_start_height - drop_land_height) * t * t, z: radius * phase.sin() }
}

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

	# One allocation for the draws and one for the colliders. A parent
	# precedes its child, so the parent's Draw is already in acc.
	first = {
		draws: List.with_capacity(List.len(curr.entities) + 1).append(floor),
		colliders: List.with_capacity(List.len(curr.entities)),
	}
	built = List.fold(
		curr.entities,
		first,
		|acc, e| {
			world = match e.parent {
				Root => { pos: e.pos, yaw: e.yaw }
				Child(parent) => match List.find_first(acc.draws, |d| d.id == parent) {
					Ok(p) => { pos: add(p.pos, rotate_y(e.pos, p.yaw)), yaw: p.yaw + e.yaw }
					Err(NotFound) => { pos: e.pos, yaw: e.yaw }
				}
			}
			if waiting(e) {
				acc
			} else {
				{ draws: acc.draws.append(draw(curr.meshes, e, world)), colliders: with_collider(acc.colliders, e, world) }
			}
		},
	)

	target = match player(curr) {
		Ok(p) => p.pos
		Err(NotFound) => origin
	}

	{ camera: Cam.follow(target, camera_offset), draws: built.draws, colliders: built.colliders }
}

draw : MeshIds, Entity, { pos : Vec3, yaw : F32 } -> Draw
draw = |meshes, e, world| {
	pos = world.pos
	yaw = world.yaw
	match e.kind {
		Player => { id: e.id, mesh: meshes.sprout, pos, scale: one, yaw, tint: { r: 1.0, g: 1.0, b: 1.0 } }
		Pickup => { id: e.id, mesh: meshes.cube, pos, scale: scale(one, 0.4), yaw, tint: { r: 0.033, g: 0.787, b: 0.133 } }
		Drop(_) => { id: e.id, mesh: meshes.sphere, pos, scale: { x: 0.07, y: 0.1, z: 0.07 }, yaw, tint: { r: 0.02, g: 0.3, b: 1.0 } }
		Door(d) => {
			lifted = { ..pos, y: pos.y + d.lift }
			{ id: e.id, mesh: meshes.cube, pos: lifted, scale: { x: 3.0, y: 3.0, z: 0.3 }, yaw, tint: { r: 0.214, g: 0.073, b: 0.604 } }
		}
	}
}

# The player's box sits on its feet.
player_half : Vec3
player_half = { x: 0.3, y: 0.5, z: 0.3 }

door_half : Vec3
door_half = { x: 1.5, y: 1.5, z: 0.15 }

pickup_radius : F32
pickup_radius = 0.4

# Floor and drops touch nothing.
with_collider : List(Vocabulary.Collider), Entity, { pos : Vec3, yaw : F32 } -> List(Vocabulary.Collider)
with_collider = |colliders, e, world| match e.kind {
	Player => colliders.append(Collider.box(e.id, { ..world.pos, y: world.pos.y + player_half.y }, world.yaw, player_half))
	Pickup => colliders.append(Collider.sphere(e.id, world.pos, pickup_radius))
	Door(d) => colliders.append(Collider.box(e.id, { ..world.pos, y: world.pos.y + d.lift }, world.yaw, door_half))
	Drop(_) => colliders
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

# A drop is not drawn until its delay ends.
waiting : Entity -> Bool
waiting = |e| match e.kind {
	Drop(d) => d.age < d.delay
	_ => Bool.False
}

# The normal of the result points from id to the other entity.
seen_from : Contact, U64 -> Try({ other : U64, normal : Vec3 }, [NotInContact])
seen_from = |c, id|
	if c.a == id {
		Ok({ other: c.b, normal: c.normal })
	} else if c.b == id {
		Ok({ other: c.a, normal: scale(c.normal, -1.0) })
	} else {
		Err(NotInContact)
	}

is_door : Entity -> Bool
is_door = |e| match e.kind {
	Door(_) => Bool.True
	_ => Bool.False
}

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

dot : Vec3, Vec3 -> F32
dot = |a, b| a.x * b.x + a.y * b.y + a.z * b.z

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
		$m = step($m, input, [], dt)
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
	moved = step(new_game(test_meshes, 0), right, [], 0.05)
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
	turned = step(m, { ..idle, held: [Key.code(W), Key.code(A)] }, [], 0.05)
	yaw_of(turned) > 0.75 * pi
}

expect {
	# Touching every pickup collects every pickup and opens the door in one step.
	after = collected(new_game(test_meshes, 2), 1.0 / 120.0)
	after.score == 2 and door_open(after) and List.len(after.entities) == 2 + 2 * drops_per_pickup
}

touch : U64, U64 -> Contact
touch = |a, b| { a, b, normal: { x: 1.0, y: 0.0, z: 0.0 }, depth: 0.1 }

is_drop : Entity -> Bool
is_drop = |e| match e.kind {
	Drop(_) => Bool.True
	_ => Bool.False
}

drop_count : Model -> U64
drop_count = |m| List.count_if(m.entities, is_drop)

expect {
	# Each collected pickup spawns its drops, and the pickup is swept.
	after = step(new_game(test_meshes, 3), idle, [touch(0, 2)], 1.0 / 120.0)
	drop_count(after) == drops_per_pickup and List.count_if(after.entities, is_pickup) == 2
}

expect {
	# New ids start past the last pickup, only grow, and are never reused.
	m = new_game(test_meshes, 2)
	after = collected(m, 1.0 / 120.0)
	drop_ids = List.keep_if(after.entities, is_drop).map(|e| e.id)
	fresh = List.all(drop_ids, |id| id >= m.next_id and id < after.next_id)
	distinct = List.all(drop_ids, |id| List.count_if(drop_ids, |other| other == id) == 1)
	m.next_id == 4 and after.next_id == m.next_id + 2 * drops_per_pickup and fresh and distinct
}

expect {
	# A drop lives for its delay plus drop_life, then sweep drops it. The
	# delays differ, so the drops die one after another.
	watered = collected(new_game(test_meshes, 1), 0.1)
	before = run_steps(watered, idle, 8, 0.1)
	some = run_steps(before, idle, 3, 0.1)
	after = run_steps(some, idle, 5, 0.1)
	partly = drop_count(some) > 0 and drop_count(some) < drops_per_pickup
	drop_count(watered) == drops_per_pickup and drop_count(before) == drops_per_pickup and partly and drop_count(after) == 0
}

drawn_drops : Model -> U64
drawn_drops = |m| List.count_if(view(m).draws, |d| d.id >= 3 and d.id < m.next_id)

expect {
	# Drops wait for their delays, so they appear one after another.
	watered = collected(new_game(test_meshes, 1), 1.0 / 120.0)
	soon = run_steps(watered, idle, 2, 0.1)
	later = run_steps(soon, idle, 3, 0.1)
	drawn_drops(watered) == 1 and drawn_drops(soon) > 1 and drawn_drops(soon) < drops_per_pickup and drawn_drops(later) == drops_per_pickup
}

expect {
	# Pickups are cubes so the spin shows. Drops are small spheres.
	watered = run_steps(collected(new_game(test_meshes, 2), 0.1), idle, 5, 0.1)
	scene = view(watered)
	pickup_mesh = List.find_first(view(new_game(test_meshes, 1)).draws, |d| d.id == 2).map_ok(|d| d.mesh) ?? 0
	drop_draws = List.keep_if(scene.draws, |d| d.id >= 4 and d.id < watered.next_id)
	pickup_mesh == test_meshes.cube and List.len(drop_draws) == 2 * drops_per_pickup and List.all(drop_draws, |d| d.mesh == test_meshes.sphere)
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

# One idle step on which the player touches every live pickup.
collected : Model, F32 -> Model
collected = |m, dt| {
	contacts = List.keep_if(m.entities, |e| is_pickup(e) and e.alive).map(|e| touch(0, e.id))
	step(m, idle, contacts, dt)
}

expect {
	# The door starts to rise on the step it opens, at door_speed.
	after = collected(new_game(test_meshes, 2), 0.1)
	near(door_lift(after), door_speed * 0.1) and near(door_draw_y(after), 1.5 + door_speed * 0.1)
}

expect {
	# Given time, the door stops at door_height.
	after = run_steps(collected(new_game(test_meshes, 2), 0.1), idle, 29, 0.1)
	near(door_lift(after), door_height) and near(door_draw_y(after), 1.5 + door_height)
}

expect {
	# A shut door does not rise.
	after = run_steps(new_game(test_meshes, 2), idle, 30, 0.1)
	door_lift(after) == 0.0 and near(door_draw_y(after), 1.5)
}

expect {
	# Nothing touched: the door stays shut and nothing is swept.
	after = step(new_game(test_meshes, 4), idle, [], 1.0 / 120.0)
	after.score == 0 and !door_open(after) and List.len(after.entities) == 6
}

expect {
	# step is pure. The same Model and Input give the same step count and score,
	# which is what makes a recorded input log a replay.
	m = new_game(test_meshes, 4)
	a = step(m, right, [], 0.5)
	b = step(m, right, [], 0.5)
	a.steps == b.steps and a.score == b.score
}

expect {
	# view carries the entity id onto its draw, so the host can pair this
	# step's draw with the last one. The floor's id never collides.
	m = new_game(test_meshes, 1)
	scene = view(step(m, right, [], 1.0))
	player_draw = List.find_first(scene.draws, |d| d.id == 0)
	ids_unique = List.len(scene.draws) == 4 and List.count_if(scene.draws, |d| d.id == floor_id) == 1
	match player_draw {
		Ok(d) => d.pos.x == 6.0 and ids_unique
		Err(_) => Bool.False
	}
}

collider_of : Scene, U64 -> Try(Vocabulary.Collider, [NotFound])
collider_of = |scene, id| List.find_first(scene.colliders, |c| c.id == id)

expect {
	# The player stands on a box, the door is a thin box and a pickup is a sphere.
	# The floor has no collider.
	scene = view(new_game(test_meshes, 1))
	player_box = collider_of(scene, 0) == Ok(Collider.box(0, { x: 0.0, y: 0.5, z: 0.0 }, 0.0, player_half))
	door_box = collider_of(scene, 1) == Ok(Collider.box(1, { x: 0.0, y: 1.5, z: -8.0 }, 0.0, door_half))
	pickup_sphere = collider_of(scene, 2) == Ok(Collider.sphere(2, { x: 4.0, y: 0.5, z: 0.0 }, pickup_radius))
	player_box and door_box and pickup_sphere and List.len(scene.colliders) == 3
}

expect {
	# The player's box turns with the player.
	scene = view(facing(new_game(test_meshes, 0), 1.0))
	collider_of(scene, 0).map_ok(|c| c.yaw) == Ok(1.0)
}

expect {
	# An open door lifts its collider out of the way with its draw.
	after = run_steps(collected(new_game(test_meshes, 2), 0.1), idle, 29, 0.1)
	collider_of(view(after), 1).map_ok(|c| near(c.pos.y, 1.5 + door_height)) == Ok(Bool.True)
}

expect {
	# Water drops touch nothing.
	watered = run_steps(collected(new_game(test_meshes, 2), 0.1), idle, 5, 0.1)
	scene = view(watered)
	drawn_drops(watered) > 0 and List.map(scene.colliders, |c| c.id) == [0, 1]
}

expect {
	# The camera follows the player from a fixed offset.
	scene = view(step(new_game(test_meshes, 1), right, [], 1.0))
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
	opened = run_steps(collected(new_game(test_meshes, 1), 0.1), idle, 29, 0.1)
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
	# A drop with no delay starts in a ring above the plant, and follows and turns with it.
	watered = collected(new_game(test_meshes, 1), 1.0 / 120.0)
	offsets = |m| {
		scene = view(m)
		p = draw_of(scene, 0).map_ok(|d| d.pos) ?? origin
		List.keep_if(scene.draws, |d| d.id >= 3 and d.id < m.next_id).map(|d| { x: d.pos.x - p.x, y: d.pos.y - p.y, z: d.pos.z - p.z })
	}
	on_ring = |o| near(o.x * o.x + o.z * o.z, drop_start_radius * drop_start_radius) and near(o.y, drop_start_height)
	still = offsets(watered)
	turned = offsets(facing(watered, pi / 2.0))
	rotated = List.map2(still, turned, |a, b| near_vec(b, { x: a.z, y: a.y, z: -a.x }))
	List.len(still) == 1 and List.all(still, on_ring) and List.all(rotated, |ok| ok)
}

expect {
	# A drop falls faster as it goes, and draws in to land on the soil at the end of its life.
	start = drop_offset(0.0, 0.0)
	half = drop_offset(0.0, drop_life / 2.0)
	end = drop_offset(0.0, drop_life)
	first_half = start.y - half.y
	second_half = half.y - end.y
	half.x < start.x and second_half > first_half and near_vec(end, { x: drop_land_radius, y: drop_land_height, z: 0.0 })
}

placed : Model, Vec3 -> Model
placed = |m, pos| map_entities(
	m,
	|e| match e.kind {
		Player => { ..e, pos }
		_ => e
	},
)

door_contact : F32 -> Contact
door_contact = |depth| { a: 0, b: 1, normal: { x: 0.0, y: 0.0, z: -1.0 }, depth }

expect {
	# A closed door pushes the player out by the depth and stops the walk into it. The walk along it goes on.
	m = placed(new_game(test_meshes, 0), { x: 0.0, y: 0.0, z: -7.6 })
	after = step(m, { ..idle, held: [Key.code(W), Key.code(D)] }, [door_contact(0.1)], 0.1)
	match player(after) {
		Ok(p) => near_vec(p.pos, { x: 0.6, y: 0.0, z: -7.5 }) and p.vel.z == 0.0
		Err(_) => Bool.False
	}
}

expect {
	# A player that walks away from the door keeps its speed.
	m = placed(new_game(test_meshes, 0), { x: 0.0, y: 0.0, z: -7.6 })
	after = step(m, { ..idle, held: [Key.code(S)] }, [door_contact(0.1)], 0.1)
	player(after).map_ok(|p| near(p.pos.z, -6.9)) ?? Bool.False
}

expect {
	# A contact collects a pickup. Distance alone does not: pickup 2 sits on the player
	# with no contact, and pickup 3 is far away with one.
	m = map_entities(
		new_game(test_meshes, 3),
		|e| if e.id == 2 {
			{ ..e, pos: origin }
		} else {
			e
		},
	)
	after = step(m, idle, [touch(0, 3)], 1.0 / 120.0)
	alive_pickups = List.keep_if(after.entities, is_pickup).map(|e| e.id)
	after.score == 1 and alive_pickups == [2, 4]
}

expect {
	# A contact with the door collects nothing.
	after = step(new_game(test_meshes, 1), idle, [touch(0, 1)], 1.0 / 120.0)
	after.score == 0 and List.count_if(after.entities, is_pickup) == 1
}

door_gap : Scene -> F32
door_gap = |scene|
	match (collider_of(scene, 0), collider_of(scene, 1)) {
		(Ok(p), Ok(d)) => (d.pos.y - door_half.y) - (p.pos.y + player_half.y)
		_ => -100.0
	}

expect {
	# A shut door reaches the player. An open door rises clear of the player's box,
	# so the host finds no contact and the player walks through under it.
	shut = new_game(test_meshes, 1)
	opened = run_steps(collected(shut, 0.1), idle, 29, 0.1)
	at_door = placed(opened, { x: 0.0, y: 0.0, z: -7.6 })
	through = run_steps(at_door, { ..idle, held: [Key.code(W)] }, 2, 0.1)
	walked = player(through).map_ok(|p| near(p.pos.z, -8.8)) ?? Bool.False
	door_gap(view(shut)) < 0.0 and door_gap(view(opened)) > 0.0 and walked
}
