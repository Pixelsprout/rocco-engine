package engine

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

// The light arrays in engine/shaders/basic.glsl have this size.
MAX_LIGHTS :: 8
SCENE_NEAR :: f32(0.1)
UP :: [3]f32{0, 1, 0}
UP_EPSILON :: f32(1e-6)

// The light_view_proj array in engine/shaders/basic.glsl has this size.
MAX_CASCADES :: 1
// The shadow box snaps outward to this grid, so the map changes size in steps
// and its edges do not crawl as a Draw moves.
SHADOW_GRID :: f32(1)
SHADOW_NORMAL_OFFSET :: f32(0.05)

#assert(len(Fs_Lights{}.light_pos) == MAX_LIGHTS)
#assert(len(Fs_Lights{}.light_view_proj) == MAX_CASCADES)

Pass :: enum {
	Shadow,
	Main,
}

// Lets tests run without sokol. Each frame begins and ends one Shadow pass
// per shadow view, then one Main pass. submit_shadow runs only in a Shadow
// pass. In the Main pass, submit_lights runs before any submit,
// submit_sky runs at most once, after every submit, and submit_ui runs at
// most once, last.
Begin_Pass :: #type proc(ctx: rawptr, pass: Pass, view: int)
End_Pass :: #type proc(ctx: rawptr)
Submit_Shadow :: #type proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params)
Submit :: #type proc(ctx: rawptr, mesh: ^Mesh, vs_params: Vs_Params, fs_params: Fs_Params)
Submit_Lights :: #type proc(ctx: rawptr, lights: Fs_Lights)
Submit_Sky :: #type proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params)
Submit_Ui :: #type proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32)

Light_Drop :: enum {
	Second_Ambient,
	Second_Sun,
	Over_Limit,
	Zero_Dir,
	Bad_Range,
}

// The renderer sizes its uniform buffer for draw_capacity Draws per Frame.
// The host drops the rest, because a release sokol writes past a full buffer.
Frame_Render :: struct {
	pairing:            Pairing,
	placed:             [dynamic]Placed,
	draw_capacity:      int,
	begin_pass:         Begin_Pass,
	end_pass:           End_Pass,
	submit_shadow:      Submit_Shadow,
	submit:             Submit,
	submit_lights:      Submit_Lights,
	submit_sky:         Submit_Sky,
	submit_ui:          Submit_Ui,
	submit_ctx:         rawptr,
	up_fallback_logged: bool,
	lights_logged:      bit_set[Light_Drop],
	draws_logged:       bool,
}

Draw_Transform :: struct {
	position:       [3]f32,
	scale:          [3]f32,
	rotation:       quaternion128,
	scale_rotation: quaternion128,
}

// A Draw at its interpolated pose, kept so both passes use one transform.
Placed :: struct {
	mesh:      ^Mesh,
	fallback:  bool,
	tint:      Rgb,
	transform: Draw_Transform,
	model:     Mat4,
}

// Maps each draw id and each Group id of the previous Scene to that Node.
// Rebuilt every Frame with clear, so the maps keep the capacity init
// reserved. The Group map takes no more than group_capacity Groups, so it
// never grows.
Pairing :: struct {
	draws:                  map[u64]Prev_Node,
	groups:                 map[u64]Prev_Node,
	logged:                 map[u64]struct {},
	capacity:               int,
	group_capacity:         int,
	draws_seen:             int,
	over_capacity_logged:   bool,
	groups_full_logged:     bool,
	group_duplicate_logged: bool,
}

// What the Frame's walk of the current Scene gathers.
@(private = "file")
Frame_Walk :: struct {
	fr:         ^Frame_Render,
	meshes:     ^Mesh_Table,
	lights:     Light_Gather,
	draws_seen: int,
}

// The Lights so far in walk order. sun is the Sun's slot, or -1 with no Sun.
Light_Gather :: struct {
	out:         Fs_Lights,
	sun:         int,
	n:           int,
	has_ambient: bool,
}

// The camera the host draws a frame with.
Camera_Pose :: struct {
	eye, target, up: [3]f32,
	fov_y:           f32,
}

frame_render_init :: proc(fr: ^Frame_Render, draws, groups: int, perm: mem.Allocator) {
	fr.draw_capacity = draws
	pairing_init(&fr.pairing, draws, groups, perm)
	fr.placed = make([dynamic]Placed, 0, draws, perm)
}

frame_render_destroy :: proc(fr: ^Frame_Render) {
	pairing_destroy(&fr.pairing)
	delete(fr.placed)
}

