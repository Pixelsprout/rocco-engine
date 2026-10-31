package engine

import "core:math/linalg"

// A light as the shader reads it. pos.w is 0 for a Directional and 1 for a
// Point. color.w is a Point's range.
Packed_Light :: struct {
	pos, color: [4]f32,
}

@(private = "file")
Light_Candidate :: struct {
	light:     ^Packed_Light,
	box_sq:    f32,
	centre_sq: f32,
}

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

box_distance_sq :: proc(box: Box, p: [3]f32) -> f32 {
	d := linalg.max(box.min - p, p - box.max)
	d = linalg.max(d, [3]f32{})
	return linalg.dot(d, d)
}

// Writes every Directional, up to MAX_LIGHTS, then the Points that reach
// bounds, nearest first. The slots after the last light keep their values,
// so the caller passes zeroed arrays. dropped is true when a Directional or a
// Point in reach gets no slot.
light_select :: proc(directionals, points: []Packed_Light, bounds: Box, pos, color: ^[MAX_LIGHTS][4]f32) -> (dropped: bool) {
	used := min(len(directionals), MAX_LIGHTS)
	dropped = len(directionals) > MAX_LIGHTS
	for i in 0 ..< used {
		pos[i] = directionals[i].pos
		color[i] = directionals[i].color
	}
	free_slots := MAX_LIGHTS - used
	// Sorted by (box_sq, centre_sq). An insert moves only past a strictly
	// greater key, so a tie keeps walk order.
	nearest: [MAX_LIGHTS]Light_Candidate
	count := 0
	centre := (bounds.min + bounds.max) * 0.5
	for &p in points {
		box_sq := box_distance_sq(bounds, p.pos.xyz)
		// Written this way round so a NaN position does not reach.
		if !(box_sq < p.color.w * p.color.w) {
			continue
		}
		to_centre := p.pos.xyz - centre
		key := Light_Candidate{&p, box_sq, linalg.dot(to_centre, to_centre)}
		if count == free_slots {
			dropped = true
			if count == 0 || !candidate_less(key, nearest[count - 1]) {
				continue
			}
			count -= 1
		}
		at := count
		for at > 0 && candidate_less(key, nearest[at - 1]) {
			nearest[at] = nearest[at - 1]
			at -= 1
		}
		nearest[at] = key
		count += 1
	}
	for c, i in nearest[:count] {
		pos[used + i] = c.light.pos
		color[used + i] = c.light.color
	}
	return
}

@(private = "file")
candidate_less :: #force_inline proc(a, b: Light_Candidate) -> bool {
	return a.box_sq < b.box_sq || (a.box_sq == b.box_sq && a.centre_sq < b.centre_sq)
}
