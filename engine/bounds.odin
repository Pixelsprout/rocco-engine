package engine

// The world box of a mesh box under m, by Arvo's method: the centre goes
// through m, and the half size through the absolute values of m's 3 x 3 part.
box_transform :: proc(box: Box, m: Mat4) -> Box {
	centre := (box.min + box.max) * 0.5
	half := (box.max - box.min) * 0.5
	world_centre := (m * [4]f32{centre.x, centre.y, centre.z, 1}).xyz
	world_half: [3]f32
	for row in 0 ..< 3 {
		for col in 0 ..< 3 {
			world_half[row] += abs(m[row, col]) * half[col]
		}
	}
	return {world_centre - world_half, world_centre + world_half}
}
