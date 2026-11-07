app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

import ui.Ui
import Layout
import Display
import Capture
import Lighting
import Effects
import Vegetation
import Quality
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest, Vec3]
import pf.Collider
import pf.Config
import pf.Draw
import pf.Environment
import pf.Input
import pf.Key
import pf.Launch
import pf.Port
import pf.Query
import pf.QueryResults
import pf.Scene

SceneSettings : { lighting : Lighting.Settings, vegetation : Vegetation.Settings }

SceneParts : { settings : SceneSettings, ground : Vocabulary.Node, buildings : List({ id : U64, children : List(Vocabulary.Node) }), source : Vocabulary.Node, field : Vocabulary.Node, after : List(Vocabulary.Node) }

Model : { manifest : Manifest, loaded_packs : List(Str), lighting : Lighting.Settings, effects : Effects.Settings, seed : U64, eye : Vec3, yaw : F32, pitch : F32, mode : [Walk, Free, Hero, Tour, Square], time : F32, route_i : U64, selected : U64, captured : Bool, vegetation : Vegetation.Settings, prepared : Vegetation.Prepared, shadow : Vocabulary.Shadow, parts : [Unbuilt, Built(SceneParts)], capture : Capture.State }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |config| {
	_capture = Capture.start(config.args)
	startup = Quality.startup(config.args)
	{ ..Launch.default, window: Display.window(config, { ..Launch.default.window, title: "Village", samples: startup.samples }), shadow_map: startup.shadow_map, shadow_cascades: startup.shadow_cascades, capacity: { ..Launch.default.capacity, meshes: 128, draws: 32768 } }
}

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| { model: { manifest: [], loaded_packs: [], lighting: Lighting.default, effects: Effects.default, seed: config.seed, eye: { x: 0.0, y: 1.7, z: 17.0 }, yaw: 0.0, pitch: 0.0, mode: Hero, time: 0.0, route_i: 0, selected: 0, captured: Bool.False, vegetation: config.args.fold(Vegetation.default, |settings, arg| Vegetation.configure(settings, arg.drop_prefix("--"))), prepared: Vegetation.empty, shadow: Quality.appearance(config.args), parts: Unbuilt, capture: Capture.start(config.args) }, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, pack, manifest| {
	combined = { ..model, manifest: List.join([model.manifest, manifest]), loaded_packs: List.join([model.loaded_packs, [pack]]) }
	if ready(combined) refresh_parts({ ..combined, prepared: Vegetation.prepare(combined.manifest), parts: Unbuilt }) else { ..combined, parts: Unbuilt }
}

route : List(Vec3)
route = [{ x: 0.3, y: 1.7, z: 12.0 }, { x: -0.5, y: 1.7, z: 6.0 }, { x: 0.4, y: 1.7, z: 0.0 }, { x: -0.2, y: 1.7, z: -5.0 }, { x: -1.2, y: 1.7, z: -9.5 }, { x: -2.4, y: 1.7, z: -12.6 }]

set_view : Model, Str -> Model
set_view = |model, name| match name {
	"hero" => { ..model, mode: Hero, time: 0.0 }
	"square" => { ..model, mode: Square, time: 0.0 }
	"walk" => { ..model, mode: Walk, eye: { x: 0.0, y: 1.7, z: 17.0 }, yaw: 0.0, pitch: 0.0, time: 0.0 }
	"tour" => { ..model, mode: Tour, eye: { x: 0.0, y: 1.7, z: 17.0 }, route_i: 0, time: 0.0 }
	"free" => { ..model, mode: Free, eye: camera(model).eye, time: 0.0 }
	"foliage" => { ..model, mode: Free, eye: { x: 10.5, y: 1.1, z: 14.5 }, yaw: 0.85, pitch: -0.1, time: 0.0 }
	"canopy" => { ..model, mode: Free, eye: { x: -13.0, y: 4.0, z: 12.0 }, yaw: -0.71, pitch: 0.4, time: 0.0 }
	_ => model
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| {
	if !ready(model) {
		commands = if Key.pressed(input, Escape) [Quit] else match requests.keep_if(|request| !model.loaded_packs.contains(request.pack)).first() {
			Ok(request) => [Load({ pack: request.pack, assets: request.assets })]
			Err(_) => []
		}
		{ model, commands }
	} else if model.capture.enabled {
		if Key.pressed(input, Escape) { model, commands: [Capture.marker(model.capture, "aborted", model.route_i), Quit] } else capture_step(model, dt)
	} else {
		views = Port.messages(results, "view").fold(model, set_view)
		from_view = { ..views, lighting: Port.messages(results, "lighting").fold(views.lighting, Lighting.compare), effects: Port.messages(results, "effects").fold(views.effects, Effects.compare) }
		from_vegetation = { ..from_view, vegetation: Port.messages(results, "vegetation").fold(from_view.vegetation, Vegetation.configure) }
		from_port = { ..from_vegetation, shadow: Port.messages(results, "quality").fold(from_vegetation.shadow, Quality.configure) }
		vegetation = if Key.pressed(input, Num4) Vegetation.configure(from_port.vegetation, "wind") else if Key.pressed(input, Num5) Vegetation.configure(from_port.vegetation, "canopy") else if Key.pressed(input, Num6) Vegetation.configure(from_port.vegetation, "grass") else if Key.pressed(input, Num7) Vegetation.configure(from_port.vegetation, "field") else if Key.pressed(input, Num8) Vegetation.configure(from_port.vegetation, "casting") else from_port.vegetation
		controlled = { ..from_port, vegetation }
		chosen = if Key.pressed(input, Num1) set_view(controlled, "hero") else if Key.pressed(input, Num2) set_view(controlled, "square") else if Key.pressed(input, Num3) set_view(controlled, "walk") else if Key.pressed(input, T) set_view(controlled, "tour") else if Key.pressed(input, F) set_view(controlled, "free") else if Key.pressed(input, R) { ..set_view(controlled, "hero"), selected: 0 } else controlled
		effect_keys = [(Num9, "outline"), (Num0, "occlusion"), (C, "colour"), (M, "smoke"), (N, "dust"), (P, "pulse"), (G, "glow"), (H, "controls")]
		controls = effect_keys.fold(chosen.effects, |settings, (key, name)| if Key.pressed(input, key) Effects.compare(settings, name) else settings)
		captured = if Key.pressed(input, Tab) !chosen.captured else chosen.captured
		looked = { ..chosen, captured, effects: controls, yaw: chosen.yaw - input.mouse.dx * 0.004 + Key.axis(input, E, Q) * dt * 1.6, pitch: clamp(chosen.pitch - input.mouse.dy * 0.003, -1.4, 1.4), time: chosen.time + dt }
		moved = match looked.mode {
			Walk => walk(looked, input, dt)
			Free => walk(looked, input, dt)
			Tour => tour(looked, dt)
			_ => looked
		}
		selected = if Key.pressed(input, Enter) match QueryResults.ray(results, 900) {
			Ok(hit) => hit.id
			Err(_) => 0
		} else moved.selected
		commands = if Key.pressed(input, Escape) [Quit] else []
		{ model: refresh_parts({ ..moved, selected }), commands }
	}
}

capture_bool : Bool -> Str
capture_bool = |value| if value "true" else "false"

capture_settings : Model -> Command
capture_settings = |model| {
	vegetation = model.vegetation
	effects = model.effects
	lighting = model.lighting
	field_casts = model.prepared.field.any(
		|node| match node {
			Draw(draw) => draw.casts_shadow
			_ => Bool.False
		},
	)
	fields = [
		("density", vegetation.density.to_str()),
		("distance", vegetation.distance.to_str()),
		("wind", capture_bool(vegetation.wind)),
		("canopy", capture_bool(vegetation.canopy)),
		("grass", capture_bool(vegetation.grass)),
		("field", capture_bool(vegetation.field)),
		("source_casts_shadow", capture_bool(vegetation.casts_shadow)),
		("field_casts_shadow", capture_bool(field_casts)),
		("outline", capture_bool(effects.outline)),
		("visible_only", capture_bool(effects.visible_only)),
		("width", effects.width.to_str()),
		("pulse", capture_bool(effects.pulse)),
		("glow", capture_bool(effects.glow)),
		("colour", capture_bool(effects.colour)),
		("smoke", capture_bool(effects.smoke)),
		("dust", capture_bool(effects.dust)),
		("controls", capture_bool(effects.controls)),
		("sun", capture_bool(lighting.sun)),
		("sky", capture_bool(lighting.sky)),
		("exposure", capture_bool(lighting.exposure)),
		("bloom", capture_bool(lighting.bloom)),
		("haze", capture_bool(lighting.haze)),
		("lamps", capture_bool(lighting.lamps)),
		("ground", capture_bool(lighting.ground)),
	]
	Port.tell("village.capture.settings.v1", "{${Str.join_with(fields.map(|(name, value)| "\"${name}\":${value}"), ",")}}")
}

