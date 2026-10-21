import Vocabulary exposing [Vec3]

## Builds the Queries that your game returns in `Scene.queries`. The owner is
## the draw id that a Query belongs to. The host skips the owner's own
## Collider. Read the results in the next `step` with `QueryResults`.
Query := [].{

	## Asks for each Contact that involves the owner's Collider.
	contacts_of : U64 -> Vocabulary.Query
	contacts_of = |owner| ContactsOf(owner)

	## Asks for the nearest Collider along `dir` within `max_distance`, in slot 0.
	ray : U64, Vec3, Vec3, F32 -> Vocabulary.Query
	ray = |owner, origin, dir, max_distance| Query.ray_slot(owner, 0, origin, dir, max_distance)

	## The same as `ray`, in a slot that you choose. Use a different slot for
	## each Raycast of one owner.
	ray_slot : U64, U32, Vec3, Vec3, F32 -> Vocabulary.Query
	ray_slot = |owner, slot, origin, dir, max_distance| Raycast({ owner, slot, origin, dir, max_distance, exclude: [] })

	## Asks for each Collider that the shape at `pos` touches, in slot 0. A box
	## carries its half extents and does not turn.
	overlap : U64, [Box(Vec3), Sphere(F32)], Vec3 -> Vocabulary.Query
	overlap = |owner, shape, pos| Query.overlap_slot(owner, 0, shape, pos)

	## The same as `overlap`, in a slot that you choose. Use a different slot
	## for each Overlap of one owner.
	overlap_slot : U64, U32, [Box(Vec3), Sphere(F32)], Vec3 -> Vocabulary.Query
	overlap_slot = |owner, slot, shape, pos| Overlap({ owner, slot, shape, pos, exclude: [] })
}

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

down : Vec3
down = { x: 0.0, y: -1.0, z: 0.0 }

expect Query.contacts_of(7) == ContactsOf(7)
expect Query.ray(7, origin, down, 5.0) == Raycast({ owner: 7, slot: 0, origin, dir: down, max_distance: 5.0, exclude: [] })
expect Query.ray_slot(7, 2, origin, down, 5.0) == Raycast({ owner: 7, slot: 2, origin, dir: down, max_distance: 5.0, exclude: [] })
expect Query.overlap(7, Sphere(2.0), origin) == Overlap({ owner: 7, slot: 0, shape: Sphere(2.0), pos: origin, exclude: [] })
expect Query.overlap_slot(7, 3, Box(down), origin) == Overlap({ owner: 7, slot: 3, shape: Box(down), pos: origin, exclude: [] })
