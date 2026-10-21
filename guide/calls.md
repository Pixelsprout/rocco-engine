---
title: The five calls
summary: Why a rocco game is five pure functions, what each one gets and returns, and the order in which the host calls them.
order: 3
---

# The five calls

When game code can draw, load files and read the keyboard whenever it
likes, it gets hard to test, and its state ends up spread across the
engine. rocco takes a different approach. Your game is a Roc app with five
plain functions: `launch`, `init`, `step`, `loaded` and `view`. The engine
calls them, and in these pages we call the engine the host when we talk
about it from your game's side.

Each call gets plain values and returns plain values. No call has an
effect: it cannot read a file, draw a mesh or ask the engine a question.
Instead, it returns values that describe what it wants, and the host does
the work. Because of this, you can test every call with `roc test`.

Your game keeps all of its state in one value, the Model. You declare the
`Model` type. The host holds the Model for you, but it never reads inside
it. Because the host holds it, hot reload can swap in new code and keep the
game where it was.

## A first look

Here are three of pong's calls. `init` makes the first Model, `loaded` has
nothing to do because pong loads no assets, and `step` moves the game
forward:

<!-- region: examples/pong/main.roc#calls -->
```roc
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |config| {
	model = {
		state: Running,
		cube: Mesh.primitive(Cube),
		left: 0.0,
		right: 0.0,
		ball: { id: ball_id_base, x: 0.0, z: 0.0, vx: 0.0, vz: 0.0 },
		score: { left: 0, right: 0 },
		rng: config.seed,
		serves: 0,
	}

	{ model: serve(model, 1.0), commands: [] }
}

# Pong draws only the cube primitive, so it loads no pack.
loaded : Model, Str, Manifest -> Model
loaded = |m, _pack, _manifest| m

step : Model, Vocabulary.Input, Vocabulary.QueryResults, F32 -> { model : Model, commands : List(Command) }
step = |m, input, _results, dt| { model: update(m, input, dt), commands: [] }
```
<!-- endregion -->

Pong reads the seed from the Config to start its random serves. Its `step`
ignores the QueryResults, because pong asks no Queries.

## What each call gets and returns

| Call | Gets | Returns |
|---|---|---|
| `launch` | the [Config] | a [Launch] |
| `init` | the Config | the first Model and a list of [Command]s |
| `step` | the Model, the [Input], the [QueryResults] and `dt` | the next Model and a list of Commands |
| `loaded` | the Model, a pack name and a [Manifest] | the Model |
| `view` | the Model | a [Scene] |

`dt` is the length of one fixed step in seconds.

### launch

`launch` returns the Launch: the window, the step rate, the shadow map size
and the table capacities. The host reads it once, before the window opens.
Pong changes only the window title:

<!-- region: examples/pong/main.roc#launch -->
```roc
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "pong" } }
```
<!-- endregion -->

See [Launch](launch.md) for each field.

### init and step

`init` returns the first Model and the first Commands. `step` returns the
next Model and the Commands for this step. Most of your game's logic lives
in `step`.

### loaded

`loaded` gets the ids of the assets that a `Load` Command asked for. It is
the only place where you learn those ids, so keep the ones you need in the
Model. See [Assets and Packs](assets.md).

### view

`view` returns the Scene: what the host draws, and the shapes and Queries
that the host tests. It gets only the Model, not the time since the last
step. See [The Scene](scene.md).

## Commands

A Command asks the host to do one thing, once. There are three:

- `Quit` stops the game. The host binds no key to `Quit`, so if you want a
  quit key, return `Quit` from `step` when that key is pressed.
  [Input](input.md) shows an example. A `Quit` from `init` stops only a
  Headless run.
- `Load` loads the assets of a Pack. See [Assets and Packs](assets.md).
- `Unload` drops a Pack. See [Assets and Packs](assets.md).

Use a Command only for something that happens once. For something that
must stay true at each step, such as the mouse lock, use a field of the
Scene.

## Test the calls

Each call is a plain function, so `roc test` can test it. Start a test from
`Config.empty`, `Input.empty` and `QueryResults.empty`, pass the values to
`init` and `step`, and compare the Model that comes back. [Input](input.md)
shows a test that holds a key.

## Fixed steps and frames

A fixed step moves the game forward by one fixed interval of time. The
interval is one over the `step_hz` of the Launch, and the default is 120
steps each second. So `step` gets the same `dt` every time.

A frame is one refresh of the display. In one frame, the host runs as many
fixed steps as the clock needs, which can be zero, and then draws one
picture. Your game never sees frames. [The Scene](scene.md) explains how
the host draws smoothly between two steps.

## The order of the calls

1. The host makes the Config.
2. The host calls `launch` once, before the window opens.
3. The host calls `init` once, with the same Config.
4. The host runs the Commands from `init`, in list order.
5. The host calls `view` once.
6. The host opens the window.
7. For each fixed step, the host calls `step`.
8. The host runs the Commands from `step`, in list order.
9. The host calls `view`.
10. The host goes back to 7 until the game stops.

A `Load` Command calls `loaded` while the host runs the Commands. So the
Model from `loaded` is the Model that the next `view` gets.

[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Input]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Input
[QueryResults]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.QueryResults
[Manifest]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Manifest
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
