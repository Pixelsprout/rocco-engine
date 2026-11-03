package engine

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"

SCENE_NEAR :: f32(0.1)

// The light_view_proj and cascade_far arrays in engine/shaders/basic.glsl have this size.
MAX_CASCADES :: 4
// The shadow box snaps outward to this grid, so the map changes size in steps
// and its edges do not crawl as a Draw moves.
SHADOW_GRID :: f32(1)
SHADOW_NORMAL_OFFSET :: f32(0.05)
// The tone_map_fs branch that draws each Tone_Map. The glue numbers the tags
// in name order, so a new tag would move them.
@(rodata)
TONE_MAP_SHADER := [Tone_Map]f32 {
	.Aces    = 0,
	.AgX     = 1,
	.Neutral = 2,
}

// A Headless run never submits, so its submits do nothing.
FRAME_RENDER_SUBMITS_NONE :: Frame_Render_Submits {
	begin_pass      = submits_none_begin_pass,
	end_pass        = submits_none_end_pass,
	submit_shadow   = submits_none_submit_shadow,
	submit          = submits_none_submit,
	submit_lights   = submits_none_submit_lights,
	submit_sky      = submits_none_submit_sky,
	submit_bloom    = submits_none_submit_bloom,
	submit_tone_map = submits_none_submit_tone_map,
	submit_ui       = submits_none_submit_ui,
}

#assert(len(Fs_Lights{}.light_view_proj) == MAX_CASCADES)
#assert(len(Fs_Lights{}.cascade_far) == MAX_CASCADES)

// The Main pass draws linear HDR colour. The Post pass adds the bloom, tone
// maps the result and then draws the UI over it, so the UI keeps its
// authored colour.
Pass :: enum {
	Shadow,
	Main,
	Post,
}

// Lets tests run without sokol. Each frame begins and ends one Shadow pass
// per shadow view, then one Main pass, then one Post pass. submit_shadow runs
// only in a Shadow pass, once per Draw. In the Main pass, submit runs once
// per part of each Draw's mesh. submit_lights runs before any submit, and
// submit_sky runs at most once, after every submit. With bloom on,
// submit_bloom runs once per Bloom_Step between the Main pass and the Post
// pass, outside any pass, because each step is a pass of its own.
// submit_tone_map runs once, first in the Post pass, and submit_ui runs at
// most once after it.
// In each pass, the skinned Draws follow the rigid ones, so the renderer
// changes pipeline once. A nil skin is a rigid Draw.
Begin_Pass :: #type proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb)
End_Pass :: #type proc(ctx: rawptr)
Submit_Shadow :: #type proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params, skin: ^Skin_Params)
Submit :: #type proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params)
Submit_Lights :: #type proc(ctx: rawptr, lights: Fs_Lights)
Submit_Sky :: #type proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params)
Submit_Bloom :: #type proc(ctx: rawptr, step: Bloom_Step)
Submit_Tone_Map :: #type proc(ctx: rawptr, params: Tone_Map_Params)
Submit_Ui :: #type proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32)

// The renderer and the test Recorder are its two adapters. ctx is passed to
// each proc.
Frame_Render_Submits :: struct {
	begin_pass:      Begin_Pass,
	end_pass:        End_Pass,
	submit_shadow:   Submit_Shadow,
	submit:          Submit,
	submit_lights:   Submit_Lights,
	submit_sky:      Submit_Sky,
	submit_bloom:    Submit_Bloom,
	submit_tone_map: Submit_Tone_Map,
	submit_ui:       Submit_Ui,
	ctx:             rawptr,
}

Light_Drop :: enum {
	Second_Ambient,
	Second_Sun,
	Zero_Dir,
	Bad_Range,
	Draw_Over_Limit,
}

// The renderer sizes its uniform buffer for draw_capacity mesh parts and
// len(skins) skinned Draws per Frame. The host drops the rest, because a
// release sokol writes past a full buffer.
Frame_Render :: struct {
	pairing:            Pairing,
	placed:             [dynamic]Placed,
	draw_capacity:      int,
	skins:              []Skin_Params,
	submits:            Frame_Render_Submits,
	up_fallback_logged: bool,
	lights_logged:      bit_set[Light_Drop],
	environment_logged: bit_set[Environment_Clamp],
	draws_logged:       bool,
	skinned_logged:     bool,
	shadow_map:         u32,
	cascades:           int,
	allocator:          mem.Allocator,
}

