app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-11-04-2622062" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Config
import pf.Draw
import pf.Environment
import pf.Key
import pf.Launch
import pf.Scene
import pf.Vocabulary exposing [Command, Manifest]

# blend is the sky_blend amount from the sky toward cool. sky_fog turns on
# the fog's sky amount.
Model : { reference : U32, warm : U32, cool : U32, sky : U8, exposure : F32, blend : F32, sky_fog : Bool }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |config| { ..Launch.default, window: { ..Launch.default.window, title: "Environment: S sky, N none, E exposure, B blend, F sky fog, U unload, R reload", width: (if (config.args.contains("--1080")) 1920 else 960), height: (if (config.args.contains("--1080")) 1080 else 540), high_dpi: Bool.False } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| { model: { reference: 0, warm: 0, cool: 0, sky: (if (config.args.contains("--none")) 2 else 0), exposure: 1.0, blend: 0.0, sky_fog: Bool.False }, commands: [Load({ pack: "reference", assets: ["reference"] }), sky_load] }

sky_load : Command
sky_load = Load({ pack: "sky", assets: ["sky/warm", "sky/cool"] })

loaded : Model, Str, Manifest -> Model
loaded = |model, pack, manifest| if (pack == "reference") { ..model, reference: Mesh.resolve(manifest, "reference") } else { ..model, warm: Mesh.resolve(manifest, "sky/warm"), cool: Mesh.resolve(manifest, "sky/cool") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, _dt| {
	sky = if (Key.pressed(input, N)) 2 else if (Key.pressed(input, S)) (if (model.sky == 0) 1 else 0) else model.sky
	exposure = if (Key.pressed(input, E)) (if (model.exposure == 1.0) 2.0 else 1.0) else model.exposure
	blend = if (Key.pressed(input, B)) next_blend(model.blend) else model.blend
	sky_fog = if (Key.pressed(input, F)) !model.sky_fog else model.sky_fog
	commands = if (Key.pressed(input, U)) [Unload("sky")] else if (Key.pressed(input, R)) [sky_load] else []
	{ model: { ..model, sky, exposure, blend, sky_fog }, commands }
}

# B steps the blend through 0, 0.5 and 1.
next_blend : F32 -> F32
next_blend = |blend| if (blend >= 1.0) 0.0 else blend + 0.5

# A rose fog that neither sky has, so the horizon shows it.
sky_fog : Vocabulary.Rgb
sky_fog = { r: 0.9, g: 0.45, b: 0.6 }

view : Model -> Vocabulary.Scene
view = |model| {
	sky = if (model.sky == 0) model.warm else if (model.sky == 1) model.cool else 0
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 0.7, z: 8.0 }, { x: 0.0, y: 0.7, z: 0.0 }), nodes: [Draw({ ..Draw.default, id: 1, mesh: model.reference })], environment: { ..Environment.default, sky, sky_blend: { to: model.cool, amount: model.blend }, exposure: model.exposure, tone_map: Neutral, fog: { ..Environment.default.fog, color: sky_fog, sky: if (model.sky_fog) 1.0 else 0.0 } } }
}

expect view(init(Config.empty).model).nodes.len() == 1

expect next_blend(0.0) == 0.5 and next_blend(0.5) == 1.0 and next_blend(1.0) == 0.0
