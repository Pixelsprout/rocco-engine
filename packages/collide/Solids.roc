import linalg.Vec3 as V

## The static shapes a character collides with in the same step, filed in a
## uniform grid on x and z. Build it once with `build` and keep it in the
## Model. It never changes, so a moving shape does not belong in it.
Solids :: {
	shapes : List(Solids.Solid),
	spans : List(Span),
	wide : List(U64),
	grid : Grid,
	cells : List(List(U64)),
}.{

	## A box turned by `yaw` about `+y`, the way the host turns a Draw, or a
	## sphere. A box carries its half extents, as a `Collider` box does.
	Solid : [Box({ center : V.Vec3, half_extents : V.Vec3, yaw : F32 }), Sphere({ center : V.Vec3, radius : F32 })]

	## An axis-aligned box from `min` to `max`.
	Bounds : { min : V.Vec3, max : V.Vec3 }

	## Files each Solid in the cells of `cell_size` metres that its bounds
	## cover. A Solid wider than eight cells, or with a bound that is not
	## finite, goes to a list that every query tests, so one ground box does
	## not stretch the grid. A `cell_size` that is not above zero crashes.
	build : List(Solids.Solid), F32 -> Solids
	build = |shapes, cell_size| {
		if !(cell_size > 0.0) {
			crash "Solids.build: cell_size must be above zero"
		}
		all_bounds = shapes.map(Solids.bounds_of)
		is_wide = |bounds| !is_finite_bounds(bounds) or (bounds.max.x - bounds.min.x) > cell_size * wide_cells or (bounds.max.z - bounds.min.z) > cell_size * wide_cells
		grid = all_bounds.drop_if(is_wide).fold(
			Empty,
			|seen, bounds| match seen {
				Empty => Seen(bounds)
				Seen(sum) => Seen(union(sum, bounds))
			},
		)
		layout = match grid {
			Empty => { origin: { x: 0.0, z: 0.0 }, cell: cell_size, columns: 0, rows: 0 }
			Seen(sum) => {
				origin: { x: sum.min.x, z: sum.min.z },
				cell: cell_size,
				columns: cells_across({ extent: sum.max.x - sum.min.x, cell: cell_size }),
				rows: cells_across({ extent: sum.max.z - sum.min.z, cell: cell_size }),
			}
		}
		spans = all_bounds.map(|bounds| if (is_wide(bounds)) Wide else span_of(layout, bounds))
		var $cells = List.repeat([], layout.columns * layout.rows)
		var $wide = []
		var $index = 0
		for span in spans {
			match span {
				Wide => {
					$wide = $wide.append($index)
				}
				Cells(range) =>
					for row in range.z0.until(range.z1 + 1) {
						for column in range.x0.until(range.x1 + 1) {
							$cells = match $cells.update(row * layout.columns + column, |list| list.append($index)) {
								Ok(filed) => filed
								Err(OutOfBounds) => crash "Solids.build: a span reaches past the grid"
							}
						}
					}
			}
			$index = $index + 1
		}
		Solids.({ shapes, spans, wide: $wide, grid: layout, cells: $cells })
	}

	## The Solids whose bounds overlap `bounds`. The grid reads only the
	## cells under `bounds`, and each Solid comes back once.
	near : Solids, Solids.Bounds -> List(Solids.Solid)
	near = |Solids.(solids), bounds| {
		is_touching = |index| match solids.shapes.get(index) {
			Ok(shape) => is_overlapping(Solids.bounds_of(shape), bounds)
			Err(OutOfBounds) => crash "Solids.near: a cell holds an index past the shapes"
		}
		from_wide = solids.wide.keep_if(is_touching)
		from_cells = match span_of_query(solids.grid, bounds) {
			Outside => []
			Cells(range) => {
				var $found = []
				for row in range.z0.until(range.z1 + 1) {
					for column in range.x0.until(range.x1 + 1) {
						cell = match solids.cells.get(row * solids.grid.columns + column) {
							Ok(indexes) => indexes
							Err(OutOfBounds) => crash "Solids.near: a query range reaches past the grid"
						}
						for index in cell {
							# A Solid in many cells counts only in the first cell that
							# both its span and the query share.
							is_first = match solids.spans.get(index) {
								Ok(Cells(span)) => column == U64.max(span.x0, range.x0) and row == U64.max(span.z0, range.z0)
								Ok(Wide) => crash "Solids.near: a wide Solid is filed in a cell"
								Err(OutOfBounds) => crash "Solids.near: a cell holds an index past the spans"
							}
							if is_first and is_touching(index) {
								$found = $found.append(index)
							}
						}
					}
				}
				$found
			}
		}
		List.join([from_wide, from_cells]).keep_oks(|index| solids.shapes.get(index))
	}

	## A vertical capsule: the point under its centre, where it stands, and
	## its radius and total height. A height below twice the radius counts as
	## a sphere.
	Capsule : { foot : V.Vec3, radius : F32, height : F32 }

	## Moves the capsule out of each Solid it overlaps, one Solid at a time,
	## along the shortest way out. Against a box the capsule counts as its
	## segment in a box grown by the radius, so its edges are square. The
	## `normal` is the unit direction of the whole move, and zero if two
	## pushes cancel. It tests the Solids near the capsule where it starts, so
	## a capsule pressed between two Solids can stay in one of them.
	push_out : Solids, Solids.Capsule -> [Pushed({ foot : V.Vec3, normal : V.Vec3 }), Clear]
	push_out = |solids, capsule| {
		segment_top = F32.max(capsule.height - capsule.radius, capsule.radius)
		reach = { min: V.add(capsule.foot, { x: -capsule.radius, y: 0.0, z: -capsule.radius }), max: V.add(capsule.foot, { x: capsule.radius, y: segment_top + capsule.radius, z: capsule.radius }) }
		moved = Solids.near(solids, reach).fold(
			Clear,
			|state, solid| {
				foot = match state {
					Clear => capsule.foot
					Moved(at) => at
				}
				match way_out(solid, { ..capsule, foot }) {
					Out(step) => Moved(V.add(foot, step))
					Apart => state
				}
			},
		)
		match moved {
			Clear => Clear
			Moved(foot) => Pushed({ foot, normal: V.normalize(V.sub(foot, capsule.foot)) })
		}
	}

	## The axis-aligned box around a Solid. A turned box grows to hold its
	## corners.
	bounds_of : Solids.Solid -> Solids.Bounds
	bounds_of = |solid| match solid {
		Box({ center, half_extents, yaw }) => {
			c = yaw.cos().abs()
			s = yaw.sin().abs()
			reach = { x: c * half_extents.x + s * half_extents.z, y: half_extents.y, z: s * half_extents.x + c * half_extents.z }
			{ min: V.sub(center, reach), max: V.add(center, reach) }
		}
		Sphere({ center, radius }) => {
			reach = { x: radius, y: radius, z: radius }
			{ min: V.sub(center, reach), max: V.add(center, reach) }
		}
	}
}