capture_step : Model, F32 -> { model : Model, commands : List(Command) }
capture_step = |model, dt| {
	result = capture_advance(model, dt)
	{ model: refresh_parts(result.model), commands: result.commands }
}

capture_advance : Model, F32 -> { model : Model, commands : List(Command) }
capture_advance = |model, dt| {
	state = model.capture
	transition = match state.phase {
		Loading => {
			capture = { ..state, phase: Warmup, count: 1 }
			prepared = { ..set_view(model, "hero"), selected: 20, lighting: Lighting.default, vegetation: Vegetation.default, effects: Effects.default, capture }
			{ model: prepared, commands: [Capture.marker(capture, "ready", 0), Capture.marker(capture, "warmup_start", 0), capture_settings(prepared)] }
		}
		Warmup => if state.count >= Capture.warmup(state) {
			capture = { ..state, phase: Route, count: 1, cycle: 1 }
			{ model: { ..set_view(model, "tour"), capture }, commands: [Capture.marker(state, "warmup_end", model.route_i), Capture.marker(capture, "route_start", 0)] }
		} else { model: { ..model, capture: { ..state, count: state.count + 1 } }, commands: [] }
		Route => if state.count >= Capture.length(state) {
			if state.cycle == 1 {
				capture = { ..state, count: 1, cycle: 2 }
				{ model: { ..set_view(model, "tour"), capture }, commands: [Capture.marker(state, "route_end", model.route_i), Capture.marker(capture, "route_start", 0)] }
			} else {
				capture = { ..state, phase: Drain, count: 1 }
				{ model: { ..model, capture }, commands: [Capture.marker(state, "route_end", model.route_i)] }
			}
		} else { model: { ..model, capture: { ..state, count: state.count + 1 } }, commands: [] }
		Drain => if state.count >= Capture.drain(state) {
			{ model: { ..model, capture: { ..state, phase: Done } }, commands: [Capture.marker(state, "complete", model.route_i), Quit] }
		} else { model: { ..model, capture: { ..state, count: state.count + 1 } }, commands: [] }
		Done => { model, commands: [] }
	}
	timed = { ..transition.model, time: transition.model.time + dt }
	moved = if timed.capture.phase == Route tour(timed, dt) else timed
	waypoint = if moved.route_i != transition.model.route_i [Capture.marker(moved.capture, "waypoint", moved.route_i)] else []
	{ model: moved, commands: List.join([transition.commands, waypoint]) }
}

