app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Config
import pf.Draw
import pf.Emitter
import pf.Environment
import pf.Image
import pf.Key
import pf.Launch
import pf.Scene
import pf.Vocabulary exposing [Command, Manifest]

Model : { enabled : Bool, image : U32, orientation_image : U32, orientation : Bool, seed : U64 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Particles: B sparks, R remove/restore, U unload image, L load image, O sprite orientation", high_dpi: Bool.False } }

load_image : Command
load_image = Load({ pack: "dust", assets: ["image/dust", "image/orientation"] })

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| { model: { enabled: Bool.True, image: 0, orientation_image: 0, orientation: Bool.False, seed: config.seed }, commands: [load_image, Emitter.burst(3, 180)] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, image: Image.resolve(manifest, "image/dust"), orientation_image: Image.resolve(manifest, "image/orientation") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, _dt| {
	enabled = if Key.pressed(input, R) !model.enabled else model.enabled
	orientation = if Key.pressed(input, O) !model.orientation else model.orientation
	commands = List.join([if Key.pressed(input, B) [Emitter.burst(3, 180)] else [], if Key.pressed(input, U) [Unload("dust")] else [], if Key.pressed(input, L) [load_image] else [], if Key.pressed(input, O) [Emitter.burst(4, 1)] else []])
	{ model: { ..model, enabled, orientation }, commands }
}

orientation_scene : Model -> Vocabulary.Scene
orientation_scene = |model| {
	source = { ..Emitter.default, id: 4, image: model.orientation_image, lifetime: 100, start_size: 3, end_size: 3, start_colour: { r: 1, g: 1, b: 1, a: 1 }, end_colour: { r: 1, g: 1, b: 1, a: 1 }, velocity: { x: 0, y: 0, z: 0 }, velocity_spread: { x: 0, y: 0, z: 0 } }
	{ ..Scene.empty, camera: Cam.look_at({ x: 0, y: 0, z: 5 }, { x: 0, y: 0, z: 0 }), emitters: [source] }
}

view : Model -> Vocabulary.Scene
view = |model| if model.orientation orientation_scene(model) else {
	smoke = { ..Emitter.default, id: 1, seed: model.seed, position: { x: -2.0, y: 1.0, z: 0.0 }, rate: 35, lifetime: 3.5, start_size: 0.3, end_size: 1.8, start_colour: { r: 0.5, g: 0.55, b: 0.6, a: 0.35 }, end_colour: { r: 0.3, g: 0.35, b: 0.4, a: 0.0 }, velocity: { x: 0.12, y: 0.9, z: 0.0 }, velocity_spread: { x: 0.25, y: 0.2, z: 0.25 }, drag: 0.1 }
	dust = { ..Emitter.default, id: 2, seed: model.seed + 7, image: model.image, position: { x: 2.0, y: 0.4, z: 0.0 }, rate: 24, lifetime: 3.0, start_size: 0.4, end_size: 2.2, start_colour: { r: 0.8, g: 0.5, b: 0.24, a: 0.4 }, end_colour: { r: 0.6, g: 0.4, b: 0.2, a: 0.0 }, velocity: { x: 0.3, y: 0.25, z: 0.0 }, velocity_spread: { x: 0.4, y: 0.15, z: 0.4 }, drag: 0.15 }
	sparks = { ..Emitter.default, id: 3, seed: model.seed + 13, position: { x: 0.0, y: 1.0, z: 0.0 }, lifetime: 1.4, start_size: 0.1, end_size: 0.02, start_colour: { r: 12.0, g: 3.0, b: 0.2, a: 1.0 }, end_colour: { r: 2.0, g: 0.1, b: 0.0, a: 0.0 }, velocity: { x: 0.0, y: 1.8, z: 0.0 }, velocity_spread: { x: 3.0, y: 2.5, z: 2.0 }, drag: 0.8, blend: Add }
	ground = Draw({ ..Draw.default, id: 1, mesh: Mesh.primitive(Plane), scale: { x: 16.0, y: 1.0, z: 12.0 }, tint: { r: 0.15, g: 0.17, b: 0.2 } })
	chimney = Draw({ ..Draw.default, id: 2, mesh: Mesh.primitive(Cube), pos: { x: -2.0, y: 0.5, z: 0.0 }, scale: { x: 0.6, y: 1.0, z: 0.6 }, tint: { r: 0.25, g: 0.2, b: 0.18 } })
	{ ..Scene.empty, camera: Cam.look_at({ x: 7.0, y: 4.0, z: 10.0 }, { x: 0.0, y: 1.8, z: 0.0 }), emitters: if model.enabled [smoke, dust, sparks] else [], nodes: [ground, chimney, Light(Ambient({ r: 0.5, g: 0.5, b: 0.5 }))], environment: { ..Environment.default, clear: { r: 0.015, g: 0.025, b: 0.045 }, bloom: { strength: 0.15, threshold: 1, knee: 0.5 } } }
}

expect view(init(Config.empty).model).emitters.len() == 3
