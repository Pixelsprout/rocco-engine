package engine

import "core:fmt"
import "core:math"
import "core:mem"
import "core:slice"

// A grid cell is this many times a typical Shape's size on the ground plane.
GRID_CELL_SCALE :: f32(2)
// The grid has at most about this many cells per Shape, so a sparse scene
// keeps a small grid.
GRID_CELLS_PER_SHAPE :: 4
// A Shape that spans more cells than this on x or z stays out of the grid,
// and every Query tests it.
GRID_BIG_SPAN :: 8
// A Shape smaller than this counts as this size when the grid picks its cell.
GRID_MIN_SIZE :: f32(1e-3)

// What the host has logged this run, so each problem logs once.
Query_Search :: struct {
	logged_ids:     map[u64]struct {},
	logged_slots:   map[Owner_Slot]struct {},
	logged_capsule: bool,
}

// A Raycast and an Overlap may share an owner and a slot.
Owner_Slot :: struct {
	kind:  Query_Tag,
	owner: u64,
	slot:  u32,
}

// A Collider in world space. A box keeps its half extents in extent and its
// turned ground-plane axes in axes. A sphere keeps its radius in extent.x.
@(private = "file")
Shape :: struct {
	id:       u64,
	tag:      Collider_Shape_Tag,
	centre:   [3]f32,
	extent:   [3]f32,
	axes:     [2][3]f32,
	min, max: [3]f32,
}

// The Shapes of one Scene and a uniform grid over them on the ground plane.
// Every Query of a step searches the same world.
@(private = "file")
Query_World :: struct {
	shapes:       []Shape,
	// The low corner of cell (0, 0).
	min_x, min_z: f32,
	cell:         f32,
	inv_cell:     f32,
	cols, rows:   int,
	// Cell (x, z) is number z * cols + x. Its Shapes, by index in shapes and
	// in rising order, are items[starts[c]:starts[c + 1]].
	starts:       []i32,
	items:        []i32,
	// The Shapes the grid does not hold, in rising order: those that span too
	// many cells, and those with a size or place the grid cannot use.
	big:          []i32,
	is_big:       []bool,
	// The id set of shapes_make, which finds a Shape by its id.
	slots:        []i32,
}

// The first and last column and row of the cells under a box.
@(private = "file")
Cell_Range :: struct {
	x0, x1, z0, z1: int,
}

// The world is built on first use, so a step that asks nothing of the
// Colliders does not build it.
@(private = "file")
Lazy_World :: struct {
	search:    ^Query_Search,
	colliders: []Collider,
	allocator: mem.Allocator,
	world:     Query_World,
	made:      bool,
}

// The ContactsOf search. seen[j] holds the asking Shape that last tested
// Shape j, plus 1, so a Shape in several cells is tested once.
@(private = "file")
Asked_Search :: struct {
	contacts: [dynamic]Contact,
	shapes:   []Shape,
	asking:   []bool,
	seen:     []i32,
}

// One Raycast while the host walks the grid.
@(private = "file")
Ray_Search :: struct {
	origin, dir: [3]f32,
	owner:       u64,
	exclude:     []u64,
	nearest:     f32,
	normal:      [3]f32,
	id:          u64,
	ok:          bool,
}

query_search_init :: proc(search: ^Query_Search, allocator: mem.Allocator) {
	search.logged_ids = make(map[u64]struct {}, allocator)
	search.logged_slots = make(map[Owner_Slot]struct {}, allocator)
}

query_search_destroy :: proc(search: ^Query_Search) {
	delete(search.logged_ids)
	delete(search.logged_slots)
}

// Every Query's answers. The Shapes and the grid are built once for all of
// them. Everything it allocates, the answers included, comes from allocator.
queries_answer :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> Query_Answers {
	lazy := lazy_make(search, colliders, allocator)
	return {contacts = lazy_contacts_asked(&lazy, queries), rays = lazy_rays_find(&lazy, queries), overlaps = lazy_overlaps_find(&lazy, queries)}
}

// One Contact per overlapping pair, with a < b, sorted by (a, b). Everything
// it allocates, the result included, comes from allocator.
contacts_find :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> []Contact {
	if len(colliders) == 0 {
		return nil
	}
	world := world_make(search, colliders, allocator)
	return world_contacts(&world, allocator)
}

