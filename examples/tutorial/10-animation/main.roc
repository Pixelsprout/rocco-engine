app [init, launch, loaded, step, view] { cam: "../../../packages/camera/main.roc", linalg: "../../../packages/linalg/main.roc", mesh: "../../../packages/mesh/main.roc", pf: platform "../../../platform/main.roc", roc: "nightly-2026-11-04-2622062", ui: "../../../packages/ui/main.roc" }

# guide/tutorial/10-animation.md copies the regions in this file. Run roc scripts/build.roc docs after a change.

# region: imports
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Contact, Element, Manifest, Vec3]
import pf.Collider
import pf.Draw
import pf.GamepadButton
import pf.Key
import pf.Launch
import pf.Light
import pf.Pose
import pf.Query
import pf.Scene
import pf.Sound
import pf.Speaker
# endregion

# id is the draw id of the pickup and of its Collider.
Pickup : { id : U64, pos : Vec3 }

Phase : [Playing, Won]

# A Sound id of 0 plays nothing.
Sounds : { blip : U32, creak : U32, hum : U32, music : U32 }

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

# region: init
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	clips = { idle: 0, walk: 0, idle_duration: 0.0, walk_duration: 0.0 }
	animation = { idle_time: 0.0, walk_time: 0.0, fade: 0.0 }
	model = { cube: Mesh.primitive(Cube), sphere: Mesh.primitive(Sphere), pip: 0, sounds: { blip: 0, creak: 0, hum: 0, music: 0 }, clips, animation, pos: V.zero, yaw: 0.0, pickups: start_pickups, door_lift: 0.0, phase: Playing }
	{ model, commands: [Load({ pack: "pip", assets: ["pip", "sound/blip", "sound/creak", "sound/hum", "sound/music"] })] }
}

# endregion

# region: loaded
loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	sounds = { blip: Sound.resolve(manifest, "sound/blip"), creak: Sound.resolve(manifest, "sound/creak"), hum: Sound.resolve(manifest, "sound/hum"), music: Sound.resolve(manifest, "sound/music") }
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
		Playing => collect(model, contacts) |> push_out(contacts) |> walk(input, dt) |> raise_door(dt) |> win(contacts) |> animate(input_speed(input), dt)
		Won => spin(model, dt) |> animate(0.0, dt)
	}
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
quit = |input| if (Key.pressed(input, Escape) or GamepadButton.pressed_any(input, Start)) [Quit] else []

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

# region: move
# W and the stick pushed up move away from the camera, toward -z.
move_dir : Vocabulary.Input -> Vec3
move_dir = |input| {
	stick = left_stick(input)
	clamp_to_disc({ x: Key.axis(input, A, D) + stick.x, y: 0.0, z: Key.axis(input, W, S) - stick.y })
}

walk : Model, Vocabulary.Input, F32 -> Model
walk = |model, input, dt| {
	dir = move_dir(input)
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

# region: animate
# The ground speed that the feet of the Walk Clip match, in units each second.
walk_speed : F32
walk_speed = 2.5

# Seconds to fade all the way from Idle to Walk, or back.
fade_seconds : F32
fade_seconds = 0.2

# The speed that the keys and the sticks ask Pip to walk at, in units each second.
input_speed : Vocabulary.Input -> F32
input_speed = |input| speed * V.length(move_dir(input))

# Idle plays at its own pace. Walk plays at the speed the input asks for, so
# the feet keep up with the ground. The fade moves toward Walk while the input
# asks Pip to walk.
animate : Model, F32, F32 -> Model
animate = |model, walking_speed, dt| {
	c = model.clips
	a = model.animation
	step_fade = dt / fade_seconds
	fade = if (walking_speed > 0.0) F32.min(a.fade + step_fade, 1.0) else F32.max(a.fade - step_fade, 0.0)
	idle_time = Pose.loop(a.idle_time + dt, c.idle_duration)
	walk_time = Pose.loop(a.walk_time + dt * walking_speed / walk_speed, c.walk_duration)
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

# region: view
view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw), pose: pip_pose(model) }
	door = { ..Draw.default, id: door_id, mesh: model.cube, scale: V.scale(door_half, 2.0), tint: { r: 0.45, g: 0.12, b: 0.05 } }
	door_group = Group({ id: door_group_id, pos: { ..door_pos, y: door_pos.y + model.door_lift }, rot: Quat.identity, selected: Bool.False }, [Draw(door)].concat(door_speakers(model)))
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
