package engine

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"

// The light arrays in engine/shaders/basic.glsl have this size.
MAX_LIGHTS :: 8
SCENE_NEAR :: f32(0.1)
UP :: [3]f32{0, 1, 0}
UP_EPSILON :: f32(1e-6)

// The pairing map holds this many draws without allocating.
PAIRING_CAPACITY :: 4096

#assert(len(Fs_Lights{}.light_pos) == MAX_LIGHTS)

// Lets tests run without sokol. submit_lights runs once per frame, before any submit.
Submit :: #type proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params)
Submit_Lights :: #type proc(ctx: rawptr, lights: Fs_Lights)

Light_Drop :: enum {
	Second_Ambient,
	Over_Limit,
	Zero_Dir,
	Bad_Range,
}

Frame_Render :: struct {
	pairing:            Pairing,
	submit:             Submit,
	submit_lights:      Submit_Lights,
	submit_ctx:         rawptr,
	up_fallback_logged: bool,
	lights_logged:      bit_set[Light_Drop],
}

Draw_Transform :: struct {
	position: [3]f32,
	scale:    [3]f32,
	rotation: quaternion128,
}

// Maps each draw id of the previous Scene to its index. Rebuilt every Frame
// with clear, so the map keeps the capacity init reserved.
Pairing :: struct {
	index:                map[u64]int,
	logged:               map[u64]struct {},
	over_capacity_logged: bool,
}

// The camera the host draws a frame with.
Camera_Pose :: struct {
	eye, target, up: [3]f32,
	fov_y:           f32,
}

frame_render_init :: proc(fr: ^Frame_Render, perm: mem.Allocator) {
	pairing_init(&fr.pairing, perm)
}

frame_render_destroy :: proc(fr: ^Frame_Render) {
	pairing_destroy(&fr.pairing)
}

// An up along the view, or a zero up, has no right vector.
frame_render_camera :: proc(fr: ^Frame_Render, prev, curr: Scene, alpha, aspect: f32) -> Mat4 {
	pose := camera_lerp(prev.camera, curr.camera, alpha)
	if v3_length(v3_cross(pose.target - pose.eye, pose.up)) < UP_EPSILON {
		if !fr.up_fallback_logged {
			fr.up_fallback_logged = true
			fmt.eprintfln("the Scene camera's up %v is zero or along its view; using +y", pose.up)
		}
		pose.up = UP
	}
	return scene_view_proj(pose, aspect)
}

// The fallback ignores the tint, so an unknown mesh id shows magenta whatever the game asked for.
frame_render_draw :: proc(fr: ^Frame_Render, prev, curr: Scene, alpha: f32, view_proj: Mat4, meshes: ^Mesh_Table) {
	fr.submit_lights(fr.submit_ctx, frame_render_lights(fr, curr.lights.elements[:curr.lights.length]))
	pairing_build(&fr.pairing, prev.draws.elements[:prev.draws.length])
	for d in curr.draws.elements[:curr.draws.length] {
		from := d
		if i, ok := pairing_find(&fr.pairing, d.id); ok {
			from = prev.draws.elements[i]
		}
		model := draw_model_matrix(draw_transform(from, d, alpha))
		mesh, fallback := mesh_resolve(meshes, d.mesh, d.id)
		tint := [4]f32{1, 1, 1, 1} if fallback else {d.tint.r, d.tint.g, d.tint.b, 1}
		fr.submit(
			fr.submit_ctx,
			mesh,
			vs_params = {mvp = view_proj * model, model = model},
			fs_params = {tint = tint},
		)
	}
}