// The Contacts that involve an owner of a ContactsOf Query, in the order
// contacts_find gives. With no such Query, it does no search.
contacts_asked :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Contact {
	lazy := lazy_make(search, colliders, allocator)
	return lazy_contacts_asked(&lazy, queries)
}

// One RayHit for each Raycast that hits, in Query order. A ray that starts
// inside a Collider hits it at its origin, with the normal against dir.
rays_find :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Ray_Hit {
	lazy := lazy_make(search, colliders, allocator)
	return lazy_rays_find(&lazy, queries)
}

// One OverlapHit for each Collider an Overlap touches, in Query order and
// then id order. Touching faces do not overlap.
overlaps_find :: proc(search: ^Query_Search, colliders: []Collider, queries: []Query, allocator: mem.Allocator) -> []Overlap_Hit {
	lazy := lazy_make(search, colliders, allocator)
	return lazy_overlaps_find(&lazy, queries)
}

@(private = "file")
lazy_make :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> Lazy_World {
	return {search = search, colliders = colliders, allocator = allocator}
}

@(private = "file")
lazy_world :: proc(lazy: ^Lazy_World) -> ^Query_World {
	if !lazy.made {
		lazy.world = world_make(lazy.search, lazy.colliders, lazy.allocator)
		lazy.made = true
	}
	return &lazy.world
}

// It searches only the cells under each asking Shape.
@(private = "file")
lazy_contacts_asked :: proc(lazy: ^Lazy_World, queries: []Query) -> []Contact {
	asks := false
	for query in queries {
		asks ||= query.tag == .ContactsOf
	}
	if !asks || len(lazy.colliders) == 0 {
		return nil
	}
	world := lazy_world(lazy)
	search := Asked_Search {
		contacts = make([dynamic]Contact, lazy.allocator),
		shapes   = world.shapes,
		asking   = make([]bool, len(world.shapes), lazy.allocator),
		seen     = make([]i32, len(world.shapes), lazy.allocator),
	}
	for query in queries {
		if query.tag == .ContactsOf {
			if i, ok := world_find(world, query.payload.contacts_of); ok {
				search.asking[i] = true
			}
		}
	}

	for ia in 0 ..< len(world.shapes) {
		if !search.asking[ia] {
			continue
		}
		if world.is_big[ia] {
			for ib in 0 ..< len(world.shapes) {
				asked_visit(&search, ia, ib)
			}
			continue
		}
		for ib in world.big {
			asked_visit(&search, ia, int(ib))
		}
		r := cell_range(world, &world.shapes[ia])
		for z in r.z0 ..= r.z1 {
			for x in r.x0 ..= r.x1 {
				for ib in cell_items(world, x, z) {
					asked_visit(&search, ia, int(ib))
				}
			}
		}
	}
	contacts_sort(search.contacts[:])
	return search.contacts[:]
}

// A pair of two asking Shapes is tested from the lower index.
@(private = "file")
asked_visit :: proc(search: ^Asked_Search, ia, ib: int) {
	stamp := i32(ia + 1)
	if ib == ia || search.seen[ib] == stamp || (search.asking[ib] && ib < ia) {
		return
	}
	search.seen[ib] = stamp
	if aabbs_overlap(&search.shapes[ia], &search.shapes[ib]) {
		pair_contact(&search.contacts, search.shapes, i32(ia), i32(ib))
	}
}

@(private = "file")
lazy_rays_find :: proc(lazy: ^Lazy_World, queries: []Query) -> []Ray_Hit {
	hits := make([dynamic]Ray_Hit, lazy.allocator)
	asked := make(map[Owner_Slot]struct {}, lazy.allocator)
	for query in queries {
		if query.tag != .Raycast {
			continue
		}
		ray := query.payload.raycast
		if !query_slot_claim(lazy.search, &asked, {.Raycast, ray.owner, ray.slot}) {
			continue
		}
		hit, ok := ray_nearest(ray, lazy_world(lazy))
		if ok {
			append(&hits, hit)
		}
	}
	return hits[:]
}

