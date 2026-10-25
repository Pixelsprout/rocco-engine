---
title: Install and first run
summary: Check that rocco fits your game, install Roc, then build and run a first game from the release bundles.
order: 1
---

# Install and first run

rocco is a 3D game engine for games written in Roc. You write your game as a
few pure functions, and the engine runs the window, the clock, the input and
the GPU for you.

You only need Roc. Each rocco release comes with the engine prebuilt for
macOS arm64, Linux x64 and Windows x64, so you don't need Odin, sokol or a C
compiler.

If you read this page on GitHub, the Roc nightly and the bundle URLs show as
markers in double braces. You can find the values in the notes of the
[latest release](https://github.com/Pixelsprout/rocco-engine/releases/latest).
The notes give the Roc nightly and the URL of each bundle.

## Is rocco right for you?

rocco is young, and it has some clear limits today. Check them before you
start a game with it:

- **Desktop only.** rocco runs on macOS arm64, Linux x64 and Windows x64.
  On Linux it needs an X11 desktop and an OpenGL driver. You build on each
  OS that you ship to, because there is no cross-compiling.
- **No mouse buttons.** The Input has the keyboard, the mouse movement and
  up to 4 gamepads, but no mouse buttons. Windows reads Xbox-compatible
  pads only. See [Gamepads](gamepad.md).
- **No physics.** The engine answers questions about shapes, such as "what
  does this ray hit?", but it moves nothing and pushes nothing apart. See
  [Collisions and Queries](collisions.md).
- **Roc changes quickly.** Roc changes from one nightly to the next. Each
  rocco release pins one nightly, and you use that exact nightly.

If those limits are fine for your game, read on.

## Install Roc

Use the nightly that the release names. A different nightly may not build
the game.

1. Download the Roc nightly `{{roc_nightly}}` for your OS from the
   [Roc nightlies](https://github.com/roc-lang/nightlies/releases).
2. Extract the archive.
3. Add the folder that holds `roc` to your `PATH`.
4. Run `roc version`. It should print `{{roc_nightly}}`.

On Linux, the game needs an X11 desktop and an OpenGL driver. On Windows,
run `roc` in a shell where `LIB` is not set. A Visual Studio developer
prompt sets `LIB`, and then the link fails.

## Make the game folder

1. Make a folder called `my-game`.
2. Make the file `my-game/main.roc`.
3. Put this header at the top of `my-game/main.roc`:

```roc
app [init, launch, loaded, step, view] { cam: "{{camera_url}}", mesh: "{{mesh_url}}", pf: platform "{{platform_url}}", roc: "{{roc_nightly}}" }
```

4. Below the header, add this code. It is the cards game from
   `examples/cards/main.roc`.

<!-- region: examples/cards/main.roc#game -->
```roc
import cam.Camera as Cam
import mesh.Mesh as Mesh
import pf.Vocabulary exposing [Command, Manifest]
import pf.Config
import pf.Draw
import pf.Input
import pf.Launch
import pf.Scene
import pf.Key
import pf.Light
import pf.QueryResults

# A game with no entities and no positions in the Model.
Card : [Ace, King, Number(U8)]

Model : { hand : List(Card), turns : U64, name : Str, card_mesh : U32 }

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| Launch.default

# A plane until a card mesh is on disk. Asking only for names in Config keeps a missing card out of the log.
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| {
	assets = if config.assets.contains("card") {
		["card"]
	} else {
		[]
	}
	model = { hand: [Ace, Number(7)], turns: 0, name: "solitaire", card_mesh: Mesh.primitive(Plane) }
	{ model, commands: [Load({ pack: "cards", assets })] }
}

loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, manifest| match List.find_first(manifest, |entry| entry.name == "card") {
	Ok(entry) => { ..m, card_mesh: entry.id }
	Err(NotFound) => m
}

update : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> Model
update = |m, input, _results, _dt|
	if Key.pressed(input, Space) {
		{ ..m, hand: List.append(m.hand, King), turns: m.turns + 1 }
	} else {
		m
	}

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, input, results, dt| { model: update(m, input, results, dt), commands: [] }

ambient : Vocabulary.Light
ambient = Light.ambient({ r: 0.2, g: 0.2, b: 0.2 })

# The BRDF divides diffuse light by pi, so 5.03 (1.6 pi) lights a white surface facing it to 1.6.
sun : Vocabulary.Light
sun = Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 })

# The Lights, then one Draw for each card.
view : Model -> Vocabulary.Scene
view = |m| {
	cards = List.map_with_index(m.hand, |card, i| Draw(card_draw(m, card, i)))
	nodes = [Light(ambient), Light(sun)].concat(cards)
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 0.0, y: 0.0, z: 0.0 }), nodes }
}

card_draw : Model, Card, U64 -> Vocabulary.Draw
card_draw = |m, card, i| {
	tint = match card {
		Ace => { r: 1.0, g: 0.787, b: 0.033 }
		King => { r: 0.604, g: 0.033, b: 0.033 }
		Number(_) => { r: 0.787, g: 0.787, b: 0.787 }
	}
	# The slot index is the draw id: a card slides to its slot when dealt.
	{ ..Draw.default, id: i, mesh: m.card_mesh, pos: { x: i.to_f32() * 1.2, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.4 }, tint }
}
```
<!-- endregion -->

## Run the game

In `my-game/`, run:

```sh
roc main.roc
```

The first run downloads the bundles and builds the game. Then a window
opens with two cards. Press Space to add a card, and close the window to
stop the game.

## What the code does

The header names the platform and each package that the game uses. `pf` is
the rocco platform, `mesh` gives the primitive meshes, and `cam` points the
camera. If your game uses vectors, add `linalg: "{{linalg_url}}"`. If it
uses the UI layout, add `ui: "{{ui_url}}"`.

The game gives the engine five calls:

- `launch` sets up the window and the step rate. The cards game keeps the
  defaults.
- `init` gives the first Model and the first Commands.
- `loaded` puts the meshes of a Pack into the Model. The cards game has no
  `assets/` folder, so it draws each card as a plane.
- `step` gives the next Model from the Input, once for each fixed step.
- `view` gives the Scene that the engine draws: the camera, and the Lights
  and the Draws in `Scene.nodes`.

Next, read [Important defaults](defaults.md) to avoid the common surprises,
then [The five calls](calls.md).
