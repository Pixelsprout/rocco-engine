import linalg.Vec3 as V
import Solids

## The height of the ground under a point, in the same step. A Ground is a
## function, so a game can write its own or combine the builders here.
Ground := [].{

	## Asked with `x`, `z` and a height `y`, a Ground answers the highest
	## surface at or below `y` under that point, with its unit normal. Ask
	## from above the foot, such as the foot plus the step height. Terrain is
	## solid all the way down, so `flat` and `heights` answer from any `y`.
	Ground : F32, F32, F32 -> Ground.Surface

	## What a Ground answers: the height and unit normal of a surface, or Miss.
	Surface : [Hit({ y : F32, normal : V.Vec3 }), Miss]

	## A level plane at height `y`.
	flat : F32 -> Ground.Ground
	flat = |y| |_x, _z, _from| Hit({ y, normal: up })

	## Terrain from a grid of heights. `heights` is row-major: `columns`
	## heights along `+x` for each of `rows` rows along `+z`, `cell` metres
	## apart from `origin`. Between grid points the height blends bilinearly.
	## A point past the grid misses. A grid smaller than 2 by 2, or a
	## `heights` list of the wrong length, crashes here.
	heights : { origin : { x : F32, z : F32 }, cell : F32, columns : U64, rows : U64, heights : List(F32) } -> Ground.Ground
	heights = |grid| {
		if grid.columns < 2 or grid.rows < 2 {
			crash "Ground.heights: the grid needs at least 2 columns and 2 rows"
		}
		if grid.heights.len() != grid.columns * grid.rows {
			crash "Ground.heights: heights must hold columns * rows values"
		}
		last_column = (grid.columns - 1).to_f32()
		last_row = (grid.rows - 1).to_f32()
		|x, z, _from| {
			along_x = (x - grid.origin.x) / grid.cell
			along_z = (z - grid.origin.z) / grid.cell
			if !(along_x >= 0.0 and along_x <= last_column and along_z >= 0.0 and along_z <= last_row) {
				Miss
			} else {
				# The last row and column belong to the cell before them.
				column = F32.min(along_x.div_floor_by(1.0), last_column - 1.0)
				row = F32.min(along_z.div_floor_by(1.0), last_row - 1.0)
				fx = along_x - column
				fz = along_z - row
				at = |dx, dz| match grid.heights.get((row.to_u64_wrap() + dz) * grid.columns + column.to_u64_wrap() + dx) {
					Ok(height) => height
					Err(OutOfBounds) => crash "Ground.heights: a cell corner lies past the heights"
				}
				h00 = at(0, 0)
				h10 = at(1, 0)
				h01 = at(0, 1)
				h11 = at(1, 1)
				y = (h00 * (1.0 - fx) + h10 * fx) * (1.0 - fz) + (h01 * (1.0 - fx) + h11 * fx) * fz
				slope_x = ((h10 - h00) * (1.0 - fz) + (h11 - h01) * fz) / grid.cell
				slope_z = ((h01 - h00) * (1.0 - fx) + (h11 - h10) * fx) / grid.cell
				Hit({ y, normal: V.normalize({ x: -slope_x, y: 1.0, z: -slope_z }) })
			}
		}
	}

	## The tops of the Solids: the flat top of a box and the upper half of a
	## sphere. A top above the asked height misses, so a character can walk
	## under a platform.
	tops : Solids -> Ground.Ground
	tops = |solids| |x, z, from| {
		below = { min: { x, y: F32.lowest, z }, max: { x, y: from, z } }
		Solids.near(solids, below).fold(Miss, |best, solid| higher(best, top_of(solid, { x, z, from })))
	}

	## The higher answer of two Grounds at each point.
	highest : Ground.Ground, Ground.Ground -> Ground.Ground
	highest = |first, second| |x, z, from| higher(first(x, z, from), second(x, z, from))

	## The surface that a foot falling from height `from` to `to` at `x`, `z`
	## lands on, or Miss if it falls past `to` before it meets one. Ask it
	## after a fast fall, which can move the foot past a thin platform in one
	## step.
	sweep : Ground.Ground, { x : F32, z : F32, from : F32, to : F32 } -> Ground.Surface
	sweep = |ground, { x, z, from, to }| match ground(x, z, from) {
		Hit(hit) if hit.y >= to => Hit(hit)
		_ => Miss
	}
}

up : V.Vec3
up = { x: 0.0, y: 1.0, z: 0.0 }

higher : Ground.Surface, Ground.Surface -> Ground.Surface
higher = |a, b| match (a, b) {
	(Hit(first), Hit(second)) => if (second.y > first.y) b else a
	(Miss, _) => b
	(_, Miss) => a
}

