package engine

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vmem "core:mem/virtual"
import "core:slice"

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

// The Main pass draws these in Scene order before the sky, and the Blend
// parts sorted after it.
SCENE_ORDER_PIPELINES :: [3]Mesh_Pipeline{.Opaque, .Mask, .Mask_Double_Sided}
// A double-sided Blend part draws its far wall first, so its near wall
// blends over it.
@(rodata)
BLEND_SUBMITS_DOUBLE_SIDED := [2]Mesh_Pipeline{.Blend_Back_Faces, .Blend}

#assert(len(Fs_Lights{}.light_view_proj) == MAX_CASCADES)
#assert(len(Fs_Lights{}.cascade_far) == MAX_CASCADES)

// World effects run before UI. Scene depth uses separate single-sample attachments.
Pass :: enum {
	Shadow,
	Main,
	Scene_Depth,
	Selection,
	Post,
}

// Bloom and game-effect callbacks own their intermediate passes.
// The AfterToneMap callback restores the final colour pass before UI submission.
Begin_Pass :: #type proc(ctx: rawptr, pass: Pass, view: int, clear_colour: Rgb)
End_Pass :: #type proc(ctx: rawptr)
Submit_Shadow :: #type proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Shadow_Vs_Params, skin: ^Skin_Params)
Submit :: #type proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params)
Submit_Surface :: #type proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params)
Submit_Lights :: #type proc(ctx: rawptr, lights: Fs_Lights, clusters: Cluster_Frame)
Submit_Environment :: #type proc(ctx: rawptr, sky: Sky_View)
Submit_Sky :: #type proc(ctx: rawptr, sky: Sky_View, vs_params: Sky_Vs_Params, fs_params: Sky_Fs_Params)
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
	submit_surface: Submit_Surface,
	submit_depth: Submit,
	submit_selection: Submit,
	prepare_post: proc(ctx: rawptr, effects: []Resolved_Post) -> Post_Inputs,
	submit_post: proc(ctx: rawptr, effects: []Resolved_Post, location: Post_Location, time: f32),
	submit_instances: proc(ctx: rawptr, pass: Surface_Pass, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, view_proj: Mat4, fs: Fs_Params, instances: []Surface_Instance),
	submit_sky:      Submit_Sky,
	submit_environment: Submit_Environment,
	submit_bloom:    Submit_Bloom,
	submit_tone_map: Submit_Tone_Map,
	submit_ui:       Submit_Ui,
	upload_particles: proc(ctx: rawptr, instances: []Particle_Instance, view: Frame_View),
	submit_particles: proc(ctx: rawptr, batch: Particle_Batch),
	ctx:             rawptr,
}

// The Main-pass pipeline of a mesh part. The Mask pipelines discard a
// fragment under the cutoff. Only Mask_Double_Sided culls nothing: Blender
// writes doubleSided true by default, so an Opaque part culls back faces
// whatever its material says. A Blend part blends over what is behind it.
// A double-sided one draws with Blend_Back_Faces, then with Blend.
Mesh_Pipeline :: enum u8 {
	Opaque,
	Mask,
	Mask_Double_Sided,
	Blend,
	Blend_Back_Faces,
}

Light_Drop :: enum {
	Second_Ambient,
	Second_Sun,
	Zero_Dir,
	Bad_Range,
	Bad_Point,
	Directional_Over_Limit,
	Points_Over_Limit,
	Cluster_Over_Limit,
}

