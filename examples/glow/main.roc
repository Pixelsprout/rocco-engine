app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# A dark Scene with a glowing window and two orbs. The window glows with no
# Light of its own. Each orb lights the floor around it. Between the orbs
# stands a salvage block with a matte ceramic body, a rusted metal lid and
# two neon tubes. source/make_salvage.py builds it. Left of the window hangs a
# ribbed panel with a normal map and an occlusion map, and a small light
# circles in front of it. source/make_panel.py builds the panel. T cycles
# the tone map from Aces to AgX to Neutral.
# The guide pages copy the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest, Rgb, Vec3]
import pf.Config
import pf.Draw
import pf.Environment
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.QueryResults
import pf.Scene

# salvage and panel are 0, the fallback mesh, until loaded gives their ids.
# time is the seconds since init, which moves the circling light.
Model : { salvage : U32, panel : U32, time : F32, tone_map : ToneMap }

ToneMap : [Aces, AgX, Neutral]

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Glow" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: { salvage: 0, panel: 0, time: 0.0, tone_map: Aces }, commands: [Load({ pack: "props", assets: ["salvage", "panel"] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, salvage: Mesh.resolve(manifest, "salvage"), panel: Mesh.resolve(manifest, "panel") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	tone_map = if Key.pressed(input, T) next_tone_map(model.tone_map) else model.tone_map
	{ model: { ..model, time: model.time + dt, tone_map }, commands: [] }
}

next_tone_map : ToneMap -> ToneMap
next_tone_map = |tone_map| match tone_map {
	Aces => AgX
	AgX => Neutral
	Neutral => Aces
}

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

# The panel's back sits on the wall's front face, so its face is 0.02 in front.
panel_centre : Vec3
panel_centre = { x: -1.35, y: 1.5, z: -1.35 }

panel : U32 -> Vocabulary.Draw
panel = |mesh| { ..Draw.default, id: 5, mesh, pos: panel_centre }

spark_color : Rgb
spark_color = { r: 1.2, g: 1.0, b: 0.75 }

# The spark circles 0.4 in front of the panel's face, once every 4 seconds.
# It starts on the right of the panel and is on the left at 2 seconds.
spark_pos : F32 -> Vec3
spark_pos = |time| {
	angle = time * 2.0 * pi / 4.0
	{ x: panel_centre.x + 0.5 * angle.cos(), y: panel_centre.y + 0.5 * angle.sin(), z: panel_centre.z + 0.02 + 0.4 }
}

spark : F32 -> List(Vocabulary.Node)
spark = |time| {
	pos = spark_pos(time)
	lit = { r: spark_color.r * 3.0, g: spark_color.g * 3.0, b: spark_color.b * 3.0 }
	ball = { ..Draw.default, id: 6, mesh: Mesh.primitive(Sphere), pos, scale: { x: 0.08, y: 0.08, z: 0.08 }, tint: { r: 1.0, g: 0.9, b: 0.7 }, glow: lit }
	[Draw(ball), Light(Light.point(pos, spark_color, 2.0))]
}

pi : F32
pi = 3.14159265

# The orbs sit below the lid, so a lamp above shows the rust's highlight.
lamp : Vocabulary.Light
lamp = Light.point({ x: 0.4, y: 2.2, z: -1.0 }, { r: 2.0, g: 1.9, b: 1.7 }, 4.0)

view : Model -> Vocabulary.Scene
view = |model| {
	camera = Cam.look_at({ x: 0.0, y: 2.4, z: 5.0 }, { x: 0.0, y: 0.8, z: 0.0 })
	orb_left = orb(10, { x: -1.6, y: 0.5, z: 0.4 }, { r: 1.0, g: 0.55, b: 0.05 })
	orb_right = orb(11, { x: 1.6, y: 0.5, z: 0.4 }, { r: 0.15, g: 0.35, b: 1.0 })
	nodes = List.join([[Light(night), Draw(floor), Draw(wall), Draw(window), Draw(salvage(model.salvage)), Draw(panel(model.panel)), Light(lamp)], orb_left, orb_right, spark(model.time)])
	{ ..Scene.empty, camera, nodes, environment: { ..Environment.default, tone_map: model.tone_map } }
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

## The Scene has the ambient, the lamp, one Point Light for each orb and the spark's, and no sun.
expect view(init(Config.empty).model).nodes.keep_if(is_light).len() == 5

## init loads the props Pack.
expect init(Config.empty).commands == [Load({ pack: "props", assets: ["salvage", "panel"] })]

## loaded keeps the salvage and panel mesh ids from the Manifest.
expect {
	entry = |name, id| { name, id, duration: 0.0, size: { w: 0, h: 0 }, clips: [] }
	model = loaded(init(Config.empty).model, "props", [entry("salvage", 7), entry("panel", 8)])
	model.salvage == 7 and model.panel == 8
}

## step adds up the time.
expect {
	stepped = step(init(Config.empty).model, Input.empty, QueryResults.empty, 0.25)
	stepped.model.time == 0.25
}

## Each press of T moves the tone map on, and the third returns to Aces.
expect {
	press = |model| step(model, { ..Input.empty, pressed: [Key.code(T)] }, QueryResults.empty, 0.0).model
	first = press(init(Config.empty).model)
	second = press(first)
	third = press(second)
	first.tone_map == AgX and second.tone_map == Neutral and third.tone_map == Aces
}

## The Scene draws with the tone map of the Model.
expect view({ ..init(Config.empty).model, tone_map: Neutral }).environment.tone_map == Neutral

## The spark is right of the panel at 0 seconds, above it at 1 and left of it at 2.
expect {
	near = |a, b| (a - b).abs() < 0.0001
	right = spark_pos(0.0)
	top = spark_pos(1.0)
	left = spark_pos(2.0)
	near(right.x, -0.85) and near(top.y, 2.0) and near(left.x, -1.85) and near(left.y, 1.5) and near(left.z, -0.93)
}
