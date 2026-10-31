import Vocabulary exposing [RayHit]

## Reads the QueryResults that `step` gets, and builds them for tests.
QueryResults := [].{

	## No Contacts, no RayHits, no OverlapHits, no port messages, no Panels under
	## the pointer and no scroll sizes. The first step gets it.
	empty : Vocabulary.QueryResults
	empty = { contacts: [], rays: [], overlaps: [], ports: [], ui: { over: [], scroll: [] } }

	## The hit of the owner's Raycast in slot 0, or `Miss`.
	ray : Vocabulary.QueryResults, U64 -> Try(RayHit, [Miss])
	ray = |results, owner| QueryResults.ray_slot(results, owner, 0)

	## The hit of the owner's Raycast in `slot`, or `Miss`.
	ray_slot : Vocabulary.QueryResults, U64, U32 -> Try(RayHit, [Miss])
	ray_slot = |results, owner, slot| match List.find_first(results.rays, |hit| hit.owner == owner and hit.slot == slot) {
		Ok(hit) => Ok(hit)
		Err(NotFound) => Err(Miss)
	}

	## The ids that the owner's Overlap in `slot` touched, in id order.
	overlaps : Vocabulary.QueryResults, U64, U32 -> List(U64)
	overlaps = |results, owner, slot| List.fold(
		results.overlaps,
		[],
		|ids, row| if row.owner == owner and row.slot == slot {
			ids.append(row.id)
		} else {
			ids
		},
	)
}

hit : U64, U32 -> RayHit
hit = |owner, slot| { owner, slot, id: 9, point: { x: 0.0, y: 1.0, z: 0.0 }, normal: { x: 0.0, y: 1.0, z: 0.0 }, distance: 2.0 }

expect QueryResults.empty.contacts.is_empty()
expect QueryResults.empty.ui == { over: [], scroll: [] }
expect QueryResults.ray(QueryResults.empty, 7) == Err(Miss)
expect QueryResults.ray({ ..QueryResults.empty, rays: [hit(3, 0), hit(7, 1), hit(7, 0)] }, 7) == Ok(hit(7, 0))
expect QueryResults.ray_slot({ ..QueryResults.empty, rays: [hit(7, 0), hit(7, 1)] }, 7, 1) == Ok(hit(7, 1))
expect QueryResults.ray_slot({ ..QueryResults.empty, rays: [hit(7, 0)] }, 7, 1) == Err(Miss)
expect QueryResults.overlaps(QueryResults.empty, 7, 0) == []
expect {
	rows = [{ owner: 7, slot: 0, id: 2 }, { owner: 3, slot: 0, id: 4 }, { owner: 7, slot: 1, id: 5 }, { owner: 7, slot: 0, id: 6 }]
	QueryResults.overlaps({ ..QueryResults.empty, overlaps: rows }, 7, 0) == [2, 6]
}
