package engine

import "core:fmt"
import "core:math"
import "core:mem"

// Maps each draw id of the previous Scene to its index. Rebuilt every fixed
// step with clear, so the map keeps its capacity and stops allocating.
Pairing :: struct {
	index:  map[u64]int,
	logged: map[u64]struct {},
}

pairing_init :: proc(p: ^Pairing, allocator: mem.Allocator) {
	p.index = make(map[u64]int, allocator)
	p.logged = make(map[u64]struct {}, allocator)
}

pairing_destroy :: proc(p: ^Pairing) {
	delete(p.index)
	delete(p.logged)
}

// On a duplicate id the first draw wins. Each duplicate id is logged once per run.
pairing_build :: proc(p: ^Pairing, draws: []Draw) {
	clear(&p.index)
	for d, i in draws {
		if d.id in p.index {
			if d.id not_in p.logged {
				p.logged[d.id] = {}
				fmt.eprintfln("two draws share id %v; the first one pairs", d.id)
			}
			continue
		}
		p.index[d.id] = i
	}
}

pairing_find :: proc(p: ^Pairing, id: u64) -> (int, bool) {
	return p.index[id]
}

Draw_Transform :: struct {
	position: [3]f32,
	scale:    [3]f32,
	yaw:      f32,
}

// A draw with no partner passes itself as prev.
draw_transform :: proc(prev, curr: Draw, alpha: f32) -> Draw_Transform {
	return {
		position = v3_lerp(prev.pos, curr.pos, alpha),
		scale = v3_lerp(prev.scale, curr.scale, alpha),
		yaw = yaw_lerp(prev.yaw, curr.yaw, alpha),
	}
}

draw_model_matrix :: proc(x: Draw_Transform) -> Mat4 {
	return transform_to_mat4({position = x.position, rotation = quat_from_axis_angle(UP, x.yaw), scale = x.scale})
}

camera_lerp :: proc(prev, curr: Scene_Camera, alpha: f32) -> Scene_Camera {
	eye := v3_lerp(prev.eye, curr.eye, alpha)
	target := v3_lerp(prev.target, curr.target, alpha)
	return {eye = {eye.x, eye.y, eye.z}, target = {target.x, target.y, target.z}, fov_y = curr.fov_y}
}

// Turns through the shorter arc, so -3 to 3 radians passes through pi.
yaw_lerp :: proc(a, b, t: f32) -> f32 {
	d := math.mod(b - a + math.PI, 2 * math.PI)
	if d < 0 {
		d += 2 * math.PI
	}
	return a + (d - math.PI) * t
}

v3_lerp :: proc(a, b: Vec3, t: f32) -> [3]f32 {
	return {math.lerp(a.x, b.x, t), math.lerp(a.y, b.y, t), math.lerp(a.z, b.z, t)}
}
