app [init, step, view] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47", cam: "../../packages/camera/main.roc" }

import cam.Camera as Cam

# ---- Types the host reads. The glue emits their Odin layout. -------------

Vec3 : { x : F32, y : F32, z : F32 }

Rgb : { r : F32, g : F32, b : F32 }

# The host builds one Input per fixed step: held keys as levels, pressed
# keys as edges (lesson 4), and the mouse delta. Roc never asks the host
# anything. Which key means what is this game's decision, below.
Input : { held : List(U16), pressed : List(U16), mouse : { dx : F32, dy : F32 } }

# A mesh is an id the engine assigned. Config carries the name-to-id manifest.
# The draw id is stable across steps so the host can pair this step's draw
# with the last one and interpolate. Entities use their own id; fixed scenery
# uses ids the entities never reach.
Draw : { id : U64, mesh : U32, pos : Vec3, scale : Vec3, yaw : F32, tint : Rgb }

Config : { seed : U64, meshes : List({ name : Str, id : U32 }) }

# What the host renders. Rebuilt every step, never stored. Derived, not authored.
Scene : { camera : Cam.View, draws : List(Draw) }

# ---- Types only Roc reads. The host carries Model through untouched. -----

Kind : [Player, Pickup, Door({ open : Bool })]

Entity : { id : U64, kind : Kind, pos : Vec3, vel : Vec3, yaw : F32, alive : Bool }

# The ids this game resolved from the manifest at init. Resolved once, kept
# in the Model, never looked up per frame.
Meshes : { cube : U32, sphere : U32, slab : U32 }

Model : { tick : U64, score : U64, meshes : Meshes, entities : List(Entity) }

# ---- init : Config -> Model ---------------------------------------------
#
# Config is the engine's: a seed and the mesh manifest, nothing about this
# game. How many pickups a round has, and which mesh is a pickup, is decided
# here.

init : Config -> Model
init = |config| new_game(resolve_meshes(config), 8)

# 0 is the engine's fallback mesh, so a misspelt name is visible, not fatal.
mesh_id : Config, Str -> U32
mesh_id = |config, name| match List.find_first(config.meshes, |m| m.name == name) {
	Ok(m) => m.id
	Err(NotFound) => 0
}

resolve_meshes : Config -> Meshes
resolve_meshes = |config| {
	cube: mesh_id(config, "cube"),
	sphere: mesh_id(config, "sphere"),
	slab: mesh_id(config, "slab"),
}

new_game : Meshes, U64 -> Model
new_game = |meshes, pickups| {
	player = { id: 0, kind: Player, pos: origin, vel: origin, yaw: 0.0, alive: Bool.True }
	door = { id: 1, kind: Door({ open: Bool.False }), pos: { x: 0.0, y: 1.5, z: -8.0 }, vel: origin, yaw: 0.0, alive: Bool.True }

	var $pickups = List.with_capacity(pickups)
	var $i = 0
	while $i < pickups {
		angle = ($i.to_f32()) * 6.2832 / (pickups.to_f32())
		pos = { x: 4.0 * angle.cos(), y: 0.5, z: 4.0 * angle.sin() }
		$pickups = List.append($pickups, { id: 2 + $i, kind: Pickup, pos, vel: origin, yaw: 0.0, alive: Bool.True })
		$i = $i + 1
	}

	{ tick: 0, score: 0, meshes, entities: List.concat([player, door], $pickups) }
}

# ---- step : Model, Input, F32 -> Model ---------------------------------
#
# The schedule is function composition. Each stage is Model -> Model and
# testable alone. Reorder the pipeline and you reorder the systems.

step : Model, Input, F32 -> Model
step = |model, input, dt|
	model
		|> steer(input)
		|> integrate(dt)
		|> spin(dt)
		|> collect
		|> open_door
		|> sweep
		|> tick

speed : F32
speed = 6.0

# The binding from keys to intent lives in the game, not the engine.
key_w : U16
key_w = 87

key_a : U16
key_a = 65

key_s : U16
key_s = 83

key_d : U16
key_d = 68

axis : Input, U16, U16 -> F32
axis = |input, neg, pos| {
	n = if List.contains(input.held, neg) {
		1.0
	} else {
		0.0
	}
	p = if List.contains(input.held, pos) {
		1.0
	} else {
		0.0
	}
	p - n
}

move_dir : Input -> Vec3
move_dir = |input| { x: axis(input, key_a, key_d), y: 0.0, z: axis(input, key_w, key_s) }

