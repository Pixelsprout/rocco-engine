app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", linalg: "../../../packages/linalg/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../../packages/ui/main.roc" }

# guide/tutorial/09-gamepad.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

# region: imports
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Contact, Element, Manifest, Vec3]
import pf.Collider
import pf.Config
import pf.Draw
import pf.GamepadButton
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Query
import pf.QueryResults
import pf.Scene
import pf.Sound
import pf.Speaker
# endregion

# id is the draw id of the pickup and of its Collider.
Pickup : { id : U64, pos : Vec3 }

Phase : [Playing, Won]

# A Sound id of 0 plays nothing.
Sounds : { blip : U32, creak : U32, hum : U32, music : U32 }

# pip is 0, the fallback mesh, and each Sound id is 0 until loaded gives the ids.
# yaw turns Pip about +y. At 0, Pip faces +z.
# door_lift goes from 0, shut, to door_height, open.
Model : { cube : U32, sphere : U32, pip : U32, sounds : Sounds, pos : Vec3, yaw : F32, pickups : List(Pickup), door_lift : F32, phase : Phase }

ground_id : U64
ground_id = 1

# Pip's id is lower than the id of every other Collider, so Pip is always `a`
# in a Contact.
pip_id : U64
pip_id = 2

door_id : U64
door_id = 3