Draw_Transform :: struct {
	position:       [3]f32,
	scale:          [3]f32,
	rotation:       quaternion128,
	scale_rotation: quaternion128,
	pose:           Draw_Pose,
}

// A Draw at its interpolated pose, kept so both passes use one transform.
// parts are the mesh parts that fit the draw capacity. skin is a slot of
// Frame_Render.skins for a skinned mesh, and nil for a rigid one. light_box
// is the mesh box in the Sun's view space; only the shadow pass of 2 to 4
// cascades fills it.
Placed :: struct {
	mesh:      ^Mesh,
	parts:     []Mesh_Part,
	fallback:  bool,
	tint:      Rgb,
	glow:      Rgb,
	transform: Draw_Transform,
	model:     Mat4,
	skin:      ^Skin_Params,
	light_box: Box,
}

// placed_next gives the rigid Draws first, then the skinned ones, so the
// renderer changes pipeline once per pass.
Placed_Order :: struct {
	placed:  []Placed,
	skinned: bool,
	next:    int,
}

// What the Frame's walk of the current Scene gathers.
@(private = "file")
Frame_Walk :: struct {
	fr:           ^Frame_Render,
	meshes:       ^Mesh_Table,
	lights:       Light_Gather,
	parts_seen:   int,
	parts_placed: int,
	skinned_seen: int,
}

// The mesh of a Draw that fits the Frame, and the parts of it that fit.
@(private = "file")
Frame_Room :: struct {
	mesh:     ^Mesh,
	fallback: bool,
	parts:    []Mesh_Part,
	skin:     ^Skin_Params,
}

// Every Directional and Point Light of the Scene, in walk order, except the
// Sun, which goes first in directionals. The lists live in the frame arena.
Light_Gather :: struct {
	frame:                Fs_Lights,
	directionals, points: [dynamic]Packed_Light,
	has_sun, has_ambient: bool,
}

// The camera the host draws a frame with.
Camera_Pose :: struct {
	eye, target, up: [3]f32,
	fov_y:           f32,
}

// The camera a Frame draws from. The cascades split its view.
Frame_View :: struct {
	view_proj: Mat4,
	camera:    Camera_Pose,
	aspect:    f32,
}

frame_render_init :: proc(fr: ^Frame_Render, draws, groups: int, shadow_map: u32, cascades: int, perm: mem.Allocator) {
	fr.draw_capacity = draws
	fr.shadow_map = shadow_map
	fr.cascades = cascades
	fr.allocator = perm
	pairing_init(&fr.pairing, draws, groups, perm)
	fr.placed = make([dynamic]Placed, 0, draws, perm)
	fr.skins = make([]Skin_Params, skinned_draw_capacity(draws), perm)
}

frame_render_destroy :: proc(fr: ^Frame_Render) {
	pairing_destroy(&fr.pairing)
	delete(fr.skins, fr.allocator)
	delete(fr.placed)
}

// An up along the view, or a zero up, has no right vector.
frame_render_camera :: proc(fr: ^Frame_Render, prev, curr: Scene, alpha, aspect: f32) -> Frame_View {
	pose := camera_lerp(prev.camera, curr.camera, alpha)
	if v3_length(v3_cross(pose.target - pose.eye, pose.up)) < UP_EPSILON {
		if !fr.up_fallback_logged {
			fr.up_fallback_logged = true
			fmt.eprintfln("the Scene camera's up %v is zero or along its view; using +y", pose.up)
		}
		pose.up = UP
	}
	return {view_proj = scene_view_proj(pose, aspect), camera = pose, aspect = aspect}
}