clamp : F32, F32, F32 -> F32
clamp = |n, lo, hi| F32.max(lo, F32.min(n, hi))

blocked : Vec3 -> Bool
blocked = |point| Layout.colliders.any(
	|box| {
		local = Quat.rotate(V.sub(point, box.pos), Quat.conjugate(box.rot))
		local.x.abs() < box.half.x + 0.3 and local.z.abs() < box.half.z + 0.3
	},
)

walk : Model, Vocabulary.Input, F32 -> Model
walk = |model, input, dt| {
	forward = Key.axis(input, S, W)
	right = Key.axis(input, A, D)
	vertical = if model.mode == Free Key.axis(input, LeftControl, Space) else 0.0
	dir = V.normalize({ x: right * model.yaw.cos() - forward * model.yaw.sin(), y: vertical, z: -forward * model.yaw.cos() - right * model.yaw.sin() })
	speed = if model.mode == Free 6.0 else if Key.held(input, LeftShift) 3.4 else 1.45
	candidate = V.add(model.eye, V.scale(dir, speed * dt))
	x_only = { ..model.eye, x: clamp(candidate.x, -95.0, 95.0) }
	x = if model.mode == Walk and blocked(x_only) model.eye.x else x_only.x
	z_only = { ..model.eye, x, z: clamp(candidate.z, -95.0, 95.0) }
	z = if model.mode == Walk and blocked(z_only) model.eye.z else z_only.z
	y = if model.mode == Walk 1.7 else clamp(candidate.y, 0.2, 80.0)
	{ ..model, eye: { x, y, z } }
}

