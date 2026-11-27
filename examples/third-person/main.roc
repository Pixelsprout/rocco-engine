app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", collide: "../../packages/collide/main.roc", controller: "../../packages/controller/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "0.1.0-RC2", ui: "../../packages/ui/main.roc" }

# guide/third-person.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

import cam.Camera as Cam
import collide.Ground
import collide.Solids
import controller.Controller
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Element, Manifest, Vec3]
import pf.Draw
import pf.GamepadButton
import pf.Key
import pf.Launch
import pf.Light
import pf.Scene

Model : { player : Controller.Controller, orbit : Cam.Orbit, cube : U32, sphere : U32, cylinder : U32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Third person" } }

spawn : Vec3
spawn = { x: 0.0, y: 0.0, z: -4.0 }

# The character falls this far into the gap before it starts again.
fall_limit : F32
fall_limit = -8.0

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { player: start_over.player, orbit: start_over.orbit, cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), cylinder: Mesh.primitive(Cylinder) }
	{ model, commands: [] }
}

start_over : { player : Controller.Controller, orbit : Cam.Orbit }
start_over = {
	player: Controller.new(Controller.default_tuning, spawn),
	orbit: Cam.orbit(Cam.default_orbit_tuning, { pos: spawn, heading: 0.0 }),
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, _manifest| model

# region: intent
# WASD and the left stick move along the view. Space and South jump and glide.
intent : Vocabulary.Input, F32 -> Controller.Intent
intent = |input, yaw| {
	keys = { x: Key.axis(input, A, D), y: Key.axis(input, S, W) }
	stick = input.gamepads.fold(keys, |sum, pad| { x: sum.x + pad.left_stick.x, y: sum.y + pad.left_stick.y })
	{
		move: Cam.to_world(clamp_to_disc(stick), yaw),
		jump_pressed: Key.pressed(input, Space) or GamepadButton.pressed_any(input, South),
		jump_held: Key.held(input, Space) or GamepadButton.held_any(input, South),
	}
}

# endregion

clamp_to_disc : Cam.Stick -> Cam.Stick
clamp_to_disc = |stick| {
	length = (stick.x * stick.x + stick.y * stick.y).sqrt()
	if (length > 1.0) { x: stick.x / length, y: stick.y / length } else stick
}

# The arrow keys and the right stick turn the camera.
look : Vocabulary.Input -> Cam.Stick
look = |input| {
	keys = { x: Key.axis(input, Left, Right), y: Key.axis(input, Up, Down) }
	clamp_to_disc(input.gamepads.fold(keys, |sum, pad| { x: sum.x + pad.right_stick.x, y: sum.y + pad.right_stick.y }))
}

# region: step
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	# The Intent turns the stick by the camera yaw of the frame the player saw.
	player = Controller.step(model.player, intent(input, model.orbit.yaw), ground, solids, dt)
	orbit = Cam.orbit_step(model.orbit, { character: character(player), look: look(input), dt })
	next = if (player.pos.y < fall_limit) { ..model, player: start_over.player, orbit: start_over.orbit } else { ..model, player, orbit }
	{ model: next, commands: if (Key.pressed(input, Escape)) [Quit] else [] }
}

# The camera reads a glide as Air, so it trails a glide the way it trails a jump.
character : Controller.Controller -> Cam.Character
character = |player| {
	pos: player.pos,
	heading: player.heading,
	speed: (player.vel.x * player.vel.x + player.vel.z * player.vel.z).sqrt(),
	footing: if (player.motion == Ground) Ground else Air,
}

# endregion

# region: level
# A flat field with a slope up to a plateau on +x, then a gap and a far field.
terrain : Ground.Ground
terrain = Ground.highest(
	Ground.heights({ origin: { x: -12.0, z: -8.0 }, cell: 4.0, columns: 9, rows: 5, heights: List.join(List.repeat(field_row, 5)) }),
	Ground.heights({ origin: { x: -12.0, z: far_z }, cell: 4.0, columns: 9, rows: 4, heights: List.repeat(0.0, 36) }),
)

# One row of heights along +x: level to x 8, up the slope to 2 at x 12, then the plateau.
field_row : List(F32)
field_row = [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 2.0]

solid_list : List(Solids.Solid)
solid_list = [
	step_box,
	Box({ center: { x: -8.0, y: 1.0, z: -4.0 }, half_extents: { x: 1.5, y: 1.0, z: 1.5 }, yaw: 0.0 }),
	Box({ center: { x: 4.0, y: 0.6, z: -4.0 }, half_extents: { x: 1.5, y: 0.6, z: 1.0 }, yaw: 0.7 }),
	thin_platform,
	Sphere({ center: { x: -5.0, y: 0.0, z: 5.0 }, radius: 1.2 }),
	cliff(8.0 - cliff_depth),
	cliff(far_z),
]

solids : Solids
solids = Solids.build(solid_list, 4.0)

# The character stands on the terrain and on the tops of the Solids.
ground : Ground.Ground
ground = Ground.highest(terrain, Ground.tops(solids))

# endregion

# Lower than step_up, so the character walks onto it.
step_box : Solids.Solid
step_box = Box({ center: { x: -4.0, y: 0.15, z: -1.0 }, half_extents: { x: 1.5, y: 0.15, z: 1.5 }, yaw: 0.0 })

# A jump reaches its top. The gap starts at its far edge.
thin_platform : Solids.Solid
thin_platform = Box({ center: { x: 0.0, y: 1.25, z: 5.5 }, half_extents: { x: 1.5, y: 0.05, z: 1.5 }, yaw: 0.0 })

# The near edge of the far field. A running jump from z 8 lands about 5.7 m on,
# so only a glide crosses the gap.
far_z : F32
far_z = 15.0

