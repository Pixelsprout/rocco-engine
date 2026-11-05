app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9" }

# Cutout parts under a Sun. Two chain-link fences stand in front of a red and
# a blue cube: the left fence is double-sided and the right one is not, so
# from behind only the left one shows. A leaf turns above Pip, so both of its
# faces come round to the camera, lit from the side the camera sees. Pip
# walks a circle with a round hole in every cell of a grid, double-sided, so
# the inside of its shell shows through. The blue cube stays visible but does
# not cast a shadow. Every cutout casts the shadow of its whole shape.
# source/make_props.py builds the meshes.
#
# The camera circles the Scene. Space stops and starts the motion, and Left
# and Right turn the camera by hand.

import cam.Camera as Cam
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest, Vec3]
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Pose
import pf.QueryResults
import pf.Scene

# The mesh ids are 0, the fallback mesh, until loaded gives them. time moves
# the leaf and Pip, and angle is the camera's turn about the centre.
Model : { meshes : Meshes, walk : U32, walk_duration : F32, time : F32, angle : F32, paused : Bool }

Meshes : { fence : U32, fence_one_sided : U32, leaf : U32, pip : U32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Mask" } }

props : List(Str)
props = ["fence", "fence_one_sided", "leaf", "pip_holes"]

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { meshes: { fence: 0, fence_one_sided: 0, leaf: 0, pip: 0 }, walk: 0, walk_duration: 0.0, time: 0.0, angle: 0.0, paused: Bool.False }
	{ model, commands: [Load({ pack: "props", assets: props })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	meshes = { fence: Mesh.resolve(manifest, "fence"), fence_one_sided: Mesh.resolve(manifest, "fence_one_sided"), leaf: Mesh.resolve(manifest, "leaf"), pip: Mesh.resolve(manifest, "pip_holes") }
	walk = Mesh.clip(manifest, "pip_holes", "Walk")
	{ ..model, meshes, walk, walk_duration: Mesh.clip_duration(manifest, walk) }
}

# Radians each second.
orbit_speed : F32
orbit_speed = 0.25

turn_speed : F32
turn_speed = 1.2

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	paused = if Key.pressed(input, Space) !model.paused else model.paused
	moving = if paused 0.0 else dt
	turn = Key.axis(input, Left, Right) * turn_speed * dt
	{ model: { ..model, paused, time: model.time + moving, angle: model.angle + orbit_speed * moving + turn }, commands: [] }
}

sky_light : Vocabulary.Light
sky_light = Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })

# From in front and to the right, so the fence shadows fall behind them.
sunlight : Vocabulary.Light
sunlight = Light.sun({ x: -0.4, y: -0.8, z: -0.45 }, { r: 4.5, g: 4.0, b: 3.4 })

ground : Vocabulary.Draw
ground = { ..Draw.default, id: 1, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 8.0, y: 0.2, z: 8.0 }, tint: { r: 0.3, g: 0.3, b: 0.28 } }

fence_x : F32
fence_x = 1.4

fence_half_width : F32
fence_half_width = 1.2

fence : U64, U32, F32 -> Vocabulary.Draw
fence = |id, mesh, x| { ..Draw.default, id, mesh, pos: { x, y: 0.0, z: 0.0 } }

post : U64, F32 -> Vocabulary.Draw
post = |id, x| { ..Draw.default, id, mesh: Mesh.primitive(Cube), pos: { x, y: 0.75, z: 0.0 }, scale: { x: 0.08, y: 1.5, z: 0.08 }, tint: { r: 0.25, g: 0.25, b: 0.27 } }

# An opaque cube behind each fence, so the holes show what is behind them.
block : U64, F32, Vocabulary.Rgb, Bool -> Vocabulary.Draw
block = |id, x, tint, casts_shadow| { ..Draw.default, id, mesh: Mesh.primitive(Cube), pos: { x, y: 0.35, z: -1.2 }, scale: { x: 0.7, y: 0.7, z: 0.7 }, tint, casts_shadow }

# Radians each second.
leaf_spin : F32
leaf_spin = 0.9

leaf : U32, F32 -> Vocabulary.Draw
leaf = |mesh, time| { ..Draw.default, id: 20, mesh, pos: { x: 0.0, y: 1.6, z: 1.6 }, rot: Quat.from_yaw(time * leaf_spin) }

walk_centre : Vec3
walk_centre = { x: 0.0, y: 0.0, z: 1.6 }

walk_radius : F32
walk_radius = 0.9

# Radians each second around the circle.
walk_turn : F32
walk_turn = 0.8

# The ground speed that the Walk clip's feet match.
clip_speed : F32
clip_speed = 2.5

pip : Model -> Vocabulary.Draw
pip = |model| {
	a = model.time * walk_turn
	pos = { x: walk_centre.x + walk_radius * a.sin(), y: 0.0, z: walk_centre.z + walk_radius * a.cos() }
	yaw = F32.atan2({ x: -a.sin(), y: a.cos() })
	clip_time = Pose.loop(model.time * walk_radius * walk_turn / clip_speed, model.walk_duration)
	pose = { clip: model.walk, time: clip_time, fade_clip: 0, fade_time: 0.0, fade: 0.0 }
	{ ..Draw.default, id: 21, mesh: model.meshes.pip, pos, rot: Quat.from_yaw(yaw), pose }
}

orbit_centre : Vec3
orbit_centre = { x: 0.0, y: 0.7, z: 0.4 }

orbit_radius : F32
orbit_radius = 5.0

view : Model -> Vocabulary.Scene
view = |model| {
	a = model.angle
	eye = { x: orbit_centre.x + orbit_radius * a.sin(), y: 2.4, z: orbit_centre.z + orbit_radius * a.cos() }
	camera = Cam.look_at(eye, orbit_centre)
	m = model.meshes
	nodes = [
		Light(sky_light),
		Light(sunlight),
		Draw(ground),
		Draw(block(10, -fence_x, { r: 0.8, g: 0.12, b: 0.08 }, Bool.True)),
		Draw(block(11, fence_x, { r: 0.08, g: 0.2, b: 0.8 }, Bool.False)),
		Draw(fence(2, m.fence, -fence_x)),
		Draw(fence(3, m.fence_one_sided, fence_x)),
		Draw(post(4, -fence_x - fence_half_width)),
		Draw(post(5, -fence_x + fence_half_width)),
		Draw(post(6, fence_x - fence_half_width)),
		Draw(post(7, fence_x + fence_half_width)),
		Draw(leaf(m.leaf, model.time)),
		Draw(pip(model)),
	]
	{ ..Scene.empty, camera, nodes }
}

start : Model
start = init(Config.empty).model

press : Model, Key.Key -> Model
press = |model, key| step(model, { ..Input.empty, pressed: [Key.code(key)] }, QueryResults.empty, 0.5).model

## init loads the props Pack.
expect init(Config.empty).commands == [Load({ pack: "props", assets: props })]

## Space stops the motion, and a second press starts it again.
expect {
	stopped = press(start, Space)
	again = press(stopped, Space)
	stopped.paused and stopped.time == 0.0 and stopped.angle == 0.0 and !again.paused and again.time == 0.5
}

## Right turns the camera while the motion is stopped.
expect {
	stopped = { ..start, paused: Bool.True }
	turned = step(stopped, { ..Input.empty, held: [Key.code(Right)] }, QueryResults.empty, 0.5).model
	turned.angle > 0.0 and turned.time == 0.0
}

## Pip starts on the far side of its circle from the fences and walks toward +x.
expect {
	p = pip(start)
	p.pos.z > walk_centre.z and p.pos.x == 0.0
}
