app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

import ui.Ui
import Layout
import Display
import Lighting
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

Model : { manifest : Manifest, loaded_packs : List(Str), lighting : Lighting.Settings, eye : Vec3, yaw : F32, pitch : F32, mode : [Walk, Free, Hero, Tour, Square], time : F32, route_i : U64, selected : U64, captured : Bool, vegetation : Vegetation.Settings, prepared : Vegetation.Prepared, shadow : Vocabulary.Shadow }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |config| {
	startup = Quality.startup(config.args)
	{ ..Launch.default, window: Display.window(config, { ..Launch.default.window, title: "Village", samples: startup.samples }), shadow_map: startup.shadow_map, shadow_cascades: startup.shadow_cascades, capacity: { ..Launch.default.capacity, meshes: 128, draws: 32768 } }
}

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| { model: { manifest: [], loaded_packs: [], lighting: Lighting.default, eye: { x: 0.0, y: 1.7, z: 17.0 }, yaw: 0.0, pitch: 0.0, mode: Hero, time: 0.0, route_i: 0, selected: 0, captured: Bool.False, vegetation: config.args.fold(Vegetation.default, |settings, arg| Vegetation.configure(settings, arg.drop_prefix("--"))), prepared: Vegetation.empty, shadow: Quality.appearance(config.args) }, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, pack, manifest| {
	combined = { ..model, manifest: List.join([model.manifest, manifest]), loaded_packs: List.join([model.loaded_packs, [pack]]) }
	if ready(combined) { ..combined, prepared: Vegetation.prepare(combined.manifest) } else combined
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
	} else {
		views = Port.messages(results, "view").fold(model, set_view)
		from_view = { ..views, lighting: Port.messages(results, "lighting").fold(views.lighting, Lighting.compare) }
		from_vegetation = { ..from_view, vegetation: Port.messages(results, "vegetation").fold(from_view.vegetation, Vegetation.configure) }
		from_port = { ..from_vegetation, shadow: Port.messages(results, "quality").fold(from_vegetation.shadow, Quality.configure) }
		vegetation = if Key.pressed(input, Num4) Vegetation.configure(from_port.vegetation, "wind") else if Key.pressed(input, Num5) Vegetation.configure(from_port.vegetation, "canopy") else if Key.pressed(input, Num6) Vegetation.configure(from_port.vegetation, "grass") else if Key.pressed(input, Num7) Vegetation.configure(from_port.vegetation, "field") else if Key.pressed(input, Num8) Vegetation.configure(from_port.vegetation, "casting") else from_port.vegetation
		controlled = { ..from_port, vegetation }
		chosen = if Key.pressed(input, Num1) set_view(controlled, "hero") else if Key.pressed(input, Num2) set_view(controlled, "square") else if Key.pressed(input, Num3) set_view(controlled, "walk") else if Key.pressed(input, T) set_view(controlled, "tour") else if Key.pressed(input, F) set_view(controlled, "free") else if Key.pressed(input, R) { ..set_view(controlled, "hero"), selected: 0 } else controlled
		captured = if Key.pressed(input, Tab) !chosen.captured else chosen.captured
		looked = { ..chosen, captured, yaw: chosen.yaw - input.mouse.dx * 0.004 + Key.axis(input, E, Q) * dt * 1.6, pitch: clamp(chosen.pitch - input.mouse.dy * 0.003, -1.4, 1.4), time: chosen.time + dt }
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
		{ model: { ..moved, selected }, commands }
	}
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

building : Model, U64 -> Vocabulary.Node
building = |model, id| {
	children = model.prepared.source.keep_if(|placement| placement.group == id).map(|placement| Draw(Lighting.windows(Vegetation.draw(placement, model.vegetation), { asset: placement.asset, settings: model.lighting })))
	Group({ id, pos: V.zero, rot: Quat.identity, selected: model.selected == id }, children)
}

view : Model -> Vocabulary.Scene
view = |model| if !ready(model) loading_view(model) else {
	cam_view = camera(model)
	ground = Lighting.ground(model.lighting)
	placed = model.prepared.source.keep_if(|placement| placement.group == 0).map(|placement| Draw(Lighting.windows(Vegetation.draw(placement, model.vegetation), { asset: placement.asset, settings: model.lighting })))
	boxes = Layout.colliders.map(|box| Collider(Collider.box(box.id, box.pos, box.rot, box.half)))
	field = Vegetation.field_nodes(model.prepared, { settings: model.vegetation, eye: cam_view.eye })
	lights = Lighting.nodes(model.lighting)
	nodes = List.join([[ground, building(model, 10), building(model, 20), building(model, 30), building(model, 40)], placed, field, boxes, lights])
	environment = Lighting.environment(model.manifest, model.lighting)
	{ ..Scene.empty, camera: cam_view, nodes, environment, shadow: model.shadow, shader_values: Vegetation.scene_values(model.vegetation, cam_view.eye), cursor: if model.captured Locked else Free, queries: [Port.listen("view"), Port.listen("lighting"), Port.listen("vegetation"), Port.listen("quality"), Query.ray(900, cam_view.eye, V.normalize(V.sub(cam_view.target, cam_view.eye)), 80.0)] }
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
requests = List.join([Layout.assets.map(|asset| { pack: asset, assets: [asset] }), [{ pack: "lighting", assets: Lighting.assets }, { pack: "village-vegetation", assets: Vegetation.assets }]])

expected_assets : List(Str)
expected_assets = List.join([Layout.assets, Lighting.assets, Vegetation.assets.keep_if(|asset| !Lighting.assets.contains(asset))])

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
