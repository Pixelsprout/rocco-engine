app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-11-04-2622062" }

# Pip walks on the spot. An orb with a Point Light rides above Pip's head,
# and a round lantern swings in Pip's right hand. Each is an Attach to a Joint of
# Pip's Skin, so it follows the Walk Clip in the same Frame.

import cam.Camera as Cam
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest, Rgb]
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Pose
import pf.QueryResults
import pf.Scene

# pip and walk are 0 until loaded gives their ids. time is the Walk time in
# seconds, wrapped into the Clip.
Model : { pip : U32, walk : U32, duration : F32, time : F32 }

pip_id : U64
pip_id = 1

ground_id : U64
ground_id = 2

orb_id : U64
orb_id = 3

lantern_id : U64
lantern_id = 4

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Attach" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { pip: 0, walk: 0, duration: 0.0, time: 0.0 }, commands: [Load({ pack: "pip", assets: ["pip"] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	walk = Mesh.clip(manifest, "pip", "Walk")
	{ ..model, pip: Mesh.resolve(manifest, "pip"), walk, duration: Mesh.clip_duration(manifest, walk) }
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	commands = if (Key.pressed(input, Escape)) [Quit] else []
	{ model: { ..model, time: Pose.loop(model.time + dt, model.duration) }, commands }
}

orb_glow : Rgb
orb_glow = { r: 0.6, g: 1.2, b: 2.4 }

orb : Vocabulary.Node
orb = Attach(
	{ draw: pip_id, joint: "head" },
	[
		Draw({ ..Draw.default, id: orb_id, mesh: Mesh.primitive(Sphere), pos: { x: 0.0, y: 0.5, z: 0.0 }, scale: { x: 0.12, y: 0.12, z: 0.12 }, tint: { r: 0.3, g: 0.6, b: 1.0 }, glow: orb_glow }),
		Light(Light.point({ x: 0.0, y: 0.5, z: 0.0 }, orb_glow, 3.0)),
	],
)

# scripts/bridge_check.py finds the lantern by its yellow.
lantern_glow : Rgb
lantern_glow = { r: 2.0, g: 1.8, b: 0.0 }

lantern : Vocabulary.Node
lantern = Attach(
	{ draw: pip_id, joint: "lower_arm.R" },
	[Draw({ ..Draw.default, id: lantern_id, mesh: Mesh.primitive(Sphere), pos: { x: 0.0, y: 0.14, z: 0.0 }, scale: { x: 0.08, y: 0.08, z: 0.08 }, tint: { r: 1.0, g: 0.9, b: 0.1 }, glow: lantern_glow })],
)

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, rot: Quat.from_yaw(0.6), pose: Pose.still(model.walk, model.time) }
	nodes = [
		Light(Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })),
		Light(Light.sun({ x: -0.5, y: -0.75, z: -0.45 }, { r: 3.0, g: 2.7, b: 2.3 })),
		Draw(ground),
		Draw(pip),
		orb,
		lantern,
	]
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 1.3, z: 2.6 }, { x: 0.0, y: 0.7, z: 0.0 }), nodes }
}