# Group ids are apart from draw ids.
door_group_id : U64
door_group_id = 1

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Pip" } }

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
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, sounds: { blip: 0, creak: 0, hum: 0, music: 0 }, pos: V.zero, yaw: 0.0, pickups: start_pickups, door_lift: 0.0, phase: Playing }
	{ model, commands: [Load({ pack: "pip", assets: ["pip", "sound/blip", "sound/creak", "sound/hum", "sound/music"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	sounds = { blip: Sound.resolve(manifest, "sound/blip"), creak: Sound.resolve(manifest, "sound/creak"), hum: Sound.resolve(manifest, "sound/hum"), music: Sound.resolve(manifest, "sound/music") }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), sounds }
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| {
	contacts = results.contacts
	next = match model.phase {
		Playing => collect(model, contacts) |> push_out(contacts) |> walk(input, dt) |> raise_door(dt) |> win(contacts)
		Won => spin(model, dt)
	}
	{ model: next, commands: quit(input).concat(blip(model, next)) }
}

# A blip plays once when Pip collects a pickup. Two pickups in one step make one blip.
blip : Model, Model -> List(Command)
blip = |before, after|
	if List.len(after.pickups) < List.len(before.pickups) {
		[Sound.play(after.sounds.blip)]
	} else {
		[]
	}

# region: quit
# Escape on the keyboard or Start on any pad quits.
quit : Vocabulary.Input -> List(Command)
quit = |input| if Key.pressed(input, Escape) or GamepadButton.pressed_any(input, Start) [Quit] else []

# endregion

# The ids of the Colliders that Pip touched in the previous step.
touched : List(Contact) -> List(U64)
touched = |contacts| List.keep_if(contacts, |c| c.a == pip_id).map(|c| c.b)

collect : Model, List(Contact) -> Model
collect = |model, contacts| {
	ids = touched(contacts)
	{ ..model, pickups: List.drop_if(model.pickups, |p| List.contains(ids, p.id)) }
}

door_height : F32
door_height = 2.0

# Units each second.
door_speed : F32
door_speed = 1.5

raise_door : Model, F32 -> Model
raise_door = |model, dt|
	if List.is_empty(model.pickups) {
		{ ..model, door_lift: F32.min(model.door_lift + door_speed * dt, door_height) }
	} else {
		model
	}

is_open : Model -> Bool
is_open = |model| model.door_lift >= door_height

# Until the door is open, it pushes Pip back out of the doorway. The normal
# points from Pip to the door.
push_out : Model, List(Contact) -> Model
push_out = |model, contacts|
	match List.find_first(contacts, |c| c.a == pip_id and c.b == door_id) {
		Ok(c) if !is_open(model) => {
			back = V.sub(model.pos, V.scale(c.normal, c.depth))
			{ ..model, pos: { ..back, y: 0.0 } }
		}
		_ => model
	}

win : Model, List(Contact) -> Model
win = |model, contacts|
	if is_open(model) and List.contains(touched(contacts), door_id) {
		{ ..model, phase: Won }
	} else {
		model
	}

# Radians each second.
spin_speed : F32
spin_speed = 4.0

spin : Model, F32 -> Model
spin = |model, dt| { ..model, yaw: model.yaw + spin_speed * dt }

# region: walk
# Units each second.
speed : F32
speed = 2.5

# Pip stops this far from the centre, inside the edge of the ground.
edge : F32
edge = 2.7

# The left sticks of all the pads, added up.
left_stick : Vocabulary.Input -> { x : F32, y : F32 }
left_stick = |input| List.fold(input.gamepads, { x: 0.0, y: 0.0 }, |sum, pad| { x: sum.x + pad.left_stick.x, y: sum.y + pad.left_stick.y })

# A vector longer than 1 shrinks to length 1. A shorter one stays as it is.
clamp_to_disc : Vec3 -> Vec3
clamp_to_disc = |v|
	if V.length(v) > 1.0 {
		V.normalize(v)
	} else {
		v
	}

# W and the stick pushed up move away from the camera, toward -z.
walk : Model, Vocabulary.Input, F32 -> Model
walk = |model, input, dt| {
	stick = left_stick(input)
	dir = clamp_to_disc({ x: Key.axis(input, A, D) + stick.x, y: 0.0, z: Key.axis(input, W, S) - stick.y })
	if dir == V.zero {
		model
	} else {
		moved = V.add(model.pos, V.scale(dir, speed * dt))
		{ ..model, pos: { x: keep_on_ground(moved.x), y: 0.0, z: keep_on_ground(moved.z) }, yaw: F32.atan2({ x: dir.z, y: dir.x }) }
	}
}

# endregion

keep_on_ground : F32 -> F32
keep_on_ground = |v| F32.max(-edge, F32.min(v, edge))

# A cool sky lights the sides that the sun misses.
sky_light : Vocabulary.Light
sky_light = Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })

# The sun shines from behind the camera and to the right, so Pip's shadow falls
# behind it and to the left.
sunlight : Vocabulary.Light
sunlight = Light.sun({ x: -0.5, y: -0.75, z: -0.45 }, { r: 4.5, g: 4.0, b: 3.4 })

pip_half : Vec3
pip_half = { x: 0.3, y: 0.55, z: 0.3 }

pickup_radius : F32
pickup_radius = 0.25

# The door stands at the far edge of the ground.
door_half : Vec3
door_half = { x: 0.8, y: 0.5 * door_height, z: 0.1 }

door_pos : Vec3
door_pos = { x: 0.0, y: door_half.y, z: -2.9 }

music_speaker_id : U64
music_speaker_id = 1

hum_speaker_id : U64
hum_speaker_id = 2

creak_speaker_id : U64
creak_speaker_id = 3

music : Model -> Vocabulary.Speaker
music = |model| { ..Speaker.default, id: music_speaker_id, sound: model.sounds.music, gain: 0.5 }

# Past this distance from the camera, the door's Speakers are silent.
door_range : F32
door_range = 10.0

# The door's Speakers sit at the centre of its Group, so they rise with it.
door_speakers : Model -> List(Vocabulary.Node)
door_speakers = |model| {
	at = At({ pos: V.zero, range: door_range })
	hum = { ..Speaker.default, id: hum_speaker_id, sound: model.sounds.hum, gain: 1.0 - model.door_lift / door_height, at }
	creak = { ..Speaker.default, id: creak_speaker_id, sound: model.sounds.creak, at, repeat: Once }
	match model.phase {
		Playing if is_open(model) => [Speaker(creak)]
		Playing if model.door_lift > 0.0 => [Speaker(hum), Speaker(creak)]
		Playing => [Speaker(hum)]
		Won => []
	}
}

camera_offset : Vec3
camera_offset = { x: 0.0, y: 3.6, z: 4.5 }

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw) }
	door = { ..Draw.default, id: door_id, mesh: model.cube, scale: V.scale(door_half, 2.0), tint: { r: 0.45, g: 0.12, b: 0.05 } }
	door_group = Group({ id: door_group_id, pos: { ..door_pos, y: door_pos.y + model.door_lift }, rot: Quat.identity }, [Draw(door)].concat(door_speakers(model)))
	pickups = model.pickups.map(|p| Draw(pickup(model.sphere, p)))
	# The camera is the Listener, so it follows Pip to let you hear the door come closer.
	camera = Cam.follow({ ..model.pos, z: model.pos.z + 0.3 }, camera_offset)
	# The box's centre is half its height up, so it stands on Pip's feet.
	pip_box = Collider.box(pip_id, { ..model.pos, y: pip_half.y }, Quat.from_yaw(model.yaw), pip_half)
	# The doorway keeps its Collider while the door rises.
	door_box = Collider.box(door_id, door_pos, Quat.identity, door_half)
	colliders = [Collider(pip_box), Collider(door_box)].concat(model.pickups.map(|p| Collider(Collider.sphere(p.id, p.pos, pickup_radius))))
	queries = [Query.contacts_of(pip_id)]
	nodes = [Light(sky_light), Light(sunlight), Speaker(music(model)), Draw(ground), Draw(pip), door_group].concat(pickups).concat(colliders)
	{ ..Scene.empty, camera, nodes, queries, ui: hud(model) }
}

