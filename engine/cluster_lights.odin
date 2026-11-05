package engine

import "core:math"
import "core:math/linalg"

MAX_DIRECTIONALS :: 4
MAX_POINT_LIGHTS :: 1024
CLUSTER_X :: 16
CLUSTER_Y :: 9
CLUSTER_Z :: 24
CLUSTER_COUNT :: CLUSTER_X * CLUSTER_Y * CLUSTER_Z
CLUSTER_LIGHT_LIMIT :: 64
CLUSTER_INDEX_LIMIT :: CLUSTER_COUNT * CLUSTER_LIGHT_LIMIT
CLUSTER_BUFFER_BYTES :: MAX_POINT_LIGHTS * size_of(Packed_Light) + CLUSTER_COUNT * size_of(Cluster_Range) + CLUSTER_INDEX_LIMIT * size_of(u32)

#assert(size_of(Packed_Light) == 32)
#assert(size_of(Cluster_Range) == 16)
#assert(CLUSTER_LIGHT_LIMIT % 4 == 0)

Packed_Light :: struct {
	pos, color: [4]f32,
}

Cluster_Range :: struct {
	offset, count, reserved0, reserved1: u32,
}

Cluster_Frame :: struct {
	points: []Packed_Light,
	ranges: []Cluster_Range,
	indices: []u32,
	grid: [4]f32,
	overflow: bool,
}

Cluster_Camera :: struct {
	eye, right, up, forward: [3]f32,
	tan_x, tan_y, far, log_scale: f32,
}

cluster_camera :: proc(view: Frame_View, points: []Packed_Light) -> Cluster_Camera {
	c: Cluster_Camera
	c.eye = view.camera.eye
	c.forward = v3_normalize(view.camera.target - c.eye)
	c.right = v3_normalize(v3_cross(c.forward, view.camera.up))
	c.up = v3_cross(c.right, c.forward)
	c.tan_y = math.tan(view.camera.fov_y / 2)
	c.tan_x = c.tan_y * view.aspect
	c.far = 100
	for p in points {
		c.far = max(c.far, linalg.dot(p.pos.xyz - c.eye, c.forward) + p.color.w)
	}
	c.log_scale = CLUSTER_Z / math.ln(c.far / SCENE_NEAR)
	return c
}

cluster_depth_slice :: proc(depth, log_scale: f32) -> int {
	return clamp(int(math.ln(max(depth, SCENE_NEAR) / SCENE_NEAR) * log_scale), 0, CLUSTER_Z - 1)
}

// Tile bounds use the sphere's enclosing box, so lights never disappear at a tile edge.
cluster_axis_bounds :: proc(axis, depth, radius, tangent: f32, tiles: int) -> (lo, hi: int, visible: bool) {
	if depth - radius <= SCENE_NEAR {
		return 0, tiles - 1, true
	}
	a := (axis - radius) / (depth - radius) / tangent
	b := (axis - radius) / (depth + radius) / tangent
	c := (axis + radius) / (depth - radius) / tangent
	d := (axis + radius) / (depth + radius) / tangent
	low, high := min(a, b, c, d), max(a, b, c, d)
	if high < -1 || low > 1 {
		return 0, 0, false
	}
	return clamp(int((low + 1) * 0.5 * f32(tiles)), 0, tiles - 1), clamp(int((high + 1) * 0.5 * f32(tiles)), 0, tiles - 1), true
}

cluster_build :: proc(points: []Packed_Light, view: Frame_View, physical_size: [2]f32) -> Cluster_Frame {
	frame := Cluster_Frame{
		points = points[:min(len(points), MAX_POINT_LIGHTS)],
		ranges = make([]Cluster_Range, CLUSTER_COUNT, context.temp_allocator),
	}
	camera := cluster_camera(view, frame.points)
	frame.grid = {CLUSTER_X / max(physical_size.x, 1), CLUSTER_Y / max(physical_size.y, 1), camera.log_scale, SCENE_NEAR}
	if len(frame.points) == 0 {
		frame.indices = make([]u32, 4, context.temp_allocator)
		return frame
	}
	indices := make([]u32, CLUSTER_INDEX_LIMIT, context.temp_allocator)
	positions := make([][3]f32, len(frame.points), context.temp_allocator)
	for p, i in frame.points {
		rel := p.pos.xyz - camera.eye
		positions[i] = {linalg.dot(rel, camera.right), linalg.dot(rel, camera.up), linalg.dot(rel, camera.forward)}
	}
	centres: [CLUSTER_Z]f32
	for &depth, z in centres {
		depth = SCENE_NEAR * f32(math.exp((f64(z) + 0.5) / f64(camera.log_scale)))
	}
	for p, i in frame.points {
		pos := positions[i]
		radius := p.color.w
		if pos.z + radius < SCENE_NEAR { continue }
		x0, x1, vx := cluster_axis_bounds(pos.x, pos.z, radius, camera.tan_x, CLUSTER_X)
		y0, y1, vy := cluster_axis_bounds(pos.y, pos.z, radius, camera.tan_y, CLUSTER_Y)
		if !vx || !vy { continue }
		z0 := cluster_depth_slice(pos.z - radius, camera.log_scale)
		z1 := cluster_depth_slice(pos.z + radius, camera.log_scale)
		for z in z0 ..= z1 {
			for y in y0 ..= y1 {
				for x in x0 ..= x1 {
					// Reject only a separating plane; corner intersections stay conservative.
					left := (2 * f32(x) / CLUSTER_X - 1) * camera.tan_x
					right := (2 * f32(x + 1) / CLUSTER_X - 1) * camera.tan_x
					bottom := (2 * f32(y) / CLUSTER_Y - 1) * camera.tan_y
					top := (2 * f32(y + 1) / CLUSTER_Y - 1) * camera.tan_y
					if pos.x - left * pos.z < -radius * math.sqrt(1 + left * left) ||
						right * pos.z - pos.x < -radius * math.sqrt(1 + right * right) ||
						pos.y - bottom * pos.z < -radius * math.sqrt(1 + bottom * bottom) ||
						top * pos.z - pos.y < -radius * math.sqrt(1 + top * top) { continue }
					cluster := (z * CLUSTER_Y + y) * CLUSTER_X + x
					range := &frame.ranges[cluster]
					base := cluster * CLUSTER_LIGHT_LIMIT
					if range.count < CLUSTER_LIGHT_LIMIT {
						indices[base + int(range.count)] = u32(i)
						range.count += 1
						continue
					}
					frame.overflow = true
					centre := [3]f32{(left + right) * 0.5 * centres[z], (bottom + top) * 0.5 * centres[z], centres[z]}
					worst := 0
					worst_distance := f32(-1)
					for old, j in indices[base:base + CLUSTER_LIGHT_LIMIT] {
						delta := positions[old] - centre
						distance := linalg.dot(delta, delta)
						if distance > worst_distance || (distance == worst_distance && old > indices[base + worst]) {
							worst, worst_distance = j, distance
						}
					}
					delta := pos - centre
					if linalg.dot(delta, delta) < worst_distance {
						indices[base + worst] = u32(i)
					}
				}
			}
		}
	}
	used := 0
	for &range, i in frame.ranges {
		range.offset = u32(used)
		copy(indices[used:used + int(range.count)], indices[i * CLUSTER_LIGHT_LIMIT:i * CLUSTER_LIGHT_LIMIT + int(range.count)])
		used += int(range.count)
	}
	padded := max(4, (used + 3) / 4 * 4)
	for &index in indices[used:padded] { index = 0 }
	frame.indices = indices[:padded]
	return frame
}