// The fallback ignores the tint and the glow, so an unknown mesh id shows
// magenta whatever the game asked for. The sky draws last, so the depth test
// hides it behind every mesh. The UI draws after the tone map. A nil ui draws
// none. With submit false, the Frame still places the Draws and lays out the
// UI, but submits nothing.
frame_render_draw :: proc(
	fr: ^Frame_Render,
	prev, curr: Scene,
	alpha: f32,
	view: Frame_View,
	meshes: ^Mesh_Table,
	skies: ^Sky_Table,
	images: ^Image_Table,
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
		lights = {
			directionals = make([dynamic]Packed_Light, 0, 16, context.temp_allocator),
			points = make([dynamic]Packed_Light, 0, 16, context.temp_allocator),
		},
	}
	walk := Tree_Walk {
		visit   = frame_render_visit,
		pairing = &fr.pairing,
		alpha   = alpha,
		data    = &frame_walk,
	}
	root := WALK_ROOT
	nodes := curr.nodes.elements[:curr.nodes.length]
	for &node, i in nodes {
		if node.tag != .Draw {
			tree_walk(&walk, nodes[i:i + 1], &root)
			continue
		}
		d := &node.payload.draw
		if room, fits := frame_room(&frame_walk, d); fits {
			frame_place(&frame_walk, d, room, draw_place_root(&fr.pairing, d, alpha))
		}
	}
	if frame_walk.parts_seen > fr.draw_capacity && !fr.draws_logged {
		fr.draws_logged = true
		fmt.eprintfln("a Scene's Draws have %v mesh parts; the host draws the first %v", frame_walk.parts_seen, fr.draw_capacity)
	}
	if frame_walk.skinned_seen > len(fr.skins) && !fr.skinned_logged {
		fr.skinned_logged = true
		fmt.eprintfln("a Scene has %v skinned draws; the host draws the first %v", frame_walk.skinned_seen, len(fr.skins))
	}
	gathered := &frame_walk.lights
	lights := gathered.frame
	eye := view.camera.eye
	lights.camera_pos = {eye.x, eye.y, eye.z, 0}
	if submit {
		frame_render_pose(fr, meshes)
	}
	span = span_close(spans, .Interpolation, span)

	quads: []Ui_Quad
	if ui != nil {
		quads = ui_frame(ui, curr.ui.elements[:curr.ui.length], window, images)
		span = span_close(spans, .Ui_Layout, span)
	}
	env := environment_clamp(curr.environment, &fr.environment_logged)
	if !submit {
		return
	}
	lights.fog_color, lights.fog = fog_uniform(env.fog)

	if gathered.has_sun && len(fr.placed) > 0 {
		frame_render_shadow(fr, &lights, gathered.directionals[0].pos.xyz, view, &span)
	}

	frame_render_begin_pass(fr, .Main, 0, env.clear, &span)
	fr.submits.submit_lights(fr.submits.ctx, lights)
	order := Placed_Order {
		placed = fr.placed[:],
	}
	for p in placed_next(&order) {
		tint := [4]f32{1, 1, 1, 1} if p.fallback else {p.tint.r, p.tint.g, p.tint.b, 1}
		glow := [4]f32{} if p.fallback else {max(p.glow.r, 0), max(p.glow.g, 0), max(p.glow.b, 0), 0}
		params := Fs_Params {
			tint = tint,
			glow = glow,
		}
		if !mesh_unlit(p.mesh) {
			// Only the Point lights need the world box.
			bounds := box_transform(p.mesh.box, p.model) if len(gathered.points) > 0 else Box{}
			if light_select(gathered.directionals[:], gathered.points[:], bounds, &params.light_pos, &params.light_color) {
				light_drop(fr, .Draw_Over_Limit)
			}
		}
		vs_params := Vs_Params {
			mvp          = view.view_proj * p.model,
			model        = p.model,
			normal_model = draw_normal_matrix(p.transform),
		}
		for &part in p.parts {
			material := part.material
			e := material.emissive
			params.material = {material.roughness, material.metallic, 1 if material.unlit else 0, 0}
			params.emissive = {e.x, e.y, e.z, 0}
			params.maps = {material.normal_scale, material.occlusion_strength, 0, 0}
			fr.submits.submit(fr.submits.ctx, p.mesh, &part, vs_params, params, p.skin)
		}
	}
	if sky, ok := sky_resolve(skies, env.sky); ok {
		fr.submits.submit_sky(fr.submits.ctx, sky, {view_proj = view.view_proj})
	}
	fr.submits.end_pass(fr.submits.ctx)

	// A window with no mip draws no bloom, so the tone map reads none.
	bloom_strength := f32(0)
	if env.bloom.strength > 0 {
		mips := bloom_mip_count({i32(window.size.x), i32(window.size.y)})
		steps, count := bloom_steps(env.bloom, mips)
		for step in steps[:count] {
			fr.submits.submit_bloom(fr.submits.ctx, step)
		}
		bloom_strength = env.bloom.strength if mips > 0 else 0
	}

	frame_render_begin_pass(fr, .Post, 0, {}, &span)
	fr.submits.submit_tone_map(fr.submits.ctx, {exposure = env.exposure, tone_map = TONE_MAP_SHADER[env.tone_map], bloom_strength = bloom_strength})
	if len(quads) > 0 {
		fr.submits.submit_ui(fr.submits.ctx, quads, window.size)
	}
	fr.submits.end_pass(fr.submits.ctx)
	span_close(spans, .Render_Submit, span)
}