top_of : Solids.Solid, { x : F32, z : F32, from : F32 } -> Ground.Surface
top_of = |solid, { x, z, from }| {
	answer = match solid {
		Box({ center, half_extents, yaw }) => {
			dx = x - center.x
			dz = z - center.z
			local_x = dx * yaw.cos() - dz * yaw.sin()
			local_z = dx * yaw.sin() + dz * yaw.cos()
			if (local_x.abs() <= half_extents.x and local_z.abs() <= half_extents.z) Hit({ y: center.y + half_extents.y, normal: up }) else Miss
		}
		Sphere({ center, radius }) => {
			dx = x - center.x
			dz = z - center.z
			rise_squared = radius * radius - dx * dx - dz * dz
			if rise_squared < 0.0 {
				Miss
			} else {
				rise = rise_squared.sqrt()
				Hit({ y: center.y + rise, normal: V.scale({ x: dx, y: rise, z: dz }, 1.0 / radius) })
			}
		}
	}
	match answer {
		Hit(hit) if hit.y <= from => answer
		_ => Miss
	}
}

is_near : V.Vec3, V.Vec3 -> Bool
is_near = |a, b| V.length(V.sub(a, b)) < 0.0001

is_hit_at : Ground.Surface, { y : F32, normal : V.Vec3 } -> Bool
is_hit_at = |answer, { y, normal }| match answer {
	Hit(hit) => (hit.y - y).abs() < 0.0001 and is_near(hit.normal, normal)
	Miss => Bool.False
}

## Flat ground answers its height at any point, even from below it.
expect {
	ground = Ground.flat(0.5)
	is_hit_at(ground(3.0, -2.0, 10.0), { y: 0.5, normal: up }) and is_hit_at(ground(3.0, -2.0, -4.0), { y: 0.5, normal: up })
}

ramp : Ground.Ground
ramp = Ground.heights({ origin: { x: 0.0, z: 0.0 }, cell: 2.0, columns: 3, rows: 2, heights: [0.0, 1.0, 2.0, 0.0, 1.0, 2.0] })

## A height grid answers its corner heights.
expect is_hit_at(ramp(4.0, 2.0, 9.0), { y: 2.0, normal: V.normalize({ x: -0.5, y: 1.0, z: 0.0 }) })

## Between corners a height grid blends the heights, and its normal leans back from the slope.
expect is_hit_at(ramp(1.0, 1.0, 9.0), { y: 0.5, normal: V.normalize({ x: -0.5, y: 1.0, z: 0.0 }) })

## A height grid blends on both axes.
expect {
	bump = Ground.heights({ origin: { x: 0.0, z: 0.0 }, cell: 1.0, columns: 2, rows: 2, heights: [0.0, 2.0, 0.0, 4.0] })
	is_hit_at(bump(0.25, 0.75, 9.0), { y: 0.875, normal: V.normalize({ x: -3.5, y: 1.0, z: -0.5 }) })
}

## A point past the edge of a height grid misses.
expect ramp(4.5, 1.0, 9.0) == Miss and ramp(1.0, -0.1, 9.0) == Miss

slab : Solids.Solid
slab = Box({ center: { x: 0.0, y: 1.45, z: 0.0 }, half_extents: { x: 1.0, y: 0.05, z: 1.0 }, yaw: 0.0 })

ball : Solids.Solid
ball = Sphere({ center: { x: 5.0, y: 1.0, z: 0.0 }, radius: 1.0 })

shelf : Ground.Ground
shelf = Ground.tops(Solids.build([slab, ball], 2.0))

## The top of a box answers from above it.
expect is_hit_at(shelf(0.5, -0.5, 3.0), { y: 1.5, normal: up })

## A point below the top of a box does not see the top.
expect shelf(0.5, -0.5, 1.45) == Miss and shelf(5.0, 0.0, 1.9) == Miss

## The top of a sphere curves, and its normal points out from the centre.
expect is_hit_at(shelf(5.0, 0.0, 3.0), { y: 2.0, normal: up }) and is_hit_at(shelf(5.6, 0.0, 3.0), { y: 1.8, normal: { x: 0.6, y: 0.8, z: 0.0 } })

## A turned box has its top where the turn puts it: its long local `+x` runs along (0.8, 0, -0.6).
expect {
	turned = Ground.tops(Solids.build([Box({ center: { x: 0.0, y: 0.5, z: 0.0 }, half_extents: { x: 2.0, y: 0.5, z: 0.25 }, yaw: 0.6435011 })], 2.0))
	is_hit_at(turned(1.2, -0.9, 3.0), { y: 1.0, normal: up }) and turned(1.2, 0.9, 3.0) == Miss
}

## The higher of two Grounds wins, and a miss in one leaves the other.
expect {
	ground = Ground.highest(Ground.flat(0.0), shelf)
	is_hit_at(ground(0.5, 0.5, 3.0), { y: 1.5, normal: up }) and is_hit_at(ground(0.5, 0.5, 1.0), { y: 0.0, normal: up }) and is_hit_at(ground(20.0, 0.0, 3.0), { y: 0.0, normal: up })
}

## A fast fall past a 0.1 m platform in one step lands on it.
expect {
	falling = { x: 0.3, z: 0.2, from: 2.0, to: 0.2 }
	is_hit_at(Ground.sweep(shelf, falling), { y: 1.5, normal: up }) and shelf(falling.x, falling.z, falling.to) == Miss
}

## A fall that stops above the platform does not reach it.
expect Ground.sweep(shelf, { x: 0.3, z: 0.2, from: 2.0, to: 1.7 }) == Miss