# A Solid wider than this many cells on x or z goes to the wide list.
wide_cells : F32
wide_cells = 8.0

Grid : { origin : { x : F32, z : F32 }, cell : F32, columns : U64, rows : U64 }

# Inclusive on both ends.
CellRange : { x0 : U64, z0 : U64, x1 : U64, z1 : U64 }

Span : [Wide, Cells(CellRange)]

cells_across : { extent : F32, cell : F32 } -> U64
cells_across = |{ extent, cell }| (extent / cell).div_floor_by(1.0).to_u64_wrap() + 1

# The cell can lie outside the grid.
cell_of : F32, { origin : F32, cell : F32 } -> I64
cell_of = |value, { origin, cell }| ((value - origin) / cell).div_floor_by(1.0).to_i64_wrap()

span_of : Grid, Solids.Bounds -> Span
span_of = |grid, bounds| match span_of_query(grid, bounds) {
	Cells(range) => Cells(range)
	Outside => crash "Solids.build: a Solid lies outside the grid built around it"
}

# The cells under `bounds`, clamped to the grid.
span_of_query : Grid, Solids.Bounds -> [Cells(CellRange), Outside]
span_of_query = |grid, bounds| {
	on_x = { origin: grid.origin.x, cell: grid.cell }
	on_z = { origin: grid.origin.z, cell: grid.cell }
	x0 = cell_of(bounds.min.x, on_x)
	x1 = cell_of(bounds.max.x, on_x)
	z0 = cell_of(bounds.min.z, on_z)
	z1 = cell_of(bounds.max.z, on_z)
	columns = grid.columns.to_i64_wrap()
	rows = grid.rows.to_i64_wrap()
	if columns == 0 or rows == 0 or x1 < 0 or z1 < 0 or x0 >= columns or z0 >= rows or !is_finite_bounds(bounds) {
		Outside
	} else {
		Cells({
			x0: I64.max(x0, 0).to_u64_wrap(),
			z0: I64.max(z0, 0).to_u64_wrap(),
			x1: I64.min(x1, columns - 1).to_u64_wrap(),
			z1: I64.min(z1, rows - 1).to_u64_wrap(),
		})
	}
}

