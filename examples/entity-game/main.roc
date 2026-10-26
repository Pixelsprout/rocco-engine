app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# The guide pages copy the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import linalg.Vec3 as V
import linalg.Quat
import linalg.Pose
import pf.Vocabulary exposing [Command, Contact, Manifest, Vec3]
import pf.Config
import pf.Draw
import pf.Input
import pf.Launch
import pf.Scene
import pf.Collider
import pf.Key
import pf.Light
import pf.Query
import pf.QueryResults

# ---- Types only Roc reads. The host carries Model through untouched. -----

Kind : [Player({ grounded : Bool }), Pickup, Block, Goal, Door({ open : Bool, lift : F32 }), Drop({ age : F32, phase : F32, delay : F32 })]

# pos and yaw are local to the parent. A parent precedes its children in the
# entity list: a child spawns later and append places it later. Reparenting to
# a younger entity is the one way to break that.
Entity : { id : U64, kind : Kind, parent : [Root, Child(U64)], pos : Vec3, vel : Vec3, yaw : F32, alive : Bool }

# The ids this game resolved from the Manifest in loaded. Resolved once, kept
# in the Model, never looked up per step.
MeshIds : { cube : U32, sphere : U32, plane : U32, sprout : U32, sky : U32 }

# next_id only grows, so an id is never reused and the host never pairs a
# new entity with a dead one.
# Won holds the seconds since the win.
Phase : [Playing, Won(F32)]

# The player's shadow sits on ground_below, the height its ground ray last hit.
Model : { steps : U64, score : U64, next_id : U64, phase : Phase, meshes : MeshIds, entities : List(Entity), orphans_logged : List(U64), ground_below : F32 }

# An entity and its index in the entity list.
Slot : { entity : Entity, index : U64 }

# region: launch
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| Launch.default

# endregion

# ---- init : Config -> { model, commands } -------------------------------
#
# Config is the engine's: a seed and the asset names on disk, nothing about
# this game. How many pickups a round has, and which mesh is a pickup, is
# decided here. The host runs the Load and calls loaded before the first view.