tour : Model, F32 -> Model
tour = |model, dt| {
	if model.time < 1.5 model else match route.get(model.route_i) {
		Err(_) => model
		Ok(target) => {
			delta = V.sub(target, model.eye)
			distance = V.length(delta)
			if distance <= 1.45 * dt { ..model, eye: target, route_i: model.route_i + 1 } else { ..model, eye: V.add(model.eye, V.scale(V.normalize(delta), 1.45 * dt)) }
		}
	}
}

camera : Model -> Vocabulary.Camera
camera = |model| {
	view = match model.mode {
		Hero => {
			u = clamp(model.time / 14.0, 0.0, 1.0)
			k = u * u * (3.0 - 2.0 * u)
			Cam.look_at({ x: 3.6 - 1.2 * k, y: 1.9 - 0.15 * k, z: 21.5 - 6.0 * k }, { x: -1.2, y: 2.6, z: -8.0 })
		}
		Square => Cam.look_at({ x: 5.8143424, y: 8.0, z: 13.974774 }, { x: 0.0, y: 2.5, z: -2.0 })
		Tour => Cam.look_at(model.eye, V.add(model.eye, { x: 0.0, y: 0.0, z: -1.0 }))
		_ => Cam.look_at(model.eye, V.add(model.eye, { x: -model.yaw.sin() * model.pitch.cos(), y: model.pitch.sin(), z: -model.yaw.cos() * model.pitch.cos() }))
	}
	{ ..view, fov_y: 1.3089969 }
}

# Group ids are apart from draw ids. The buildings use 10 to 40.
source_group_id : U64
source_group_id = 1

field_group_id : U64
field_group_id = 2

group : U64, Bool -> { id : U64, pos : Vec3, rot : Vocabulary.Quat, selected : Bool }
group = |id, selected| { id, pos: V.zero, rot: Quat.identity, selected }

source_nodes : Model, U64 -> List(Vocabulary.Node)
source_nodes = |model, id| model.prepared.source.keep_if(|placement| placement.group == id).map(|placement| Draw(Lighting.windows(Vegetation.draw(placement, model.vegetation), { asset: placement.asset, settings: model.lighting })))

scene_settings : Model -> SceneSettings
scene_settings = |model| { lighting: model.lighting, vegetation: model.vegetation }

build_parts : Model -> SceneParts
build_parts = |model| {
	settings: scene_settings(model),
	ground: Lighting.ground(model.lighting),
	buildings: [10, 20, 30, 40].map(|id| { id, children: source_nodes(model, id) }),
	source: Group(group(source_group_id, Bool.False), source_nodes(model, 0)),
	field: Group(group(field_group_id, Bool.False), Vegetation.field_nodes(model.prepared, model.vegetation)),
	after: List.join([Layout.colliders.map(|box| Collider(Collider.box(box.id, box.pos, box.rot, box.half))), Lighting.nodes(model.lighting)]),
}