// The renderer sizes its uniform buffer for draw_capacity part draws and
// len(skins) skin blocks per pass. In the Main pass, a skinned Draw applies
// its skin block at each change of Mesh_Pipeline. The host drops the Draws
// past either limit, because a release sokol writes past a full buffer.
Frame_Render :: struct {
	packs: ^Packs,
	render_time: f32,
	pairing:            Pairing,
	particles:          ^Particles,
	particles_paused:   bool,
	placed:             [dynamic]Placed,
	draw_capacity:      int,
	instance_scratch: vmem.Arena,
	instance_scratch_peak: uint,
	skins:              []Skin_Params,
	submits:            Frame_Render_Submits,
	up_fallback_logged: bool,
	lights_logged:      bit_set[Light_Drop],
	environment_logged: bit_set[Environment_Clamp],
	shadow_logged:      bit_set[Shadow_Field],
	draws_logged:       bool,
	skinned_logged:     bool,
	attach_logged:      map[Attach_Key]struct {},
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
// cascades fills it. A Draw with a shadow_count of 0 casts no shadow.
Placed :: struct {
	draw_id: u64,
	mesh:         ^Mesh,
	box: Box,
	bounds_resolved: bool,
	camera_visible: bool,
	selected: bool,
	parts:        []Mesh_Part,
	fallback:     bool,
	tint:         Rgb,
	glow:         Rgb,
	transform:    Draw_Transform,
	model:        Mat4,
	skin:         ^Skin_Params,
	light_box:    Box,
	shadow_count: int,
}

// placed_next gives the rigid Draws first, then the skinned ones, so the
// renderer can reuse each shadow pipeline and skin block.
Placed_Order :: struct {
	placed:  []Placed,
	skinned: bool,
	next:    int,
}

// A Draw's uniform blocks, made once and shared by all its parts.
Draw_Params :: struct {
	p:         ^Placed,
	vs_params: Vs_Params,
	fs_params: Fs_Params,
}

// The distance is to the centre of the Draw's world box.
@(private = "file")
Blend_Draw :: struct {
	params:      Draw_Params,
	distance_sq: f32,
	emitter: ^Particle_Batch,
}

// What the Frame's walk of the current Scene gathers.
@(private = "file")
Frame_Walk :: struct {
	fr:           ^Frame_Render,
	meshes:       ^Mesh_Table,
	scene_values: []Shader_Values,
	surfaces: Surface_Reuse,
	lights:       Light_Gather,
	part_draws_seen:   int,
	part_draws_placed: int,
	skinned_seen: int,
	// The skinned Draws placed, and their skin blocks in the Main pass.
	skinned_placed: int,
	skin_blocks: int,
	skin_blocks_seen: int,
}

// The mesh of a Draw that fits the Frame, and the parts of it that fit.
@(private = "file")
Frame_Room :: struct {
	mesh:     ^Mesh,
	fallback: bool,
	parts:    []Mesh_Part,
	skin:     ^Skin_Params,
}

// The bounded light lists live in the Frame arena. The Sun leads directionals.
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
	fr.attach_logged = make(map[Attach_Key]struct {}, perm)
}

frame_render_destroy :: proc(fr: ^Frame_Render) {
	vmem.arena_destroy(&fr.instance_scratch)
	pairing_destroy(&fr.pairing)
	delete(fr.skins, fr.allocator)
	delete(fr.placed)
	delete(fr.attach_logged)
}