// An up along the view, or a zero up, has no right vector.
frame_render_camera :: proc(fr: ^Frame_Render, prev, curr: Scene, alpha, aspect: f32) -> (view_proj: Mat4, eye: [3]f32) {
	pose := camera_lerp(prev.camera, curr.camera, alpha)
	if v3_length(v3_cross(pose.target - pose.eye, pose.up)) < UP_EPSILON {
		if !fr.up_fallback_logged {
			fr.up_fallback_logged = true
			fmt.eprintfln("the Scene camera's up %v is zero or along its view; using +y", pose.up)
		}
		pose.up = UP
	}
	return scene_view_proj(pose, aspect), pose.eye
}

// The fallback ignores the tint, so an unknown mesh id shows magenta whatever
// the game asked for. The sky draws last, so the depth test hides it behind
// every mesh. The UI draws over everything. A nil ui draws none. With submit
// false, the Frame still places the Draws and lays out the UI, but submits
// nothing.
frame_render_draw :: proc(
	fr: ^Frame_Render,
	prev, curr: Scene,
	alpha: f32,
	view_proj: Mat4,
	eye: [3]f32,
	meshes: ^Mesh_Table,
	skies: ^Sky_Table,
	ui: ^Ui,
	window: Ui_Window,
	spans: ^Span_Sink = nil,
	submit := true,
) {
	span := span_open()
	pairing_build(&fr.pairing, prev.nodes.elements[:prev.nodes.length])
	clear(&fr.placed)
	frame_walk := Frame_Walk {
		fr = fr,
		meshes = meshes,
		lights = {sun = -1},
	}
	walk := Tree_Walk {
		visit   = frame_render_visit,
		pairing = &fr.pairing,
		alpha   = alpha,
		data    = &frame_walk,
	}
	tree_walk(&walk, curr.nodes.elements[:curr.nodes.length], WALK_ROOT)
	if frame_walk.draws_seen > fr.draw_capacity && !fr.draws_logged {
		fr.draws_logged = true
		fmt.eprintfln("a Scene has %v draws; the host draws the first %v", frame_walk.draws_seen, fr.draw_capacity)
	}
	lights, sun := frame_walk.lights.out, frame_walk.lights.sun
	lights.camera_pos = {eye.x, eye.y, eye.z, 0}
	span = span_close(spans, .Interpolation, span)

	quads: []Ui_Quad
	if ui != nil {
		quads = ui_frame(ui, curr.ui.elements[:curr.ui.length], window)
		span = span_close(spans, .Ui_Layout, span)
	}
	if !submit {
		return
	}

	if sun >= 0 && len(fr.placed) > 0 {
		frame_render_shadow(fr, &lights, sun, &span)
	}

	frame_render_begin_pass(fr, .Main, 0, &span)
	fr.submit_lights(fr.submit_ctx, lights)
	for p in fr.placed {
		tint := [4]f32{1, 1, 1, 1} if p.fallback else {p.tint.r, p.tint.g, p.tint.b, 1}
		material := p.mesh.material
		fr.submit(
			fr.submit_ctx,
			p.mesh,
			vs_params = {mvp = view_proj * p.model, model = p.model, normal_model = draw_normal_matrix(p.transform)},
			fs_params = {tint = tint, material = {material.roughness, material.metallic, 1 if material.unlit else 0, 0}},
		)
	}
	if sky, ok := sky_resolve(skies, curr.sky); ok {
		fr.submit_sky(fr.submit_ctx, sky, {view_proj = view_proj})
	}
	if len(quads) > 0 {
		fr.submit_ui(fr.submit_ctx, quads, window.size)
	}
	fr.end_pass(fr.submit_ctx)
	span_close(spans, .Render_Submit, span)
}

// Places each Draw at its Pose for this Frame and gathers each Light, both
// in walk order. Past the draw capacity, it counts the Draws and skips them.
@(private = "file")
frame_render_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: Walk_Parent) {
	fw := (^Frame_Walk)(walk.data)
	fr := fw.fr
	switch node.tag {
	case .Draw:
		d := &node.payload.draw
		fw.draws_seen += 1
		if len(fr.placed) == fr.draw_capacity {
			return
		}
		prev := pairing_draw(walk.pairing, d.id)
		world, _ := node_place(prev, parent, pose_of(d.pos, d.rot), walk.alpha)
		x := draw_transform(prev.draw if prev != nil else d, d, world, walk.alpha)
		mesh, fallback := mesh_resolve(fw.meshes, d.mesh, d.id)
		append(&fr.placed, Placed{mesh = mesh, fallback = fallback, tint = d.tint, transform = x, model = draw_model_matrix(x)})
	case .Light:
		light_gather(fr, &fw.lights, light_under(node.payload.light, parent))
	case .Group, .Collider:
	}
}