# The parts ignore the eye, so only a settings change rebuilds them.
refresh_parts : Model -> Model
refresh_parts = |model| match model.parts {
	Built(parts) if parts.settings == scene_settings(model) => model
	_ => if ready(model) { ..model, parts: Built(build_parts(model)) } else { ..model, parts: Unbuilt }
}

scene_nodes : Model, SceneParts -> List(Vocabulary.Node)
scene_nodes = |model, parts| List.join([[parts.ground], parts.buildings.map(|building| Group(group(building.id, model.selected == building.id), building.children)), [parts.source, parts.field], parts.after])

view : Model -> Vocabulary.Scene
view = |model| if !ready(model) loading_view(model) else {
	cam_view = camera(model)
	parts = match model.parts {
		Built(built) if built.settings == scene_settings(model) => built
		_ => build_parts(model)
	}
	nodes = scene_nodes(model, parts)
	environment = Lighting.environment(model.manifest, model.lighting)
	{ ..Scene.empty, camera: cam_view, nodes, environment, shadow: model.shadow, shader_values: Vegetation.scene_values(model.vegetation, cam_view.eye), cursor: if model.captured Locked else Free, post: Effects.post(model.effects, model.selected), emitters: Effects.emitters(model.manifest, model.seed, model.effects), ui: effects_ui(model.effects), queries: [Port.listen("view"), Port.listen("lighting"), Port.listen("vegetation"), Port.listen("quality"), Port.listen("effects"), Query.ray(900, cam_view.eye, V.normalize(V.sub(cam_view.target, cam_view.eye)), 80.0)] }
}

expect blocked({ x: -6.4, y: 1.7, z: 1.0 }) and blocked({ x: 6.6, y: 1.7, z: 5.0 }) and !blocked({ x: 0.0, y: 1.7, z: 5.0 })
expect {
	start = { ..init(Config.empty).model, mode: Walk, eye: { x: 4.29, y: 1.7, z: 5.0 } }
	moved = walk(start, { ..Input.empty, held: [Key.code(D)] }, 1.0 / 120.0)
	moved.eye.x == start.eye.x
}
expect {
	start = init(Config.empty).model
	camera(start).eye == { x: 3.6, y: 1.9, z: 21.5 } and V.length(V.sub(camera({ ..start, time: 14.0 }).eye, { x: 2.4, y: 1.75, z: 15.5 })) < 0.00001
}

ready : Model -> Bool
ready = |model| requests.all(|request| model.loaded_packs.contains(request.pack)) and expected_assets.all(|asset| model.manifest.any(|entry| entry.name == asset and entry.id != 0)) and model.manifest.all(|entry| entry.id != 0)

requests : List({ pack : Str, assets : List(Str) })
requests = List.join([Layout.assets.map(|asset| { pack: asset, assets: [asset] }), [{ pack: "lighting", assets: Lighting.assets }, { pack: "village-vegetation", assets: Vegetation.assets }, { pack: "effects", assets: Effects.assets }]])

expected_assets : List(Str)
expected_assets = List.join([Layout.assets, Lighting.assets, Vegetation.assets.keep_if(|asset| !Lighting.assets.contains(asset)), Effects.assets])

loading_view : Model -> Vocabulary.Scene
loading_view = |model| {
	failed = model.manifest.any(|entry| entry.id == 0)
	title = if failed "Village could not load" else "Loading village"
	progress = if failed "Read the host log. Press Escape to exit." else "${expected_assets.keep_if(|asset| model.manifest.any(|entry| entry.name == asset and entry.id != 0)).len().to_str()} / ${expected_assets.len().to_str()} assets"
	panel = { ..Ui.panel(CenterCenter, { x: 0.0, y: 0.0 }), direction: Col, gap: 16.0, child_align: { x: Center, y: Center } }
	{ ..Scene.empty, environment: { ..Environment.default, clear: { r: 0.025, g: 0.04, b: 0.055 } }, ui: [Panel(panel, [Text({ ..Ui.label(title), size: 36.0 }), Text(Ui.label(progress))])] }
}

