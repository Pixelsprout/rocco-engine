app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# A dark Scene with a glowing window and two orbs. The window glows with no
# Light of its own. Each orb lights the floor around it. Between the orbs
# stands a salvage block with a matte ceramic body, a rusted metal lid and
# two neon tubes. source/make_salvage.py builds it.
# The guide pages copy the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest, Rgb, Vec3]
import pf.Config
import pf.Draw
import pf.Launch
import pf.Light
import pf.Scene

# salvage is 0, the fallback mesh, until loaded gives its id.
Model : { salvage : U32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Glow" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { salvage: 0 }, commands: [Load({ pack: "salvage", assets: ["salvage"] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, salvage: Mesh.resolve(manifest, "salvage") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, _input, _results, _dt| { model, commands: [] }

night : Vocabulary.Light
night = Light.ambient({ r: 0.02, g: 0.02, b: 0.03 })

floor : Vocabulary.Draw
floor = { ..Draw.default, id: 1, mesh: Mesh.primitive(Plane), scale: { x: 8.0, y: 1.0, z: 8.0 }, tint: { r: 0.6, g: 0.6, b: 0.6 } }

wall : Vocabulary.Draw
wall = { ..Draw.default, id: 2, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: 1.2, z: -1.5 }, scale: { x: 4.0, y: 2.4, z: 0.3 }, tint: { r: 0.40, g: 0.11, b: 0.05 } }

# Agent Town's Theme.window_dark tint and Theme.window_lit glow.
# region: window
window : Vocabulary.Draw
window = { ..Draw.default, id: 3, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: 1.4, z: -1.33 }, scale: { x: 1.4, y: 0.6, z: 0.06 }, tint: { r: 0.02, g: 0.018, b: 0.015 }, glow: { r: 3.2, g: 1.9, b: 0.6 } }

# endregion

# region: orb
orb : U64, Vec3, Rgb -> List(Vocabulary.Node)
orb = |id, pos, color| {
	lit = { r: color.r * 3.0, g: color.g * 3.0, b: color.b * 3.0 }
	sphere = { ..Draw.default, id, mesh: Mesh.primitive(Sphere), pos, scale: { x: 0.5, y: 0.5, z: 0.5 }, tint: color, glow: lit }
	[Draw(sphere), Light(Light.point(pos, lit, 4.0))]
}

# endregion

# The turn shows the front with the neon and the side with a rusted rib.
salvage : U32 -> Vocabulary.Draw
salvage = |mesh| { ..Draw.default, id: 4, mesh, pos: { x: 0.0, y: 0.0, z: -0.3 }, scale: { x: 1.3, y: 1.3, z: 1.3 }, rot: Quat.from_yaw(-0.5) }

# The orbs sit below the lid, so a lamp above shows the rust's highlight.
lamp : Vocabulary.Light
lamp = Light.point({ x: 0.4, y: 2.2, z: -1.0 }, { r: 2.0, g: 1.9, b: 1.7 }, 4.0)

view : Model -> Vocabulary.Scene
view = |model| {
	camera = Cam.look_at({ x: 0.0, y: 2.4, z: 5.0 }, { x: 0.0, y: 0.8, z: 0.0 })
	orb_left = orb(10, { x: -1.6, y: 0.5, z: 0.4 }, { r: 1.0, g: 0.55, b: 0.05 })
	orb_right = orb(11, { x: 1.6, y: 0.5, z: 0.4 }, { r: 0.15, g: 0.35, b: 1.0 })
	nodes = List.join([[Light(night), Draw(floor), Draw(wall), Draw(window), Draw(salvage(model.salvage)), Light(lamp)], orb_left, orb_right])
	{ ..Scene.empty, camera, nodes }
}

is_light : Vocabulary.Node -> Bool
is_light = |node| match node {
	Light(_) => Bool.True
	_ => Bool.False
}

## The window's tint stays from 0 to 1. Its glow carries the brightness.
expect {
	in_range = |c| c >= 0.0 and c <= 1.0
	in_range(window.tint.r) and in_range(window.tint.g) and in_range(window.tint.b) and window.glow.r > 1.0
}

## The Scene has the ambient, the lamp and one Point Light for each orb, and no sun.
expect view(init(Config.empty).model).nodes.keep_if(is_light).len() == 4

## init loads the salvage Pack.
expect init(Config.empty).commands == [Load({ pack: "salvage", assets: ["salvage"] })]

## loaded keeps the salvage mesh id from the Manifest.
expect {
	model = loaded(init(Config.empty).model, "salvage", [{ name: "salvage", id: 7, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }])
	model.salvage == 7
}