// A blend from no sky starts at the clear colour.
sky_fs_params :: proc(sky: Sky_View, env: Environment) -> Sky_Fs_Params {
	from_clear := f32(1) if sky.from == nil else 0
	return {blend = {sky.amount, env.fog.sky, from_clear, 0}, fog_color = {env.fog.color.r, env.fog.color.g, env.fog.color.b, 0}, clear = {env.clear.r, env.clear.g, env.clear.b, 0}}
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
// magenta whatever the game asked for. The sky draws after every part that
// writes depth, so the depth test hides it behind them, and before every
// Blend part, so they blend over it. The UI draws after the tone map. A nil ui draws
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
	if submit && fr.packs != nil {
		shader_table_frame(&fr.packs.shaders)
		packs_shader_reload_poll(fr.packs)
	}
	pairing_build(&fr.pairing, prev.nodes.elements[:prev.nodes.length])
	clear(&fr.placed)
	frame_walk := Frame_Walk {
		fr = fr,
		meshes = meshes,
		scene_values = curr.shader_values.elements[:curr.shader_values.length],
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
		joint_pose = frame_attach_joint,
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
	tree_walk_attached(&walk)
	if frame_walk.part_draws_seen > fr.draw_capacity && !fr.draws_logged {
		fr.draws_logged = true
		fmt.eprintfln("a Scene's Draws need %v mesh part draws; the host draws the first %v", frame_walk.part_draws_seen, fr.draw_capacity)
	}
	if frame_walk.skin_blocks_seen > len(fr.skins) && !fr.skinned_logged {
		fr.skinned_logged = true
		fmt.eprintfln("a Scene has %v skinned draws, which need %v skin blocks; the host draws the ones that fit in %v", frame_walk.skinned_seen, frame_walk.skin_blocks_seen, len(fr.skins))
	}
	gathered := &frame_walk.lights
	lights := gathered.frame
	eye := view.camera.eye
	lights.camera_pos = {eye.x, eye.y, eye.z, 0}
	forward := v3_normalize(view.camera.target - eye)
	lights.view_dir = {forward.x, forward.y, forward.z, 0}
	lights.ambient.w = f32(len(gathered.directionals))
	for d, i in gathered.directionals {
		lights.directional_pos[i] = d.pos
		lights.directional_color[i] = d.color
	}
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
	shadow := shadow_clamp(curr.shadow, &fr.shadow_logged)
	if !submit {
		return
	}
	clusters := cluster_build(gathered.points[:], view, window.size * window.dpi)
	lights.cluster_grid = clusters.grid
	if clusters.overflow { light_drop(fr, .Cluster_Over_Limit) }
	span = span_close(spans, .Cluster_Build, span)
	lights.fog_color, lights.fog_ramp = fog_uniform(env.fog)
	lights.fog_color.w = shadow_filter_radius(shadow.filter)
	lights.camera_pos.w = shadow.depth_bias

	sky, has_sky := sky_view(skies, env.sky, env.sky_blend)
	if fr.submits.submit_environment != nil { fr.submits.submit_environment(fr.submits.ctx, sky) }

	when ODIN_OS == .Darwin { render_diagnostics_begin(fr, view) }
	if gathered.has_sun && placed_casts(fr.placed[:]) {
		frame_render_shadow(fr, &lights, gathered.directionals[0].pos.xyz, view, &span, shadow)
	}

	frame_render_begin_pass(fr, .Main, 0, env.clear, &span)
	fr.submits.submit_lights(fr.submits.ctx, lights, clusters)
	camera_frustum := frustum_from_matrix(view.view_proj)
	draw_params := make([]Draw_Params, len(fr.placed), context.temp_allocator)
	for &p, i in fr.placed {
		p.camera_visible = p.skin != nil || frustum_contains_box(camera_frustum, box_transform(placed_box(&p), p.model))
		draw_params[i] = frame_render_draw_params(&p, view)
	}
	when ODIN_OS == .Darwin { render_diagnostics_visible(draw_params) }
	for skinned in ([2]bool{false, true}) {
		for pipeline in SCENE_ORDER_PIPELINES {
			if !skinned && fr.submits.submit_instances != nil {
				frame_render_instances(fr, .Colour, pipeline, view.view_proj, draw_params = draw_params)
				continue
			}
			for d in draw_params {
				if d.p.camera_visible && (d.p.skin != nil) == skinned {
					frame_render_submit_parts(fr, d, pipeline)
				}
			}
		}
	}
	if has_sky {
		fr.submits.submit_sky(fr.submits.ctx, sky, {view_proj = view.view_proj}, sky_fs_params(sky, env))
	}
	instances, batches := particles_frame(fr.particles, 1 if fr.particles_paused else alpha)
	if fr.submits.upload_particles != nil { fr.submits.upload_particles(fr.submits.ctx, instances, view) }
	for b in frame_render_sort_blend_draws(draw_params, view.camera.eye, batches) {
		if b.emitter != nil {
			if fr.submits.submit_particles != nil { fr.submits.submit_particles(fr.submits.ctx, b.emitter^) }
		} else { frame_render_submit_blend_parts(fr, b.params) }
	}
	if fr.submits.submit_particles != nil {
		for batch in batches { if batch.blend == .Add { fr.submits.submit_particles(fr.submits.ctx, batch) } }
	}
	fr.submits.end_pass(fr.submits.ctx)

	effects := post_resolve(fr.packs, curr.post.elements[:curr.post.length], frame_walk.scene_values, fr.render_time)
	if fr.submits.prepare_post != nil {
		inputs := fr.submits.prepare_post(fr.submits.ctx, effects)
		if .Scene_Depth in inputs { frame_render_depth(fr, draw_params, view.view_proj, &span) }
		if .Selection_Coverage in inputs || .Selection_Depth in inputs { frame_render_selection(fr, draw_params, &span) }
	}
	if fr.submits.submit_post != nil { fr.submits.submit_post(fr.submits.ctx, effects, .BeforeBloom, fr.render_time) }

	// A window with no mip draws no bloom, so the tone map reads none.
	bloom_strength := f32(0)
	if env.bloom.strength > 0 {
		mips := bloom_mip_count({i32(window.size.x), i32(window.size.y)}, window.dpi)
		steps, count := bloom_steps(env.bloom, mips)
		for step in steps[:count] {
			fr.submits.submit_bloom(fr.submits.ctx, step)
		}
		bloom_strength = env.bloom.strength if mips > 0 else 0
	}

	frame_render_begin_pass(fr, .Post, 0, {}, &span)
	fr.submits.submit_tone_map(fr.submits.ctx, {exposure = env.exposure, tone_map = TONE_MAP_SHADER[env.tone_map], bloom_strength = bloom_strength})
	if fr.submits.submit_post != nil { fr.submits.submit_post(fr.submits.ctx, effects, .AfterToneMap, fr.render_time) }
	if len(quads) > 0 {
		fr.submits.submit_ui(fr.submits.ctx, quads, window.size)
	}
	fr.submits.end_pass(fr.submits.ctx)
	span_close(spans, .Render_Submit, span)
}

@(private = "file")
frame_render_draw_params :: proc(p: ^Placed, view: Frame_View) -> Draw_Params {
 vs, fs := placed_draw_params(p, view.view_proj)
 return {p, vs, fs}
}

placed_draw_params :: proc(p: ^Placed, view_proj: Mat4) -> (vs: Vs_Params, fs: Fs_Params) {
 fs.tint = [4]f32{1, 1, 1, 1} if p.fallback else {p.tint.r, p.tint.g, p.tint.b, 1}
 fs.glow = [4]f32{} if p.fallback else {max(p.glow.r, 0), max(p.glow.g, 0), max(p.glow.b, 0), 0}
 vs = {mvp = view_proj * p.model, model = p.model, normal_model = draw_normal_matrix(p.transform)}
 return
}

frame_render_part_params :: proc(base: Fs_Params, part: ^Mesh_Part, resolved_alpha_policy := false) -> (params: Fs_Params) {
 material := part.material
 params = base
 params.material = {material.roughness, material.metallic, 1 if material.unlit else 0, material.alpha_cutoff}
 params.emissive = {material.emissive.x, material.emissive.y, material.emissive.z, 0}
 policy := f32(material.alpha_mode) if resolved_alpha_policy || part.surface != nil else 0
 params.maps = {material.normal_scale, material.occlusion_strength, policy, 0}
 if part.raw_colour { params.tint *= part.base_colour }
 return
}

// Equal distances keep Draw order, then retained source slot order.
@(private = "file")
frame_render_sort_blend_draws :: proc(draw_params: []Draw_Params, eye: [3]f32, batches: []Particle_Batch = nil) -> []Blend_Draw {
	blend := make([dynamic]Blend_Draw, 0, len(draw_params) + len(batches), context.temp_allocator)
	for d in draw_params {
		if !d.p.camera_visible || !placed_has_blend(d.p) {
			continue
		}
		box := box_transform(placed_box(d.p), d.p.model)
		to_centre := (box.min + box.max) / 2 - eye
		append(&blend, Blend_Draw{params = d, distance_sq = linalg.dot(to_centre, to_centre)})
	}
	for &batch in batches {
		if batch.blend == .Alpha {
			delta := batch.position - eye
			append(&blend, Blend_Draw{emitter = &batch, distance_sq = linalg.dot(delta, delta)})
		}
	}
	slice.stable_sort_by(blend[:], proc(a, b: Blend_Draw) -> bool {
		return a.distance_sq > b.distance_sq
	})
	return blend[:]
}

@(private = "file")
placed_has_blend :: proc(p: ^Placed) -> bool {
	for part in p.parts {
		if part.material.alpha_mode == .Blend {
			return true
		}
	}
	return false
}

@(private = "file")
frame_render_submit_parts :: proc(fr: ^Frame_Render, d: Draw_Params, pipeline: Mesh_Pipeline) {
	for &part in d.p.parts {
		if p, ok := part_pipeline(part.material); ok && p == pipeline {
			frame_render_submit_part(fr, d, &part, pipeline)
		}
	}
}

// The Blend parts of a Draw keep their file order.
@(private = "file")
frame_render_submit_blend_parts :: proc(fr: ^Frame_Render, d: Draw_Params) {
	for &part in d.p.parts {
		for pipeline in blend_submits(part.material) {
			frame_render_submit_part(fr, d, &part, pipeline)
		}
	}
}

@(private = "file")
frame_render_submit_part :: proc(fr: ^Frame_Render, d: Draw_Params, part: ^Mesh_Part, pipeline: Mesh_Pipeline) {
	params := frame_render_part_params(d.fs_params, part)
	if part.surface != nil {
		if fr.submits.submit_surface != nil {
			fr.submits.submit_surface(fr.submits.ctx, .Colour, d.p.mesh, part, pipeline, d.vs_params, params, d.p.skin)
		}
	} else {
		fr.submits.submit(fr.submits.ctx, d.p.mesh, part, pipeline, d.vs_params, params, d.p.skin)
	}
}

// The pipeline of a part that draws before the sky. A Blend part has no
// such pipeline.
part_pipeline :: proc(m: Material) -> (pipeline: Mesh_Pipeline, ok: bool) {
	switch m.alpha_mode {
	case .Opaque:
		return .Opaque, true
	case .Mask:
		return .Mask_Double_Sided if m.double_sided else .Mask, true
	case .Blend:
	}
	return {}, false
}

// Empty for a part that draws before the sky.
@(private = "file")
blend_submits :: proc(m: Material) -> []Mesh_Pipeline {
	if m.alpha_mode != .Blend {
		return nil
	}
	return BLEND_SUBMITS_DOUBLE_SIDED[:] if m.double_sided else BLEND_SUBMITS_DOUBLE_SIDED[1:]
}

@(private = "file")
part_draws :: proc(m: Material) -> int {
	return max(len(blend_submits(m)), 1)
}

// A skinned Draw applies its skin block again at each change of pipeline:
// once for each pipeline it uses before the sky, then once for each run of
// one pipeline in its Blend submits.
@(private = "file")
skin_blocks :: proc(parts: []Mesh_Part) -> int {
	used: bit_set[Mesh_Pipeline]
	runs := 0
	for part in parts { if part.surface != nil { count := 0; for p in parts { count += part_draws(p.material) }; return count } }
	last := Mesh_Pipeline.Opaque
	for part in parts {
		if p, ok := part_pipeline(part.material); ok {
			used += {p}
		}
		for p in blend_submits(part.material) {
			runs += 1 if p != last else 0
			last = p
		}
	}
	return card(used) + runs
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
			frame_place(fw, d, room, draw_place(walk.pairing, d, parent, walk.alpha), parent.selected)
		}
	case .Light:
		light_gather(fw.fr, &fw.lights, light_under(node.payload.light, parent))
	case .Group, .Attach, .Collider, .Speaker:
	}
}