expect view(init(Config.empty).model).nodes.is_empty()
expect !ready(init(Config.empty).model)
expect {
	start = init(Config.empty).model
	manifest = expected_assets.map(|asset| { name: asset, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	full = { ..start, loaded_packs: requests.map(|request| request.pack), manifest, prepared: Vegetation.prepare(manifest) }
	ready(full) and !view(full).nodes.is_empty() and view(full).ui.is_empty()
}
expect {
	start = init(Config.empty).model
	manifest = expected_assets.map(|asset| { name: asset, id: 0, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	failed = loaded(start, "village", manifest)
	!ready(failed) and view(failed).nodes.is_empty() and !view(failed).ui.is_empty()
}

expect {
	start = init(Config.empty).model
	manifest = expected_assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	partial = { ..start, loaded_packs: requests.map(|request| request.pack).keep_if(|pack| pack != "village-vegetation"), manifest }
	!ready(partial)
}
expect {
	start = init(Config.empty).model
	manifest = expected_assets.map(|name| { name: if name == "shader/VillageGround" "extra" else name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	!ready({ ..start, loaded_packs: requests.map(|request| request.pack), manifest })
}

effects_ui : Effects.Settings -> List(Vocabulary.Element)
effects_ui = |settings| if settings.controls {
	panel = { ..Ui.float_at(LeftTop, { x: 16.0, y: 16.0 }), direction: Col, gap: 5.0, pad: { left: 12.0, right: 12.0, top: 10.0, bottom: 10.0 }, background: { r: 0.02, g: 0.03, b: 0.04, a: 1.0 } }
	[Panel(panel, [Text(Ui.label("9 Outline | 0 Visible / through walls")), Text(Ui.label("C Colour | M Smoke | N Dust")), Text(Ui.label("P Pulse | G Glow | H Hide controls"))])]
} else []

expect Effects.post(Effects.default, 0).len() == 1
expect Effects.post(Effects.default, 20).len() == 2
expect Effects.post(Effects.compare(Effects.default, "none"), 20).is_empty()

ready_test_model : Model
ready_test_model = {
	start = init(Config.empty).model
	manifest = expected_assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	{ ..start, loaded_packs: requests.map(|request| request.pack), manifest, prepared: Vegetation.prepare(manifest), selected: 20 }
}

reference_view : Model -> Vocabulary.Scene
reference_view = |model| if !ready(model) loading_view(model) else {
	cam_view = camera(model)
	source = |id| model.prepared.source.keep_if(|placement| placement.group == id).map(|placement| Draw(Lighting.windows(Vegetation.draw(placement, model.vegetation), { asset: placement.asset, settings: model.lighting })))
	identity = |id| { id, pos: V.zero, rot: Quat.identity, selected: model.selected == id }
	buildings = [10, 20, 30, 40].map(|id| Group(identity(id), source(id)))
	boxes = Layout.colliders.map(|box| Collider(Collider.box(box.id, box.pos, box.rot, box.half)))
	nodes = List.join([[Lighting.ground(model.lighting)], buildings, [Group(identity(1), source(0)), Group(identity(2), Vegetation.field_nodes(model.prepared, model.vegetation))], boxes, Lighting.nodes(model.lighting)])
	environment = Lighting.environment(model.manifest, model.lighting)
	{ ..Scene.empty, camera: cam_view, nodes, environment, shadow: model.shadow, shader_values: Vegetation.scene_values(model.vegetation, cam_view.eye), cursor: if model.captured Locked else Free, post: Effects.post(model.effects, model.selected), emitters: Effects.emitters(model.manifest, model.seed, model.effects), ui: effects_ui(model.effects), queries: [Port.listen("view"), Port.listen("lighting"), Port.listen("vegetation"), Port.listen("quality"), Port.listen("effects"), Query.ray(900, cam_view.eye, V.normalize(V.sub(cam_view.target, cam_view.eye)), 80.0)] }
}

expect {
	built = refresh_parts(ready_test_model)
	cameras = ["hero", "square", "walk", "tour", "free", "foliage", "canopy"].map(|name| set_view(built, name))
	vegetation = ["wind", "canopy", "grass", "field", "casting", "density=0", "density=1", "density=12345", "density=22000", "distance=1", "distance=65", "distance=200"].map(|message| { ..built, vegetation: Vegetation.configure(built.vegetation, message) })
	lighting = ["all", "none", "sun", "sky", "exposure", "bloom", "haze", "lamps", "ground"].map(|message| { ..built, lighting: Lighting.compare(built.lighting, message) })
	effects = ["all", "none", "outline", "occlusion", "colour", "smoke", "dust", "pulse", "glow", "controls"].map(|message| { ..built, effects: Effects.compare(built.effects, message) })
	other = [{ ..built, time: 14.0 }, { ..built, selected: 0 }, { ..built, selected: 10 }, { ..built, selected: 30 }, { ..built, selected: 40 }, { ..built, captured: Bool.True }, { ..set_view(built, "free"), eye: { x: -95.0, y: 80.0, z: 95.0 } }, { ..set_view(built, "free"), eye: { x: 95.0, y: 0.2, z: -95.0 } }]
	List.join([cameras, vegetation, lighting, effects, other]).all(|model| view(model) == reference_view(model) and view(refresh_parts(model)) == reference_view(model))
}

expect {
	built = refresh_parts(ready_test_model)
	controls = [Num1, Num2, Num3, Num4, Num5, Num6, Num7, Num8, Num9, Num0, C, M, N, P, G, H, T, F, R, Tab, Enter]
	checked = controls.fold(
		{ model: built, matches: Bool.True },
		|state, key| {
			next = step(state.model, { ..Input.empty, pressed: [Key.code(key)] }, QueryResults.empty, 1.0 / 120.0).model
			{ model: next, matches: state.matches and view(next) == reference_view(next) }
		},
	)
	checked.matches
}

expect {
	built = refresh_parts(ready_test_model)
	changed_manifest = { ..built, manifest: built.manifest.map(|asset| { ..asset, id: 9 }) }
	reloaded = loaded(changed_manifest, "repeat", [])
	failed = loaded(built, "failed", [{ name: "failed", id: 0, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }])
	view(reloaded) == reference_view(reloaded) and reloaded.prepared.source.all(|placement| placement.draw.mesh == 9) and !ready(failed) and failed.parts == Unbuilt and view(failed) == reference_view(failed)
}

## The Scene Nodes do not depend on the eye. The grass shader fades distant plants.
expect {
	built = refresh_parts(set_view(ready_test_model, "free"))
	corner = refresh_parts({ ..built, eye: { x: -95.0, y: 80.0, z: 95.0 } })
	view(corner).nodes == view(built).nodes and corner.parts == built.parts
}

expect {
	field = [
		{ ..Draw.default, id: 100003, pos: { x: -74.0, y: 0.0, z: 17.0 } },
		{ ..Draw.default, id: 100000, pos: { x: 74.0, y: 0.0, z: -5.0 } },
		{ ..Draw.default, id: 100002, pos: { x: -74.0, y: 0.0, z: -17.0 } },
		{ ..Draw.default, id: 100001, pos: { x: 74.0, y: 0.0, z: 5.0 } },
	]
	prepared = { source: ready_test_model.prepared.source.take_first(4), field: field.map(|plant| Draw(plant)), field_plain: field.map(|plant| Draw(plant)) }
	start = refresh_parts({ ..set_view(ready_test_model, "tour"), prepared })
	checked = List.repeat({}, 3600).fold(
		{ model: start, matches: Bool.True },
		|state, _| {
			next = step(state.model, Input.empty, QueryResults.empty, 1.0 / 120.0).model
			{ model: next, matches: state.matches and view(next) == reference_view(next) }
		},
	)
	checked.matches and checked.model.route_i == 6
}

expect {
	start = { ..ready_test_model, capture: Capture.start(["--capture-route=operation-v1"]) }
	first = capture_step(start, 1.0 / 120.0)
	first.model.selected == 20 and first.model.capture.count == 1 and first.commands.len() == 3
}
expect {
	start = { ..ready_test_model, capture: { ..Capture.start(["--capture-route=full-v1"]), phase: Warmup, count: 1800 } }
	first = capture_step(start, 1.0 / 120.0)
	first.model.mode == Tour and first.model.capture.phase == Route and first.model.capture.count == 1 and first.model.capture.cycle == 1
}
expect {
	start = { ..ready_test_model, capture: { ..Capture.start(["--capture-route=full-v1"]), phase: Route, count: 3600, cycle: 1 } }
	first = capture_step(start, 1.0 / 120.0)
	first.model.eye == { x: 0.0, y: 1.7, z: 17.0 } and first.model.capture.count == 1 and first.model.capture.cycle == 2
}
expect {
	start = { ..ready_test_model, capture: { ..Capture.start(["--capture-route=full-v1"]), phase: Drain, count: 120, cycle: 2 } }
	first = capture_step(start, 1.0 / 120.0)
	first.model.capture.phase == Done and first.commands.last() == Ok(Quit)
}

capture_test_run : Model, U64 -> { model : Model, warmup : U64, route : U64, drain : U64, done : U64, selected : Bool, events : List({ step : U64, message : Str }) }
capture_test_run = |model, steps| List.repeat({}, steps).map_with_index(|_, i| i + 1).fold(
	{ model, warmup: 0, route: 0, drain: 0, done: 0, selected: Bool.True, events: [] },
	|state, step_i| {
		next = capture_advance(state.model, 1.0 / 120.0)
		messages = next.commands.map(
			|command| match command {
				Tell(message) => if message.port == "village.capture.v1" [message.msg] else []
				_ => []
			},
		).join()
		{
			model: next.model,
			warmup: state.warmup + if next.model.capture.phase == Warmup 1 else 0,
			route: state.route + if next.model.capture.phase == Route 1 else 0,
			drain: state.drain + if next.model.capture.phase == Drain 1 else 0,
			done: state.done + if next.model.capture.phase == Done 1 else 0,
			selected: state.selected and next.model.selected == 20,
			events: List.join([state.events, messages.map(|message| { step: step_i, message })]),
		}
	},
)

expect {
	start = init({ ..Config.empty, args: ["--capture-route=full-v1"] }).model
	waiting = step(start, Input.empty, QueryResults.empty, 1.0 / 120.0)
	waiting.model.capture == start.capture
}
expect {
	start = init({ ..Config.empty, args: ["--capture-route=full-v1"] }).model
	finished = capture_test_run(start, 9121)
	finished.warmup == 1800 and finished.route == 7200 and finished.drain == 120 and finished.done == 1 and finished.selected and finished.events.len() == 20 and [
		{ step: 1, message: "ready|0|1|0|full" },
		{ step: 1801, message: "route_start|1|1|0|full" },
		{ step: 5401, message: "route_end|1|3600|6|full" },
		{ step: 5401, message: "route_start|2|1|0|full" },
		{ step: 9001, message: "route_end|2|3600|6|full" },
		{ step: 9121, message: "complete|2|120|6|full" },
	].all(|event| finished.events.contains(event))
}
expect {
	start = init({ ..Config.empty, args: ["--capture-route=full-v1"] }).model
	warmed = capture_test_run(start, 1800).model
	compared = List.repeat({}, 3600).fold(
		{ captured: warmed, source: set_view(warmed, "tour"), equal: Bool.True },
		|state, _| {
			captured = capture_advance(state.captured, 1.0 / 120.0).model
			source = tour({ ..state.source, time: state.source.time + 1.0 / 120.0 }, 1.0 / 120.0)
			{ captured, source, equal: state.equal and camera(captured) == camera(source) }
		},
	)
	warmed.mode == Hero and warmed.capture.count == 1800 and V.length(V.sub(camera(warmed).eye, { x: 2.4, y: 1.75, z: 15.5 })) < 0.00001 and compared.equal and compared.captured.route_i == 6 and compared.captured.capture.count == 3600
}
