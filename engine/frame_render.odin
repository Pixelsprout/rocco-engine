package engine

import "core:fmt"
import "core:math"
import "core:mem"

LIGHT_DIR :: [4]f32{2.0 / 7.0, 3.0 / 7.0, 6.0 / 7.0, 0} // 4 + 9 + 36 = 49, so |L| = 1 exactly
SCENE_NEAR :: f32(0.1)
UP :: [3]f32{0, 1, 0}

Frame_Render :: struct {
	pairing: Pairing,
}

frame_render_init :: proc(fr: ^Frame_Render, perm: mem.Allocator) {
	pairing_init(&fr.pairing, perm)
}

frame_render_destroy :: proc(fr: ^Frame_Render) {
	pairing_destroy(&fr.pairing)
}

frame_render_camera :: proc(prev, curr: Scene, alpha, aspect: f32) -> Mat4 {
	return scene_view_proj(camera_lerp(prev.camera, curr.camera, alpha), aspect)
}

// The fallback ignores the tint, so an unknown mesh id shows magenta whatever the game asked for.
frame_render_draw :: proc(fr: ^Frame_Render, r: ^Renderer, prev, curr: Scene, alpha: f32, view_proj: Mat4, meshes: ^Mesh_Table) {
	pairing_build(&fr.pairing, prev.draws.elements[:prev.draws.length])
	for d in curr.draws.elements[:curr.draws.length] {
		from := d
		if i, ok := pairing_find(&fr.pairing, d.id); ok {
			from = prev.draws.elements[i]
		}
		model := draw_model_matrix(draw_transform(from, d, alpha))
		mesh, fallback := mesh_resolve(meshes, d.mesh, d.id)
		tint := [4]f32{1, 1, 1, 1} if fallback else {d.tint.r, d.tint.g, d.tint.b, 1}
		renderer_draw(
			r,
			mesh,
			vs_params = {mvp = view_proj * model, model = model},
			fs_params = {
				light_dir = LIGHT_DIR,
				light_color = [4]f32{1, 1, 1, 1},
				ambient = [4]f32{0.1, 0.1, 0.1, 1},
				tint = tint,
			},
		)
	}
}

scene_view_proj :: proc(camera: Camera_Pose, aspect: f32) -> Mat4 {
	return mat4_perspective_reversed_infinite(camera.fov_y, aspect, SCENE_NEAR) * mat4_look_at(camera.eye, camera.target, UP)
}

// Maps each draw id of the previous Scene to its index. Rebuilt every Frame
// with clear, so the map keeps its capacity and stops allocating.
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

// The camera the host draws a frame with.
Camera_Pose :: struct {
	eye, target: [3]f32,
	fov_y:       f32,
}

camera_lerp :: proc(prev, curr: Scene_Camera, alpha: f32) -> Camera_Pose {
	return {eye = v3_lerp(prev.eye, curr.eye, alpha), target = v3_lerp(prev.target, curr.target, alpha), fov_y = curr.fov_y}
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
	return math.lerp(vec3_array(a), vec3_array(b), t)
}

vec3_array :: proc(v: Vec3) -> [3]f32 {
	return {v.x, v.y, v.z}
}