// Must run before the Main pass begins, because sokol passes do not nest.
frame_render_shadow :: proc(fr: ^Frame_Render, lights: ^Fs_Lights, sun: int, span: ^Span_Tick) {
	light_view_proj := shadow_view_proj(lights.light_pos[sun].xyz, fr.placed[:])
	// The shader reads x as the view count, y as the Sun's slot and z as the normal offset.
	lights.shadow = {1, f32(sun), SHADOW_NORMAL_OFFSET, 0}
	lights.light_view_proj[0] = light_view_proj
	frame_render_begin_pass(fr, .Shadow, 0, span)
	for p in fr.placed {
		fr.submit_shadow(fr.submit_ctx, p.mesh, {light_mvp = light_view_proj * p.model})
	}
	fr.end_pass(fr.submit_ctx)
}

// On Metal, the first begin_pass of a Frame waits for a free in-flight frame,
// and the Main pass waits for the swapchain drawable. These waits pace the
// Frames, so the render Span leaves every begin_pass out.
@(private = "file")
frame_render_begin_pass :: proc(fr: ^Frame_Render, pass: Pass, view: int, span: ^Span_Tick) {
	waited := span_open()
	fr.begin_pass(fr.submit_ctx, pass, view)
	span^ = span_skip(span^, waited)
}

// An orthographic view from the Sun over the box of every placed Draw.
shadow_view_proj :: proc(to_light: [3]f32, placed: []Placed) -> Mat4 {
	up := UP if abs(to_light.y) < 0.99 else [3]f32{0, 0, 1}
	light_view := mat4_look_at({}, -to_light, up)
	lo := [3]f32{max(f32), max(f32), max(f32)}
	hi := -lo
	for p in placed {
		to_view := light_view * p.model
		for corner in 0 ..< 8 {
			c := [3]f32 {
				p.mesh.box.max.x if corner & 1 != 0 else p.mesh.box.min.x,
				p.mesh.box.max.y if corner & 2 != 0 else p.mesh.box.min.y,
				p.mesh.box.max.z if corner & 4 != 0 else p.mesh.box.min.z,
			}
			v := (to_view * [4]f32{c.x, c.y, c.z, 1}).xyz
			lo = linalg.min(lo, v)
			hi = linalg.max(hi, v)
		}
	}
	lo = linalg.floor(lo / SHADOW_GRID) * SHADOW_GRID
	// A flat box would give a zero extent and divide by zero.
	hi = linalg.max(linalg.ceil(hi / SHADOW_GRID) * SHADOW_GRID, lo + SHADOW_GRID)
	return mat4_ortho_reversed(lo.x, hi.x, lo.y, hi.y, -hi.z, -lo.z) * light_view
}

// A dropped light does not take a slot. An unused slot keeps a zero colour, so it adds no light.
light_gather :: proc(fr: ^Frame_Render, g: ^Light_Gather, l: Light) {
	pos: [4]f32
	color: Rgb
	range: f32
	switch l.tag {
	case .Ambient:
		if g.has_ambient {
			light_drop(fr, .Second_Ambient)
			return
		}
		g.has_ambient = true
		c := l.payload.ambient
		g.out.ambient = {c.r, c.g, c.b, 1}
		return
	case .Directional:
		d := l.payload.directional
		to_light := -v3_normalize_or_zero(vec3_array(d.dir))
		if to_light == 0 {
			light_drop(fr, .Zero_Dir)
			return
		}
		if d.shadow && g.sun >= 0 {
			light_drop(fr, .Second_Sun)
		} else if d.shadow && g.n < MAX_LIGHTS {
			g.sun = g.n
		}
		pos = {to_light.x, to_light.y, to_light.z, 0}
		color = d.color
	case .Point:
		p := l.payload.point
		// Written this way round so a NaN range drops too.
		if !(p.range > 0) {
			light_drop(fr, .Bad_Range)
			return
		}
		pos = {p.pos.x, p.pos.y, p.pos.z, 1}
		color = p.color
		range = p.range
	}
	if g.n == MAX_LIGHTS {
		light_drop(fr, .Over_Limit)
		return
	}
	g.out.light_pos[g.n] = pos
	g.out.light_color[g.n] = {color.r, color.g, color.b, range}
	g.n += 1
}

