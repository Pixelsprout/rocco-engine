---
title: The five calls
summary: The five functions that your game gives the engine, the order in which the host calls them, and what each one returns.
order: 2
---

# The five calls

Your game is a Roc app. It gives the engine five functions: `launch`,
`init`, `step`, `loaded` and `view`. In these pages, the host is the engine
seen from your game. The host calls the five functions.

Each call gets plain values and returns plain values. No call has an
effect. A call cannot read a file, draw a mesh or ask the engine a
question. The host does those things from the values that the calls return.

Your game keeps all of its state in one value, the Model. You declare the
`Model` type. The host holds the Model and never reads inside it.

## What each call gets and returns

| Call | Gets | Returns |
|---|---|---|
| `launch` | the [Config] | a [Launch] |
| `init` | the Config | the first Model and a list of [Command]s |
| `step` | the Model, the [Input], the [QueryResults] and `dt` | the next Model and a list of Commands |
| `loaded` | the Model, a pack name and a [Manifest] | the Model |
| `view` | the Model | a [Scene] |

`dt` is the length of one fixed step in seconds.

## The order of the calls

1. The host makes the Config.
2. The host calls `launch` once, before the window opens.
3. The host calls `init` once, with the same Config.
4. The host runs the Commands from `init` in list order.
5. The host calls `view` once.
6. The host opens the window.
7. For each fixed step, the host calls `step`.
8. The host runs the Commands from `step` in list order.
9. The host calls `view`.
10. The host goes back to step 7 until the game stops.

A `Load` Command calls `loaded` while the host runs the Commands. So the
Model from `loaded` is the Model that the next `view` gets.

## Fixed steps and frames

A fixed step moves the game forward by one fixed interval. The interval is
one over the `step_hz` of the Launch. The default is 120 steps each second.
So `step` gets the same `dt` each time.

A frame is one refresh of the display. In one frame, the host runs zero or
more fixed steps, as the clock needs. Then it draws one picture. Your game
does not see frames. [The Scene](scene.md) tells how the host draws between
two steps.

## launch

`launch` returns the Launch: the window, the step rate, the shadow map size
and the table capacities. The host reads it once. Pong changes only the
window title:

<!-- region: examples/pong/main.roc#launch -->
```roc
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "pong" } }
```
<!-- endregion -->

[Launch](launch.md) tells about each field.

## init, loaded and step

`init` returns the first Model and the first Commands. `step` returns the
next Model and the Commands for this step. These are the three calls in
pong:

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

Pong reads the seed from the Config to start its random serves. Its
`loaded` returns the Model unchanged, because pong loads no Pack. Its
`step` ignores the QueryResults.

## view

`view` returns the Scene: what the host draws, and what the host tests for
the Queries. `view` gets only the Model. It does not get the time since the
last step. [The Scene](scene.md) tells about the fields.

## Commands

A Command tells the host to do one thing one time. There are three
Commands:

- `Quit` stops the game. The host binds no key to `Quit`. If you want a
  quit key, return `Quit` from `step` when the key is pressed.
  [Input](input.md) shows an example. A `Quit` from `init` stops only a
  Headless run.
- `Load` loads the assets of a Pack. See [Assets and Packs](assets.md).
- `Unload` drops a Pack. See [Assets and Packs](assets.md).

A Command is for a thing that happens once. For a thing that must be true
at each step, such as the mouse lock, use a field of the Scene.

## Test the calls

Each call is a plain function, so `roc test` can test it. Start a test
from `Config.empty`, `Input.empty` and `QueryResults.empty`. Give the test
values to `init` and `step`. Then compare the Model. [Input](input.md) shows
a test that holds a key.

[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Input]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Input
[QueryResults]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.QueryResults
[Manifest]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Manifest
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