# A Ground from `heights` is solid all the way down, so a character that falls
# into the gap and drifts under a field would rise onto it. A wall under each
# edge of the gap pushes it back.
cliff : F32 -> Solids.Solid
cliff = |z| Box({ center: { x: 4.0, y: -5.0, z: z + cliff_depth / 2.0 }, half_extents: { x: 16.0, y: 4.99, z: cliff_depth / 2.0 }, yaw: 0.0 })

cliff_depth : F32
cliff_depth = 0.5

sky_light : Vocabulary.Light
sky_light = Light.ambient({ r: 0.25, g: 0.28, b: 0.35 })

sunlight : Vocabulary.Light
sunlight = Light.sun({ x: -0.4, y: -0.8, z: 0.45 }, { r: 3.6, g: 3.3, b: 2.9 })

grass : Vocabulary.Rgb
grass = { r: 0.16, g: 0.3, b: 0.12 }

stone : Vocabulary.Rgb
stone = { r: 0.45, g: 0.42, b: 0.38 }

slab : U32, { min : Vec3, max : Vec3, tint : Vocabulary.Rgb } -> Vocabulary.Draw
slab = |cube, { min, max, tint }| { ..Draw.default, mesh: cube, pos: V.scale(V.add(min, max), 0.5), scale: V.sub(max, min), tint }

# The slope rises 2 over 4 along +x. Its slab is turned about +z and dropped by
# half its thickness along its normal, so its top meets both fields.
slope : U32 -> Vocabulary.Draw
slope = |cube| {
	angle = F32.atan2({ x: 4.0, y: 2.0 })
	thickness : F32
	thickness = 0.2
	length : F32
	length = F32.sqrt(20.0)
	{
		..Draw.default,
		mesh: cube,
		pos: { x: 10.0 + angle.sin() * thickness / 2.0, y: 1.0 - angle.cos() * thickness / 2.0, z: 0.0 },
		rot: Quat.from_axis_angle({ x: 0.0, y: 0.0, z: 1.0 }, angle),
		scale: { x: length, y: thickness, z: 16.0 },
		tint: grass,
	}
}

solid_draw : Model, Solids.Solid -> Vocabulary.Draw
solid_draw = |model, solid| match solid {
	Box({ center, half_extents, yaw }) => { ..Draw.default, mesh: model.cube, pos: center, rot: Quat.from_yaw(yaw), scale: V.scale(half_extents, 2.0), tint: stone }
	Sphere({ center, radius }) => { ..Draw.default, mesh: model.sphere, pos: center, scale: V.scale(V.one, 2.0 * radius), tint: stone }
}

body_tint : Controller.Motion -> Vocabulary.Rgb
body_tint = |motion| match motion {
	Ground => { r: 0.9, g: 0.55, b: 0.15 }
	Air => { r: 0.95, g: 0.8, b: 0.2 }
	Glide => { r: 0.3, g: 0.75, b: 0.95 }
}

# Above the ids of the level Draws.
body_id : U64
body_id = 100

# A cylinder the size of the capsule, and a nose that shows the heading.
player_draws : Model -> List(Vocabulary.Node)
player_draws = |model| {
	player = model.player
	tuning = player.tuning
	body = {
		..Draw.default,
		id: body_id,
		mesh: model.cylinder,
		pos: { ..player.pos, y: player.pos.y + tuning.height / 2.0 },
		scale: { x: 2.0 * tuning.radius, y: tuning.height, z: 2.0 * tuning.radius },
		tint: body_tint(player.motion),
	}
	nose = {
		..Draw.default,
		id: body_id + 1,
		mesh: model.cube,
		pos: { x: player.pos.x + player.heading.sin() * tuning.radius, y: player.pos.y + 1.1, z: player.pos.z + player.heading.cos() * tuning.radius },
		rot: Quat.from_yaw(player.heading),
		scale: { x: 0.2, y: 0.2, z: 0.3 },
		tint: { r: 0.15, g: 0.1, b: 0.1 },
	}
	[Draw(body), Draw(nose)]
}

view : Model -> Vocabulary.Scene
view = |model| {
	field = slab(model.cube, { min: { x: -12.0, y: -0.2, z: -8.0 }, max: { x: 8.0, y: 0.0, z: 8.0 }, tint: grass })
	plateau = slab(model.cube, { min: { x: 12.0, y: -1.0, z: -8.0 }, max: { x: 20.0, y: 2.0, z: 8.0 }, tint: grass })
	far = slab(model.cube, { min: { x: -12.0, y: -0.2, z: far_z }, max: { x: 20.0, y: 0.0, z: far_z + 12.0 }, tint: grass })
	level = List.join([[field, slope(model.cube), plateau, far], solid_list.map(|solid| solid_draw(model, solid))])
	# Each Draw needs its own id, so the host can pair it with the previous frame.
	numbered = level.map_with_index(|draw, index| Draw({ ..draw, id: index + 1 }))
	nodes = List.join([[Light(sky_light), Light(sunlight)], numbered, player_draws(model)])
	camera = Cam.orbit_view(model.orbit, model.player.pos)
	{ ..Scene.empty, camera, nodes, ui: hud(model) }
}

motion_text : Controller.Motion -> Str
motion_text = |motion| match motion {
	Ground => "Ground"
	Air => "Air"
	Glide => "Glide"
}

hud : Model -> List(Element)
hud = |model| {
	lines = ["Motion: ${motion_text(model.player.motion)}", "WASD move, Space jump, hold Space to glide, arrows turn the camera"]
	[Panel({ ..Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), direction: Col, gap: 4.0 }, lines.map(|line| Text({ ..Ui.label(line), wrap: None })))]
}