@(private = "file")
lazy_overlaps_find :: proc(lazy: ^Lazy_World, queries: []Query) -> []Overlap_Hit {
	hits := make([dynamic]Overlap_Hit, lazy.allocator)
	asked := make(map[Owner_Slot]struct {}, lazy.allocator)
	// seen[i] holds the number of the last Overlap that tested Shape i, so a
	// Shape in several cells is tested once.
	seen: []i32
	for query, number in queries {
		if query.tag != .Overlap {
			continue
		}
		overlap := query.payload.overlap
		if !query_slot_claim(lazy.search, &asked, {.Overlap, overlap.owner, overlap.slot}) {
			continue
		}
		world := lazy_world(lazy)
		if seen == nil {
			seen = make([]i32, len(world.shapes), lazy.allocator)
		}
		stamp := i32(number + 1)
		probe := overlap_shape_make(overlap)
		exclude := overlap.exclude.elements[:overlap.exclude.length]
		first := len(hits)
		if !shape_fits_grid(&probe) {
			// The grid cannot place this probe, so it tests every Shape.
			for &shape in world.shapes {
				overlap_test(&hits, overlap, exclude, &probe, &shape)
			}
		} else {
			for i in world.big {
				overlap_test(&hits, overlap, exclude, &probe, &world.shapes[i])
			}
			if world.cols > 0 {
				r := cell_range(world, &probe)
				for z in r.z0 ..= r.z1 {
					for x in r.x0 ..= r.x1 {
						for i in cell_items(world, x, z) {
							if seen[i] == stamp {
								continue
							}
							seen[i] = stamp
							overlap_test(&hits, overlap, exclude, &probe, &world.shapes[i])
						}
					}
				}
			}
		}
		heap_sort(hits[first:], proc(x, y: Overlap_Hit) -> bool {return x.id < y.id})
	}
	return hits[:]
}

// The box test only skips the narrowphase when both boxes are usable.
@(private = "file")
overlap_test :: proc(hits: ^[dynamic]Overlap_Hit, overlap: Query_Overlap, exclude: []u64, probe, shape: ^Shape) {
	if shape.id == overlap.owner || slice.contains(exclude, shape.id) {
		return
	}
	if shape_fits_grid(probe) && shape_fits_grid(shape) && !aabbs_overlap(probe, shape) {
		return
	}
	if _, _, ok := narrowphase(probe^, shape^); ok {
		append(hits, Overlap_Hit{owner = overlap.owner, slot = overlap.slot, id = shape.id})
	}
}

// false for a second Query with the same owner and slot. It logs each once.
@(private = "file")
query_slot_claim :: proc(search: ^Query_Search, asked: ^map[Owner_Slot]struct {}, key: Owner_Slot) -> bool {
	if key in asked {
		if key not_in search.logged_slots {
			search.logged_slots[key] = {}
			fmt.eprintfln("two queries share owner %v and slot %v; the first one is answered", key.owner, key.slot)
		}
		return false
	}
	asked[key] = {}
	return true
}