// The Joint at the placed Draw's interpolated Pose and Clip time, so an
// attached child follows the Clip in the same Frame. A Draw past the draw
// capacity is not placed, so its Attach finds no Draw.
@(private = "file")
frame_attach_joint :: proc(walk: ^Tree_Walk, config: ^Attach_Config) -> (world: Pose, ok: bool) {
	fw := (^Frame_Walk)(walk.data)
	for &p in fw.fr.placed {
		if p.draw_id != config.draw {
			continue
		}
		miss: Attach_Miss
		world, miss = attach_joint_pose(fw.meshes, p.mesh, p.transform.pose, p.model, roc_str_string(&config.joint))
		if miss != .None {
			attach_log(&fw.fr.attach_logged, config, p.mesh, miss)
		}
		return world, miss == .None
	}
	attach_log(&fw.fr.attach_logged, config, nil, .No_Draw)
	return
}

// The draw capacity counts part draws, so the Draw that crosses it keeps the
// parts before the first that does not fit, and the Draws after it draw
// nothing. Past the draw capacity or the room for skin blocks, the Frame
// counts the Draw and skips it.
@(private = "file")
frame_room :: #force_inline proc(fw: ^Frame_Walk, d: ^Draw) -> (room: Frame_Room, fits: bool) {
	mesh, fallback := mesh_resolve(fw.meshes, d.mesh, d.id)
	parts := surface_reuse_parts(&fw.surfaces, fw.fr.packs, d, mesh, fw.scene_values, fw.fr.render_time)
	left := fw.fr.draw_capacity - fw.part_draws_placed
	count, counted := 0, 0
	for part, i in parts {
		n := part_draws(part.material)
		fw.part_draws_seen += n
		if count == i && counted + n <= left {
			count += 1
			counted += n
		}
	}
	if count < len(parts) {
		fw.part_draws_placed = fw.fr.draw_capacity
		counted = 0
	}
	if count == 0 {
		return {}, false
	}
	skin: ^Skin_Params
	if mesh_skinned(mesh) {
		fw.skinned_seen += 1
		blocks := skin_blocks(parts[:count])
		fw.skin_blocks_seen += blocks
		if fw.skin_blocks + blocks > len(fw.fr.skins) {
			return {}, false
		}
		skin = &fw.fr.skins[fw.skinned_placed]
		fw.skinned_placed += 1
		fw.skin_blocks += blocks
	}
	fw.part_draws_placed += counted
	return {mesh = mesh, fallback = fallback, parts = parts[:count], skin = skin}, true
}