// Places each Draw in a Group at its Pose for this Frame and gathers each
// Light, both in walk order. frame_render_draw places the root Draws itself.
@(private = "file")
frame_render_visit :: proc(walk: ^Tree_Walk, node: ^Node, parent: ^Walk_Parent) {
	fw := (^Frame_Walk)(walk.data)
	switch node.tag {
	case .Draw:
		d := &node.payload.draw
		if room, fits := frame_room(fw, d); fits {
			frame_place(fw, d, room, draw_place(walk.pairing, d, parent, walk.alpha))
		}
	case .Light:
		light_gather(fw.fr, &fw.lights, light_under(node.payload.light, parent))
	case .Group, .Collider, .Speaker:
	}
}

// The draw capacity counts parts, so the Draw that crosses it keeps the parts
// that fit. Past the draw capacity or the skinned capacity, the Frame counts
// the Draw and skips it.
@(private = "file")
frame_room :: #force_inline proc(fw: ^Frame_Walk, d: ^Draw) -> (room: Frame_Room, fits: bool) {
	mesh, fallback := mesh_resolve(fw.meshes, d.mesh, d.id)
	fw.parts_seen += len(mesh.parts)
	count := min(len(mesh.parts), fw.fr.draw_capacity - fw.parts_placed)
	if count <= 0 {
		return {}, false
	}
	skin: ^Skin_Params
	if mesh_skinned(mesh) {
		fw.skinned_seen += 1
		if fw.skinned_seen > len(fw.fr.skins) {
			return {}, false
		}
		skin = &fw.fr.skins[fw.skinned_seen - 1]
	}
	fw.parts_placed += count
	return {mesh = mesh, fallback = fallback, parts = mesh.parts[:count], skin = skin}, true
}

@(private = "file")
frame_place :: #force_inline proc(fw: ^Frame_Walk, d: ^Draw, room: Frame_Room, x: Draw_Transform) {
	append(
		&fw.fr.placed,
		Placed {
			mesh = room.mesh,
			parts = room.parts,
			fallback = room.fallback,
			tint = d.tint,
			glow = d.glow,
			transform = x,
			model = draw_model_matrix(x),
			skin = room.skin,
		},
	)
}

// A mesh with fewer than MAX_JOINTS Joints leaves the rest of its skin as it
// was, and no vertex reads it.
frame_render_pose :: proc(fr: ^Frame_Render, meshes: ^Mesh_Table) {
	for p in fr.placed {
		if p.skin != nil {
			skin_matrices(meshes, p.mesh, p.transform.pose, &p.skin.joints)
		}
	}
}

// Must run before the Main pass begins, because sokol passes do not nest.
// One cascade draws one map over every Draw. 2 to 4 cascades split the view
// up to SHADOW_DISTANCE, and each one draws only the Draws over its square.
frame_render_shadow :: proc(fr: ^Frame_Render, lights: ^Fs_Lights, to_light: [3]f32, view: Frame_View, span: ^Span_Tick) {
	if fr.cascades <= 1 {
		light_view_proj := shadow_view_proj(to_light, fr.placed[:])
		// The shader reads x as the cascade count, y as the Sun's slot, which
		// is always 0, and z as the normal offset.
		lights.shadow = {1, 0, SHADOW_NORMAL_OFFSET, 0}
		lights.light_view_proj[0] = light_view_proj
		frame_render_begin_pass(fr, .Shadow, 0, {}, span)
		order := Placed_Order {
			placed = fr.placed[:],
		}
		for p in placed_next(&order) {
			fr.submits.submit_shadow(fr.submits.ctx, p.mesh, {light_mvp = light_view_proj * p.model}, p.skin)
		}
		fr.submits.end_pass(fr.submits.ctx)
		return
	}

	light_view := light_view_of(to_light)
	for &p in fr.placed {
		p.light_box = light_box(light_view, p.model, p.mesh.box)
	}
	splits := cascade_splits(SCENE_NEAR, SHADOW_DISTANCE, fr.cascades, CASCADE_SPLIT_WEIGHT)
	for i in 0 ..< fr.cascades {
		sphere := cascade_sphere(view.camera, view.aspect, cascade_slice_near(splits, SCENE_NEAR, i), splits[i])
		cascade := cascade_view(light_view, sphere, fr.shadow_map, fr.placed[:])
		lights.light_view_proj[i] = cascade.view_proj
		frame_render_begin_pass(fr, .Shadow, i, {}, span)
		order := Placed_Order {
			placed = fr.placed[:],
		}
		for p in placed_next(&order) {
			if cascade_covers(cascade, p.light_box) {
				fr.submits.submit_shadow(fr.submits.ctx, p.mesh, {light_mvp = cascade.view_proj * p.model}, p.skin)
			}
		}
		fr.submits.end_pass(fr.submits.ctx)
	}
	forward := v3_normalize(view.camera.target - view.camera.eye)
	lights.shadow = {f32(fr.cascades), 0, SHADOW_NORMAL_OFFSET, CASCADE_BLEND}
	lights.cascade_far = splits
	lights.view_dir = {forward.x, forward.y, forward.z, 0}
}