// The cell size is a few times the geometric mean of the Shapes' sizes, so
// one huge Shape, such as a ground box, does not set it. A Shape that does
// not fit the grid goes to big, and if no cell size works, every Shape does.
@(private = "file")
world_make :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> (world: Query_World) {
	shapes, slots := shapes_make(search, colliders, allocator)
	world.shapes = shapes[:]
	world.slots = slots
	n := len(shapes)
	if n == 0 {
		return
	}
	world.is_big = make([]bool, n, allocator)
	big := make([dynamic]i32, allocator)

	lo := [2]f32{max(f32), max(f32)}
	hi := [2]f32{min(f32), min(f32)}
	log_size: f32
	fitting := 0
	for &shape in shapes {
		if !shape_fits_grid(&shape) {
			continue
		}
		lo = {min(lo.x, shape.min.x), min(lo.y, shape.min.z)}
		hi = {max(hi.x, shape.max.x), max(hi.y, shape.max.z)}
		log_size += math.ln(max(shape.max.x - shape.min.x, shape.max.z - shape.min.z, GRID_MIN_SIZE))
		fitting += 1
	}
	span := hi - lo
	cell := GRID_CELL_SCALE * math.exp(log_size / f32(max(fitting, 1)))
	limit := f32(GRID_CELLS_PER_SHAPE * n)
	cell = max(cell, math.sqrt(span.x * span.y / limit), span.x / limit, span.y / limit)
	if fitting == 0 || !(cell < max(f32)) || !(span.x < max(f32)) || !(span.y < max(f32)) {
		for i in 0 ..< n {
			world.is_big[i] = true
			append(&big, i32(i))
		}
		world.big = big[:]
		return
	}
	world.min_x, world.min_z = lo.x, lo.y
	world.cell = cell
	world.inv_cell = 1 / cell
	world.cols = int(span.x / cell) + 1
	world.rows = int(span.y / cell) + 1

	counts := make([]i32, world.cols * world.rows + 1, allocator)
	// Each Shape's cells, kept for the second pass.
	ranges := make([]Cell_Range, n, allocator)
	for &shape, i in shapes {
		r := cell_range(&world, &shape)
		if !shape_fits_grid(&shape) || r.x1 - r.x0 >= GRID_BIG_SPAN || r.z1 - r.z0 >= GRID_BIG_SPAN {
			world.is_big[i] = true
			append(&big, i32(i))
			continue
		}
		ranges[i] = r
		for z in r.z0 ..= r.z1 {
			for x in r.x0 ..= r.x1 {
				counts[z * world.cols + x + 1] += 1
			}
		}
	}
	for c in 1 ..< len(counts) {
		counts[c] += counts[c - 1]
	}
	world.starts = counts
	world.big = big[:]

	world.items = make([]i32, counts[len(counts) - 1], allocator)
	next := slice.clone(counts[:len(counts) - 1], allocator)
	for r, i in ranges {
		if world.is_big[i] {
			continue
		}
		for z in r.z0 ..= r.z1 {
			for x in r.x0 ..= r.x1 {
				c := z * world.cols + x
				world.items[next[c]] = i32(i)
				next[c] += 1
			}
		}
	}
	return
}

// false for a Shape whose box the grid cannot use: a box at infinity, with a
// NaN, or inside out from a negative size.
@(private = "file")
shape_fits_grid :: proc(shape: ^Shape) -> bool {
	span := shape.max - shape.min
	return span.x >= 0 && span.y >= 0 && span.z >= 0 && span.x < max(f32) && span.y < max(f32) && span.z < max(f32)
}

@(private = "file")
cell_range :: proc(world: ^Query_World, shape: ^Shape) -> Cell_Range {
	return {grid_x(world, shape.min.x), grid_x(world, shape.max.x), grid_z(world, shape.min.z), grid_z(world, shape.max.z)}
}

@(private = "file")
cell_items :: proc(world: ^Query_World, x, z: int) -> []i32 {
	c := z * world.cols + x
	return world.items[world.starts[c]:world.starts[c + 1]]
}

// The column that holds x, clamped to the grid. A NaN gives column 0.
@(private = "file")
grid_x :: proc(world: ^Query_World, x: f32) -> int {
	return int(clamp((x - world.min_x) * world.inv_cell, 0, f32(world.cols - 1)))
}

@(private = "file")
grid_z :: proc(world: ^Query_World, z: f32) -> int {
	return int(clamp((z - world.min_z) * world.inv_cell, 0, f32(world.rows - 1)))
}

@(private = "file")
world_contacts :: proc(world: ^Query_World, allocator: mem.Allocator) -> []Contact {
	contacts := make([dynamic]Contact, allocator)
	shapes := world.shapes
	for z in 0 ..< world.rows {
		for x in 0 ..< world.cols {
			items := cell_items(world, x, z)
			for ia, k in items {
				a := &shapes[ia]
				for ib in items[k + 1:] {
					b := &shapes[ib]
					if !aabbs_overlap(a, b) {
						continue
					}
					// A pair can share several cells. Only the cell that holds the
					// corner where the two boxes start to overlap gives it.
					if grid_x(world, max(a.min.x, b.min.x)) != x || grid_z(world, max(a.min.z, b.min.z)) != z {
						continue
					}
					pair_contact(&contacts, shapes, ia, ib)
				}
			}
		}
	}
	for ib in world.big {
		for &a, ia in shapes {
			if (world.is_big[ia] && i32(ia) >= ib) || !aabbs_overlap(&a, &shapes[ib]) {
				continue
			}
			pair_contact(&contacts, shapes, i32(ia), ib)
		}
	}
	contacts_sort(contacts[:])
	return contacts[:]
}

