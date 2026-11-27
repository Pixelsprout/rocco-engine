app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "0.1.0-RC2" }

import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Config
import pf.Draw
import pf.Emitter
import pf.Environment
import pf.Image
import pf.Key
import pf.Launch
import pf.Scene
import pf.Vocabulary exposing [Command, Manifest]

Model : { enabled : Bool, image : U32, orientation_image : U32, orientation : Bool, paused : Bool, seed : U64, time : F32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Particles: B sparks, R remove/restore, U unload image, L load image, O sprite orientation, P pause", high_dpi: Bool.False } }

load_image : Command
load_image = Load({ pack: "dust", assets: ["image/dust", "image/orientation"] })

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| { model: { enabled: Bool.True, image: 0, orientation_image: 0, orientation: Bool.False, paused: Bool.False, seed: config.seed, time: 0 }, commands: [load_image, Emitter.burst(3, 180)] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, image: Image.resolve(manifest, "image/dust"), orientation_image: Image.resolve(manifest, "image/orientation") }

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	enabled = if (Key.pressed(input, R)) !model.enabled else model.enabled
	orientation = if (Key.pressed(input, O)) !model.orientation else model.orientation
	paused = if (Key.pressed(input, P)) !model.paused else model.paused
	commands = List.join([if (Key.pressed(input, B)) [Emitter.burst(3, 180)] else [], if (Key.pressed(input, U)) [Unload("dust")] else [], if (Key.pressed(input, L)) [load_image] else [], if (Key.pressed(input, O)) [Emitter.burst(4, 1)] else []])
	time = if (paused) model.time else model.time + dt
	{ model: { ..model, enabled, orientation, paused, time }, commands }
}

orientation_scene : Model -> Vocabulary.Scene
orientation_scene = |model| {
	source = { ..Emitter.default, id: 4, image: model.orientation_image, lifetime: 100, start_size: 3, end_size: 3, start_colour: { r: 1, g: 1, b: 1, a: 1 }, end_colour: { r: 1, g: 1, b: 1, a: 1 }, velocity: { x: 0, y: 0, z: 0 }, velocity_spread: { x: 0, y: 0, z: 0 } }
	{ ..Scene.empty, camera: Cam.look_at({ x: 0, y: 0, z: 5 }, { x: 0, y: 0, z: 0 }), nodes: [Emitter(source)] }
}

view : Model -> Vocabulary.Scene
view = |model| if (model.orientation) orientation_scene(model) else {
	# A time scale of 0 holds every particle where it is and emits none.
	time_scale = if (model.paused) 0 else 1
	smoke = { ..Emitter.default, id: 1, time_scale, seed: model.seed, pos: { x: -2.0, y: 1.0, z: 0.0 }, rate: 35, lifetime: 3.5, start_size: 0.3, end_size: 1.8, start_colour: { r: 0.5, g: 0.55, b: 0.6, a: 0.35 }, end_colour: { r: 0.3, g: 0.35, b: 0.4, a: 0.0 }, velocity: { x: 0.12, y: 0.9, z: 0.0 }, velocity_spread: { x: 0.25, y: 0.2, z: 0.25 }, drag: 0.1 }
	dust = { ..Emitter.default, id: 2, time_scale, seed: model.seed + 7, image: model.image, pos: { x: 2.0, y: 0.4, z: 0.0 }, rate: 24, lifetime: 3.0, start_size: 0.4, end_size: 2.2, start_colour: { r: 0.8, g: 0.5, b: 0.24, a: 0.4 }, end_colour: { r: 0.6, g: 0.4, b: 0.2, a: 0.0 }, velocity: { x: 0.3, y: 0.25, z: 0.0 }, velocity_spread: { x: 0.4, y: 0.15, z: 0.4 }, drag: 0.15 }
	sparks = { ..Emitter.default, id: 3, time_scale, seed: model.seed + 13, pos: { x: 0.0, y: 1.0, z: 0.0 }, lifetime: 1.4, start_size: 0.1, end_size: 0.02, start_colour: { r: 12.0, g: 3.0, b: 0.2, a: 1.0 }, end_colour: { r: 2.0, g: 0.1, b: 0.0, a: 0.0 }, velocity: { x: 0.0, y: 1.8, z: 0.0 }, velocity_spread: { x: 3.0, y: 2.5, z: 2.0 }, drag: 0.8, blend: Add }
	# A dust devil: particles start on a small disc, rise, turn about the source's upright line and drift out from it.
	devil = { ..Emitter.default, id: 5, time_scale, seed: model.seed + 19, image: model.image, pos: { x: 0.0, y: 0.05, z: -3.0 }, rate: 60, lifetime: 3.0, start_size: 0.15, end_size: 0.7, start_colour: { r: 0.75, g: 0.55, b: 0.35, a: 0.35 }, end_colour: { r: 0.6, g: 0.45, b: 0.3, a: 0.0 }, velocity: { x: 0.0, y: 0.2, z: 0.0 }, velocity_spread: { x: 0.05, y: 0.1, z: 0.05 }, drag: 0.2, acceleration: { x: 0.0, y: 0.6, z: 0.0 }, spawn_radius: 0.25, swirl: 5.0, outward: 0.12 }
	cart = cart_node({ time: model.time, time_scale, seed: model.seed + 29 })
	ground = Draw({ ..Draw.default, id: 1, mesh: Mesh.primitive(Plane), scale: { x: 16.0, y: 1.0, z: 12.0 }, tint: { r: 0.15, g: 0.17, b: 0.2 } })
	chimney = Draw({ ..Draw.default, id: 2, mesh: Mesh.primitive(Cube), pos: { x: -2.0, y: 0.5, z: 0.0 }, scale: { x: 0.6, y: 1.0, z: 0.6 }, tint: { r: 0.25, g: 0.2, b: 0.18 } })
	{ ..Scene.empty, camera: Cam.look_at({ x: 7.0, y: 4.0, z: 10.0 }, { x: 0.0, y: 1.8, z: 0.0 }), nodes: List.join([[ground, chimney, Light(Ambient({ r: 0.5, g: 0.5, b: 0.5 }))], if (model.enabled) [Emitter(smoke), Emitter(dust), Emitter(sparks), Emitter(devil), cart] else []]), environment: { ..Environment.default, clear: { r: 0.015, g: 0.025, b: 0.045 }, bloom: { strength: 0.15, threshold: 1, knee: 0.5 } } }
}

