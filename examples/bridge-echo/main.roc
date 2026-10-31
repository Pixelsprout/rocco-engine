app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../packages/ui/main.roc" }

# A game for the Bridge check: it Listens on the port echo and Tells each
# message back on the same port. A left click on the button Tells click.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Manifest]
import pf.Draw
import pf.Input
import pf.Launch
import pf.Light
import pf.MouseButton
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
step = |model, input, results, _dt| {
	echoed = reply(model, results)
	{ ..echoed, commands: echoed.commands.concat(clicks(input, results)) }
}

clicks : Vocabulary.Input, Vocabulary.QueryResults -> List(Command)
clicks = |input, results| if MouseButton.released(input, Left) and List.contains(results.ui.over, button_id) {
	[Port.tell("click", button_id.to_str())]
} else {
	[]
}

# The Bridge check points at these ids, at the 960 by 540 window of
# Launch.default.
button_id : U64
button_id = 7

menu_id : U64
menu_id = 8

log_id : U64
log_id = 9

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

grey : Ui.Rgba
grey = { r: 0.3, g: 0.3, b: 0.3, a: 0.9 }

# x 824 to 944 and y 16 to 56. The menu under it is x 824 to 944 and y 60 to 90.
button : Vocabulary.Element
button = {
	menu = Panel({ ..Ui.default_panel, id: menu_id, width: Fixed(120.0), height: Fixed(30.0), background: grey, floating: Float({ to: Parent, attach: LeftTop, on: LeftBottom, offset: { x: 0.0, y: 4.0 } }) }, [])
	Panel({ ..Ui.float_at(RightTop, { x: -16.0, y: 16.0 }), id: button_id, width: Fixed(120.0), height: Fixed(40.0), background: grey }, [menu])
}

# x 16 to 216 and y 424 to 524. The offset hides the first of its 10 rows.
log : Vocabulary.Element
log = {
	rows = [log_row(1), log_row(2), log_row(3), log_row(4), log_row(5), log_row(6), log_row(7), log_row(8), log_row(9), log_row(10)]
	Panel({ ..Ui.float_at(LeftBottom, { x: 16.0, y: -16.0 }), id: log_id, width: Fixed(200.0), height: Fixed(100.0), direction: Col, background: grey, overflow: Scroll({ x: 0.0, y: -20.0 }) }, rows)
}

log_row : U64 -> Vocabulary.Element
log_row = |n| Panel({ ..Ui.default_panel, width: Fixed(200.0), height: Fixed(20.0) }, [Text({ ..Ui.label("Line ${n.to_str()}"), size: 14.0, wrap: None })])

view : Model -> Vocabulary.Scene
view = |model| {
	cube = { ..Draw.default, id: 1, mesh: Mesh.primitive(Cube), tint: { r: 0.9, g: 0.22, b: 0.03 } }
	camera = Cam.look_at({ x: 2.0, y: 2.0, z: 4.0 }, { x: 0.0, y: 0.0, z: 0.0 })
	hud = Panel(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text({ ..Ui.label(hud_text(model)), wrap: None })])
	{ ..Scene.empty, camera, nodes: [Light(sky_light), Light(sunlight), Draw(cube)], queries: [Port.listen("echo")], ui: [hud, button, log] }
}

expect reply({ heard: [] }, QueryResults.empty) == { model: { heard: [] }, commands: [] }
expect reply({ heard: [] }, { ..QueryResults.empty, ports: [{ port: "echo", msg: "a" }, { port: "x", msg: "b" }, { port: "echo", msg: "" }] }) == { model: { heard: ["a", ""] }, commands: [Port.tell("echo", "a"), Port.tell("echo", "")] }
expect hud_text({ heard: [] }) == "Listening on echo"
expect hud_text({ heard: ["a", "b"] }) == "b"
expect view({ heard: [] }).queries == [Port.listen("echo")]

released = { ..Input.empty, pointer: { ..Input.empty.pointer, released: [MouseButton.code(Left)] } }

over_button = { ..QueryResults.empty, ui: { over: [7], scroll: [] } }

expect clicks(released, over_button) == [Port.tell("click", "7")]
expect clicks(released, QueryResults.empty) == []
expect clicks(Input.empty, over_button) == []
