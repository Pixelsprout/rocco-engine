app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", linalg: "../../../packages/linalg/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "nightly-2026-10-11-7d256b9", ui: "../../../packages/ui/main.roc" }

# guide/tutorial/10-animation.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

# region: imports
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Contact, Element, Manifest, Vec3]
import pf.Button
import pf.Collider
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Loop
import pf.Pose
import pf.Query
import pf.QueryResults
import pf.Scene
import pf.Sound
# endregion

# id is the draw id of the pickup and of its Collider.
Pickup : { id : U64, pos : Vec3 }

Phase : [Playing, Won]

# A Sound id of 0 plays nothing.
Sounds : { blip : U32, hum : U32, music : U32 }

# region: model
# A Clip id of 0 is no Clip, so Pip stands in its bind pose. Each duration is
# 0 until loaded gives it.
Clips : { idle : U32, walk : U32, idle_duration : F32, walk_duration : F32 }

# Each time is in seconds, wrapped into its Clip. fade goes from 0, all Idle,
# to 1, all Walk.
Animation : { idle_time : F32, walk_time : F32, fade : F32 }

# pip is 0, the fallback mesh, and each Sound id is 0 until loaded gives the ids.
# yaw turns Pip about +y. At 0, Pip faces +z.
# door_lift goes from 0, shut, to door_height, open.
Model : { cube : U32, sphere : U32, pip : U32, sounds : Sounds, clips : Clips, animation : Animation, pos : Vec3, yaw : F32, pickups : List(Pickup), door_lift : F32, phase : Phase }

# endregion

ground_id : U64
ground_id = 1

# Pip's id is lower than the id of every other Collider, so Pip is always `a`
# in a Contact.
pip_id : U64
pip_id = 2

door_id : U64
door_id = 3

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

# region: init
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	clips = { idle: 0, walk: 0, idle_duration: 0.0, walk_duration: 0.0 }
	animation = { idle_time: 0.0, walk_time: 0.0, fade: 0.0 }
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, sounds: { blip: 0, hum: 0, music: 0 }, clips, animation, pos: V.zero, yaw: 0.0, pickups: start_pickups, door_lift: 0.0, phase: Playing }
	{ model, commands: [Load({ pack: "pip", assets: ["pip", "sound/blip", "sound/hum", "sound/music"] })] }
}

# endregion

# region: loaded
loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	sounds = { blip: Sound.resolve(manifest, "sound/blip"), hum: Sound.resolve(manifest, "sound/hum"), music: Sound.resolve(manifest, "sound/music") }
	idle = Mesh.clip(manifest, "pip", "Idle")
	walk = Mesh.clip(manifest, "pip", "Walk")
	clips = { idle, walk, idle_duration: Mesh.clip_duration(manifest, idle), walk_duration: Mesh.clip_duration(manifest, walk) }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), sounds, clips }
}

# endregion

# region: step
step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, results, dt| {
	contacts = results.contacts
	next = match model.phase {
		Playing => collect(model, contacts) |> push_out(contacts) |> walk(input, dt) |> raise_door(dt) |> win(contacts)
		Won => spin(model, dt)
	}
		|> animate(model.pos, dt)
	{ model: next, commands: quit(input).concat(blip(model, next)) }
}

# endregion

# A blip plays once when Pip collects a pickup. Two pickups in one step make one blip.
blip : Model, Model -> List(Command)
blip = |before, after|
	if List.len(after.pickups) < List.len(before.pickups) {
		[Sound.play(after.sounds.blip)]
	} else {
		[]
	}

# Escape on the keyboard or Start on any pad quits.
quit : Vocabulary.Input -> List(Command)
quit = |input| if Key.pressed(input, Escape) or Button.pressed_any(input, Start) [Quit] else []

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

keep_on_ground : F32 -> F32
keep_on_ground = |v| F32.max(-edge, F32.min(v, edge))

# region: animate
# The ground speed that the feet of the Walk Clip match, in units each second.
walk_speed : F32
walk_speed = 2.5

# Seconds to fade all the way from Idle to Walk, or back.
fade_seconds : F32
fade_seconds = 0.2

# Idle plays at its own pace. Walk plays as fast as Pip moves, so the feet
# keep up with the ground. The fade moves toward Walk while Pip moves.
animate : Model, Vec3, F32 -> Model
animate = |model, before, dt| {
	c = model.clips
	a = model.animation
	moved = V.length(V.sub(model.pos, before))
	step_fade = dt / fade_seconds
	fade = if moved > 0.0 F32.min(a.fade + step_fade, 1.0) else F32.max(a.fade - step_fade, 0.0)
	idle_time = Pose.loop(a.idle_time + dt, c.idle_duration)
	walk_time = Pose.loop(a.walk_time + moved / walk_speed, c.walk_duration)
	{ ..model, animation: { idle_time, walk_time, fade } }
}

# endregion

# region: pose
pip_pose : Model -> Vocabulary.Pose
pip_pose = |model| {
	c = model.clips
	a = model.animation
	{ clip: c.idle, time: a.idle_time, fade_clip: c.walk, fade_time: a.walk_time, fade: a.fade }
}

# endregion

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

# The door's centre, as it rises.
door_at : Model -> Vec3
door_at = |model| { ..door_pos, y: door_pos.y + model.door_lift }

music_loop_id : U64
music_loop_id = 1

hum_loop_id : U64
hum_loop_id = 2

# Past this distance from the camera, the hum is silent.
hum_range : F32
hum_range = 10.0

