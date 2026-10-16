import Vocabulary exposing [Vec3]

# Builds the Queries a game returns in Scene.queries.
Query := [].{
	# Asks for each Contact that involves the owner's Collider.
	contacts_of : U64 -> Vocabulary.Query
	contacts_of = |owner| ContactsOf(owner)

	# Asks for the nearest Collider along dir within max_distance, in slot 0.
	ray : U64, Vec3, Vec3, F32 -> Vocabulary.Query
	ray = |owner, origin, dir, max_distance| Query.ray_slot(owner, 0, origin, dir, max_distance)

	ray_slot : U64, U32, Vec3, Vec3, F32 -> Vocabulary.Query
	ray_slot = |owner, slot, origin, dir, max_distance| Raycast({ owner, slot, origin, dir, max_distance, exclude: [] })
}

origin : Vec3
origin = { x: 0.0, y: 0.0, z: 0.0 }

down : Vec3
down = { x: 0.0, y: -1.0, z: 0.0 }

expect Query.contacts_of(7) == ContactsOf(7)
expect Query.ray(7, origin, down, 5.0) == Raycast({ owner: 7, slot: 0, origin, dir: down, max_distance: 5.0, exclude: [] })
expect Query.ray_slot(7, 2, origin, down, 5.0) == Raycast({ owner: 7, slot: 2, origin, dir: down, max_distance: 5.0, exclude: [] })