# A line of HUD text never wraps.
label : Str -> Ui.Text
label = |str| { ..Ui.label(str), wrap: None }

count_text : Model -> Str
count_text = |model| {
	total = List.len(start_pickups)
	collected = total - List.len(model.pickups)
	"Pickups: ${collected.to_str()} / ${total.to_str()}"
}

status_text : Model -> Str
status_text = |model| match model.phase {
	Playing if is_open(model) => "The door is open. Walk through it."
	Playing if List.is_empty(model.pickups) => "The door is opening."
	Playing => "Collect every pickup."
	Won => "You win! Press Escape or Start to quit."
}

# A bottom point of the window needs a negative y offset to move up into it.
hud : Model -> List(Element)
hud = |model| {
	count = Panel(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text(label(count_text(model)))])
	status = Panel(Ui.panel(CenterBottom, { x: 0.0, y: -16.0 }), [Text(label(status_text(model)))])
	[count, status]
}

# The sphere mesh is 1 unit wide.
pickup : U32, Pickup -> Vocabulary.Draw
pickup = |mesh, p| {
	size = 2.0 * pickup_radius
	{ ..Draw.default, id: p.id, mesh, pos: p.pos, scale: { x: size, y: size, z: size }, tint: { r: 1.0, g: 0.62, b: 0.08 } }
}

pi : F32
pi = 3.14159265

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

start : Model
start = init(Config.empty).model

hold : List(Key.Key) -> Vocabulary.Input
hold = |keys| { ..Input.empty, held: keys.map(Key.code) }

# W for one step moves Pip toward -z and turns it to face -z.
expect {
	moved = step(start, hold([W]), QueryResults.empty, 0.1).model
	near(moved.pos.z, -0.25) and near(moved.pos.x, 0.0) and near(moved.yaw, pi)
}

# Two keys at once move Pip no faster than one key.
expect {
	moved = step(start, hold([W, D]), QueryResults.empty, 0.1).model
	near(V.length(moved.pos), 0.25)
}

# Pip stops at the edge of the ground.
expect {
	moved = step(start, hold([D]), QueryResults.empty, 10.0).model
	near(moved.pos.x, edge)
}