is_finite_bounds : Solids.Bounds -> Bool
is_finite_bounds = |{ min, max }| min.x.is_finite() and min.z.is_finite() and max.x.is_finite() and max.z.is_finite()

is_overlapping : Solids.Bounds, Solids.Bounds -> Bool
is_overlapping = |a, b| a.min.x <= b.max.x and b.min.x <= a.max.x and a.min.y <= b.max.y and b.min.y <= a.max.y and a.min.z <= b.max.z and b.min.z <= a.max.z

union : Solids.Bounds, Solids.Bounds -> Solids.Bounds
union = |a, b| {
	min: { x: F32.min(a.min.x, b.min.x), y: F32.min(a.min.y, b.min.y), z: F32.min(a.min.z, b.min.z) },
	max: { x: F32.max(a.max.x, b.max.x), y: F32.max(a.max.y, b.max.y), z: F32.max(a.max.z, b.max.z) },
}

way_out : Solids.Solid, Solids.Capsule -> [Out(V.Vec3), Apart]
way_out = |solid, { foot, radius, height }| {
	bottom = foot.y + radius
	top = foot.y + F32.max(height - radius, radius)
	match solid {
		Box({ center, half_extents, yaw }) => {
			c = yaw.cos()
			s = yaw.sin()
			dx = foot.x - center.x
			dz = foot.z - center.z
			local_x = dx * c - dz * s
			local_z = dx * s + dz * c
			reach_x = half_extents.x + radius
			reach_z = half_extents.z + radius
			reach_y = half_extents.y + radius
			low = bottom - center.y
			high = top - center.y
			if local_x.abs() >= reach_x or local_z.abs() >= reach_z or high <= -reach_y or low >= reach_y {
				Apart
			} else {
				ways = [
					{ depth: reach_x - local_x, local: { x: reach_x - local_x, y: 0.0, z: 0.0 } },
					{ depth: reach_x + local_x, local: { x: -(reach_x + local_x), y: 0.0, z: 0.0 } },
					{ depth: reach_z - local_z, local: { x: 0.0, y: 0.0, z: reach_z - local_z } },
					{ depth: reach_z + local_z, local: { x: 0.0, y: 0.0, z: -(reach_z + local_z) } },
					{ depth: reach_y - low, local: { x: 0.0, y: reach_y - low, z: 0.0 } },
					{ depth: high + reach_y, local: { x: 0.0, y: -(high + reach_y), z: 0.0 } },
				]
				shortest = ways.fold({ depth: F32.highest, local: V.zero }, |best, way| if (way.depth < best.depth) way else best)
				# Turn the local move back by the yaw, as the host turns a Draw.
				Out({ x: shortest.local.x * c + shortest.local.z * s, y: shortest.local.y, z: shortest.local.z * c - shortest.local.x * s })
			}
		}
		Sphere(sphere) => {
			nearest = { x: foot.x, y: F32.min(F32.max(sphere.center.y, bottom), top), z: foot.z }
			apart = V.sub(nearest, sphere.center)
			distance = V.length(apart)
			reach = sphere.radius + radius
			if distance >= reach {
				Apart
			} else if distance == 0.0 {
				# The centre is on the segment, so no side is nearer: lift the segment bottom clear.
				Out({ x: 0.0, y: sphere.center.y - bottom + reach, z: 0.0 })
			} else {
				Out(V.scale(apart, (reach - distance) / distance))
			}
		}
	}
}

# A linear congruential step, so the scattered tests replay the same.
next_seed : U64 -> U64
next_seed = |seed| seed.times_wrap(6364136223846793005).plus_wrap(1442695040888963407)

