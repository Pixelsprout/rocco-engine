---
title: Collisions and Queries
summary: The Colliders a Scene holds, the Queries that ask about them, the results that the next step gets, and the one-step latency.
order: 6
---

# Collisions and Queries

The engine has no physics. It moves nothing and pushes nothing apart. It
answers Queries about shapes. Your game puts the shapes and the Queries in
its [Scene]. The next `step` gets the QueryResults, and your game decides
what they mean.

## Colliders

A [Collider] is a shape with the id of a [Draw]. Put the Colliders in
`Scene.colliders`. Make each one with the
[Collider module][Collider module]:

- [`Collider.box`][Collider.box] makes a box. `yaw` turns it about +y only.
- [`Collider.sphere`][Collider.sphere] makes a sphere.
- [`Collider.capsule`][Collider.capsule] makes a capsule. The host does not
  test capsules yet. It skips each one and logs one line.

An entity with no Collider touches nothing. The shape of a Collider does
not need to match the mesh of the Draw. The entity game gives each kind of
entity its own shape:

<!-- region: examples/entity-game/main.roc#colliders -->
```roc
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

# Floor and drops touch nothing.
with_collider : List(Vocabulary.Collider), Entity, World -> List(Vocabulary.Collider)
with_collider = |colliders, e, world| match e.kind {
	Player(_) => colliders.append(Collider.box(e.id, { ..world.pos, y: world.pos.y + player_half.y }, world.yaw, player_half))
	Pickup => colliders.append(Collider.sphere(e.id, world.pos, pickup_radius))
	Block => colliders.append(Collider.box(e.id, world.pos, world.yaw, block_half))
	Goal => colliders.append(Collider.box(e.id, world.pos, world.yaw, goal_half))
	Door(d) => colliders.append(Collider.box(e.id, { ..world.pos, y: world.pos.y + d.lift }, world.yaw, door_half))
	Drop(_) => colliders
}
```
<!-- endregion -->

If two Colliders have the same id, the host uses the first one. It logs the
id once and skips the second.

## Queries

A [Query] asks the host about the Colliders. Put the Queries in
`Scene.queries`. Make each one with the [Query module][Query module]:

| Query | Asks | Make it with |
|---|---|---|
| `ContactsOf` | each Collider that overlaps the owner's Collider | [`Query.contacts_of`][Query.contacts_of] |
| `Raycast` | the nearest Collider along a ray | [`Query.ray`][Query.ray] or [`Query.ray_slot`][Query.ray_slot] |
| `Overlap` | each Collider that a box or a sphere touches | [`Query.overlap`][Query.overlap] or [`Query.overlap_slot`][Query.overlap_slot] |

The owner is the draw id that a Query belongs to. A slot tells apart two
Raycasts, or two Overlaps, of one owner. The [Query] type gives the rules
for owners and slots. A Raycast and an Overlap can use the same owner and
slot.

The entity game asks three Queries for its player: its Contacts, a ray down
to the ground, and an Overlap sphere that pulls pickups in:

<!-- region: examples/entity-game/main.roc#queries -->
```roc
	# Every Contact the game reads involves the player.
	queries = match player(curr) {
		Ok(p) => [Query.contacts_of(p.id), ground_ray(p), Query.overlap(p.id, Sphere(magnet_radius), player_middle(p))]
		Err(NotFound) => []
	}
```
<!-- endregion -->

## The one-step latency

The host answers the Queries of a Scene against the Colliders of the same
Scene. The next `step` gets the [QueryResults]. So the QueryResults are
always one step old:

1. `step` N moves the player.
2. `view` N puts the player's Collider and Queries in Scene N.
3. The host answers the Queries of Scene N.
4. `step` N+1 gets the QueryResults.

The first step gets empty QueryResults. The host does not answer the
Queries of the Scene that `view` returns after `init`.

Write your stages for this latency. The entity game pushes the player out
of a block before it moves the player, because the Contact comes from
where the player was.

## Read the results

The QueryResults hold one list for each kind of Query. A miss has no row.
The [QueryResults module][QueryResults module] reads the lists:

- `QueryResults.ray(results, owner)` gives the [RayHit] of slot 0, or
  `Err(Miss)`. `QueryResults.ray_slot` takes a slot.
- `QueryResults.overlaps(results, owner, slot)` gives the ids that the
  Overlap touched, in id order.
- `results.contacts` is the list of [Contact]s.

The entity game reads its ground ray and its Overlap in `step`:

<!-- region: examples/entity-game/main.roc#results -->
```roc
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
```
<!-- endregion -->

## Contacts

With no `ContactsOf` Query, the host finds no Contacts. With one or more,
the host gives each overlapping pair that holds the owner of a
`ContactsOf` Query, once:

- `a` is the lower id and `b` is the higher id.
- `normal` points from `a` to `b`.
- `depth` is how far the shapes overlap along `normal`.
- The host sorts the list by `a`, then by `b`.

Your Collider can be `a` or `b`. The entity game reads a Contact from the
side of one id, then asks if the other id is a thing:

<!-- region: examples/entity-game/main.roc#touches -->
```roc
touches : List(Contact), U64, U64 -> Bool
touches = |contacts, id, other| List.any(contacts, |c| seen_from(c, id).map_ok(|side| side.other == other) ?? Bool.False)
```
<!-- endregion -->

<!-- region: examples/entity-game/main.roc#win -->
```roc
win : Model, List(Contact) -> Model
win = |m, contacts|
	match (m.phase, player(m)) {
		(Playing, Ok(p)) if List.any(m.entities, |e| e.kind == Goal and touches(contacts, p.id, e.id)) => { ..m, phase: Won(0.0) }
		_ => m
	}
```
<!-- endregion -->

The host tests where the shapes are, not the path between two steps. So a
fast, small shape can pass through a thin shape in one step.

## Rays and Overlaps

- The host makes the ray direction a unit vector. A zero direction hits
  nothing.
- A ray that starts inside a Collider hits it at the origin of the ray.
- If two Colliders are at the same distance, the lower id wins.
- An Overlap box does not turn.
- Two shapes that only touch at a face do not overlap.
- To skip more ids than the owner, make the `Raycast` or `Overlap` tag
  yourself and fill its `exclude` list.

[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Draw]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Draw
[Collider]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Collider
[Collider module]: https://pixelsprout.dev/projects/rocco/api/platform/Collider/
[Collider.box]: https://pixelsprout.dev/projects/rocco/api/platform/Collider/#Collider.box
[Collider.sphere]: https://pixelsprout.dev/projects/rocco/api/platform/Collider/#Collider.sphere
[Collider.capsule]: https://pixelsprout.dev/projects/rocco/api/platform/Collider/#Collider.capsule
[Query]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Query
[Query module]: https://pixelsprout.dev/projects/rocco/api/platform/Query/
[Query.contacts_of]: https://pixelsprout.dev/projects/rocco/api/platform/Query/#Query.contacts_of
[Query.ray]: https://pixelsprout.dev/projects/rocco/api/platform/Query/#Query.ray
[Query.ray_slot]: https://pixelsprout.dev/projects/rocco/api/platform/Query/#Query.ray_slot
[Query.overlap]: https://pixelsprout.dev/projects/rocco/api/platform/Query/#Query.overlap
[Query.overlap_slot]: https://pixelsprout.dev/projects/rocco/api/platform/Query/#Query.overlap_slot
[QueryResults]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.QueryResults
[QueryResults module]: https://pixelsprout.dev/projects/rocco/api/platform/QueryResults/
[RayHit]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.RayHit
[Contact]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Contact
