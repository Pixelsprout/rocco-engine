app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# guide/tutorial/02-character.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest]
import pf.Config
import pf.Draw
import pf.Launch
import pf.Light
import pf.Scene

# region: model
# pip is 0, the fallback mesh, until loaded gives its id.
Model : { ground : U32, pip : U32 }

# endregion

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Pip" } }

# region: load
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { ground: Mesh.primitive(Cube), pip: 0 }
	{ model, commands: [Load({ pack: "pip", assets: ["pip"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, pip: Mesh.resolve(manifest, "pip") }

# endregion

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }

lights : List(Vocabulary.Node)
lights = [
	Light(Light.ambient({ r: 0.3, g: 0.3, b: 0.3 })),
	Light(Light.directional({ x: -0.4, y: -0.8, z: -0.45 }, { r: 4.0, g: 4.0, b: 4.0 })),
]

# region: view
view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: 1, mesh: model.ground, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: 2, mesh: model.pip }
	camera = Cam.look_at({ x: 0.0, y: 1.4, z: 2.6 }, { x: 0.0, y: 0.5, z: 0.0 })
	{ ..Scene.empty, camera, nodes: lights.concat([Draw(ground), Draw(pip)]) }
}

# endregion

# region: tests
expect init(Config.empty).commands == [Load({ pack: "pip", assets: ["pip"] })]

expect {
	model = loaded(init(Config.empty).model, "pip", [{ name: "pip", id: 4 }])
	model.pip == 4
}

# endregion
