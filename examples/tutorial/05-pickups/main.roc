app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", linalg: "../../../packages/linalg/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "0.1.0-RC2" }

# guide/tutorial/05-pickups.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

# region: imports
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Contact, Manifest, Vec3]
import pf.Collider
import pf.Draw
import pf.Key
import pf.Launch
import pf.Light
import pf.Query
import pf.Scene
# endregion

# region: model
# id is the draw id of the pickup and of its Collider.
Pickup : { id : U64, pos : Vec3 }

# pip is 0, the fallback mesh, until loaded gives its id.
# yaw turns Pip about +y. At 0, Pip faces +z.
Model : { cube : U32, sphere : U32, pip : U32, pos : Vec3, yaw : F32, pickups : List(Pickup) }

# endregion

# region: ids
ground_id : U64
ground_id = 1

# Pip's id is lower than the id of every other Collider, so Pip is always `a`
# in a Contact.
pip_id : U64
pip_id = 2

# endregion

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Pip" } }

# region: init
start_pickups : List(Pickup)
start_pickups = [
	{ id: 10, pos: { x: -2.0, y: 0.45, z: -1.6 } },
	{ id: 11, pos: { x: 2.1, y: 0.45, z: -1.9 } },
	{ id: 12, pos: { x: 0.5, y: 0.45, z: -1.0 } },
	{ id: 13, pos: { x: -1.7, y: 0.45, z: 1.6 } },
	{ id: 14, pos: { x: 1.8, y: 0.45, z: 1.9 } },
]

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, pos: V.zero, yaw: 0.0, pickups: start_pickups }
	{ model, commands: [Load({ pack: "pip", assets: ["pip"] })] }
}

# endregion

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, pip: Mesh.resolve(manifest, "pip") }

# region: step
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| { model: collect(model, results.contacts) |> walk(input, dt), commands: [] }

# The ids of the Colliders that Pip touched in the previous step.
touched : List(Contact) -> List(U64)
touched = |contacts| List.keep_if(contacts, |c| c.a == pip_id).map(|c| c.b)

collect : Model, List(Contact) -> Model
collect = |model, contacts| {
	ids = touched(contacts)
	{ ..model, pickups: List.drop_if(model.pickups, |p| List.contains(ids, p.id)) }
}

# endregion

# Units each second.
speed : F32
speed = 2.5

# Pip stops this far from the centre, inside the edge of the ground.
edge : F32
edge = 2.7

# W moves away from the camera, toward -z.
walk : Model, Vocabulary.Input, F32 -> Model
walk = |model, input, dt| {
	dir = { x: Key.axis(input, A, D), y: 0.0, z: Key.axis(input, W, S) }
	if dir == V.zero {
		model
	} else {
		moved = V.add(model.pos, V.scale(V.normalize(dir), speed * dt))
		{ ..model, pos: { x: keep_on_ground(moved.x), y: 0.0, z: keep_on_ground(moved.z) }, yaw: F32.atan2({ x: dir.z, y: dir.x }) }
	}
}

keep_on_ground : F32 -> F32
keep_on_ground = |v| F32.max(-edge, F32.min(v, edge))

# A cool sky lights the sides that the sun misses.
sky_light : Vocabulary.Light
sky_light = Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })

# The sun shines from behind the camera and to the right, so Pip's shadow falls
# behind it and to the left.
sunlight : Vocabulary.Light
sunlight = Light.sun({ x: -0.5, y: -0.75, z: -0.45 }, { r: 4.5, g: 4.0, b: 3.4 })

# region: view
pip_half : Vec3
pip_half = { x: 0.3, y: 0.55, z: 0.3 }

pickup_radius : F32
pickup_radius = 0.25

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw) }
	pickups = model.pickups.map(|p| Draw(pickup(model.sphere, p)))
	camera = Cam.look_at({ x: 0.0, y: 3.6, z: 4.8 }, { x: 0.0, y: 0.0, z: 0.3 })
	# The box's centre is half its height up, so it stands on Pip's feet.
	pip_box = Collider.box(pip_id, { ..model.pos, y: pip_half.y }, Quat.from_yaw(model.yaw), pip_half)
	colliders = [Collider(pip_box)].concat(model.pickups.map(|p| Collider(Collider.sphere(p.id, p.pos, pickup_radius))))
	queries = [Query.contacts_of(pip_id)]
	nodes = [Light(sky_light), Light(sunlight), Draw(ground), Draw(pip)].concat(pickups).concat(colliders)
	{ ..Scene.empty, camera, nodes, queries }
}

# The sphere mesh is 1 unit wide.
pickup : U32, Pickup -> Vocabulary.Draw
pickup = |mesh, p| {
	size = 2.0 * pickup_radius
	{ ..Draw.default, id: p.id, mesh, pos: p.pos, scale: { x: size, y: size, z: size }, tint: { r: 1.0, g: 0.62, b: 0.08 } }
}

# endregion