# With no key, Pip stays where it is and keeps its yaw.
expect {
	turned = { ..start, yaw: 1.0 }
	step(turned, Input.empty, QueryResults.empty, 0.1).model == turned
}

contact_with : U64 -> Vocabulary.QueryResults
contact_with = |id| { ..QueryResults.empty, contacts: [{ a: pip_id, b: id, normal: { x: 0.0, y: 0.0, z: -1.0 }, depth: 0.1 }] }

# A Contact with a pickup collects it, and only it.
expect {
	after = step(start, Input.empty, contact_with(12), 0.1).model
	after.pickups.map(|p| p.id) == [10, 11, 13, 14]
}

# With no Contact, every pickup stays.
expect step(start, Input.empty, QueryResults.empty, 0.1).model.pickups == start_pickups

# The Scene asks for Pip's Contacts, and each pickup has a Collider.
expect {
	scene = view(start)
	has_collider = |p| List.any(
		scene.nodes,
		|node| match node {
			Collider(c) => c.id == p.id
			_ => Bool.False
		},
	)
	scene.queries == [Query.contacts_of(pip_id)] and List.all(start_pickups, has_collider)
}

# With every pickup collected, the door rises to its full height.
expect {
	cleared = { ..start, pickups: [] }
	step(cleared, Input.empty, QueryResults.empty, 10.0).model.door_lift == door_height
}

# While one pickup is left, the door stays shut.
expect {
	one_left = { ..start, pickups: [{ id: 10, pos: V.zero }] }
	step(one_left, Input.empty, QueryResults.empty, 10.0).model.door_lift == 0.0
}

# A shut door pushes Pip back, and Pip has not won.
expect {
	at_door = { ..start, pos: { x: 0.0, y: 0.0, z: -2.6 } }
	after = step(at_door, Input.empty, contact_with(door_id), 0.1).model
	near(after.pos.z, -2.5) and after.phase == Playing
}

# Pip wins when it walks into the open door.
expect {
	open = { ..start, pickups: [], door_lift: door_height }
	step(open, Input.empty, contact_with(door_id), 0.1).model.phase == Won
}

# After the win, the keys no longer move Pip.
expect {
	won = { ..start, phase: Won }
	step(won, hold([W]), QueryResults.empty, 0.1).model.pos == start.pos
}

# Escape quits at any time.
expect {
	escape = { ..Input.empty, pressed: [Key.code(Escape)] }
	step(start, escape, QueryResults.empty, 0.1).commands == [Quit]
}

expect count_text(start) == "Pickups: 0 / 5"

# Each pickup that Pip collects counts up by one.
expect {
	after = step(start, Input.empty, contact_with(12), 0.1).model
	count_text(after) == "Pickups: 1 / 5"
}

expect status_text({ ..start, pickups: [] }) == "The door is opening."

expect status_text({ ..start, pickups: [], door_lift: door_height }) == "The door is open. Walk through it."

expect status_text({ ..start, phase: Won }) == "You win! Press Escape or Start to quit."

with_sounds : Model
with_sounds = { ..start, sounds: { blip: 7, creak: 6, hum: 8, music: 9 } }

rising : Model
rising = { ..with_sounds, pickups: [], door_lift: 0.5 * door_height }

# Pip collects a pickup, and the step plays the blip once.
expect step(with_sounds, Input.empty, contact_with(12), 0.1).commands == [Sound.play(7)]

# With no pickup collected, nothing plays.
expect step(with_sounds, Input.empty, QueryResults.empty, 0.1).commands == []

# The music plays Here, outside the door's Group.
expect {
	root = speakers_of(view(with_sounds))
	root.map(|s| s.id) == [music_speaker_id] and root.map(|s| s.sound) == [9] and root.map(|s| s.at) == [Here]
}

# While the door is shut, its Group holds the hum at its centre, and no creak.
expect {
	door = door_of(view(with_sounds))
	ids = door.speakers.map(|s| s.id)
	places = door.speakers.map(|s| s.at)
	door.pos == door_pos and ids == [hum_speaker_id] and places == [At({ pos: V.zero, range: door_range })]
}