placed_next :: proc(order: ^Placed_Order) -> (p: ^Placed, ok: bool) {
	for {
		if order.next == len(order.placed) {
			if order.skinned {
				return nil, false
			}
			order.skinned = true
			order.next = 0
			continue
		}
		p = &order.placed[order.next]
		order.next += 1
		if (p.skin != nil) == order.skinned {
			return p, true
		}
	}
}

// On Metal, the first begin_pass of a Frame waits for a free in-flight frame,
// and the Main pass waits for the swapchain drawable. These waits pace the
// Frames, so the render Span leaves every begin_pass out.
@(private = "file")
frame_render_begin_pass :: proc(fr: ^Frame_Render, pass: Pass, view: int, clear_colour: Rgb, span: ^Span_Tick) {
	waited := span_open()
	fr.submits.begin_pass(fr.submits.ctx, pass, view, clear_colour)
	span^ = span_skip(span^, waited)
}

// An orthographic view from the Sun over the box of every placed Draw. A
// skinned mesh's box is padded at load, so it holds the posed mesh.
shadow_view_proj :: proc(to_light: [3]f32, placed: []Placed) -> Mat4 {
	light_view := light_view_of(to_light)
	lo := [3]f32{max(f32), max(f32), max(f32)}
	hi := -lo
	for p in placed {
		box := light_box(light_view, p.model, p.mesh.box)
		lo = linalg.min(lo, box.min)
		hi = linalg.max(hi, box.max)
	}
	lo = linalg.floor(lo / SHADOW_GRID) * SHADOW_GRID
	// A flat box would give a zero extent and divide by zero.
	hi = linalg.max(linalg.ceil(hi / SHADOW_GRID) * SHADOW_GRID, lo + SHADOW_GRID)
	return mat4_ortho_reversed(lo.x, hi.x, lo.y, hi.y, -hi.z, -lo.z) * light_view
}

// A dropped light does not go in a list.
light_gather :: proc(fr: ^Frame_Render, g: ^Light_Gather, l: Light) {
	switch l.tag {
	case .Ambient:
		if g.has_ambient {
			light_drop(fr, .Second_Ambient)
			return
		}
		g.has_ambient = true
		c := l.payload.ambient
		g.frame.ambient = {c.r, c.g, c.b, 1}
	case .Directional:
		d := l.payload.directional
		to_light := -v3_normalize_or_zero(vec3_array(d.dir))
		if to_light == 0 {
			light_drop(fr, .Zero_Dir)
			return
		}
		packed := Packed_Light{{to_light.x, to_light.y, to_light.z, 0}, {d.color.r, d.color.g, d.color.b, 0}}
		if d.shadow && g.has_sun {
			light_drop(fr, .Second_Sun)
		} else if d.shadow {
			g.has_sun = true
			inject_at(&g.directionals, 0, packed)
			return
		}
		append(&g.directionals, packed)
	case .Point:
		p := l.payload.point
		// Written this way round so a NaN range drops too.
		if !(p.range > 0) {
			light_drop(fr, .Bad_Range)
			return
		}
		append(&g.points, Packed_Light{{p.pos.x, p.pos.y, p.pos.z, 1}, {p.color.r, p.color.g, p.color.b, p.range}})
	}
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
	case .Zero_Dir:
		fmt.eprintln("a directional light has a zero dir; the host drops it")
	case .Bad_Range:
		fmt.eprintln("a point light has a range <= 0; the host drops it")
	case .Draw_Over_Limit:
		fmt.eprintfln("a Draw has more than %v directional and point lights in reach; the host keeps the directionals, then the nearest point lights", MAX_LIGHTS)
	}
}

