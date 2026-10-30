app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# A dark Scene with a glowing window and two orbs. The window glows with no
# Light of its own. Each orb lights the floor around it.
# The guide pages copy the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest]
import pf.Draw
import pf.Glow
import pf.Launch
import pf.Light
import pf.Scene

Model : {}

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Glow" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: {}, commands: [] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

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
orb_left : List(Vocabulary.Node)
orb_left = Glow.orb({ id: 10, pos: { x: -1.6, y: 0.5, z: 0.4 }, radius: 0.25, color: { r: 1.0, g: 0.55, b: 0.05 }, strength: 3.0, range: 4.0 })

# endregion

orb_right : List(Vocabulary.Node)
orb_right = Glow.orb({ id: 11, pos: { x: 1.6, y: 0.5, z: 0.4 }, radius: 0.25, color: { r: 0.15, g: 0.35, b: 1.0 }, strength: 3.0, range: 4.0 })

view : Model -> Vocabulary.Scene
view = |_model| {
	camera = Cam.look_at({ x: 0.0, y: 2.4, z: 5.0 }, { x: 0.0, y: 0.8, z: 0.0 })
	nodes = List.join([[Light(night), Draw(floor), Draw(wall), Draw(window)], orb_left, orb_right])
	{ ..Scene.empty, camera, nodes }
}

is_light : Vocabulary.Node -> Bool
is_light = |node| match node {
	Light(_) => Bool.True
	_ => Bool.False
}

## Glow.orb draws the Sphere Primitive of the mesh package.
expect
	match Glow.orb({ id: 1, pos: { x: 0.0, y: 0.0, z: 0.0 }, radius: 1.0, color: { r: 1.0, g: 1.0, b: 1.0 }, strength: 1.0, range: 1.0 }).first() {
		Ok(Draw(d)) => d.mesh == Mesh.primitive(Sphere)
		_ => Bool.False
	}

## The window's tint stays from 0 to 1. Its glow carries the brightness.
expect {
	in_range = |c| c >= 0.0 and c <= 1.0
	in_range(window.tint.r) and in_range(window.tint.g) and in_range(window.tint.b) and window.glow.r > 1.0
}

## The Scene has the ambient and one Point Light for each orb, and no sun.
expect view({}).nodes.keep_if(is_light).len() == 3