@(private = "file")
contacts_sort :: proc(contacts: []Contact) {
	heap_sort(contacts, proc(x, y: Contact) -> bool {return x.a < y.a || (x.a == y.a && x.b < y.b)})
}

// Touching boxes count, so the narrowphase decides.
@(private = "file")
aabbs_overlap :: proc(a, b: ^Shape) -> bool {
	return !(b.min.x > a.max.x || a.min.x > b.max.x || b.min.y > a.max.y || a.min.y > b.max.y || b.min.z > a.max.z || a.min.z > b.max.z)
}

// The narrowphase takes the Shape that starts first on x as a, then the
// lower index, as a sweep on x would.
@(private = "file")
pair_contact :: proc(contacts: ^[dynamic]Contact, shapes: []Shape, ia, ib: i32) {
	a, b := &shapes[ia], &shapes[ib]
	if b.min.x < a.min.x || (b.min.x == a.min.x && ib < ia) {
		a, b = b, a
	}
	normal, depth, ok := narrowphase(a^, b^)
	if !ok {
		return
	}
	if a.id > b.id {
		append(contacts, Contact{a = b.id, b = a.id, normal = to_vec3(-normal), depth = depth})
	} else {
		append(contacts, Contact{a = a.id, b = b.id, normal = to_vec3(normal), depth = depth})
	}
}

// It walks the cells along the ray and stops once the next cell starts past
// the nearest hit. A ray with a NaN or an infinity tests every Shape.
@(private = "file")
ray_nearest :: proc(ray: Query_Raycast, world: ^Query_World) -> (hit: Ray_Hit, ok: bool) {
	dir := [3]f32{ray.dir.x, ray.dir.y, ray.dir.z}
	length := v3_length(dir)
	if length == 0 {
		return {}, false
	}
	r := Ray_Search {
		origin  = {ray.origin.x, ray.origin.y, ray.origin.z},
		dir     = dir / length,
		owner   = ray.owner,
		exclude = ray.exclude.elements[:ray.exclude.length],
		nearest = ray.max_distance,
	}
	// x - x is 0 only for a finite x.
	if r.origin - r.origin != 0 || r.dir - r.dir != 0 {
		for &shape in world.shapes {
			ray_consider(&r, &shape)
		}
	} else {
		for i in world.big {
			ray_consider(&r, &world.shapes[i])
		}
		if world.cols > 0 {
			ray_walk(&r, world)
		}
	}
	if !r.ok {
		return {}, false
	}
	hit.owner = ray.owner
	hit.slot = ray.slot
	hit.id = r.id
	hit.point = to_vec3(r.origin + r.dir * r.nearest)
	hit.normal = to_vec3(r.normal)
	hit.distance = r.nearest
	return hit, true
}

