app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

import ui.Ui
import Display
import Layout
import Lighting
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

Model : { manifest : Manifest, eye : Vec3, yaw : F32, pitch : F32, mode : [Walk, Free, Hero, Tour, Square], time : F32, route_i : U64, selected : U64, captured : Bool, lighting : Lighting.Settings }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |config| { ..Launch.default, window: Display.window(config, { ..Launch.default.window, title: "Village baseline" }), shadow_cascades: 2 }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { manifest: [], eye: { x: 0.0, y: 1.7, z: 17.0 }, yaw: 0.0, pitch: 0.0, mode: Hero, time: 0.0, route_i: 0, selected: 0, captured: Bool.False, lighting: Lighting.default }, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, manifest: List.join([model.manifest, manifest]) }

route : List(Vec3)
route = [{ x: 0.3, y: 1.7, z: 12.0 }, { x: -0.5, y: 1.7, z: 6.0 }, { x: 0.4, y: 1.7, z: 0.0 }, { x: -0.2, y: 1.7, z: -5.0 }, { x: -1.2, y: 1.7, z: -9.5 }, { x: -2.4, y: 1.7, z: -12.6 }]

set_view : Model, Str -> Model
set_view = |model, name| match name {
	"hero" => { ..model, mode: Hero, time: 0.0 }
	"square" => { ..model, mode: Square, time: 0.0 }
	"walk" => { ..model, mode: Walk, eye: { x: 0.0, y: 1.7, z: 17.0 }, yaw: 0.0, pitch: 0.0, time: 0.0 }
	"tour" => { ..model, mode: Tour, eye: { x: 0.0, y: 1.7, z: 17.0 }, route_i: 0, time: 0.0 }
	"free" => { ..model, mode: Free, eye: camera(model).eye, time: 0.0 }
	_ => model
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| {
	if !ready(model) {
		missing_meshes = Layout.assets.keep_if(|asset| Mesh.resolve(model.manifest, asset) == 0)
		commands = if Key.pressed(input, Escape) [Quit] else match missing_meshes.first() {
			Ok(asset) => [Load({ pack: asset, assets: [asset] })]
			Err(_) => [Load({ pack: "lighting", assets: Lighting.assets })]
		}
		{ model, commands }
	} else {
		views = Port.messages(results, "view").fold(model, set_view)
		from_port = { ..views, lighting: Port.messages(results, "lighting").fold(views.lighting, Lighting.compare) }
		chosen = if Key.pressed(input, Num1) set_view(from_port, "hero") else if Key.pressed(input, Num2) set_view(from_port, "square") else if Key.pressed(input, Num3) set_view(from_port, "walk") else if Key.pressed(input, T) set_view(from_port, "tour") else if Key.pressed(input, F) set_view(from_port, "free") else if Key.pressed(input, R) { ..set_view(from_port, "hero"), selected: 0 } else from_port
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

# The source boxes turn 90 degrees, so their world half extents are (2, 3).
blocked : Vec3 -> Bool
blocked = |p| ((p.x + 6.4).abs() < 2.3 and (p.z - 1.0).abs() < 3.3) or ((p.x - 6.6).abs() < 2.3 and (p.z - 5.0).abs() < 3.3)

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
	children = Layout.placements.keep_if(|p| p.group == id and Mesh.resolve(model.manifest, p.asset) != 0).map(
		|p| {
			tint = if model.selected == id { r: 1.0, g: 0.85, b: 0.55 } else { r: 1.0, g: 1.0, b: 1.0 }
			Draw(Lighting.windows({ ..Draw.default, id: p.id, mesh: Mesh.resolve(model.manifest, p.asset), pos: p.pos, rot: p.rot, scale: p.scale, tint }, { asset: p.asset, settings: model.lighting }))
		},
	)
	Group({ id, pos: V.zero, rot: Quat.identity, selected: Bool.False }, children)
}

view : Model -> Vocabulary.Scene
view = |model| if !ready(model) loading_view(model) else {
	cam_view = camera(model)
	ground = Lighting.ground(model.lighting)
	placed = Layout.placements.keep_if(|p| p.group == 0 and Mesh.resolve(model.manifest, p.asset) != 0).map(|p| Draw({ ..Draw.default, id: p.id, mesh: Mesh.resolve(model.manifest, p.asset), pos: p.pos, rot: p.rot, scale: p.scale }))
	boxes = [Collider(Collider.box(10, { x: -6.4, y: 3.0, z: 1.0 }, Quat.identity, { x: 2.0, y: 3.0, z: 3.0 })), Collider(Collider.box(20, { x: 6.6, y: 1.5, z: 5.0 }, Quat.identity, { x: 2.0, y: 1.5, z: 3.0 }))]
	lights = Lighting.nodes(model.lighting)
	nodes = List.join([[ground, building(model, 10), building(model, 20)], placed, boxes, lights])
	environment = Lighting.environment(model.manifest, model.lighting)
	{ ..Scene.empty, camera: cam_view, nodes, environment, cursor: if model.captured Locked else Free, queries: [Port.listen("view"), Port.listen("lighting"), Query.ray(900, cam_view.eye, V.normalize(V.sub(cam_view.target, cam_view.eye)), 80.0)] }
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

assets : List(Str)
assets = List.join([Layout.assets, Lighting.assets])

ready : Model -> Bool
ready = |model| assets.all(|asset| Mesh.resolve(model.manifest, asset) != 0)

loading_view : Model -> Vocabulary.Scene
loading_view = |model| {
	failed = model.manifest.any(|entry| entry.id == 0)
	title = if failed "Village could not load" else "Loading village"
	progress = if failed "Read the host log. Press Escape to exit." else "${model.manifest.len().to_str()} / ${assets.len().to_str()} assets"
	panel = { ..Ui.panel(CenterCenter, { x: 0.0, y: 0.0 }), direction: Col, gap: 16.0, child_align: { x: Center, y: Center } }
	{ ..Scene.empty, environment: { ..Environment.default, clear: { r: 0.025, g: 0.04, b: 0.055 } }, ui: [Panel(panel, [Text({ ..Ui.label(title), size: 36.0 }), Text(Ui.label(progress))])] }
}

expect view(init(Config.empty).model).nodes.is_empty()
expect !ready(init(Config.empty).model)
expect {
	start = init(Config.empty).model
	manifest = assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	full = loaded(start, "village", manifest)
	ready(full) and !view(full).nodes.is_empty() and view(full).ui.is_empty()
}
expect {
	start = init(Config.empty).model
	manifest = assets.map(|name| { name, id: 0, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	failed = loaded(start, "village", manifest)
	!ready(failed) and view(failed).nodes.is_empty() and !view(failed).ui.is_empty()
}

expect {
	start = init(Config.empty).model
	manifest = Layout.assets.map(|name| { name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	!ready(loaded(start, "meshes", manifest))
}
expect {
	start = init(Config.empty).model
	manifest = assets.map(|name| { name: if name == "shader/VillageGround" "extra" else name, id: 4, duration: 0.0, size: { w: 0, h: 0 }, clips: [] })
	!ready(loaded(start, "village", manifest))
}