@(private = "file")
frame_place :: #force_inline proc(fw: ^Frame_Walk, d: ^Draw, room: Frame_Room, x: Draw_Transform, selected := false) {
 box := room.mesh.box
 displacement := f32(0)
 for part in room.parts { if part.surface != nil { displacement = max(displacement, part.surface.shader.package_data.max_displacement) } }
 box.min -= displacement; box.max += displacement
	append(
		&fw.fr.placed,
		Placed {
			mesh = room.mesh,
			draw_id = d.id,
			selected = selected,
			box = box,
			bounds_resolved = true,
			parts = room.parts,
			fallback = room.fallback,
			tint = d.tint,
			glow = d.glow,
			transform = x,
			model = draw_model_matrix(x),
			skin = room.skin,
			shadow_count = parts_shadow_count(room.parts) if d.casts_shadow else 0,
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
// Distance 0 keeps the legacy single-map fit. A finite view range uses
// camera slices, including with one cascade.
frame_render_shadow :: proc(fr: ^Frame_Render, lights: ^Fs_Lights, to_light: [3]f32, view: Frame_View, span: ^Span_Tick, settings := SHADOW_DEFAULT) {
	distance := shadow_distance(settings, fr.cascades)
	if distance == 0 {
		light_view_proj := shadow_view_proj(to_light, fr.placed[:])
		lights.shadow = {1, 0, settings.normal_bias, 0}
		lights.light_view_proj[0] = light_view_proj
		frame_render_begin_pass(fr, .Shadow, 0, {}, span)
		frame_render_shadow_parts(fr, light_view_proj)
		fr.submits.end_pass(fr.submits.ctx)
		return
	}

	light_view := light_view_of(to_light)
	for &p in fr.placed {
		if p.shadow_count > 0 {
			p.light_box = light_box(light_view, p.model, placed_box(&p))
		}
	}
	splits := cascade_splits(SCENE_NEAR, distance, fr.cascades, settings.distribution)
	for i in 0 ..< fr.cascades {
		sphere := cascade_sphere(view.camera, view.aspect, cascade_slice_near(splits, SCENE_NEAR, i, settings.blend), splits[i])
		cascade := cascade_view(light_view, sphere, fr.shadow_map, fr.placed[:], shadow_filter_radius(settings.filter))
		lights.light_view_proj[i] = cascade.view_proj
		frame_render_begin_pass(fr, .Shadow, i, {}, span)
		frame_render_shadow_parts(fr, cascade.view_proj, &cascade)
		fr.submits.end_pass(fr.submits.ctx)
	}
	forward := v3_normalize(view.camera.target - view.camera.eye)
	lights.shadow = {f32(fr.cascades), 0, settings.normal_bias, settings.blend}
	lights.cascade_far = splits
	lights.view_dir = {forward.x, forward.y, forward.z, distance}
}

// Opaque ranges precede all fragment-discard work in each cascade.
@(private = "file")
frame_render_shadow_parts :: proc(fr: ^Frame_Render, light_view_proj: Mat4, cascade: ^Cascade_View = nil) {
	for pipeline in SCENE_ORDER_PIPELINES {
		if fr.submits.submit_instances != nil { frame_render_instances(fr, .Shadow, pipeline, light_view_proj, cascade) }
		order := Placed_Order{placed = fr.placed[:]}
		for p in placed_next(&order) {
			if (fr.submits.submit_instances != nil && p.skin == nil) || p.shadow_count == 0 || (cascade != nil && !cascade_covers(cascade^, p.light_box)) {
				continue
			}
			params := Shadow_Vs_Params{light_mvp = light_view_proj * p.model}
			if pipeline == .Opaque && !p.parts[0].raw_colour {
				part := Mesh_Part{count = parts_opaque_count(p.parts)}
				if part.count > 0 {
					fr.submits.submit_shadow(fr.submits.ctx, p.mesh, &part, pipeline, params, p.skin)
				}
				continue
			}
			for &part in p.parts {
				if pp, ok := part_pipeline(part.material); ok && pp == pipeline {
					params.shadow_material = {part.material.alpha_cutoff, 0, 0, 0}
					if part.raw_colour && part.base_colour.a != 1 {
						params.shadow_material.x /= max(part.base_colour.a, 0.000001)
					}
					if part.surface != nil {
						if fr.submits.submit_surface != nil {
							vs, base := placed_draw_params(p, light_view_proj)
							fs := frame_render_part_params(base, &part)
							fr.submits.submit_surface(fr.submits.ctx, .Shadow, p.mesh, &part, pipeline, vs, fs, p.skin)
						}
					} else {
						fr.submits.submit_shadow(fr.submits.ctx, p.mesh, &part, pipeline, params, p.skin)
					}
				}
			}
		}
	}
}

@(private = "file")
placed_casts :: proc(placed: []Placed) -> bool {
	for &p in placed {
		if p.shadow_count > 0 {
			return true
		}
	}
	return false
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

// An orthographic view from the Sun over the box of every placed Draw that
// casts a shadow. A skinned mesh's box is padded at load, so it holds the
// posed mesh. At least one Draw must cast.
shadow_view_proj :: proc(to_light: [3]f32, placed: []Placed) -> Mat4 {
	light_view := light_view_of(to_light)
	lo := [3]f32{max(f32), max(f32), max(f32)}
	hi := -lo
	for &p in placed {
		if p.shadow_count == 0 {
			continue
		}
		box := light_box(light_view, p.model, placed_box(&p))
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
		g.frame.ambient = {c.r, c.g, c.b, 0}
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
			if len(g.directionals) == MAX_DIRECTIONALS {
				resize(&g.directionals, MAX_DIRECTIONALS - 1)
				light_drop(fr, .Directional_Over_Limit)
			}
			inject_at(&g.directionals, 0, packed)
			return
		}
		if len(g.directionals) == MAX_DIRECTIONALS {
			light_drop(fr, .Directional_Over_Limit)
			return
		}
		append(&g.directionals, packed)
	case .Point:
		p := l.payload.point
		// Written this way round so a NaN range drops too.
		if !(p.range > 0 && p.range < max(f32)) {
			light_drop(fr, .Bad_Range)
			return
		}
		if p.pos.x - p.pos.x != 0 || p.pos.y - p.pos.y != 0 || p.pos.z - p.pos.z != 0 {
			light_drop(fr, .Bad_Point)
			return
		}
		if len(g.points) == MAX_POINT_LIGHTS {
			light_drop(fr, .Points_Over_Limit)
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
		fmt.eprintln("a point light has a nonfinite range or a range <= 0; the host drops it")
	case .Bad_Point:
		fmt.eprintln("a point light has a nonfinite position; the host drops it")
	case .Directional_Over_Limit:
		fmt.eprintfln("a Scene has more than %v directional lights; the host keeps the Sun and the first remaining lights", MAX_DIRECTIONALS)
	case .Points_Over_Limit:
		fmt.eprintfln("a Scene has more than %v point lights; the host keeps the first lights", MAX_POINT_LIGHTS)
	case .Cluster_Over_Limit:
		fmt.eprintfln("a cluster has more than %v point lights; the host keeps the nearest lights to its centre", CLUSTER_LIGHT_LIMIT)
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
submits_none_submit_shadow :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Shadow_Vs_Params, skin: ^Skin_Params) {}

@(private = "file")
submits_none_submit :: proc(ctx: rawptr, mesh: ^Mesh, part: ^Mesh_Part, pipeline: Mesh_Pipeline, vs_params: Vs_Params, fs_params: Fs_Params, skin: ^Skin_Params) {}

@(private = "file")
submits_none_submit_lights :: proc(ctx: rawptr, lights: Fs_Lights, clusters: Cluster_Frame) {}

@(private = "file")
submits_none_submit_sky :: proc(ctx: rawptr, sky: Sky_View, vs_params: Sky_Vs_Params, fs_params: Sky_Fs_Params) {}

@(private = "file")
submits_none_submit_ui :: proc(ctx: rawptr, quads: []Ui_Quad, screen: [2]f32) {}

@(private = "file")
submits_none_submit_bloom :: proc(ctx: rawptr, step: Bloom_Step) {}

@(private = "file")
submits_none_submit_tone_map :: proc(ctx: rawptr, params: Tone_Map_Params) {}


placed_box :: proc(p: ^Placed) -> Box { return p.box if p.bounds_resolved else p.mesh.box }

frame_render_depth :: proc(fr: ^Frame_Render, draws: []Draw_Params, view_proj: Mat4, span: ^Span_Tick) {
 frame_render_begin_pass(fr, .Scene_Depth, 0, {}, span)
 for skinned in ([2]bool{false, true}) {
  for pipeline in SCENE_ORDER_PIPELINES {
   if !skinned && fr.submits.submit_instances != nil {
    frame_render_instances(fr, .Selection, pipeline, view_proj, draw_params = draws)
    continue
   }
   for d in draws {
    if !d.p.camera_visible || (d.p.skin != nil) != skinned { continue }
    for &part in d.p.parts {
     selected, writes := part_pipeline(part.material)
     if !writes || selected != pipeline { continue }
     fs := frame_render_part_params(d.fs_params, &part)
     if part.surface != nil {
      if fr.submits.submit_surface != nil { fr.submits.submit_surface(fr.submits.ctx, .Selection, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
     } else if fr.submits.submit_depth != nil { fr.submits.submit_depth(fr.submits.ctx, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
    }
   }
  }
 }
 fr.submits.end_pass(fr.submits.ctx)
}

// Selection keeps its own depth test so occluders cannot remove selected coverage.
frame_render_selection :: proc(fr: ^Frame_Render, draws: []Draw_Params, span: ^Span_Tick) {
	frame_render_begin_pass(fr, .Selection, 0, {}, span)
	for skinned in ([2]bool{false, true}) {
		for pipeline in SCENE_ORDER_PIPELINES {
			for d in draws {
				if !d.p.selected || !d.p.camera_visible || (d.p.skin != nil) != skinned { continue }
				for &part in d.p.parts {
					if selection_pipeline(part.material) != pipeline { continue }
					fs := frame_render_part_params(d.fs_params, &part)
					if part.surface != nil {
						if fr.submits.submit_surface != nil { fr.submits.submit_surface(fr.submits.ctx, .Selection, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
					} else if fr.submits.submit_selection != nil { fr.submits.submit_selection(fr.submits.ctx, d.p.mesh, &part, pipeline, d.vs_params, fs, d.p.skin) }
				}
			}
		}
	}
	fr.submits.end_pass(fr.submits.ctx)
}

selection_pipeline :: proc(material: Material) -> Mesh_Pipeline {
	if material.double_sided { return .Mask_Double_Sided }
	return .Mask if material.alpha_mode == .Mask else .Opaque
}