@(private = "file")
ray_walk :: proc(r: ^Ray_Search, world: ^Query_World) {
	// Clip the ray to the grid's rectangle on x and z.
	enter, exit := f32(0), r.nearest
	lo := [2]f32{world.min_x, world.min_z}
	hi := lo + {f32(world.cols), f32(world.rows)} * world.cell
	ground := [2]f32{r.dir.x, r.dir.z}
	start := [2]f32{r.origin.x, r.origin.z}
	for axis in 0 ..< 2 {
		if ground[axis] == 0 {
			if start[axis] < lo[axis] || start[axis] > hi[axis] {
				return
			}
			continue
		}
		near := (lo[axis] - start[axis]) / ground[axis]
		far := (hi[axis] - start[axis]) / ground[axis]
		enter = max(enter, min(near, far))
		exit = min(exit, max(near, far))
	}
	if enter > exit {
		return
	}

	at := start + ground * enter
	cell := [2]int{grid_x(world, at.x), grid_z(world, at.y)}
	step: [2]int
	next, delta: [2]f32
	for axis in 0 ..< 2 {
		low := lo[axis] + f32(cell[axis]) * world.cell
		if ground[axis] > 0 {
			step[axis] = 1
			next[axis] = (low + world.cell - start[axis]) / ground[axis]
			delta[axis] = world.cell / ground[axis]
		} else if ground[axis] < 0 {
			step[axis] = -1
			next[axis] = (low - start[axis]) / ground[axis]
			delta[axis] = -world.cell / ground[axis]
		} else {
			next[axis] = max(f32)
		}
	}
	// Float error in next can put a hit just past a cell's computed end.
	slack := world.cell * 1e-3
	for {
		ray_cell(r, world, cell)
		leave := min(next.x, next.y)
		// A ray along y never leaves its cell.
		if step == {0, 0} || leave > r.nearest + slack || leave > exit + slack {
			return
		}
		axis := 0 if next.x < next.y else 1
		// Near a corner, float error can send the walk past the wrong side of
		// it, so the cell across the other edge is tested too.
		if abs(next.x - next.y) <= slack && step.x != 0 && step.y != 0 {
			side := cell
			side[1 - axis] += step[1 - axis]
			ray_cell(r, world, side)
		}
		cell[axis] += step[axis]
		next[axis] += delta[axis]
		if cell.x < 0 || cell.x >= world.cols || cell.y < 0 || cell.y >= world.rows {
			return
		}
	}
}

// It skips a cell outside the grid.
@(private = "file")
ray_cell :: proc(r: ^Ray_Search, world: ^Query_World, cell: [2]int) {
	if cell.x < 0 || cell.x >= world.cols || cell.y < 0 || cell.y >= world.rows {
		return
	}
	for i in cell_items(world, cell.x, cell.y) {
		ray_consider(r, &world.shapes[i])
	}
}

@(private = "file")
ray_consider :: proc(r: ^Ray_Search, shape: ^Shape) {
	if shape.id == r.owner || slice.contains(r.exclude, shape.id) {
		return
	}
	distance, normal, ok := ray_shape(r.origin, r.dir, shape^)
	if !ok {
		return
	}
	// Equal distances go to the lower id, so the Collider order does not matter.
	if distance < r.nearest || (distance == r.nearest && (!r.ok || shape.id < r.id)) {
		r.nearest = distance
		r.normal = normal
		r.id = shape.id
		r.ok = true
	}
}

// dir is a unit vector. shape_make never makes a capsule.
@(private = "file")
ray_shape :: proc(origin, dir: [3]f32, shape: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	switch shape.tag {
	case .Box:
		return ray_box(origin, dir, shape)
	case .Sphere:
		return ray_sphere(origin, dir, shape)
	case .Capsule:
	}
	return 0, {}, false
}

// A slab test in the box's frame.
@(private = "file")
ray_box :: proc(origin, dir: [3]f32, box: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	d := origin - box.centre
	local_origin := [3]f32{v3_dot(d, box.axes[0]), d.y, v3_dot(d, box.axes[1])}
	local_dir := [3]f32{v3_dot(dir, box.axes[0]), dir.y, v3_dot(dir, box.axes[1])}

	enter, exit := min(f32), max(f32)
	local_normal: [3]f32
	for i in 0 ..< 3 {
		if local_dir[i] == 0 {
			if abs(local_origin[i]) > box.extent[i] {
				return 0, {}, false
			}
			continue
		}
		near := (-math.sign(local_dir[i]) * box.extent[i] - local_origin[i]) / local_dir[i]
		far := (math.sign(local_dir[i]) * box.extent[i] - local_origin[i]) / local_dir[i]
		if near > enter {
			enter = near
			local_normal = {}
			local_normal[i] = -math.sign(local_dir[i])
		}
		exit = min(exit, far)
	}
	if exit < max(enter, 0) {
		return 0, {}, false
	}
	if enter <= 0 {
		return 0, -dir, true
	}
	return enter, local_normal.x * box.axes[0] + local_normal.y * UP + local_normal.z * box.axes[1], true
}