scene_view_proj :: proc(camera: Camera_Pose, aspect: f32) -> Mat4 {
	return mat4_perspective_reversed_infinite(camera.fov_y, aspect, SCENE_NEAR) * mat4_look_at(camera.eye, camera.target, camera.up)
}

// A root Pose is a world Pose. So a root Draw whose partner was also a root
// Draw interpolates its own Pose, with no parent to compose.
draw_place_root :: #force_inline proc(p: ^Pairing, d: ^Draw, alpha: f32) -> Draw_Transform {
	index, found := p.draws[d.id]
	if !found {
		return draw_transform(d, d, pose_of(d.pos, d.rot), alpha)
	}
	from := p.prev_draws[index]
	if from.parent.grouped {
		root := WALK_ROOT
		return draw_place(p, d, &root, alpha)
	}
	return draw_transform(from.draw, d, pose_lerp(pose_of(from.draw.pos, from.draw.rot), pose_of(d.pos, d.rot), alpha), alpha)
}

draw_place :: proc(p: ^Pairing, d: ^Draw, parent: ^Walk_Parent, alpha: f32) -> Draw_Transform {
	from, prev, paired := pairing_draw(p, d.id, parent.id)
	world := node_world(&prev if paired else nil, parent, pose_of(d.pos, d.rot), alpha)
	return draw_transform(from if paired else d, d, world, alpha)
}

// world is the Draw's Pose for this Frame. A Draw with no partner passes
// itself as prev. A Group has no scale, so scale and scale_rot interpolate
// on their own.
draw_transform :: #force_inline proc(prev, curr: ^Draw, world: Pose, alpha: f32) -> Draw_Transform {
	return {
		position = world.pos,
		scale = v3_lerp(prev.scale, curr.scale, alpha),
		rotation = world.rot,
		// Most draws keep one scale_rot, so most skip the slerp.
		scale_rotation = quat_of(curr.scale_rot) if prev.scale_rot == curr.scale_rot else quat_slerp(quat_of(prev.scale_rot), quat_of(curr.scale_rot), alpha),
		pose = draw_pose_lerp(prev.pose, curr.pose, alpha),
	}
}

// A time blends only when its Clip is the same in both Scenes and the time
// did not go back, as it does when the game wraps a loop. The fade blends
// only when both Clips are the same. The rest takes the current values.
draw_pose_lerp :: proc(prev, curr: Draw_Pose, alpha: f32) -> Draw_Pose {
	pose := curr
	same_clip := prev.clip == curr.clip
	same_fade_clip := prev.fade_clip == curr.fade_clip
	if same_clip && curr.time >= prev.time {
		pose.time = prev.time + (curr.time - prev.time) * alpha
	}
	if same_fade_clip && curr.fade_time >= prev.fade_time {
		pose.fade_time = prev.fade_time + (curr.fade_time - prev.fade_time) * alpha
	}
	if same_clip && same_fade_clip {
		pose.fade = prev.fade + (curr.fade - prev.fade) * alpha
	}
	return pose
}

// The scale acts along the axes of scale_rotation, then rotation turns the result.
draw_model_matrix :: #force_inline proc(x: Draw_Transform) -> Mat4 {
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

@(private = "file")
submits_none_begin_pass :: proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb) {}

@(private = "file")
submits_none_end_pass :: proc(ctx: rawptr) {}

@(private = "file")
submits_none_submit_shadow :: proc(ctx: rawptr, mesh: ^Mesh, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {}

@(private = "file")
submits_none_submit :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {}

@(private = "file")
submits_none_submit_lights :: proc(ctx: rawptr, lights: Fs_Lights) {}

@(private = "file")
submits_none_submit_sky :: proc(ctx: rawptr, sky: ^Sky, vs_params: Sky_Vs_Params) {}

@(private = "file")
submits_none_submit_ui :: proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {}

@(private = "file")
submits_none_submit_bloom :: proc(ctx: rawptr, step: Bloom_Step) {}

@(private = "file")
submits_none_submit_tone_map :: proc(ctx: rawptr, params: Tone_Map_Params) {}