# The hum fades as the door rises, and stops when the door is open.
loops : Model -> List(Vocabulary.Loop)
loops = |model| {
	music = { ..Loop.default, id: music_loop_id, sound: model.sounds.music, gain: 0.5 }
	hum = { ..Loop.default, id: hum_loop_id, sound: model.sounds.hum, gain: 1.0 - model.door_lift / door_height, at: At({ pos: door_at(model), range: hum_range }) }
	if is_open(model) [music] else [music, hum]
}

camera_offset : Vec3
camera_offset = { x: 0.0, y: 3.6, z: 4.5 }

# region: view
view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw), pose: pip_pose(model) }
	door = { ..Draw.default, id: door_id, mesh: model.cube, pos: door_at(model), scale: V.scale(door_half, 2.0), tint: { r: 0.45, g: 0.12, b: 0.05 } }
	pickups = model.pickups.map(|p| Draw(pickup(model.sphere, p)))
	# The camera is the Listener, so it follows Pip to let you hear the door come closer.
	camera = Cam.follow({ ..model.pos, z: model.pos.z + 0.3 }, camera_offset)
	# The box's centre is half its height up, so it stands on Pip's feet.
	pip_box = Collider.box(pip_id, { ..model.pos, y: pip_half.y }, Quat.from_yaw(model.yaw), pip_half)
	# The doorway keeps its Collider while the door rises.
	door_box = Collider.box(door_id, door_pos, Quat.identity, door_half)
	colliders = [Collider(pip_box), Collider(door_box)].concat(model.pickups.map(|p| Collider(Collider.sphere(p.id, p.pos, pickup_radius))))
	queries = [Query.contacts_of(pip_id)]
	nodes = [Light(sky_light), Light(sunlight), Draw(ground), Draw(pip), Draw(door)].concat(pickups).concat(colliders)
	{ ..Scene.empty, camera, nodes, queries, ui: hud(model), loops: loops(model) }
}

# endregion

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
	count = Box(Ui.panel(LeftTop, { x: 16.0, y: 16.0 }), [Text(label(count_text(model)))])
	status = Box(Ui.panel(CenterBottom, { x: 0.0, y: -16.0 }), [Text(label(status_text(model)))])
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
with_sounds = { ..start, sounds: { blip: 7, hum: 8, music: 9 } }

# Pip collects a pickup, and the step plays the blip once.
expect step(with_sounds, Input.empty, contact_with(12), 0.1).commands == [Sound.play(7)]

# With no pickup collected, nothing plays.
expect step(with_sounds, Input.empty, QueryResults.empty, 0.1).commands == []

# The music plays Here, and the hum plays at the door while it is shut.
expect {
	scene = view(with_sounds)
	ids = scene.loops.map(|l| l.id)
	sounds = scene.loops.map(|l| l.sound)
	places = scene.loops.map(|l| l.at)
	ids == [music_loop_id, hum_loop_id] and sounds == [9, 8] and places == [Here, At({ pos: door_pos, range: hum_range })]
}

# Halfway up, the hum plays at half gain.
expect {
	half = view({ ..with_sounds, pickups: [], door_lift: 0.5 * door_height })
	half.loops.map(|l| l.gain) == [0.5, 0.5]
}

# Once the door is open, only the music plays.
expect view({ ..with_sounds, pickups: [], door_lift: door_height }).loops.map(|l| l.id) == [music_loop_id]

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
	start_pressed = { ..Input.idle_gamepad, slot: 2, pressed: [Button.code(Start)] }
	step(start, with_pads([Input.idle_gamepad, start_pressed]), QueryResults.empty, 0.1).commands == [Quit]
}

# Start held from an earlier step does not quit again.
expect {
	start_held = { ..Input.idle_gamepad, held: [Button.code(Start)] }
	step(start, with_pads([start_held]), QueryResults.empty, 0.1).commands == []
}

# region: tests
# Pip after loaded, with the Idle Clip 2 s long and the Walk Clip 1 s long.
animated : Model
animated = { ..start, clips: { idle: 1, walk: 2, idle_duration: 2.0, walk_duration: 1.0 } }

# One step of W fades halfway to Walk. Walk moves by the distance over walk_speed.
expect {
	a = step(animated, hold([W]), QueryResults.empty, 0.1).model.animation
	near(a.fade, 0.5) and near(a.walk_time, 0.1) and near(a.idle_time, 0.1)
}

# The fade stops at 1, all Walk.
expect {
	walking = { ..animated, animation: { idle_time: 0.0, walk_time: 0.0, fade: 0.9 } }
	step(walking, hold([W]), QueryResults.empty, 0.1).model.animation.fade == 1.0
}

# Standing still fades back toward Idle, and the walk time stays.
expect {
	walking = { ..animated, animation: { idle_time: 0.0, walk_time: 0.5, fade: 1.0 } }
	a = step(walking, Input.empty, QueryResults.empty, 0.1).model.animation
	near(a.fade, 0.5) and a.walk_time == 0.5
}

# The stick halfway up plays Walk at half speed.
expect {
	half_up = { ..Input.idle_gamepad, left_stick: { x: 0.0, y: 0.5 } }
	near(step(animated, with_pads([half_up]), QueryResults.empty, 0.1).model.animation.walk_time, 0.05)
}

# Each time wraps back to the start of its Clip.
expect {
	late = { ..animated, animation: { idle_time: 1.95, walk_time: 0.95, fade: 1.0 } }
	a = step(late, hold([W]), QueryResults.empty, 0.1).model.animation
	near(a.idle_time, 0.05) and near(a.walk_time, 0.05)
}

# Pip's Draw plays Idle and fades to Walk.
expect {
	pose = pip_pose({ ..animated, animation: { idle_time: 1.5, walk_time: 0.25, fade: 0.5 } })
	pose == { clip: 1, time: 1.5, fade_clip: 2, fade_time: 0.25, fade: 0.5 }
}
# endregion