light_drop :: proc(fr: ^Frame_Render, reason: Light_Drop) {
	if reason in fr.lights_logged {
		return
	}
	fr.lights_logged += {reason}
	switch reason {
	case .Second_Ambient:
		fmt.eprintln("a Scene has a second ambient light; the host uses the first")
	case .Second_Sun:
		fmt.eprintln("a second directional light sets shadow; it lights but casts no shadow")
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

pairing_init :: proc(p: ^Pairing, capacity, group_capacity: int, allocator: mem.Allocator) {
	p.capacity = capacity
	p.group_capacity = group_capacity
	p.draws = make(map[u64]Prev_Node, allocator)
	// A map grows once it is MAP_LOAD_FACTOR percent full, not when it is full.
	reserve(&p.draws, capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	p.groups = make(map[u64]Prev_Node, allocator)
	reserve(&p.groups, group_capacity * 100 / runtime.MAP_LOAD_FACTOR + 1)
	p.logged = make(map[u64]struct {}, allocator)
}

pairing_destroy :: proc(p: ^Pairing) {
	delete(p.draws)
	delete(p.groups)
	delete(p.logged)
}

// On a duplicate draw id the first Draw in walk order wins, and each
// duplicate id is logged once per run. On a duplicate Group id the first
// Group wins, and the first duplicate of the run is logged. Past
// group_capacity, the first Groups pair.
pairing_build :: proc(p: ^Pairing, nodes: []Node) {
	clear(&p.draws)
	clear(&p.groups)
	p.draws_seen = 0
	walk := Tree_Walk {
		visit = pairing_visit,
		data  = p,
	}
	tree_walk(&walk, nodes, WALK_ROOT)
	if p.draws_seen > p.capacity && !p.over_capacity_logged {
		p.over_capacity_logged = true
		fmt.eprintfln("a Scene has %v draws; the pairing map allocates past %v", p.draws_seen, p.capacity)
	}
}

@(private = "file")
pairing_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: Walk_Parent) {
	p := (^Pairing)(walk.data)
	switch node.tag {
	case .Draw:
		d := &node.payload.draw
		p.draws_seen += 1
		if d.id in p.draws {
			if d.id not_in p.logged {
				p.logged[d.id] = {}
				fmt.eprintfln("two draws share id %v; the first one pairs", d.id)
			}
			return
		}
		local := pose_of(d.pos, d.rot)
		p.draws[d.id] = {parent = parent.id, local = local, world = pose_under(parent, parent.scene, local), draw = d}
	case .Group:
		g := node.payload.group._0
		if g.id in p.groups {
			if !p.group_duplicate_logged {
				p.group_duplicate_logged = true
				fmt.eprintfln("two groups share id %v; the first one pairs", g.id)
			}
			return
		}
		if len(p.groups) == p.group_capacity {
			if !p.groups_full_logged {
				p.groups_full_logged = true
				fmt.eprintfln("a Scene has more than %v groups; the host pairs the first %v", p.group_capacity, p.group_capacity)
			}
			return
		}
		local := pose_of(g.pos, g.rot)
		p.groups[g.id] = {parent = parent.id, local = local, world = pose_under(parent, parent.scene, local)}
	case .Light, .Collider:
	}
}

// nil when the previous Scene has no Draw with this id.
pairing_draw :: proc(p: ^Pairing, id: u64) -> ^Prev_Node {
	return &p.draws[id] if id in p.draws else nil
}

// nil when the previous Scene has no paired Group with this id.
pairing_group :: proc(p: ^Pairing, id: u64) -> ^Prev_Node {
	return &p.groups[id] if id in p.groups else nil
}

// world is the Draw's Pose for this Frame. A Draw with no partner passes
// itself as prev. A Group has no scale, so scale and scale_rot interpolate
// on their own.
draw_transform :: proc(prev, curr: ^Draw, world: Pose, alpha: f32) -> Draw_Transform {
	return {
		position = world.pos,
		scale = v3_lerp(prev.scale, curr.scale, alpha),
		rotation = world.rot,
		// Most draws keep one scale_rot, so most skip the slerp.
		scale_rotation = quat_of(curr.scale_rot) if prev.scale_rot == curr.scale_rot else quat_slerp(quat_of(prev.scale_rot), quat_of(curr.scale_rot), alpha),
	}
}

// The scale acts along the axes of scale_rotation, then rotation turns the result.
draw_model_matrix :: proc(x: Draw_Transform) -> Mat4 {
	return mat4_translate(x.position) * draw_rotate_scale(x, x.scale)
}

// The inverse transpose of the model's linear part. Each rotation is its own
// inverse transpose, so only the scale inverts.
draw_normal_matrix :: proc(x: Draw_Transform) -> Mat4 {
	inverse_scale: [3]f32
	for s, i in x.scale {
		inverse_scale[i] = 1 / s if s != 0 else 0
	}
	return draw_rotate_scale(x, inverse_scale)
}

draw_rotate_scale :: proc(x: Draw_Transform, scale: [3]f32) -> Mat4 {
	frame := mat4_from_quat(x.scale_rotation)
	return mat4_from_quat(x.rotation) * frame * mat4_scale(scale) * linalg.transpose(frame)
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