# A value in [low, high) from the top bits of a seed.
seed_to_range : U64, { low : F32, high : F32 } -> F32
seed_to_range = |seed, { low, high }| low + (high - low) * seed.shr_zf_wrap(40).to_f32() / 16777216.0

# Shapes of mixed size and turn across a 40 m square, with one wide floor.
scattered : { count : U64, seed : U64 } -> List(Solids.Solid)
scattered = |{ count, seed }| {
	var $seed = seed
	var $shapes = [Box({ center: { x: 0.0, y: -0.5, z: 0.0 }, half_extents: { x: 200.0, y: 0.5, z: 200.0 }, yaw: 0.0 })]
	for _index in U64.until(0, count) {
		a = next_seed($seed)
		b = next_seed(a)
		c = next_seed(b)
		d = next_seed(c)
		e = next_seed(d)
		center = { x: seed_to_range(a, { low: -20.0, high: 20.0 }), y: seed_to_range(b, { low: 0.0, high: 4.0 }), z: seed_to_range(c, { low: -20.0, high: 20.0 }) }
		size = seed_to_range(d, { low: 0.2, high: 3.0 })
		$shapes = $shapes.append(
			if e.shr_zf_wrap(63) == 0 {
				Box({ center, half_extents: { x: size, y: size * 0.5, z: size * 0.7 }, yaw: seed_to_range(e, { low: 0.0, high: 6.28 }) })
			} else {
				Sphere({ center, radius: size })
			},
		)
		$seed = e
	}
	$shapes
}

query_boxes : List(Solids.Solid) -> List(Solids.Bounds)
query_boxes = |shapes| shapes.map(
	|shape| {
		around = Solids.bounds_of(shape)
		{ min: V.add(around.min, { x: 1.3, y: 0.4, z: -2.1 }), max: V.add(around.max, { x: 2.9, y: 0.4, z: 0.7 }) }
	},
)

has_same_solids : List(Solids.Solid), List(Solids.Solid) -> Bool
has_same_solids = |a, b| a.len() == b.len() and a.all(|solid| b.contains(solid))

## The grid finds the same Solids as a test of every Solid.
expect {
	shapes = scattered({ count: 300, seed: 7 })
	solids = Solids.build(shapes, 2.0)
	query_boxes(shapes).all(|bounds| has_same_solids(Solids.near(solids, bounds), shapes.keep_if(|shape| is_overlapping(Solids.bounds_of(shape), bounds))))
}

## A query box past the edge of the grid still finds the Solids it overlaps.
expect {
	shapes = scattered({ count: 100, seed: 11 })
	solids = Solids.build(shapes, 1.5)
	edge = { min: { x: 18.0, y: -1.0, z: -60.0 }, max: { x: 80.0, y: 9.0, z: -15.0 } }
	has_same_solids(Solids.near(solids, edge), shapes.keep_if(|shape| is_overlapping(Solids.bounds_of(shape), edge)))
}

## A query far from every Solid finds only the wide floor that covers it.
expect {
	solids = Solids.build(scattered({ count: 50, seed: 3 }), 2.0)
	far = { min: { x: 150.0, y: -1.0, z: 150.0 }, max: { x: 151.0, y: 1.0, z: 151.0 } }
	Solids.near(solids, far).len() == 1
}

## A Solid in many cells comes back once.
expect {
	long = Box({ center: { x: 0.0, y: 0.0, z: 0.0 }, half_extents: { x: 5.0, y: 1.0, z: 0.5 }, yaw: 0.0 })
	solids = Solids.build([long], 1.0)
	Solids.near(solids, { min: { x: -4.0, y: -1.0, z: -1.0 }, max: { x: 4.0, y: 1.0, z: 1.0 } }) == [long]
}

## A box turned a quarter turn swaps its reach on x and z.
expect {
	turned = Solids.bounds_of(Box({ center: { x: 0.0, y: 0.0, z: 0.0 }, half_extents: { x: 2.0, y: 1.0, z: 0.5 }, yaw: 1.5707964 }))
	(turned.max.x - 0.5).abs() < 0.0001 and (turned.max.z - 2.0).abs() < 0.0001
}

is_near : V.Vec3, V.Vec3 -> Bool
is_near = |a, b| V.length(V.sub(a, b)) < 0.0001

