app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "0.1.0-RC2" }

# The starting source of the first Tour step: an empty window. Chapter 1 adds the cube.

import pf.Vocabulary exposing [Command, Manifest]
import pf.Launch
import pf.Scene

Model : {}

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Pip" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: {}, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }

view : Model -> Vocabulary.Scene
view = |_model| Scene.empty
