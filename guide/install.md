---
title: Install and first run
summary: Install Roc, then build and run a first rocco game from the release bundles.
order: 1
---

# Install and first run

To make a rocco game, you need only Roc. You do not need Odin, sokol or a C
compiler. Each rocco release has the engine prebuilt for macOS arm64, Linux
x64 and Windows x64.

If you read this page on GitHub, the Roc nightly and the bundle URLs show as
markers in double braces. Get the values from the notes of the
[latest release](https://github.com/Pixelsprout/rocco-engine/releases/latest).
The notes give the Roc nightly and the URL of each bundle.

## Install Roc

Roc changes from one nightly to the next. Use the nightly that the release
names.

1. Download the Roc nightly `{{roc_nightly}}` for your OS from the
   [Roc nightlies](https://github.com/roc-lang/nightlies/releases).
2. Extract the archive.
3. Add the folder that holds `roc` to your `PATH`.
4. Run `roc version`. Make sure that it prints `{{roc_nightly}}`.

On Linux, the game needs an X11 desktop and an OpenGL driver. On Windows,
run `roc` in a shell where `LIB` is not set. A Visual Studio developer
prompt sets `LIB`, and then the link fails.

## Make the game folder

1. Make a folder with the name `my-game`.
2. Download the source code of the
   [latest release](https://github.com/Pixelsprout/rocco-engine/releases/latest).
3. Copy its `packages/camera/` folder to `my-game/camera/`. The release has
   no bundle for the camera package.
4. Make the file `my-game/main.roc`.
5. Put this header at the top of `my-game/main.roc`:

```roc
app [init, launch, loaded, step, view] { cam: "camera/main.roc", mesh: "{{mesh_url}}", pf: platform "{{platform_url}}", roc: "{{roc_nightly}}" }
```

6. Below the header, add this code. It is the cards game from
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

# The BRDF divides diffuse light by pi, so 5.03 (1.6 pi) lights a white surface facing it to 1.6.
lights : List(Vocabulary.Light)
lights = [
	Light.ambient({ r: 0.2, g: 0.2, b: 0.2 }),
	Light.directional({ x: -2.0 / 7.0, y: -3.0 / 7.0, z: -6.0 / 7.0 }, { r: 5.03, g: 5.03, b: 5.03 }),
]

view : Model -> Vocabulary.Scene
view = |m| {
	draws = List.map_with_index(
		m.hand,
		|card, i| {
			tint = match card {
				Ace => { r: 1.0, g: 0.787, b: 0.033 }
				King => { r: 0.604, g: 0.033, b: 0.033 }
				Number(_) => { r: 0.787, g: 0.787, b: 0.787 }
			}
			# The slot index is the draw id: a card slides to its slot when dealt.
			{ ..Draw.default, id: i, mesh: m.card_mesh, pos: { x: i.to_f32() * 1.2, y: 0.0, z: 0.0 }, scale: { x: 1.0, y: 1.0, z: 1.4 }, tint }
		},
	)
	{ ..Scene.empty, camera: Cam.look_at({ x: 0.0, y: 8.0, z: 8.0 }, { x: 0.0, y: 0.0, z: 0.0 }), draws, lights }
}
```
<!-- endregion -->

The header names the platform and each package that the game uses. `pf` is
the rocco platform. `mesh` gives the primitive meshes, and `cam` points the
camera. A game that uses vectors adds `linalg: "{{linalg_url}}"`. A game
that uses the UI layout adds `ui: "{{ui_url}}"`.

The game gives the engine five calls:

- `launch` gives the window and the step rate. This game uses the defaults.
- `init` gives the first Model and the first Commands.
- `loaded` puts the meshes of a Pack into the Model. This game has no
  `assets/` folder, so it uses a plane for each card.
- `step` gives the next Model from the Input, once for each fixed step.
- `view` gives the Scene that the engine draws: the camera, the draws and
  the lights.

## Run the game

In `my-game/`, run:

```sh
roc main.roc
```

The first run downloads the bundles and builds the game. A window opens and
shows two cards. Press Space to add a card. Close the window to stop the
game.