# A cart that drives in a circle. Its exhaust points out of the back of the
# cart, so the Group turns it, and the smoke trails behind in the world.
cart_node : { time : F32, time_scale : F32, seed : U64 } -> Vocabulary.Node
cart_node = |{ time, time_scale, seed }| {
	angle = 0.8 * time
	# The cart's +x points along its path round the circle.
	heading = -(angle + quarter_turn)
	pos = { x: 2.5 * angle.cos(), y: 0.25, z: 1.0 + 2.5 * angle.sin() }
	rot = { x: 0.0, y: (heading / 2).sin(), z: 0.0, w: (heading / 2).cos() }
	body = Draw({ ..Draw.default, id: 3, mesh: Mesh.primitive(Cube), scale: { x: 0.7, y: 0.4, z: 0.4 }, tint: { r: 0.7, g: 0.3, b: 0.15 } })
	exhaust = { ..Emitter.default, id: 6, time_scale, seed, pos: { x: -0.4, y: 0.1, z: 0.0 }, rate: 40, lifetime: 2.5, start_size: 0.12, end_size: 0.6, start_colour: { r: 0.45, g: 0.45, b: 0.5, a: 0.4 }, end_colour: { r: 0.3, g: 0.3, b: 0.35, a: 0.0 }, velocity: { x: -0.8, y: 0.3, z: 0.0 }, velocity_spread: { x: 0.1, y: 0.1, z: 0.1 }, drag: 0.4 }
	Group({ id: 10, pos, rot, selected: Bool.False }, [body, Emitter(exhaust)])
}

quarter_turn : F32
quarter_turn = 1.5707963

emitters_of : List(Vocabulary.Node) -> List(Vocabulary.Emitter)
emitters_of = |nodes| nodes.join_map(
	|node| match node {
		Emitter(e) => [e]
		Group(_, children) => emitters_of(children)
		Attach(_, children) => emitters_of(children)
		_ => []
	},
)

## The view holds smoke, dust, sparks, the dust devil and the cart exhaust.
expect emitters_of(view(init(Config.empty).model).nodes).len() == 5

## A pause sets every Emitter's time scale to 0, the cart's included.
expect {
	paused = { ..init(Config.empty).model, paused: Bool.True }
	emitters_of(view(paused).nodes).all(|e| e.time_scale == 0)
}

## Removing the Emitters also removes the cart, so none stays in the tree.
expect {
	model = init(Config.empty).model
	removed = { ..model, enabled: Bool.False }
	emitters_of(view(removed).nodes).is_empty()
}
