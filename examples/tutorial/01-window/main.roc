app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# guide/tutorial/01-window.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

# region: imports
import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest]
import pf.Draw
import pf.Launch
import pf.Light
import pf.Scene
# endregion

# region: model
Model : { cube : U32 }

# endregion

# region: launch
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Pip" } }

# endregion

# region: init
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { cube: Mesh.primitive(Cube) }, commands: [] }

# endregion

# region: later
loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }

# endregion

# region: view
lights : List(Vocabulary.Node)
lights = [
	Light(Light.ambient({ r: 0.3, g: 0.3, b: 0.3 })),
	Light(Light.directional({ x: -0.4, y: -0.8, z: -0.45 }, { r: 4.0, g: 4.0, b: 4.0 })),
]

view : Model -> Vocabulary.Scene
view = |model| {
	cube = { ..Draw.default, id: 1, mesh: model.cube, tint: { r: 0.9, g: 0.22, b: 0.03 } }
	camera = Cam.look_at({ x: 2.0, y: 2.0, z: 4.0 }, { x: 0.0, y: 0.0, z: 0.0 })
	{ ..Scene.empty, camera, nodes: lights.concat([Draw(cube)]) }
}
# endregion