@(private = "file")
ray_sphere :: proc(origin, dir: [3]f32, sphere: Shape) -> (distance: f32, normal: [3]f32, ok: bool) {
	d := origin - sphere.centre
	radius := sphere.extent.x
	inside := v3_dot(d, d) - radius * radius
	if inside <= 0 {
		return 0, -dir, true
	}
	along := v3_dot(d, dir)
	disc := along * along - inside
	if along >= 0 || disc < 0 {
		return 0, {}, false
	}
	distance = -along - math.sqrt(disc)
	return distance, (d + dir * distance) / radius, true
}

// Each Collider the host can test, with each id once. It logs a capsule and
// a shared id once each.
@(private = "file")
shapes_make :: proc(search: ^Query_Search, colliders: []Collider, allocator: mem.Allocator) -> (shapes: [dynamic]Shape, slots: []i32) {
	shapes = make([dynamic]Shape, 0, len(colliders), allocator)
	// An open-addressing set of the ids so far: a slot holds a Shape's index
	// plus 1, or 0 when it is empty. A map costs several times as much here.
	slots = make([]i32, max(16, math.next_power_of_two(2 * len(colliders))), allocator)
	for col in colliders {
		// A skipped Collider does not claim its id.
		shape, ok := shape_make(col)
		if !ok {
			if !search.logged_capsule {
				search.logged_capsule = true
				fmt.eprintfln("collider %v is a capsule; queries skip capsules", col.id)
			}
			continue
		}
		slot := id_slot(shapes[:], slots, col.id)
		if slots[slot] != 0 {
			if col.id not_in search.logged_ids {
				search.logged_ids[col.id] = {}
				fmt.eprintfln("two colliders share id %v; the first one collides", col.id)
			}
			continue
		}
		append(&shapes, shape)
		slots[slot] = i32(len(shapes))
	}
	return
}

// The slot that holds id, or the empty slot where it would go. len(slots) is
// a power of two.
@(private = "file")
id_slot :: proc(shapes: []Shape, slots: []i32, id: u64) -> u64 {
	mask := u64(len(slots) - 1)
	slot := (id * 0x9E3779B97F4A7C15 >> 32) & mask
	for slots[slot] != 0 && shapes[slots[slot] - 1].id != id {
		slot = (slot + 1) & mask
	}
	return slot
}

// The index of the Shape with id.
@(private = "file")
world_find :: proc(world: ^Query_World, id: u64) -> (index: int, ok: bool) {
	slot := world.slots[id_slot(world.shapes, world.slots, id)]
	return int(slot) - 1, slot != 0
}

// ok is false for a capsule: the host does not test capsules yet.
@(private = "file")
shape_make :: proc(col: Collider) -> (b: Shape, ok: bool) {
	b = Shape {
		id     = col.id,
		tag    = col.shape.tag,
		centre = {col.pos.x, col.pos.y, col.pos.z},
	}
	reach: [3]f32
	switch col.shape.tag {
	case .Box:
		half := col.shape.payload.box
		b.extent = {half.x, half.y, half.z}
		// Turned the way the host turns a Draw: +z goes to (sin, 0, cos).
		s, c := math.sincos(col.yaw)
		b.axes = {{c, 0, -s}, {s, 0, c}}
		reach = {abs(c) * b.extent.x + abs(s) * b.extent.z, b.extent.y, abs(s) * b.extent.x + abs(c) * b.extent.z}
	case .Sphere:
		b.extent.x = col.shape.payload.sphere
		reach = b.extent.x
	case .Capsule:
		return {}, false
	}
	b.min = b.centre - reach
	b.max = b.centre + reach
	return b, true
}

// An Overlap box does not turn.
@(private = "file")
overlap_shape_make :: proc(overlap: Query_Overlap) -> Shape {
	shape := Shape {
		centre = {overlap.pos.x, overlap.pos.y, overlap.pos.z},
		axes   = {{1, 0, 0}, {0, 0, 1}},
	}
	switch overlap.shape.tag {
	case .Box:
		half := overlap.shape.payload.box
		shape.tag = .Box
		shape.extent = {half.x, half.y, half.z}
	case .Sphere:
		shape.tag = .Sphere
		shape.extent.x = overlap.shape.payload.sphere
		shape.extent.y = shape.extent.x
		shape.extent.z = shape.extent.x
	}
	shape.min = shape.centre - shape.extent
	shape.max = shape.centre + shape.extent
	return shape
}

