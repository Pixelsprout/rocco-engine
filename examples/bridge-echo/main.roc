app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

# A game for the Bridge check: it Listens on the port echo and Tells each
# message back on the same port.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Manifest]
import pf.Draw
import pf.Launch
import pf.Light
import pf.Port
import pf.QueryResults
import pf.Scene

Model : { heard : List(Str) }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Echo" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { heard: [] }, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, results, _dt| reply(model, results)

reply : Model, Vocabulary.QueryResults -> { model : Model, commands : List(Command) }
reply = |model, results| {
	msgs = Port.messages(results, "echo")
	{ model: { heard: model.heard.concat(msgs) }, commands: msgs.map(|msg| Port.tell("echo", msg)) }
}

sky_light : Vocabulary.Light
sky_light = Light.ambient({ r: 0.3, g: 0.3, b: 0.3 })

sunlight : Vocabulary.Light
sunlight = Light.directional({ x: -0.4, y: -0.8, z: -0.45 }, { r: 4.0, g: 4.0, b: 4.0 })

hud_text : Model -> Str
hud_text = |model| match List.last(model.heard) {
	Ok(msg) => msg
	Err(_) => "Listening on echo"
}

view : Model -> Vocabulary.Scene
view = |model| {
	cube = { ..Draw.default, id: 1, mesh: Mesh.primitive(Cube), tint: { r: 0.9, g: 0.22, b: 0.03 } }
	camera = Cam.look_at({ x: 2.0, y: 2.0, z: 4.0 }, { x: 0.0, y: 0.0, z: 0.0 })
	hud = Box(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text({ ..Ui.label(hud_text(model)), wrap: None })])
	{ ..Scene.empty, camera, nodes: [Light(sky_light), Light(sunlight), Draw(cube)], queries: [Port.listen("echo")], ui: [hud] }
}

expect reply({ heard: [] }, QueryResults.empty) == { model: { heard: [] }, commands: [] }
expect reply({ heard: [] }, { ..QueryResults.empty, ports: [{ port: "echo", msg: "a" }, { port: "x", msg: "b" }, { port: "echo", msg: "" }] }) == { model: { heard: ["a", ""] }, commands: [Port.tell("echo", "a"), Port.tell("echo", "")] }
expect hud_text({ heard: [] }) == "Listening on echo"
expect hud_text({ heard: ["a", "b"] }) == "b"
expect view({ heard: [] }).queries == [Port.listen("echo")]
