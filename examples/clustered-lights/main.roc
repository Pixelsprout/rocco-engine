app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Config
import pf.Draw
import pf.Environment
import pf.Key
import pf.Launch
import pf.Light
import pf.Scene
import pf.Vocabulary exposing [Command, Manifest, Vec3]

Model : { floor : U32, time : F32, camera_x : F32, paused : Bool, lights : Bool }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "200 clustered lamps: A/D camera, P pause, L lamps", high_dpi: False } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { floor: 0, time: 0.0, camera_x: 0.0, paused: Bool.False, lights: Bool.True }, commands: [Load({ pack: "lamps", assets: ["floor"] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, floor: Mesh.resolve(manifest, "floor") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	paused = if Key.pressed(input, P) !model.paused else model.paused
	lights = if Key.pressed(input, L) !model.lights else model.lights
	direction = (if Key.held(input, D) 1.0 else 0.0) - (if Key.held(input, A) 1.0 else 0.0)
	time = if paused model.time else model.time + dt
	camera_x = model.camera_x + direction * dt * 8.0
	{ model: { ..model, time, camera_x, paused, lights }, commands: [] }
}

lamp_pos : U64, F32 -> Vec3
lamp_pos = |id, time| {
	x = (id % 20).to_f32() * 2.0 - 19.0
	z = (id // 20).to_f32() * 2.0 - 9.0
	{ x: x + 0.25 * time.sin(), y: 0.8, z: z + 0.25 * time.cos() }
}

lamps : Model, U64 -> List(Vocabulary.Node)
lamps = |model, id| {
	if id == 200 {
		[]
	} else {
		pos = lamp_pos(id, model.time)
		colour = { r: 7.0, g: 3.5, b: 0.7 }
		ball = { ..Draw.default, id: id + 1, mesh: Mesh.primitive(Sphere), pos, scale: { x: 0.16, y: 0.16, z: 0.16 }, glow: colour }
		point = if model.lights [Light(Light.point(pos, colour, 2.4))] else []
		List.join([[Draw(ball)], point, lamps(model, id + 1)])
	}
}

view : Model -> Vocabulary.Scene
view = |model| {
	floor = { ..Draw.default, id: 0, mesh: model.floor }
	camera = Cam.look_at({ x: model.camera_x, y: 30.0, z: 32.0 }, { x: model.camera_x, y: 0.0, z: 0.0 })
	{ ..Scene.empty, camera, nodes: List.join([[Draw(floor), Light(Light.ambient({ r: 0.005, g: 0.005, b: 0.005 }))], lamps(model, 0)]), environment: Environment.default }
}

expect view(init(Config.empty).model).nodes.len() == 402
expect view({ ..init(Config.empty).model, lights: Bool.False }).nodes.len() == 202
expect lamp_pos(0, 0.0) == { x: -19.0, y: 0.8, z: -8.75 }
