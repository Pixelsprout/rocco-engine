import Vocabulary exposing [RayHit]

# Reads and builds QueryResults.
QueryResults := [].{
	# What the first step gets.
	empty : Vocabulary.QueryResults
	empty = { contacts: [], rays: [], overlaps: [] }

	# The hit of the owner's Raycast in slot 0.
	ray : Vocabulary.QueryResults, U64 -> Try(RayHit, [Miss])
	ray = |results, owner| QueryResults.ray_slot(results, owner, 0)

	ray_slot : Vocabulary.QueryResults, U64, U32 -> Try(RayHit, [Miss])
	ray_slot = |results, owner, slot| match List.find_first(results.rays, |hit| hit.owner == owner and hit.slot == slot) {
		Ok(hit) => Ok(hit)
		Err(NotFound) => Err(Miss)
	}
}

hit : U64, U32 -> RayHit
hit = |owner, slot| { owner, slot, id: 9, point: { x: 0.0, y: 1.0, z: 0.0 }, normal: { x: 0.0, y: 1.0, z: 0.0 }, distance: 2.0 }

expect QueryResults.empty.contacts.is_empty()
expect QueryResults.ray(QueryResults.empty, 7) == Err(Miss)
expect QueryResults.ray({ ..QueryResults.empty, rays: [hit(3, 0), hit(7, 1), hit(7, 0)] }, 7) == Ok(hit(7, 0))
expect QueryResults.ray_slot({ ..QueryResults.empty, rays: [hit(7, 0), hit(7, 1)] }, 7, 1) == Ok(hit(7, 1))
expect QueryResults.ray_slot({ ..QueryResults.empty, rays: [hit(7, 0)] }, 7, 1) == Err(Miss)