steer : Model, Input -> Model
steer = |m, input| map_entities(
	m,
	|e| match e.kind {
		Player => { ..e, vel: scale(move_dir(input), speed) }
		_ => e
	},
)

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
		entities = List.map(
			m.entities,
			|e| if touched(e) {
				{ ..e, alive: Bool.False }
			} else {
				e
			},
		)
		{ ..m, score: m.score + gained, entities }
	}
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
				Door(_) => { ..e, kind: Door({ open: Bool.True }) }
				_ => e
			},
		)
	}
}

sweep : Model -> Model
sweep = |m| { ..m, entities: List.keep_if(m.entities, |e| e.alive) }

tick : Model -> Model
tick = |m| { ..m, tick: m.tick + 1 }

# ---- view : Model -> Scene -------------------------------------------------
#
# Runs once per fixed step, after step. It sees one Model and no alpha. The
# host holds this Scene and the previous one and interpolates between draws
# with the same id at render time. That keeps the Model's refcount at one,
# so step mutates in place and nothing is copied to remember the past.

floor_id : U64
floor_id = 1_000_000

camera_offset : Vec3
camera_offset = { x: 0.0, y: 8.0, z: 8.0 }

view : Model -> Scene
view = |curr| {
	floor = { id: floor_id, mesh: curr.meshes.slab, pos: { x: 0.0, y: -0.05, z: 0.0 }, scale: { x: 20.0, y: 0.1, z: 20.0 }, yaw: 0.0, tint: { r: 0.25, g: 0.25, b: 0.28 } }

	draws = List.map(curr.entities, |e| draw(curr.meshes, e))

	target = match player(curr) {
		Ok(p) => p.pos
		Err(NotFound) => origin
	}

	{ camera: Cam.follow(target, camera_offset), draws: List.concat([floor], draws) }
}

draw : Meshes, Entity -> Draw
draw = |meshes, e| {
	pos = e.pos
	yaw = e.yaw
	match e.kind {
		Player => { id: e.id, mesh: meshes.cube, pos, scale: one, yaw, tint: { r: 0.9, g: 0.6, b: 0.2 } }
		Pickup => { id: e.id, mesh: meshes.sphere, pos, scale: scale(one, 0.4), yaw, tint: { r: 0.2, g: 0.9, b: 0.4 } }
		Door({ open }) => {
			lifted = if open {
				{ ..pos, y: pos.y + 3.0 }
			} else {
				pos
			}
			{ id: e.id, mesh: meshes.slab, pos: lifted, scale: { x: 3.0, y: 3.0, z: 0.3 }, yaw, tint: { r: 0.5, g: 0.3, b: 0.8 } }
		}
	}
}

# ---- helpers -------------------------------------------------------------

map_entities : Model, (Entity -> Entity) -> Model
map_entities = |m, f| { ..m, entities: List.map(m.entities, f) }

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
		Door({ open }) => open
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

dist2 : Vec3, Vec3 -> F32
dist2 = |a, b| {
	d = { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }
	d.x * d.x + d.y * d.y + d.z * d.z
}

# ---- tests. `roc test main.roc` runs these with no engine. ----------------

# What the engine would hand init on this machine.
manifest : Config
manifest = { seed: 0, meshes: [{ name: "cube", id: 1 }, { name: "sphere", id: 2 }, { name: "slab", id: 3 }] }

test_meshes : Meshes
test_meshes = resolve_meshes(manifest)

idle : Input
idle = { held: [], pressed: [], mouse: { dx: 0.0, dy: 0.0 } }

right : Input
right = { ..idle, held: [key_d] }

expect {
	m = new_game(test_meshes, 3)
	List.len(m.entities) == 5 and m.score == 0
}

expect {
	# A name the engine did not load resolves to the fallback id, never crashes.
	mesh_id(manifest, "sphere") == 2 and mesh_id(manifest, "dragon") == 0
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
	after.score == 2 and door_open(after) and List.len(after.entities) == 2
}

expect {
	# Nothing touched: the door stays shut and nothing is swept.
	after = step(new_game(test_meshes, 4), idle, 1.0 / 120.0)
	after.score == 0 and !door_open(after) and List.len(after.entities) == 6
}

expect {
	# step is pure. The same Model and Input give the same tick and score,
	# which is what makes a recorded input log a replay.
	m = new_game(test_meshes, 4)
	a = step(m, right, 0.5)
	b = step(m, right, 0.5)
	a.tick == b.tick and a.score == b.score
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
	scene.camera.target.x == 6.0 and scene.camera.eye.x == 6.0 and scene.camera.eye.y == 8.0
}
