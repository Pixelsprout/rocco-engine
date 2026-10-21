---
title: "7. A HUD"
summary: Show the pickup count and a message over the game with Scene.ui and the ui package, and finish the game.
order: 7
---

# 7. A HUD

The game works, but it tells the player nothing. You can't see how many
pickups are left, that the door is open, or that you have won. In this
chapter, you add a HUD: text that sits over the game. You use:

- the `ui` field of the Scene, which the host draws over the 3D view,
- the `ui` package, which builds the UI from boxes and text.

![Pip on the ground, with "Pickups: 0 / 5" at the top left and "Collect every pickup." at the bottom](../images/tutorial-07-hud.png)

This chapter starts from your app from
[6. The door and the win](06-door.md). The full app is
[`examples/tutorial/07-hud/main.roc`](../../examples/tutorial/07-hud/main.roc).
To see every change, compare the two chapter apps:

```sh
git diff --no-index examples/tutorial/06-door/main.roc examples/tutorial/07-hud/main.roc
```

`pip.glb` stays the same.

## The header and the imports

Add the `ui` package to the header:

```roc
app [init, launch, loaded, step, view] { cam: "{{camera_url}}", linalg: "{{linalg_url}}", mesh: "{{mesh_url}}", pf: platform "{{platform_url}}", roc: "{{roc_nightly}}", ui: "{{ui_url}}" }
```

Then import `ui.Ui`, and add `Element` and `Rgba` to the exposed types:

<!-- region: examples/tutorial/07-hud/main.roc#imports -->
```roc
import cam.Camera as Cam
import linalg.Vec3 as V
import linalg.Quat
import mesh.Mesh as Mesh
import ui.Ui
import pf.Vocabulary exposing [Command, Contact, Element, Manifest, Rgba, Vec3]
import pf.Collider
import pf.Config
import pf.Draw
import pf.Input
import pf.Key
import pf.Launch
import pf.Light
import pf.Query
import pf.QueryResults
import pf.Scene
```
<!-- endregion -->

## The HUD

Your game can't lay out the UI itself, because it never learns the size of
the window or how wide a string is. So the host does the layout. Your game
describes the UI as boxes and text, and the host places them.

<!-- region: examples/tutorial/07-hud/main.roc#hud -->
```roc
white : Rgba
white = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }

text_style : Ui.TextStyle
text_style = { size: 24.0, color: white, wrap: None }

hud_box : Ui.AttachPoint, Ui.Offset -> Ui.BoxConfig
hud_box = |attach, offset| { ..Ui.float_at(attach, offset), pad: Ui.pad_all(8.0), background: { r: 0.0, g: 0.0, b: 0.0, a: 0.5 }, radius: 8.0 }

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
	Won => "You win! Press Escape to quit."
}

# A bottom point of the window needs a negative y offset to move up into it.
hud : Model -> List(Element)
hud = |model| {
	count = Ui.box(hud_box(LeftTop, { x: 16.0, y: 16.0 }), [Ui.text(count_text(model), text_style)])
	status = Ui.box(hud_box(CenterBottom, { x: 0.0, y: -16.0 }), [Ui.text(status_text(model), text_style)])
	count.concat(status)
}
```
<!-- endregion -->

- `count_text` and `status_text` give the strings. They read only the
  Model, so the tests can check them without the host. `status_text`
  uses `is_open` from chapter 6, so it says that the door is open only
  once the door has risen all the way.
- `Ui.text` gives one string in a style: a size in logical pixels, a
  colour and whether to wrap.
- `Ui.box` gives a Box with its children. `hud_box` starts from
  `Ui.float_at`, which makes a Box that floats over the window at one of
  its points, then adds padding, a see-through black background and round
  corners.
- The count sits at the top left. The status sits at the bottom centre, so
  it moves up by 16 pixels with a negative `y`.

Each call gives a list of Elements, so `concat` joins the two Boxes into
one list. [The UI](../ui.md) explains the Elements and the layout rules.

## view

Put the HUD in the Scene:

<!-- region: examples/tutorial/07-hud/main.roc#view -->
```roc
view : Model -> Vocabulary.Scene
view = |model| {
	ground = { ..Draw.default, id: ground_id, mesh: model.cube, pos: { x: 0.0, y: -0.1, z: 0.0 }, scale: { x: 6.0, y: 0.2, z: 6.0 }, tint: { r: 0.12, g: 0.25, b: 0.1 } }
	pip = { ..Draw.default, id: pip_id, mesh: model.pip, pos: model.pos, rot: Quat.from_yaw(model.yaw) }
	door = { ..Draw.default, id: door_id, mesh: model.cube, pos: { ..door_pos, y: door_pos.y + model.door_lift }, scale: V.scale(door_half, 2.0), tint: { r: 0.45, g: 0.12, b: 0.05 } }
	pickups = model.pickups.map(|p| pickup(model.sphere, p))
	camera = Cam.look_at({ x: 0.0, y: 3.6, z: 4.8 }, { x: 0.0, y: 0.0, z: 0.3 })
	# The box's centre is half its height up, so it stands on Pip's feet.
	pip_box = Collider.box(pip_id, { ..model.pos, y: pip_half.y }, model.yaw, pip_half)
	# The doorway keeps its Collider while the door rises.
	door_box = Collider.box(door_id, door_pos, 0.0, door_half)
	colliders = [pip_box, door_box].concat(model.pickups.map(|p| Collider.sphere(p.id, p.pos, pickup_radius)))
	queries = [Query.contacts_of(pip_id)]
	{ ..Scene.empty, camera, draws: [ground, pip, door].concat(pickups), colliders, lights, queries, ui: hud(model) }
}
```
<!-- endregion -->

Like the rest of the Scene, `view` builds the HUD again at each step, from
the Model. The text changes as soon as the Model does, with no code to
update it.

## Test the HUD

Add these tests below the tests from chapter 6:

<!-- region: examples/tutorial/07-hud/main.roc#tests -->
```roc
expect count_text(start) == "Pickups: 0 / 5"

# Each pickup that Pip collects counts up by one.
expect {
	after = step(start, Input.empty, contact_with(12), 0.1).model
	count_text(after) == "Pickups: 1 / 5"
}

expect status_text({ ..start, pickups: [] }) == "The door is opening."

expect status_text({ ..start, pickups: [], door_lift: door_height }) == "The door is open. Walk through it."

expect status_text({ ..start, phase: Won }) == "You win! Press Escape to quit."
```
<!-- endregion -->

Run the tests:

```sh
roc test main.roc
```

## Play the game

In `pip/`, run:

```sh
roc main.roc
```

Collect the five pickups and watch the count go up. When the door opens,
walk Pip through it. The HUD says that you have won. Press Escape to quit.

You have made a whole game: a character that you load from a file, moves
with the keys, collects pickups and wins, with lights, a shadow and a HUD.

The tutorial goes on when rocco gets sound, a gamepad and animation. Until
then, the guide pages explain each part in more detail. Start with
[Collisions and Queries](../collisions.md) and [The UI](../ui.md), or read
[Shipping a game](../shipping.md) to build your game for other people.