// A dropped light does not take a slot. An unused slot keeps a zero colour, so it adds no light.
frame_render_lights :: proc(fr: ^Frame_Render, lights: []Light) -> Fs_Lights {
	out: Fs_Lights
	has_ambient := false
	n := 0
	for l in lights {
		pos: [4]f32
		color: Rgb
		range: f32
		switch l.tag {
		case .Ambient:
			if has_ambient {
				light_drop(fr, .Second_Ambient)
				continue
			}
			has_ambient = true
			c := l.payload.ambient
			out.ambient = {c.r, c.g, c.b, 1}
			continue
		case .Directional:
			d := l.payload.directional
			to_light := -v3_normalize_or_zero(vec3_array(d.dir))
			if to_light == 0 {
				light_drop(fr, .Zero_Dir)
				continue
			}
			pos = {to_light.x, to_light.y, to_light.z, 0}
			color = d.color
		case .Point:
			p := l.payload.point
			// Written this way round so a NaN range drops too.
			if !(p.range > 0) {
				light_drop(fr, .Bad_Range)
				continue
			}
			pos = {p.pos.x, p.pos.y, p.pos.z, 1}
			color = p.color
			range = p.range
		}
		if n == MAX_LIGHTS {
			light_drop(fr, .Over_Limit)
			continue
		}
		out.light_pos[n] = pos
		out.light_color[n] = {color.r, color.g, color.b, range}
		n += 1
	}
	return out
}

light_drop :: proc(fr: ^Frame_Render, reason: Light_Drop) {
	if reason in fr.lights_logged {
		return
	}
	fr.lights_logged += {reason}
	switch reason {
	case .Second_Ambient:
		fmt.eprintln("a Scene has a second ambient light; the host uses the first")
	case .Over_Limit:
		fmt.eprintfln("a Scene has more than %v directional and point lights; the host drops the rest", MAX_LIGHTS)
	case .Zero_Dir:
		fmt.eprintln("a directional light has a zero dir; the host drops it")
	case .Bad_Range:
		fmt.eprintln("a point light has a range <= 0; the host drops it")
	}
}

scene_view_proj :: proc(camera: Camera_Pose, aspect: f32) -> Mat4 {
	return mat4_perspective_reversed_infinite(camera.fov_y, aspect, SCENE_NEAR) * mat4_look_at(camera.eye, camera.target, camera.up)
}

pairing_init :: proc(p: ^Pairing, allocator: mem.Allocator) {
	p.index = make(map[u64]int, allocator)
	// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
	reserve(&p.index, PAIRING_CAPACITY * 100 / runtime.MAP_LOAD_FACTOR + 1)
	p.logged = make(map[u64]struct {}, allocator)
}

pairing_destroy :: proc(p: ^Pairing) {
	delete(p.index)
	delete(p.logged)
}

// On a duplicate id the first draw wins. Each duplicate id is logged once per run.
pairing_build :: proc(p: ^Pairing, draws: []Draw) {
	if len(draws) > PAIRING_CAPACITY && !p.over_capacity_logged {
		p.over_capacity_logged = true
		fmt.eprintfln("a Scene has %v draws; the pairing map allocates past %v", len(draws), PAIRING_CAPACITY)
	}
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

// A draw with no partner passes itself as prev.
draw_transform :: proc(prev, curr: Draw, alpha: f32) -> Draw_Transform {
	return {
		position = v3_lerp(prev.pos, curr.pos, alpha),
		scale = v3_lerp(prev.scale, curr.scale, alpha),
		rotation = quat_slerp(quat_of(prev.rot), quat_of(curr.rot), alpha),
	}
}

draw_model_matrix :: proc(x: Draw_Transform) -> Mat4 {
	return transform_to_mat4({position = x.position, rotation = x.rotation, scale = x.scale})
}

camera_lerp :: proc(prev, curr: Scene_Camera, alpha: f32) -> Camera_Pose {
	return {
		eye = v3_lerp(prev.eye, curr.eye, alpha),
		target = v3_lerp(prev.target, curr.target, alpha),
		up = v3_normalize_or_zero(v3_lerp(prev.up, curr.up, alpha)),
		fov_y = curr.fov_y,
	}
}

v3_lerp :: proc(a, b: Vec3, t: f32) -> [3]f32 {
	return math.lerp(vec3_array(a), vec3_array(b), t)
}

vec3_array :: proc(v: Vec3) -> [3]f32 {
	return {v.x, v.y, v.z}
}

quat_of :: proc(q: Quat) -> quaternion128 {
	return quaternion(w = q.w, x = q.x, y = q.y, z = q.z)
}

