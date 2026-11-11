app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-11-04-2622062" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Config
import pf.Draw
import pf.Launch
import pf.Light
import pf.Scene
import pf.Vocabulary exposing [Command, Manifest]

Model : { cube : U32, sphere : U32, plane : U32, cylinder : U32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Primitives", width: 800, height: 600 } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), plane: Mesh.primitive(Plane), cylinder: Mesh.primitive(Cylinder) }
	{ model, commands: [] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: 1, mesh: model.plane, scale: { x: 8.0, y: 1.0, z: 6.0 }, tint: { r: 0.35, g: 0.38, b: 0.33 } }
	cube = { ..Draw.default, id: 2, mesh: model.cube, pos: { x: -2.4, y: 0.5, z: 0.0 }, tint: { r: 0.9, g: 0.22, b: 0.03 } }
	sphere = { ..Draw.default, id: 3, mesh: model.sphere, pos: { x: -0.8, y: 0.5, z: 0.0 }, tint: { r: 0.2, g: 0.5, b: 0.9 } }
	cylinder = { ..Draw.default, id: 4, mesh: model.cylinder, pos: { x: 0.8, y: 0.5, z: 0.0 }, tint: { r: 0.95, g: 0.75, b: 0.2 } }
	post = { ..Draw.default, id: 5, mesh: model.cylinder, pos: { x: 2.2, y: 1.5, z: 0.0 }, scale: { x: 0.25, y: 3.0, z: 0.25 }, tint: { r: 0.3, g: 0.8, b: 0.4 } }
	disc = { ..Draw.default, id: 6, mesh: model.cylinder, pos: { x: 0.0, y: 0.05, z: 1.6 }, scale: { x: 1.6, y: 0.1, z: 1.6 }, tint: { r: 0.8, g: 0.8, b: 0.85 } }
	{
		..Scene.empty,
		camera: Cam.look_at({ x: 3.0, y: 3.5, z: 6.5 }, { x: 0.0, y: 0.7, z: 0.0 }),
		nodes: [
			Light(Light.ambient({ r: 0.3, g: 0.3, b: 0.35 })),
			Light(Light.sun({ x: -0.4, y: -0.8, z: -0.45 }, { r: 4.0, g: 4.0, b: 4.0 })),
			Draw(ground),
			Draw(cube),
			Draw(sphere),
			Draw(cylinder),
			Draw(post),
			Draw(disc),
		],
	}
}

expect init(Config.empty).model.cylinder == 4
expect view(init(Config.empty).model).nodes.len() == 8