# region: load
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: new_game(primitive_meshes, round_pickups, 0), commands: [Load({ pack: "sprout", assets: ["sprout", sky_name] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, meshes: resolve_meshes(manifest) }

sky_name : Str
sky_name = "sky/meadow"

# sprout is 0, the fallback, until loaded. A sky of 0 draws no sky.
primitive_meshes : MeshIds
primitive_meshes = {
	cube: Mesh.primitive(Cube),
	sphere: Mesh.primitive(Sphere),
	plane: Mesh.primitive(Plane),
	sprout: 0,
	sky: 0,
}

resolve_meshes : Manifest -> MeshIds
resolve_meshes = |manifest| { ..primitive_meshes, sprout: Mesh.resolve(manifest, "sprout"), sky: Mesh.resolve(manifest, sky_name) }

# endregion

# Fills the first `pickups` pickup spots.
new_game : MeshIds, U64, U64 -> Model
new_game = |meshes, pickups, first_id| {
	player_entity = { id: first_id, kind: Player({ grounded: Bool.True }), parent: Root, pos: V.zero, vel: V.zero, yaw: 0.0, alive: Bool.True }
	door = { id: first_id + 1, kind: Door({ open: Bool.False, lift: 0.0 }), parent: Root, pos: { x: 0.0, y: 1.5, z: -8.0 }, vel: V.zero, yaw: 0.0, alive: Bool.True }
	block_entity = { id: first_id + 2 + pickups, kind: Block, parent: Root, pos: block_pos, vel: V.zero, yaw: 0.0, alive: Bool.True }
	goal = { id: first_id + 3 + pickups, kind: Goal, parent: Root, pos: goal_pos, vel: V.zero, yaw: 0.0, alive: Bool.True }

	pickup = |i| { id: first_id + 2 + i, kind: Pickup, parent: Root, pos: pickup_spot(i), vel: V.zero, yaw: 0.0, alive: Bool.True }
	entities = List.join([[player_entity, door], (0..<pickups).iter().map(pickup).collect(), [block_entity, goal]])

	{ steps: 0, score: 0, next_id: first_id + 4 + pickups, phase: Playing, meshes, entities, orphans_logged: [], ground_below: 0.0 }
}

block_pos : Vec3
block_pos = { x: -4.5, y: 0.5, z: -4.0 }

# Behind the door. A box, not a plane, so it does not z-fight the floor.
goal_pos : Vec3
goal_pos = { x: 0.0, y: 0.05, z: -9.2 }

arc_pickups : U64
arc_pickups = 7

round_pickups : U64
round_pickups = arc_pickups + 1

# The arc runs from the player's left to its right across the front half, so the
# camera sees every spot at the start. The last spot is on top of the block.
pickup_spot : U64 -> Vec3
pickup_spot = |i|
	if i < arc_pickups {
		angle = pi + i.to_f32() * pi / (arc_pickups - 1).to_f32()
		{ x: 4.0 * angle.cos(), y: 0.5, z: 4.0 * angle.sin() }
	} else {
		{ ..block_pos, y: block_pos.y + block_half.y + 0.5 }
	}

# ---- update : Model, Input, List(Contact), F32 -> Model -----------------
#
# The schedule is function composition. Each stage is Model -> Model and
# testable alone. Reorder the pipeline and you reorder the stages.

update : Model, Vocabulary.Input, List(Contact), F32 -> Model
update = |model, input, contacts, dt| {
	active_input = match model.phase {
		Playing => input
		Won(_) => Input.empty
	}
	model
		|> steer(active_input)
		|> jump(active_input)
		|> face(dt)
		|> gravity(dt)
		|> block(contacts)
		|> integrate(dt)
		|> ground
		|> spin(dt)
		|> expire(dt)
		|> collect(contacts)
		|> celebrate(dt)
		|> win(contacts)
		|> fall
		|> open_door
		|> raise_door(dt)
		|> sweep
		|> log_orphans
		|> count_step
		|> restart
}

# region: results
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| { model: update(model, input, results.contacts, dt) |> see_ground(results) |> magnet(results, dt), commands: quit_on_escape(input) }

# The floor has no collider, so a miss means the floor.
see_ground : Model, Vocabulary.QueryResults -> Model
see_ground = |m, results| match player(m) {
	Ok(p) => {
		ground_below = match QueryResults.ray(results, p.id) {
			Ok(hit) => hit.point.y
			Err(Miss) => 0.0
		}
		{ ..m, ground_below }
	}
	Err(NotFound) => m
}

magnet_radius : F32
magnet_radius = 2.0

# Units per second.
magnet_speed : F32
magnet_speed = 4.0

magnet : Model, Vocabulary.QueryResults, F32 -> Model
magnet = |m, results, dt| match player(m) {
	Ok(p) => {
		caught = QueryResults.overlaps(results, p.id, 0)
		if List.is_empty(caught) {
			m
		} else {
			map_entities(
				m,
				|e| if is_pickup(e) and List.contains(caught, e.id) {
					{ ..e, pos: toward(e.pos, player_middle(p), magnet_speed * dt) }
				} else {
					e
				},
			)
		}
	}
	Err(NotFound) => m
}

# endregion

# Moves at most max_step, so it stops at to.
toward : Vec3, Vec3, F32 -> Vec3
toward = |from, to, max_step| {
	gap = V.sub(to, from)
	dist = V.length(gap)
	if dist <= max_step {
		to
	} else {
		V.add(from, V.scale(gap, max_step / dist))
	}
}

# Seconds from the win to the next round.
celebration : F32
celebration = 4.0

# The new round's ids start at next_id, so the host pairs nothing across it.
restart : Model -> Model
restart = |m| match m.phase {
	Won(t) if t >= celebration => new_game(m.meshes, round_pickups, m.next_id)
	_ => m
}

speed : F32
speed = 6.0

# region: keys
# The game, not the engine, decides what each key means.
move_dir : Vocabulary.Input -> Vec3
move_dir = |input| { x: Key.axis(input, A, D), y: 0.0, z: Key.axis(input, W, S) }

# Reads the raw input, so ESC quits during the celebration too.
quit_on_escape : Vocabulary.Input -> List(Command)
quit_on_escape = |input|
	if Key.pressed(input, Escape) {
		[Quit]
	} else {
		[]
	}

# endregion

steer : Model, Vocabulary.Input -> Model
steer = |m, input| map_entities(
	m,
	|e| match e.kind {
		Player(_) => { ..e, vel: { ..V.scale(move_dir(input), speed), y: e.vel.y } }
		_ => e
	},
)

# Units per second, and units per second squared. The apex is about 1.2 units.
jump_speed : F32
jump_speed = 7.0

fall_accel : F32
fall_accel = 20.0

# region: jump
jump : Model, Vocabulary.Input -> Model
jump = |m, input|
	if Key.pressed(input, Space) {
		map_entities(
			m,
			|e| match e.kind {
				Player(p) if p.grounded => { ..e, kind: Player({ grounded: Bool.False }), vel: { ..e.vel, y: jump_speed } }
				_ => e
			},
		)
	} else {
		m
	}

# endregion

# Runs before block, so a solid under the player takes this pull back out.
gravity : Model, F32 -> Model
gravity = |m, dt| map_entities(
	m,
	|e| match e.kind {
		Player(_) => { ..e, vel: { ..e.vel, y: e.vel.y - fall_accel * dt } }
		_ => e
	},
)

# The floor has no collider. It is y 0 for the player.
ground : Model -> Model
ground = |m| map_entities(
	m,
	|e| match e.kind {
		Player(_) if e.pos.y <= 0.0 => { ..e, kind: Player({ grounded: Bool.True }), pos: { ..e.pos, y: 0.0 }, vel: { ..e.vel, y: F32.max(e.vel.y, 0.0) } }
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
		Player(_) if e.vel.x != 0.0 or e.vel.z != 0.0 => { ..e, yaw: turn_toward(e.yaw, F32.atan2({ x: e.vel.z, y: e.vel.x }), turn_speed * dt) }
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
# player. The host orders a contact by id, so the player can be a or b. A
# landing from above is the same push-out with a +y normal.
block : Model, List(Contact) -> Model
block = |m, contacts|
	if List.is_empty(contacts) {
		m
	} else {
		match player(m) {
			Err(NotFound) => m
			Ok(p) => {
				is_solid_id = |id| List.any(m.entities, |e| e.id == id and is_solid(e))
				moved = List.fold(contacts, p, |acc, c| push_out(acc, c, is_solid_id))
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

# A player that moves up off a solid is leaving it, so that contact does not ground it.
push_out : Entity, Contact, (U64 -> Bool) -> Entity
push_out = |e, c, is_solid_id| match seen_from(c, e.id) {
	Ok(side) if is_solid_id(side.other) => {
		away = V.scale(side.normal, -1.0)
		into = V.dot(e.vel, away)
		vel = if into < 0.0 {
			V.add(e.vel, V.scale(away, -into))
		} else {
			e.vel
		}
		kind = match e.kind {
			Player(_) if away.y > 0.0 and into <= 0.0 => Player({ grounded: Bool.True })
			k => k
		}
		{ ..e, kind, pos: V.add(e.pos, V.scale(away, c.depth)), vel }
	}
	_ => e
}

integrate : Model, F32 -> Model
integrate = |m, dt| map_entities(m, |e| { ..e, pos: V.add(e.pos, V.scale(e.vel, dt)) })

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
				touched = |e| is_pickup(e) and e.alive and touches(contacts, p.id, e.id)
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

# region: win
win : Model, List(Contact) -> Model
win = |m, contacts|
	match (m.phase, player(m)) {
		(Playing, Ok(p)) if List.any(m.entities, |e| e.kind == Goal and touches(contacts, p.id, e.id)) => { ..m, phase: Won(0.0) }
		_ => m
	}

# endregion

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
	spawned = |i| {
		slot = i % drops_per_pickup
		delay = List.get(drop_delays, slot) ?? 0.0
		drop(m.next_id + i, parent, ring_phase(slot), delay)
	}
	{ ..m, next_id: m.next_id + count, entities: m.entities.concat((0..<count).iter().map(spawned).collect()) }
}

drop : U64, U64, F32, F32 -> Entity
drop = |id, parent, phase, delay| { id, kind: Drop({ age: 0.0, phase, delay }), parent: Child(parent), pos: V.zero, vel: V.zero, yaw: 0.0, alive: Bool.True }

ring_phase : U64 -> F32
ring_phase = |slot| (slot % drops_per_pickup).to_f32() * 2.0 * pi / drops_per_pickup.to_f32()

# Seconds between drops after the win.
rain_every : F32
rain_every = 0.08

celebrate : Model, F32 -> Model
celebrate = |m, dt| match m.phase {
	Playing => m
	Won(t) => {
		advanced = { ..m, phase: Won(t + dt) }
		due = (t + dt).div_floor_by(rain_every) > t.div_floor_by(rain_every)
		match player(m) {
			Ok(p) if due => { ..advanced, next_id: m.next_id + 1, entities: List.append(m.entities, drop(m.next_id, p.id, ring_phase(m.steps), 0.0)) }
			_ => advanced
		}
	}
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
		swept = List.fold(
			m.entities,
			{ kept: [], dropped: [] },
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
# host holds this Scene and the previous one and interpolates between Draws
# with the same id, and Groups with the same Group id, when it draws a frame.
# That keeps the Model's refcount at one, so step mutates in place and nothing
# is copied to remember the past.

# region: scenery-id
# Scenery ids count down from the top, so next_id never reaches them.
floor_id : U64
floor_id = U64.highest

# endregion

camera_offset : Vec3
camera_offset = { x: 0.0, y: 1.5, z: 3.5 }

ambient : Vocabulary.Light
ambient = Light.ambient({ r: 0.2, g: 0.2, b: 0.2 })

# The BRDF divides diffuse light by pi, so 5.03 (1.6 pi) lights a white surface facing it to 1.6.
sun : Vocabulary.Light
sun = Light.sun({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })

pickup_light : Vec3 -> Vocabulary.Light
pickup_light = |pos| Light.point(pos, { r: 3.0, g: 1.5, b: 0.5 }, 3.0)

view : Model -> Vocabulary.Scene
view = |curr| {
	floor = { ..Draw.default, id: floor_id, mesh: curr.meshes.plane, scale: { x: 20.0, y: 1.0, z: 20.0 }, tint: { r: 0.051, g: 0.051, b: 0.064 } }

	# The engine keeps the first 8 directional and point lights, so the Sun goes before the Points.
	scenery = [
		Draw(floor),
		Light(ambient),
		Light(sun),
	]
	slots = List.map_with_index(curr.entities, |entity, index| { entity, index })
	roots = List.keep_if(slots, |slot| is_root(curr.entities, slot))
	entities = List.join_map(roots, |slot| entity_nodes(curr, slots, slot))

	target = match player(curr) {
		Ok(p) => p.pos
		Err(NotFound) => V.zero
	}

	# region: queries
	# Every Contact the game reads involves the player.
	queries = match player(curr) {
		Ok(p) => [Query.contacts_of(p.id), ground_ray(p), Query.overlap(p.id, Sphere(magnet_radius), player_middle(p))]
		Err(NotFound) => []
	}
	# endregion

	shadows = match player(curr) {
		Ok(p) => [Draw(shadow(curr, p))]
		Err(NotFound) => []
	}

	camera = match curr.phase {
		Playing => Cam.follow(target, camera_offset)
		Won(t) => Cam.look_at(orbit_eye(target, t), target)
	}

	{ ..Scene.empty, camera, nodes: List.join([scenery, entities, shadows]), sky: curr.meshes.sky, queries }
}

# region: tree
# A parent precedes its children in the entity list. An entity is a root when
# it has no parent, or when its parent is missing or comes later.
is_root : List(Entity), Slot -> Bool
is_root = |entities, slot| match slot.entity.parent {
	Root => Bool.True
	Child(parent) => match List.find_first_index(entities, |p| p.id == parent) {
		Ok(j) => j >= slot.index
		Err(_) => Bool.True
	}
}

# An entity with children, such as the player with its drops, is a Group with
# the entity's id. Its own leaves sit at the Group's origin, and its children
# at their local Poses. The host moves and turns them all with the Group. An
# entity with no children gives its leaves at its local Pose.
entity_nodes : Model, List(Slot), Slot -> List(Vocabulary.Node)
entity_nodes = |m, slots, slot| {
	e = slot.entity
	pose = local_pose(e)
	children = List.keep_if(slots, |c| c.index > slot.index and c.entity.parent == Child(e.id))
	if List.is_empty(children) {
		leaves(m.meshes, e, pose)
	} else {
		inner = leaves(m.meshes, e, Pose.identity).concat(List.join_map(children, |c| entity_nodes(m, slots, c)))
		[Group({ id: e.id, pos: pose.pos, rot: pose.rot }, inner)]
	}
}

# endregion

# Starts at the middle of the player's box, which the host skips.
ground_ray : Entity -> Vocabulary.Query
ground_ray = |p| Query.ray(p.id, player_middle(p), { x: 0.0, y: -1.0, z: 0.0 }, ground_ray_length)

ground_ray_length : F32
ground_ray_length = 20.0

shadow_id : U64
shadow_id = floor_id - 1

# Lifts the shadow off the ground so it does not z-fight the surface under it.
shadow_lift : F32
shadow_lift = 0.01

shadow : Model, Entity -> Vocabulary.Draw
shadow = |m, p| {
	pos = { x: p.pos.x, y: m.ground_below + shadow_lift, z: p.pos.z }
	{ ..Draw.default, id: shadow_id, mesh: m.meshes.sphere, pos, scale: { x: 0.6, y: 0.01, z: 0.6 }, tint: { r: 0.01, g: 0.01, b: 0.01 } }
}

# Radians per second. At t 0 the eye is behind the player, on the follow camera's side.
orbit_speed : F32
orbit_speed = 0.8

orbit_eye : Vec3, F32 -> Vec3
orbit_eye = |target, t| {
	angle = orbit_speed * t
	{ x: target.x + 6.0 * angle.sin(), y: target.y + 3.0, z: target.z + 6.0 * angle.cos() }
}

# Where an entity's leaves and children sit, in its parent's space. The door's
# slab lifts.
local_pose : Entity -> Pose.Pose
local_pose = |e| {
	pos = match e.kind {
		Door(d) => { ..e.pos, y: e.pos.y + d.lift }
		_ => e.pos
	}
	{ pos, rot: Quat.from_yaw(e.yaw) }
}

draw : MeshIds, Entity, Pose.Pose -> Vocabulary.Draw
draw = |meshes, e, pose| {
	pos = pose.pos
	rot = pose.rot
	match e.kind {
		Player(_) => { ..Draw.default, id: e.id, mesh: meshes.sprout, pos, rot, tint: { r: 1.0, g: 1.0, b: 1.0 } }
		Pickup => { ..Draw.default, id: e.id, mesh: meshes.cube, pos, scale: V.scale(V.one, 0.4), rot, tint: { r: 0.033, g: 0.787, b: 0.133 } }
		Block => { ..Draw.default, id: e.id, mesh: meshes.cube, pos, scale: V.scale(block_half, 2.0), rot, tint: { r: 0.28, g: 0.16, b: 0.08 } }
		Goal => { ..Draw.default, id: e.id, mesh: meshes.cube, pos, scale: V.scale(goal_half, 2.0), rot, tint: { r: 1.0, g: 0.75, b: 0.05 } }
		Drop(_) => { ..Draw.default, id: e.id, mesh: meshes.sphere, pos, scale: { x: 0.07, y: 0.1, z: 0.07 }, rot, tint: { r: 0.02, g: 0.3, b: 1.0 } }
		Door(_) => { ..Draw.default, id: e.id, mesh: meshes.cube, pos, scale: { x: 3.0, y: 3.0, z: 0.3 }, rot, tint: { r: 0.214, g: 0.073, b: 0.604 } }
	}
}

# region: colliders
# The player's box sits on its feet.
player_half : Vec3
player_half = { x: 0.3, y: 0.5, z: 0.3 }

door_half : Vec3
door_half = { x: 1.5, y: 1.5, z: 0.15 }

block_half : Vec3
block_half = { x: 0.5, y: 0.5, z: 0.5 }

goal_half : Vec3
goal_half = { x: 1.0, y: 0.05, z: 0.75 }

pickup_radius : F32
pickup_radius = 0.4

# The floor and drops touch nothing, and a drop is not drawn until its delay
# ends. The pose is local to the entity's parent, and the host composes the
# world Pose before the Queries.
leaves : MeshIds, Entity, Pose.Pose -> List(Vocabulary.Node)
leaves = |meshes, e, pose| {
	drawn = Draw(draw(meshes, e, pose))
	match e.kind {
		Player(_) => [drawn, Collider(Collider.box(e.id, { ..pose.pos, y: pose.pos.y + player_half.y }, pose.rot, player_half))]
		Pickup => [drawn, Collider(Collider.sphere(e.id, pose.pos, pickup_radius)), Light(pickup_light(pose.pos))]
		Block => [drawn, Collider(Collider.box(e.id, pose.pos, pose.rot, block_half))]
		Goal => [drawn, Collider(Collider.box(e.id, pose.pos, pose.rot, goal_half))]
		Door(_) => [drawn, Collider(Collider.box(e.id, pose.pos, pose.rot, door_half))]
		Drop(_) if waiting(e) => []
		Drop(_) => [drawn]
	}
}

# endregion

# ---- helpers -------------------------------------------------------------

map_entities : Model, (Entity -> Entity) -> Model
map_entities = |m, f| { ..m, entities: List.map(m.entities, f) }

player_middle : Entity -> Vec3
player_middle = |p| { ..p.pos, y: p.pos.y + player_half.y }

player : Model -> Try(Entity, [NotFound])
player = |m| List.find_first(
	m.entities,
	|e| match e.kind {
		Player(_) => Bool.True
		_ => Bool.False
	},
)

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
		Ok({ other: c.a, normal: V.scale(c.normal, -1.0) })
	} else {
		Err(NotInContact)
	}

# region: touches
touches : List(Contact), U64, U64 -> Bool
touches = |contacts, id, other| List.any(contacts, |c| seen_from(c, id).map_ok(|side| side.other == other) ?? Bool.False)

# endregion

# Solid kinds push the player out.
is_solid : Entity -> Bool
is_solid = |e| match e.kind {
	Door(_) | Block => Bool.True
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

pi : F32
pi = 3.1415927

# ---- tests. `roc test main.roc` runs these with no engine. ----------------

# What the engine would hand loaded on this machine.
manifest : Manifest
manifest = [{ name: "sprout", id: 4, duration: 0.0, clips: [] }, { name: "sky/meadow", id: 1, duration: 0.0, clips: [] }]

test_meshes : MeshIds
test_meshes = resolve_meshes(manifest)

expect launch(Config.empty) == Launch.default
expect init({ ..Config.empty, assets: ["sprout", "sky/meadow"] }).commands == [Load({ pack: "sprout", assets: ["sprout", "sky/meadow"] })]
expect loaded(init(Config.empty).model, "sprout", manifest).meshes == { cube: 1, sphere: 2, plane: 3, sprout: 4, sky: 1 }
expect view(init(Config.empty).model).sky == 0
expect view(loaded(init(Config.empty).model, "sprout", manifest)).sky == 1

right : Vocabulary.Input
right = { ..Input.empty, held: [Key.code(D)] }

expect {
	m = new_game(test_meshes, 3, 0)
	List.len(m.entities) == 7 and m.score == 0
}

expect {
	# A plane floor, a sprout player, a cube door and cube pickups.
	scene = view(new_game(test_meshes, 1, 0))
	mesh_of = |id| List.find_first(draws_of(scene), |d| d.id == id).map_ok(|d| d.mesh) ?? 0
	mesh_of(floor_id) == test_meshes.plane and mesh_of(0) == test_meshes.sprout and mesh_of(1) == test_meshes.cube and mesh_of(2) == test_meshes.cube
}

expect {
	centre = { x: 0.0, y: 0.5, z: 0.0 }
	view(new_game(test_meshes, 1, 0)).queries == [Query.contacts_of(0), Query.ray(0, centre, { x: 0.0, y: -1.0, z: 0.0 }, ground_ray_length), Query.overlap(0, Sphere(magnet_radius), centre)]
}

pos_of : Model, U64 -> Vec3
pos_of = |m, id| List.find_first(m.entities, |e| e.id == id).map_ok(|e| e.pos) ?? { x: -100.0, y: -100.0, z: -100.0 }

caught : List(U64) -> Vocabulary.QueryResults
caught = |ids| { ..QueryResults.empty, overlaps: List.map(ids, |id| { owner: 0, slot: 0, id }) }

expect {
	m = step(new_game(test_meshes, 2, 0), Input.empty, caught([2]), 0.1).model
	near_vec(pos_of(m, 2), { x: -3.6, y: 0.5, z: 0.0 }) and pos_of(m, 3) == pickup_spot(1)
}

expect {
	# The magnet pulls pickups only, so the block stays.
	m = step(new_game(test_meshes, 1, 0), Input.empty, caught([3]), 0.1).model
	pos_of(m, 3) == block_pos
}

expect {
	# Another owner's overlap does not pull.
	other = { ..QueryResults.empty, overlaps: [{ owner: 5, slot: 0, id: 2 }] }
	m = step(new_game(test_meshes, 1, 0), Input.empty, other, 0.1).model
	pos_of(m, 2) == pickup_spot(0)
}

expect toward({ x: 1.0, y: 0.0, z: 0.0 }, V.zero, 4.0) == V.zero

shadow_y : Vocabulary.Scene -> F32
shadow_y = |scene| List.find_first(draws_of(scene), |d| d.id == shadow_id).map_ok(|d| d.pos.y) ?? -100.0

ground_hit : U64, F32 -> Vocabulary.RayHit
ground_hit = |owner, y| { owner, slot: 0, id: 3, point: { x: 0.0, y, z: 0.0 }, normal: { x: 0.0, y: 1.0, z: 0.0 }, distance: player_half.y - y }

expect {
	# The first step gets empty QueryResults, so the shadow is on the floor.
	m = step(new_game(test_meshes, 1, 0), Input.empty, QueryResults.empty, 1.0 / 120.0).model
	m.ground_below == 0.0 and near(shadow_y(view(m)), shadow_lift)
}

expect {
	# A hit on the block puts the shadow on its top.
	hit = { ..QueryResults.empty, rays: [ground_hit(0, 1.0)] }
	m = step(new_game(test_meshes, 1, 0), Input.empty, hit, 1.0 / 120.0).model
	m.ground_below == 1.0 and near(shadow_y(view(m)), 1.0 + shadow_lift)
}

expect {
	# A miss after a hit puts the shadow back on the floor.
	hit = { ..QueryResults.empty, rays: [ground_hit(0, 1.0)] }
	over_block = step(new_game(test_meshes, 1, 0), Input.empty, hit, 1.0 / 120.0).model
	missed = step(over_block, Input.empty, { ..QueryResults.empty, rays: [ground_hit(5, 1.0)] }, 1.0 / 120.0).model
	missed.ground_below == 0.0 and near(shadow_y(view(missed)), shadow_lift)
}

expect {
	# The sprout carries its own colours, so its tint is white.
	scene = view(new_game(test_meshes, 1, 0))
	match List.find_first(draws_of(scene), |d| d.id == 0) {
		Ok(d) => d.tint == { r: 1.0, g: 1.0, b: 1.0 }
		Err(_) => Bool.False
	}
}

# The leaves of a Scene in walk order, each at its world Pose, as the host
# composes them.
world_leaves : Vocabulary.Scene -> List(Vocabulary.Node)
world_leaves = |scene| List.join_map(scene.nodes, |node| leaves_under(Pose.identity, node))

leaves_under : Pose.Pose, Vocabulary.Node -> List(Vocabulary.Node)
leaves_under = |parent, node| match node {
	Group(g, children) => {
		group = Pose.compose(parent, { pos: g.pos, rot: g.rot })
		List.join_map(children, |child| leaves_under(group, child))
	}
	Draw(d) => [Draw(in_world(parent, d))]
	Collider(c) => [Collider(in_world(parent, c))]
	Light(Point(l)) => [Light(Point({ ..l, pos: Pose.compose(parent, { pos: l.pos, rot: Quat.identity }).pos }))]
	Light(Directional(l)) => [Light(Directional({ ..l, dir: Quat.rotate(l.dir, parent.rot) }))]
	Light(l) => [Light(l)]
	Speaker(s) => match s.at {
		At(a) => [Speaker({ ..s, at: At({ ..a, pos: Pose.compose(parent, { pos: a.pos, rot: Quat.identity }).pos }) })]
		Here => [Speaker(s)]
	}
}

# A leaf with its pos and rot moved from its parent's space to the world.
in_world : Pose.Pose, { pos : Vec3, rot : Quat.Quat, ..a } -> { pos : Vec3, rot : Quat.Quat, ..a }
in_world = |parent, leaf| {
	world = Pose.compose(parent, { pos: leaf.pos, rot: leaf.rot })
	{ ..leaf, pos: world.pos, rot: world.rot }
}

draws_of : Vocabulary.Scene -> List(Vocabulary.Draw)
draws_of = |scene| List.keep_oks(
	world_leaves(scene),
	|node| match node {
		Draw(d) => Ok(d)
		_ => Err(NotDraw)
	},
)

colliders_of : Vocabulary.Scene -> List(Vocabulary.Collider)
colliders_of = |scene| List.keep_oks(
	world_leaves(scene),
	|node| match node {
		Collider(c) => Ok(c)
		_ => Err(NotCollider)
	},
)

lights_of : Vocabulary.Scene -> List(Vocabulary.Light)
lights_of = |scene| List.keep_oks(
	world_leaves(scene),
	|node| match node {
		Light(l) => Ok(l)
		_ => Err(NotLight)
	},
)

yaw_of : Model -> F32
yaw_of = |m| player(m).map_ok(|p| p.yaw) ?? -100.0

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

run_steps : Model, Vocabulary.Input, U64, F32 -> Model
run_steps = |m, input, n, dt| {
	var $m = m
	var $i = 0
	while $i < n {
		$m = update($m, input, [], dt)
		$i = $i + 1
	}
	$m
}

facing : Model, F32 -> Model
facing = |m, yaw| map_entities(
	m,
	|e| match e.kind {
		Player(_) => { ..e, yaw }
		_ => e
	},
)

expect {
	# One short step turns the player part of the way, at turn_speed.
	moved = update(new_game(test_meshes, 0, 0), right, [], 0.05)
	near(yaw_of(moved), turn_speed * 0.05)
}

expect {
	# Given time, the player faces where it moves, and keeps that yaw when it stops.
	moved = run_steps(new_game(test_meshes, 0, 0), right, 20, 0.05)
	stopped = run_steps(moved, Input.empty, 5, 0.05)
	back = run_steps(stopped, { ..Input.empty, held: [Key.code(W)] }, 20, 0.05)
	near(yaw_of(moved), pi / 2.0) and near(yaw_of(stopped), pi / 2.0) and near(yaw_of(back), pi)
}

expect {
	# From 3/4 pi toward -3/4 pi, the short way is up through pi.
	m = facing(new_game(test_meshes, 0, 0), 0.75 * pi)
	turned = update(m, { ..Input.empty, held: [Key.code(W), Key.code(A)] }, [], 0.05)
	yaw_of(turned) > 0.75 * pi
}

expect {
	# Touching every pickup collects every pickup and opens the door in one step.
	after = collected(new_game(test_meshes, 2, 0), 1.0 / 120.0)
	after.score == 2 and door_open(after) and List.len(after.entities) == 4 + 2 * drops_per_pickup
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
	after = update(new_game(test_meshes, 3, 0), Input.empty, [touch(0, 2)], 1.0 / 120.0)
	drop_count(after) == drops_per_pickup and List.count_if(after.entities, is_pickup) == 2
}

expect {
	# New ids start past the last pickup, only grow, and are never reused.
	m = new_game(test_meshes, 2, 0)
	after = collected(m, 1.0 / 120.0)
	drop_ids = List.keep_if(after.entities, is_drop).map(|e| e.id)
	fresh = List.all(drop_ids, |id| id >= m.next_id and id < after.next_id)
	distinct = List.all(drop_ids, |id| List.count_if(drop_ids, |other| other == id) == 1)
	m.next_id == 6 and after.next_id == m.next_id + 2 * drops_per_pickup and fresh and distinct
}

expect {
	# A drop lives for its delay plus drop_life, then sweep drops it. The
	# delays differ, so the drops die one after another.
	watered = collected(new_game(test_meshes, 1, 0), 0.1)
	before = run_steps(watered, Input.empty, 8, 0.1)
	some = run_steps(before, Input.empty, 3, 0.1)
	after = run_steps(some, Input.empty, 5, 0.1)
	partly = drop_count(some) > 0 and drop_count(some) < drops_per_pickup
	drop_count(watered) == drops_per_pickup and drop_count(before) == drops_per_pickup and partly and drop_count(after) == 0
}

drop_draws : Model -> List(Vocabulary.Draw)
drop_draws = |m| List.keep_if(draws_of(view(m)), |d| List.any(m.entities, |e| e.id == d.id and is_drop(e)))

drawn_drops : Model -> U64
drawn_drops = |m| List.len(drop_draws(m))

expect {
	# Drops wait for their delays, so they appear one after another.
	watered = collected(new_game(test_meshes, 1, 0), 1.0 / 120.0)
	soon = run_steps(watered, Input.empty, 2, 0.1)
	later = run_steps(soon, Input.empty, 3, 0.1)
	drawn_drops(watered) == 1 and drawn_drops(soon) > 1 and drawn_drops(soon) < drops_per_pickup and drawn_drops(later) == drops_per_pickup
}

expect {
	# Pickups are cubes so the spin shows. Drops are small spheres.
	watered = run_steps(collected(new_game(test_meshes, 2, 0), 0.1), Input.empty, 5, 0.1)
	pickup_mesh = List.find_first(draws_of(view(new_game(test_meshes, 1, 0))), |d| d.id == 2).map_ok(|d| d.mesh) ?? 0
	drops = drop_draws(watered)
	pickup_mesh == test_meshes.cube and List.len(drops) == 2 * drops_per_pickup and List.all(drops, |d| d.mesh == test_meshes.sphere)
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
door_draw_y = |m| List.find_first(draws_of(view(m)), |d| d.id == 1).map_ok(|d| d.pos.y) ?? -1.0

# One idle step on which the player touches every live pickup.
collected : Model, F32 -> Model
collected = |m, dt| {
	contacts = List.keep_if(m.entities, |e| is_pickup(e) and e.alive).map(|e| touch(0, e.id))
	update(m, Input.empty, contacts, dt)
}

expect {
	# The door starts to rise on the step it opens, at door_speed.
	after = collected(new_game(test_meshes, 2, 0), 0.1)
	near(door_lift(after), door_speed * 0.1) and near(door_draw_y(after), 1.5 + door_speed * 0.1)
}

expect {
	# Given time, the door stops at door_height.
	after = run_steps(collected(new_game(test_meshes, 2, 0), 0.1), Input.empty, 29, 0.1)
	near(door_lift(after), door_height) and near(door_draw_y(after), 1.5 + door_height)
}

expect {
	# A shut door does not rise.
	after = run_steps(new_game(test_meshes, 2, 0), Input.empty, 30, 0.1)
	door_lift(after) == 0.0 and near(door_draw_y(after), 1.5)
}

expect {
	# Nothing touched: the door stays shut and nothing is swept.
	after = update(new_game(test_meshes, 4, 0), Input.empty, [], 1.0 / 120.0)
	after.score == 0 and !door_open(after) and List.len(after.entities) == 8
}

expect {
	# update is pure. The same Model and Input give the same step count and score,
	# which is what makes a recorded input log a replay.
	m = new_game(test_meshes, 4, 0)
	a = update(m, right, [], 0.5)
	b = update(m, right, [], 0.5)
	a.steps == b.steps and a.score == b.score
}

expect {
	out = step(new_game(test_meshes, 1, 0), { ..Input.empty, pressed: [Key.code(Escape)] }, QueryResults.empty, 1.0 / 120.0)
	out.commands == [Quit]
}

expect {
	out = step(new_game(test_meshes, 1, 0), Input.empty, QueryResults.empty, 1.0 / 120.0)
	out.commands == []
}

expect {
	m = new_game(test_meshes, 1, 0)
	stepped = step(m, Input.empty, { ..QueryResults.empty, contacts: [touch(0, 2)] }, 0.1).model
	stepped.score == update(m, Input.empty, [touch(0, 2)], 0.1).score and stepped.score != m.score
}

expect {
	won = { ..new_game(test_meshes, 1, 0), phase: Won(0.0) }
	out = step(won, { ..Input.empty, pressed: [Key.code(Escape)] }, QueryResults.empty, 1.0 / 120.0)
	out.commands == [Quit]
}

expect {
	# view carries the entity id onto its draw, so the host can pair this
	# step's draw with the last one. The floor's id never collides.
	m = new_game(test_meshes, 1, 0)
	scene = view(update(m, right, [], 1.0))
	player_draw = List.find_first(draws_of(scene), |d| d.id == 0)
	ids_unique = List.len(draws_of(scene)) == 7 and List.count_if(draws_of(scene), |d| d.id == floor_id) == 1
	match player_draw {
		Ok(d) => d.pos.x == 6.0 and ids_unique
		Err(_) => Bool.False
	}
}

collider_of : Vocabulary.Scene, U64 -> Try(Vocabulary.Collider, [NotFound])
collider_of = |scene, id| List.find_first(colliders_of(scene), |c| c.id == id)

expect {
	# The player stands on a box, the door is a thin box, a pickup is a sphere, the
	# block is a cube and the goal is a flat box. The floor has no collider.
	scene = view(new_game(test_meshes, 1, 0))
	player_box = collider_of(scene, 0) == Ok(Collider.box(0, { x: 0.0, y: 0.5, z: 0.0 }, Quat.identity, player_half))
	door_box = collider_of(scene, 1) == Ok(Collider.box(1, { x: 0.0, y: 1.5, z: -8.0 }, Quat.identity, door_half))
	pickup_sphere = collider_of(scene, 2).map_ok(|c| c.shape == Sphere(pickup_radius) and near_vec(c.pos, { x: -4.0, y: 0.5, z: 0.0 })) == Ok(Bool.True)
	block_box = collider_of(scene, 3) == Ok(Collider.box(3, block_pos, Quat.identity, block_half))
	goal_box = collider_of(scene, 4) == Ok(Collider.box(4, { x: 0.0, y: 0.05, z: -9.2 }, Quat.identity, { x: 1.0, y: 0.05, z: 0.75 }))
	player_box and door_box and pickup_sphere and block_box and goal_box and List.len(colliders_of(scene)) == 5
}

expect {
	# The player's box turns with the player.
	scene = view(facing(new_game(test_meshes, 0, 0), 1.0))
	collider_of(scene, 0).map_ok(|c| c.rot) == Ok(Quat.from_yaw(1.0))
}

expect {
	# An open door lifts its collider out of the way with its draw.
	after = run_steps(collected(new_game(test_meshes, 2, 0), 0.1), Input.empty, 29, 0.1)
	collider_of(view(after), 1).map_ok(|c| near(c.pos.y, 1.5 + door_height)) == Ok(Bool.True)
}

expect {
	# Water drops touch nothing.
	watered = run_steps(collected(new_game(test_meshes, 2, 0), 0.1), Input.empty, 5, 0.1)
	scene = view(watered)
	drawn_drops(watered) > 0 and List.map(colliders_of(scene), |c| c.id) == [0, 1, 4, 5]
}

expect {
	# The camera follows the player from a fixed offset.
	scene = view(update(new_game(test_meshes, 1, 0), right, [], 1.0))
	scene.camera.target.x == 6.0 and scene.camera.eye.x == 6.0 and scene.camera.eye.y == 1.5
}

# A Pickup draws at its world pos and yaw with no offset.
entity_at : U64, [Root, Child(U64)], Vec3, F32 -> Entity
entity_at = |id, parent, pos, yaw| { id, kind: Pickup, parent, pos, vel: V.zero, yaw, alive: Bool.True }

with_entities : List(Entity) -> Model
with_entities = |entities| { ..new_game(test_meshes, 0, 0), entities }

draw_of : Vocabulary.Scene, U64 -> Try(Vocabulary.Draw, [NotFound])
draw_of = |scene, id| List.find_first(draws_of(scene), |d| d.id == id)

near_vec : Vec3, Vec3 -> Bool
near_vec = |a, b| near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z)

near_rot : Quat.Quat, Quat.Quat -> Bool
near_rot = |a, b| near(a.x, b.x) and near(a.y, b.y) and near(a.z, b.z) and near(a.w, b.w)

expect {
	# A child's world pos is its local pos turned by the parent yaw, plus the
	# parent pos. Yaws add. Depth is unbounded.
	scene = view(
		with_entities([
			entity_at(10, Root, { x: 1.0, y: 0.0, z: 0.0 }, pi / 2.0),
			entity_at(11, Child(10), { x: 0.0, y: 2.0, z: 1.0 }, 0.5),
			entity_at(12, Child(11), { x: 0.0, y: 0.0, z: 1.0 }, 0.0),
		]),
	)
	match (draw_of(scene, 11), draw_of(scene, 12)) {
		(Ok(child), Ok(grandchild)) => {
			turned = pi / 2.0 + 0.5
			want = { x: 2.0 + turned.sin(), y: 2.0, z: turned.cos() }
			near_vec(child.pos, { x: 2.0, y: 2.0, z: 0.0 }) and near_rot(child.rot, Quat.from_yaw(turned)) and near_vec(grandchild.pos, want)
		}
		_ => Bool.False
	}
}

expect {
	# A child's collider turns by the parent's world rot, then by its own yaw.
	parent = entity_at(10, Root, V.zero, 1.0)
	child = { ..entity_at(11, Child(10), { x: 0.0, y: 0.0, z: 2.0 }, 0.5), kind: Block }
	collider_of(view(with_entities([parent, child])), 11).map_ok(|c| near_rot(c.rot, Quat.from_yaw(1.5))) == Ok(Bool.True)
}

expect {
	# Scale is not inherited.
	scene = view(with_entities([entity_at(10, Root, V.zero, 0.0), entity_at(11, Child(10), V.zero, 0.0)]))
	match (draw_of(scene, 10), draw_of(scene, 11)) {
		(Ok(parent), Ok(child)) => parent.scale == child.scale
		_ => Bool.False
	}
}

expect {
	# A child whose parent is missing, or later in the list, draws at its local values.
	local = { x: 3.0, y: 1.0, z: 2.0 }
	scene = view(
		with_entities([
			entity_at(10, Child(99), local, 0.25),
			entity_at(11, Child(12), local, 0.25),
			entity_at(12, Root, { x: 5.0, y: 0.0, z: 0.0 }, 1.0),
		]),
	)
	at_local = |id| draw_of(scene, id).map_ok(|d| d.pos == local and d.rot == Quat.from_yaw(0.25)) ?? Bool.False
	at_local(10) and at_local(11)
}

expect {
	# log_orphans records each orphan id once, however many steps it lives.
	m = with_entities([entity_at(10, Child(99), V.zero, 0.0), entity_at(11, Child(12), V.zero, 0.0), entity_at(12, Root, V.zero, 0.0), entity_at(13, Child(13), V.zero, 0.0)])
	after = run_steps(m, Input.empty, 3, 0.1)
	after.orphans_logged == [10, 11, 13]
}

expect {
	# A child of the door lifts with the slab, because the door's Group carries the lift.
	opened = run_steps(collected(new_game(test_meshes, 1, 0), 0.1), Input.empty, 29, 0.1)
	with_child = { ..opened, entities: List.append(opened.entities, entity_at(50, Child(1), { x: 0.0, y: 2.0, z: 0.0 }, 0.0)) }
	draw_of(view(with_child), 50).map_ok(|d| near(d.pos.y, 1.5 + door_height + 2.0)) ?? Bool.False
}

expect {
	# Sweep drops a dead entity, then every descendant of it in the same pass.
	dead = { ..entity_at(10, Root, V.zero, 0.0), alive: Bool.False }
	swept = sweep(
		with_entities([
			dead,
			entity_at(11, Child(10), V.zero, 0.0),
			entity_at(12, Child(11), V.zero, 0.0),
			entity_at(13, Root, V.zero, 0.0),
			entity_at(14, Child(13), V.zero, 0.0),
		]),
	)
	swept.entities.map(|e| e.id) == [13, 14]
}

expect {
	# A drop with no delay starts in a ring above the plant, and follows and turns with it.
	watered = collected(new_game(test_meshes, 1, 0), 1.0 / 120.0)
	offsets = |m| {
		p = draw_of(view(m), 0).map_ok(|d| d.pos) ?? V.zero
		drop_draws(m).map(|d| V.sub(d.pos, p))
	}
	on_ring = |o| near(o.x * o.x + o.z * o.z, drop_start_radius * drop_start_radius) and near(o.y, drop_start_height)
	still = offsets(watered)
	turned = offsets(facing(watered, pi / 2.0))
	rotated = List.map2(still, turned, |a, b| near_vec(b, { x: a.z, y: a.y, z: -a.x }))
	List.len(still) == 1 and List.all(still, on_ring) and List.all(rotated, |ok| ok)
}

expect {
	# The drops sit in the player's Group, at their local offsets, so the host
	# turns them with the player along an arc. The player's own leaves sit at
	# the Group's origin.
	watered = facing(collected(new_game(test_meshes, 1, 0), 1.0 / 120.0), 1.0)
	in_player = |node| match node {
		Group(g, _) => g.id == 0
		_ => Bool.False
	}
	match List.find_first(view(watered).nodes, in_player) {
		Ok(Group(g, [Draw(sprout), Collider(_), Draw(water)])) => {
			first = List.find_first(watered.entities, is_drop).map_ok(|e| e.pos) ?? V.zero
			g.rot == Quat.from_yaw(1.0) and sprout.pos == V.zero and sprout.rot == Quat.identity and water.pos == first
		}
		_ => Bool.False
	}
}

expect {
	# With no children the player is no Group, so a quiet step makes no Group list.
	scene = view(new_game(test_meshes, 1, 0))
	List.all(
		scene.nodes,
		|node| match node {
			Group(_, _) => Bool.False
			_ => Bool.True
		},
	)
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
		Player(_) => { ..e, pos }
		_ => e
	},
)

door_contact : F32 -> Contact
door_contact = |depth| { a: 0, b: 1, normal: { x: 0.0, y: 0.0, z: -1.0 }, depth }

expect {
	# A closed door pushes the player out by the depth and stops the walk into it. The walk along it goes on.
	m = placed(new_game(test_meshes, 0, 0), { x: 0.0, y: 0.0, z: -7.6 })
	after = update(m, { ..Input.empty, held: [Key.code(W), Key.code(D)] }, [door_contact(0.1)], 0.1)
	match player(after) {
		Ok(p) => near_vec(p.pos, { x: 0.6, y: 0.0, z: -7.5 }) and p.vel.z == 0.0
		Err(_) => Bool.False
	}
}

expect {
	# A player that walks away from the door keeps its speed.
	m = placed(new_game(test_meshes, 0, 0), { x: 0.0, y: 0.0, z: -7.6 })
	after = update(m, { ..Input.empty, held: [Key.code(S)] }, [door_contact(0.1)], 0.1)
	player(after).map_ok(|p| near(p.pos.z, -6.9)) ?? Bool.False
}

expect {
	# A contact collects a pickup. Distance alone does not: pickup 2 sits on the player
	# with no contact, and pickup 3 is far away with one.
	m = map_entities(
		new_game(test_meshes, 3, 0),
		|e| if e.id == 2 {
			{ ..e, pos: V.zero }
		} else {
			e
		},
	)
	after = update(m, Input.empty, [touch(0, 3)], 1.0 / 120.0)
	alive_pickups = List.keep_if(after.entities, is_pickup).map(|e| e.id)
	after.score == 1 and alive_pickups == [2, 4]
}

expect {
	# A contact with the door collects nothing.
	after = update(new_game(test_meshes, 1, 0), Input.empty, [touch(0, 1)], 1.0 / 120.0)
	after.score == 0 and List.count_if(after.entities, is_pickup) == 1
}

door_gap : Vocabulary.Scene -> F32
door_gap = |scene|
	match (collider_of(scene, 0), collider_of(scene, 1)) {
		(Ok(p), Ok(d)) => (d.pos.y - door_half.y) - (p.pos.y + player_half.y)
		_ => -100.0
	}

expect {
	# A shut door reaches the player. An open door rises clear of the player's box,
	# so the host finds no contact and the player walks through under it.
	shut = new_game(test_meshes, 1, 0)
	opened = run_steps(collected(shut, 0.1), Input.empty, 29, 0.1)
	at_door = placed(opened, { x: 0.0, y: 0.0, z: -7.6 })
	through = run_steps(at_door, { ..Input.empty, held: [Key.code(W)] }, 2, 0.1)
	walked = player(through).map_ok(|p| near(p.pos.z, -8.8)) ?? Bool.False
	door_gap(view(shut)) < 0.0 and door_gap(view(opened)) > 0.0 and walked
}

space : Vocabulary.Input
space = { ..Input.empty, pressed: [Key.code(Space)] }

height_of : Model -> F32
height_of = |m| player(m).map_ok(|p| p.pos.y) ?? -100.0

# The highest the player gets over n idle steps.
peak : Model, U64, F32 -> F32
peak = |m, n, dt| {
	var $m = m
	var $top = height_of(m)
	var $i = 0
	while $i < n {
		$m = update($m, Input.empty, [], dt)
		$top = F32.max($top, height_of($m))
		$i = $i + 1
	}
	$top
}

expect {
	# A jump peaks near jump_speed squared over twice fall_accel and lands within a second.
	dt = 1.0 / 120.0
	jumped = update(new_game(test_meshes, 0, 0), space, [], dt)
	top = peak(jumped, 120, dt)
	landed = run_steps(jumped, Input.empty, 120, dt)
	top > 1.15 and top < 1.25 and height_of(landed) == 0.0
}

expect {
	# Space in the air does nothing. Space again after the landing jumps.
	dt = 1.0 / 120.0
	in_air = run_steps(update(new_game(test_meshes, 0, 0), space, [], dt), Input.empty, 10, dt)
	landed = run_steps(in_air, Input.empty, 120, dt)
	again = update(landed, space, [], dt)
	player(update(in_air, space, [], dt)) == player(update(in_air, Input.empty, [], dt)) and height_of(again) > 0.0
}

airborne : F32 -> Entity
airborne = |y| { id: 0, kind: Player({ grounded: Bool.False }), parent: Root, pos: { ..block_pos, y }, vel: V.zero, yaw: 0.0, alive: Bool.True }

test_block : Entity
test_block = { id: 5, kind: Block, parent: Root, pos: block_pos, vel: V.zero, yaw: 0.0, alive: Bool.True }

grounded : Model -> Bool
grounded = |m|
	match player(m).map_ok(|p| p.kind) {
		Ok(Player(p)) => p.grounded
		_ => Bool.False
	}

expect {
	# A +y contact with a solid stops the fall and grounds the player. The contact on
	# the jump step comes from the last Scene, so it does not ground the player again.
	dt = 1.0 / 120.0
	falling = { ..airborne(0.95), vel: { x: 0.0, y: -3.0, z: 0.0 } }
	on_top = { a: 0, b: 5, normal: { x: 0.0, y: -1.0, z: 0.0 }, depth: 0.05 }
	landed = update(with_entities([falling, test_block]), Input.empty, [on_top], dt)
	jumped = update(landed, space, [on_top], dt)
	near(height_of(landed), 1.0) and grounded(landed) and height_of(jumped) > 1.0 and !grounded(jumped)
}

floor_pickup : Entity -> Bool
floor_pickup = |e| is_pickup(e) and e.pos.y < 1.0

touch_all : Model, (Entity -> Bool) -> Model
touch_all = |m, keep| update(m, Input.empty, List.keep_if(m.entities, keep).map(|e| touch(0, e.id)), 1.0 / 120.0)

expect {
	# The arc runs left to right in front of the player. The last pickup is out of reach from the floor.
	m = new_game(test_meshes, 8, 0)
	scene = view(m)
	arc = List.keep_if(m.entities, floor_pickup)
	xs = arc.map(|e| e.pos.x)
	on_arc = List.all(arc, |e| near(e.pos.x * e.pos.x + e.pos.z * e.pos.z, 16.0) and e.pos.z <= 0.0001)
	left_to_right = List.fold(xs, { ok: Bool.True, last: -100.0 }, |acc, x| { ok: acc.ok and x > acc.last, last: x }).ok
	cube = List.find_first(m.entities, |e| e.kind == Block).map_ok(|e| collider_of(scene, e.id))
	high = List.find_first(m.entities, |e| is_pickup(e) and !floor_pickup(e)).map_ok(|e| collider_of(scene, e.id))
	block_ok = cube == Ok(Ok(Collider.box(10, { x: -4.5, y: 0.5, z: -4.0 }, Quat.identity, block_half)))
	high_ok = match high {
		Ok(Ok({ pos, shape: Sphere(radius), .. })) => pos.x == -4.5 and pos.z == -4.0 and pos.y - radius > 2.0 * player_half.y
		_ => Bool.False
	}
	List.len(arc) == 7 and on_arc and left_to_right and block_ok and high_ok
}

expect {
	# The door stays shut until the pickup on the block is collected.
	m = new_game(test_meshes, 8, 0)
	floor_done = touch_all(m, floor_pickup)
	all_done = touch_all(floor_done, is_pickup)
	floor_done.score == 7 and !door_open(floor_done) and all_done.score == 8 and door_open(all_done)
}

expect {
	# Standing on the block, the contact comes and goes because it is one step late.
	# The player stays grounded and level with the top, and can jump.
	dt = 1.0 / 120.0
	top = block_pos.y + block_half.y
	var $m = update(with_entities([airborne(top), test_block]), Input.empty, [], dt)
	var $steady = Bool.True
	var $i = 0
	while $i < 120 {
		y = height_of($m)
		contacts = if y < top [{ a: 0, b: 5, normal: { x: 0.0, y: -1.0, z: 0.0 }, depth: top - y }] else []
		$m = update($m, Input.empty, contacts, dt)
		$steady = $steady and grounded($m) and (height_of($m) - top).abs() < 0.01
		$i = $i + 1
	}
	$steady and height_of(update($m, space, [], dt)) > top + 0.01
}

goal_id : Model -> U64
goal_id = |m| List.find_first(m.entities, |e| e.kind == Goal).map_ok(|e| e.id) ?? 999

expect {
	# A goal contact wins the round. The goal is not solid, so it does not move the player.
	m = new_game(test_meshes, 1, 0)
	after = update(m, Input.empty, [touch(0, goal_id(m))], 1.0 / 120.0)
	at_origin = player(after).map_ok(|p| p.pos == V.zero) ?? Bool.False
	m.phase == Playing and after.phase == Won(0.0) and at_origin
}

expect {
	# After the win, keys neither move the player nor make it jump.
	won = { ..new_game(test_meshes, 0, 0), phase: Won(0.0) }
	dt = 1.0 / 120.0
	player(update(won, { ..right, pressed: [Key.code(Space)] }, [], dt)) == player(update(won, Input.empty, [], dt))
}

expect {
	# After the win, one drop falls onto the player every 0.08 seconds: six in half a second.
	dt = 1.0 / 120.0
	raining = run_steps({ ..new_game(test_meshes, 0, 0), phase: Won(0.0) }, Input.empty, 60, dt)
	dry = run_steps(new_game(test_meshes, 0, 0), Input.empty, 60, dt)
	drops = List.keep_if(raining.entities, is_drop)
	on_player = List.all(drops, |e| e.parent == Child(0))
	phases = drops.map(
		|e| match e.kind {
			Drop(d) => d.phase
			_ => -1.0
		},
	)
	varied = List.any(phases, |a| a != List.first(phases) ?? a)
	List.len(drops) == 6 and on_player and varied and drop_count(dry) == 0
}

expect {
	# Four seconds after the win a new round starts. Every entity in it has an id
	# the last round never used, so the host pairs nothing across the restart.
	won = { ..new_game(test_meshes, 8, 0), score: 8, phase: Won(0.0) }
	before = run_steps(won, Input.empty, 39, 0.1)
	after = run_steps(before, Input.empty, 2, 0.1)
	fresh = List.all(after.entities, |e| e.id >= before.next_id)
	at_start = player(after).map_ok(|p| p.pos == V.zero) ?? Bool.False
	pickups = List.count_if(after.entities, is_pickup)
	before.phase != Playing and after.phase == Playing and after.score == 0 and fresh and at_start and pickups == 8 and drop_count(after) == 0
}

expect {
	# After the win the camera circles the player at radius 6 and height 3, 0.8 radians a second.
	won = placed({ ..new_game(test_meshes, 0, 0), phase: Won(1.0) }, { x: 1.0, y: 0.0, z: -2.0 })
	cam = view(won).camera
	near_vec(cam.target, { x: 1.0, y: 0.0, z: -2.0 }) and near_vec(cam.eye, { x: 5.30414, y: 3.0, z: 2.18024 })
}

expect {
	shadows = List.keep_oks(
		lights_of(view(new_game(test_meshes, 1, 0))),
		|l| match l {
			Directional(d) => Ok(d.shadow)
			_ => Err(NotDirectional)
		},
	)
	shadows == [Bool.True]
}

point_positions : Vocabulary.Scene -> List(Vec3)
point_positions = |scene| List.keep_oks(
	lights_of(scene),
	|l| match l {
		Point(p) => Ok(p.pos)
		_ => Err(NotPoint)
	},
)

expect {
	# A fresh round has one Point per pickup, at the pickup.
	m = new_game(test_meshes, round_pickups, 0)
	pickup_pos = List.keep_if(m.entities, is_pickup).map(|e| e.pos)
	point_positions(view(m)) == pickup_pos and List.len(pickup_pos) == round_pickups
}

expect {
	# Collecting a pickup removes its Point.
	m = new_game(test_meshes, 2, 0)
	after = update(m, Input.empty, [touch(0, 2)], 1.0 / 120.0)
	point_positions(view(after)) == [pickup_spot(1)]
}

expect {
	# The engine keeps 8 directional and point lights, so it drops the last one: the Point on the block.
	lights = lights_of(view(new_game(test_meshes, round_pickups, 0)))
	List.len(lights) == 10 and List.take_first(lights, 2) == [ambient, sun] and List.last(lights) == Ok(pickup_light(pickup_spot(arc_pickups)))
}