push_out_of : List(Solids.Solid), Solids.Capsule -> [Pushed({ foot : V.Vec3, normal : V.Vec3 }), Clear]
push_out_of = |shapes, capsule| Solids.push_out(Solids.build(shapes, 2.0), capsule)

block : Solids.Solid
block = Box({ center: { x: 0.0, y: 1.0, z: 0.0 }, half_extents: { x: 1.0, y: 1.0, z: 1.0 }, yaw: 0.0 })

## A capsule in the side of a box moves out along the shallowest axis.
expect {
	match push_out_of([block], { foot: { x: 1.2, y: 0.0, z: 0.3 }, radius: 0.5, height: 1.8 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 1.5, y: 0.0, z: 0.3 }) and is_near(normal, { x: 1.0, y: 0.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A foot just under the top of a box rises onto it.
expect {
	match push_out_of([block], { foot: { x: 0.2, y: 1.9, z: -0.4 }, radius: 0.5, height: 1.8 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 0.2, y: 2.0, z: -0.4 }) and is_near(normal, { x: 0.0, y: 1.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A quarter turn makes a box long on z and thin on x, so the capsule moves out on x.
expect {
	turned = Box({ center: { x: 0.0, y: 1.0, z: 0.0 }, half_extents: { x: 2.0, y: 1.0, z: 0.5 }, yaw: 1.5707964 })
	match push_out_of([turned], { foot: { x: 0.8, y: 0.0, z: 1.5 }, radius: 0.5, height: 1.8 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 1.0, y: 0.0, z: 1.5 }) and is_near(normal, { x: 1.0, y: 0.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A box turned so its local `+x` points along (0.8, 0, -0.6) pushes out along that axis.
expect {
	turned = Box({ center: { x: 0.0, y: 1.0, z: 0.0 }, half_extents: { x: 1.0, y: 1.0, z: 1.0 }, yaw: 0.6435011 })
	match push_out_of([turned], { foot: { x: 1.02, y: 0.0, z: -0.64 }, radius: 0.5, height: 1.8 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 1.26, y: 0.0, z: -0.82 }) and is_near(normal, { x: 0.8, y: 0.0, z: -0.6 })
		Clear => Bool.False
	}
}

## The same box without the turn does not reach the capsule.
expect {
	straight = Box({ center: { x: 0.0, y: 1.0, z: 0.0 }, half_extents: { x: 2.0, y: 1.0, z: 0.5 }, yaw: 0.0 })
	push_out_of([straight], { foot: { x: 0.8, y: 0.0, z: 1.5 }, radius: 0.5, height: 1.8 }) == Clear
}

## A capsule beside a sphere moves out from the nearest point of its segment.
expect {
	ball = Sphere({ center: { x: 0.0, y: 1.0, z: 0.0 }, radius: 1.0 })
	match push_out_of([ball], { foot: { x: 1.2, y: 0.0, z: 0.0 }, radius: 0.5, height: 2.0 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 1.5, y: 0.0, z: 0.0 }) and is_near(normal, { x: 1.0, y: 0.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A capsule above a sphere moves up from the sphere's top.
expect {
	ball = Sphere({ center: { x: 0.0, y: 1.0, z: 0.0 }, radius: 1.0 })
	match push_out_of([ball], { foot: { x: 0.0, y: 1.8, z: 0.0 }, radius: 0.5, height: 2.0 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 0.0, y: 2.0, z: 0.0 }) and is_near(normal, { x: 0.0, y: 1.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A sphere centred on the capsule's segment lifts the capsule clear above it.
expect {
	pebble = Sphere({ center: { x: 0.0, y: 1.0, z: 0.0 }, radius: 0.3 })
	match push_out_of([pebble], { foot: { x: 0.0, y: 0.0, z: 0.0 }, radius: 0.5, height: 2.0 }) {
		Pushed({ foot, normal }) => is_near(foot, { x: 0.0, y: 1.3, z: 0.0 }) and is_near(normal, { x: 0.0, y: 1.0, z: 0.0 })
		Clear => Bool.False
	}
}

## A capsule that touches nothing is Clear.
expect push_out_of([block], { foot: { x: 3.0, y: 0.0, z: 0.0 }, radius: 0.5, height: 1.8 }) == Clear