// The normal points from a to b. shape_make never makes a capsule.
@(private = "file")
narrowphase :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	switch a.tag {
	case .Box:
		switch b.tag {
		case .Box:
			return box_box(a, b)
		case .Sphere:
			return box_sphere(a, b)
		case .Capsule:
		}
	case .Sphere:
		switch b.tag {
		case .Box:
			normal, depth = box_sphere(b, a) or_return
			return -normal, depth, true
		case .Sphere:
			return sphere_sphere(a, b)
		case .Capsule:
		}
	case .Capsule:
	}
	return {}, 0, false
}

// A separating axis test on y and the ground-plane axes of each box. A box
// only turns about y, so no edge cross product can separate them.
@(private = "file")
box_box :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := b.centre - a.centre
	depth = max(f32)
	for axis in ([5][3]f32{UP, a.axes[0], a.axes[1], b.axes[0], b.axes[1]}) {
		along := v3_dot(d, axis)
		overlap := box_reach(a, axis) + box_reach(b, axis) - abs(along)
		if overlap <= 0 {
			return {}, 0, false
		}
		if overlap < depth {
			depth = overlap
			normal = axis if along >= 0 else -axis
		}
	}
	return normal, depth, true
}

@(private = "file")
box_reach :: proc(box: Shape, axis: [3]f32) -> f32 {
	return box.extent.x * abs(v3_dot(box.axes[0], axis)) + box.extent.y * abs(axis.y) + box.extent.z * abs(v3_dot(box.axes[1], axis))
}

// Two spheres at the same centre push apart along +y.
@(private = "file")
sphere_sphere :: proc(a, b: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := b.centre - a.centre
	dist := v3_length(d)
	depth = a.extent.x + b.extent.x - dist
	if depth <= 0 {
		return {}, 0, false
	}
	return d / dist if dist > 0 else UP, depth, true
}

// The normal points from the box to the sphere. A sphere whose centre is
// inside the box leaves through the face nearest its centre.
@(private = "file")
box_sphere :: proc(box, sphere: Shape) -> (normal: [3]f32, depth: f32, ok: bool) {
	d := sphere.centre - box.centre
	local := [3]f32{v3_dot(d, box.axes[0]), d.y, v3_dot(d, box.axes[1])}
	off := local - [3]f32{clamp(local.x, -box.extent.x, box.extent.x), clamp(local.y, -box.extent.y, box.extent.y), clamp(local.z, -box.extent.z, box.extent.z)}
	dist := v3_length(off)
	radius := sphere.extent.x

	local_normal: [3]f32
	if dist > 0 {
		if dist >= radius {
			return {}, 0, false
		}
		local_normal = off / dist
		depth = radius - dist
	} else {
		depth = max(f32)
		for i in 0 ..< 3 {
			through := box.extent[i] - abs(local[i]) + radius
			if through < depth {
				depth = through
				local_normal = {}
				local_normal[i] = 1 if local[i] >= 0 else -1
			}
		}
	}
	return local_normal.x * box.axes[0] + local_normal.y * UP + local_normal.z * box.axes[1], depth, true
}

// slice.sort_by calls less through a pointer and swaps bytes. This one is
// built per element type and less.
@(private = "file")
heap_sort :: proc(data: []$T, $less: proc(a, b: T) -> bool) {
	sift :: #force_inline proc(data: []T, root, n: int) {
		root := root
		for {
			child := 2 * root + 1
			if child >= n {
				return
			}
			if child + 1 < n && less(data[child], data[child + 1]) {
				child += 1
			}
			if !less(data[root], data[child]) {
				return
			}
			data[root], data[child] = data[child], data[root]
			root = child
		}
	}
	n := len(data)
	for i := n / 2 - 1; i >= 0; i -= 1 {
		sift(data, i, n)
	}
	for end := n - 1; end > 0; end -= 1 {
		data[0], data[end] = data[end], data[0]
		sift(data, 0, end)
	}
}

@(private = "file")
to_vec3 :: proc(v: [3]f32) -> Vec3 {
	return {v.x, v.y, v.z}
}