# Halfway up, the Group has risen, the hum plays at half gain and the creak plays once.
expect {
	door = door_of(view(rising))
	ids = door.speakers.map(|s| s.id)
	gains = door.speakers.map(|s| s.gain)
	repeats = door.speakers.map(|s| s.repeat)
	door.pos == { ..door_pos, y: door_pos.y + 0.5 * door_height } and ids == [hum_speaker_id, creak_speaker_id] and gains == [0.5, 1.0] and repeats == [Loop, Once]
}

# Once the door is open, the hum has gone and the creak plays on.
expect door_of(view({ ..rising, door_lift: door_height })).speakers.map(|s| s.id) == [creak_speaker_id]

# When Pip walks through, the creak leaves the Scene, so it stops.
expect {
	door = door_of(view({ ..rising, door_lift: door_height, phase: Won }))
	door.pos == { ..door_pos, y: door_pos.y + door_height } and door.speakers == []
}

# The root Speakers of a Scene, in list order.
speakers_of : Vocabulary.Scene -> List(Vocabulary.Speaker)
speakers_of = |scene| List.keep_oks(
	scene.nodes,
	|node| match node {
		Speaker(s) => Ok(s)
		_ => Err(NotSpeaker)
	},
)

# The door's Group, and the Speakers in it.
door_of : Vocabulary.Scene -> { pos : Vec3, speakers : List(Vocabulary.Speaker) }
door_of = |scene| {
	groups = List.keep_oks(
		scene.nodes,
		|node| match node {
			Group(g, children) if g.id == door_group_id => Ok({ pos: g.pos, speakers: speakers_of({ ..scene, nodes: children }) })
			_ => Err(NotDoor)
		},
	)
	match List.first(groups) {
		Ok(door) => door
		Err(_) => { pos: V.zero, speakers: [] }
	}
}

# region: tests
with_pads : List(Vocabulary.Gamepad) -> Vocabulary.Input
with_pads = |pads| { ..Input.empty, gamepads: pads }

# The stick halfway up walks Pip toward -z at half speed.
expect {
	half_up = { ..Input.idle_gamepad, left_stick: { x: 0.0, y: 0.5 } }
	moved = step(start, with_pads([half_up]), QueryResults.empty, 0.1).model
	near(moved.pos.z, -0.125) and near(moved.pos.x, 0.0) and near(moved.yaw, pi)
}

# The stick all the way right walks Pip toward +x at full speed.
expect {
	right = { ..Input.idle_gamepad, left_stick: { x: 1.0, y: 0.0 } }
	moved = step(start, with_pads([right]), QueryResults.empty, 0.1).model
	near(moved.pos.x, 0.25) and near(moved.pos.z, 0.0)
}

# W and the stick up together walk Pip no faster than W alone.
expect {
	up = { ..Input.idle_gamepad, left_stick: { x: 0.0, y: 1.0 } }
	both = { ..with_pads([up]), held: [Key.code(W)] }
	moved = step(start, both, QueryResults.empty, 0.1).model
	near(V.length(moved.pos), 0.25)
}

# A pad at rest leaves Pip where it is.
expect step(start, with_pads([Input.idle_gamepad]), QueryResults.empty, 0.1).model == start

# Start pressed on any pad quits, here on the pad in slot 2.
expect {
	start_pressed = { ..Input.idle_gamepad, slot: 2, pressed: [GamepadButton.code(Start)] }
	step(start, with_pads([Input.idle_gamepad, start_pressed]), QueryResults.empty, 0.1).commands == [Quit]
}

# Start held from an earlier step does not quit again.
expect {
	start_held = { ..Input.idle_gamepad, held: [GamepadButton.code(Start)] }
	step(start, with_pads([start_held]), QueryResults.empty, 0.1).commands == []
}

# endregion
