app [init, launch, loaded, step, view] { cam: "../../packages/camera/main.roc", linalg: "../../packages/linalg/main.roc", mesh: "../../packages/mesh/main.roc", pf: platform "../../platform/main.roc", roc: "nightly-2026-11-04-2622062" }

# Pip walks on the spot. Space fades it into Run, and Space again fades it
# back into Walk. The camera looks at Pip from the side, so the feet show
# against the ground.

import cam.Camera as Cam
import linalg.Quat
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest]
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Pose
import pf.QueryResults
import pf.Scene

# A Clip id of 0 is no Clip. Each duration is 0 until loaded gives it.
Clips : { walk : U32, run : U32, walk_duration : F32, run_duration : F32 }

# Each time is in seconds, wrapped into its Clip. fade goes from 0, all Walk,
# to 1, all Run.
Animation : { walk_time : F32, run_time : F32, fade : F32 }

# pip is 0, the fallback mesh, until loaded gives its id. running is the Clip
# that the fade moves toward.
Model : { pip : U32, clips : Clips, animation : Animation, running : Bool }

pip_id : U64
pip_id = 1

ground_id : U64
ground_id = 2

# Seconds to fade all the way from Walk to Run, or back.
fade_seconds : F32
fade_seconds = 0.5

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "Animation" } }

init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| {
	clips = { walk: 0, run: 0, walk_duration: 0.0, run_duration: 0.0 }
	animation = { walk_time: 0.0, run_time: 0.0, fade: 0.0 }
	{ model: { pip: 0, clips, animation, running: Bool.False }, commands: [Load({ pack: "pip", assets: ["pip"] })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| {
	walk = Mesh.clip(manifest, "pip", "Walk")
	run = Mesh.clip(manifest, "pip", "Run")
	clips = { walk, run, walk_duration: Mesh.clip_duration(manifest, walk), run_duration: Mesh.clip_duration(manifest, run) }
	{ ..model, pip: Mesh.resolve(manifest, "pip"), clips }
}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |model, input, _results, dt| {
	running = if (Key.pressed(input, Space)) !model.running else model.running
	commands = if (Key.pressed(input, Escape)) [Quit] else []
	{ model: animate({ ..model, running }, dt), commands }
}

# Both Clips play at their own pace, and the fade moves toward the Clip that
# running names.
animate : Model, F32 -> Model
animate = |model, dt| {
	c = model.clips
	a = model.animation
	step_fade = dt / fade_seconds
	fade = if (model.running) F32.min(a.fade + step_fade, 1.0) else F32.max(a.fade - step_fade, 0.0)
	walk_time = Pose.loop(a.walk_time + dt, c.walk_duration)
	run_time = Pose.loop(a.run_time + dt, c.run_duration)
	{ ..model, animation: { walk_time, run_time, fade } }
}

pip_pose : Model -> Vocabulary.Pose
pip_pose = |model| {
	c = model.clips
	a = model.animation
	{ clip: c.walk, time: a.walk_time, fade_clip: c.run, fade_time: a.run_time, fade: a.fade }
}

view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: Mesh.primitive(Cube), pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, rot: Quat.from_yaw(1.2), pose: pip_pose(model) }
	nodes = [
		Light(Light.ambient({ r: 0.2, g: 0.25, b: 0.35 })),
		Light(Light.sun({ x: -0.5, y: -0.75, z: -0.45 }, { r: 3.0, g: 2.7, b: 2.3 })),
		Draw(ground),
		Draw(pip),
	]
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 0.8, z: 2.4 }, { x: 0.0, y: 0.45, z: 0.0 }), nodes }
}

near : F32, F32 -> Bool
near = |a, b| (a - b).abs() < 0.0001

start : Model
start = init(Config.empty).model

# Pip after loaded, with the Walk Clip 1 s long and the Run Clip 0.75 s long.
animated : Model
animated = { ..start, clips: { walk: 2, run: 3, walk_duration: 1.0, run_duration: 0.75 } }

space : Vocabulary.Input
space = { ..Input.empty, pressed: [Key.code(Space)] }

# Pip starts in Walk.
expect start.running == Bool.False and start.animation.fade == 0.0

# Space starts the fade into Run, a step of 0.1 s at a time.
expect {
	after = step(animated, space, QueryResults.empty, 0.1).model
	after.running and near(after.animation.fade, 0.2)
}

# With no key, the fade keeps moving toward Run and stops at 1.
expect {
	running = { ..animated, running: Bool.True, animation: { walk_time: 0.0, run_time: 0.0, fade: 0.9 } }
	step(running, Input.empty, QueryResults.empty, 0.1).model.animation.fade == 1.0
}

# Space again fades back toward Walk.
expect {
	running = { ..animated, running: Bool.True, animation: { walk_time: 0.0, run_time: 0.0, fade: 1.0 } }
	after = step(running, space, QueryResults.empty, 0.1).model
	!after.running and near(after.animation.fade, 0.8)
}

# Each Clip plays at its own pace and wraps at its own duration.
expect {
	late = { ..animated, animation: { walk_time: 0.95, run_time: 0.7, fade: 0.0 } }
	a = step(late, Input.empty, QueryResults.empty, 0.1).model.animation
	near(a.walk_time, 0.05) and near(a.run_time, 0.05)
}

# Escape quits.
expect {
	escape = { ..Input.empty, pressed: [Key.code(Escape)] }
	step(start, escape, QueryResults.empty, 0.1).commands == [Quit]
}

# Pip's Draw plays Walk and fades to Run.
expect {
	pose = pip_pose({ ..animated, animation: { walk_time: 0.5, run_time: 0.25, fade: 0.5 } })
	pose == { clip: 2, time: 0.5, fade_clip: 3, fade_time: 0.25, fade: 0.5 }
}

# The Scene draws Pip with its Pose.
expect {
	model = { ..animated, pip: 7, animation: { walk_time: 0.5, run_time: 0.25, fade: 0.5 } }
	draws = List.keep_oks(
		view(model).nodes,
		|node| match node {
			Draw(d) if d.id == pip_id => Ok(d)
			_ => Err(NotPip)
		},
	)
	draws.map(|d| d.mesh) == [7] and draws.map(|d| d.pose) == [pip_pose(model)]
}
