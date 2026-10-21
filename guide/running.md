---
title: Running and debugging
summary: Run, check and test a game with roc, use hot reload and know its limits, and set the ROCCO_ variables.
order: 9
---

# Running and debugging

Use the `roc` command to run, check and test your game. Run each command in
the folder that holds `main.roc`.

| Command | Does |
|---|---|
| `roc main.roc` | Builds the game with the dev backend and runs it. |
| `roc run main.roc -- <args>` | The same, and gives the words after `--` to the game as `args` in the [Config]. |
| `roc check main.roc` | Finds type errors and does not build. |
| `roc test main.roc` | Runs each `expect` in the game. |

The dev backend builds fast. [Shipping a game](shipping.md) tells how to
make a fast binary.

The host writes its log lines to the terminal. Each problem that the host
repairs, such as a misspelt asset name, gives one log line. If the game
looks wrong, read the log. A `dbg` in your Roc code also prints to the
terminal. [`Mesh.resolve`][Mesh.resolve] prints the name with `dbg` when
the name is not in the [Manifest].

When the game stops, the host prints `Frame Count: N`, the number of frames
that it ran.

## Hot reload

Hot reload changes the code of a running game and keeps its Model.

1. Run `roc run main.roc`.
2. Change `main.roc` and save it.
3. The running game uses the new code from its current Model.

Hot reload has these limits:

- Do not change the `Model` type. The host cannot see the layout of the
  Model, so new code that reads the old Model is undefined. After a change
  to the `Model` type, start the game again.
- The host does not call `launch` or `init` again. After a change to
  `launch` or `init`, start the game again.
- Hot reload needs the dev backend, which is the default of `roc run`.
- rocco tests hot reload only on macOS.

## The ROCCO_ variables

Set a variable before the command, for example
`ROCCO_SEED=7 roc main.roc`. The host checks the values of `ROCCO_SEED`,
`ROCCO_EXIT_AFTER_FRAMES`, `ROCCO_LOCKSTEP` and `ROCCO_HEADLESS`. If one of
them is not valid, the game prints the rule and exits with code 1.
`ROCCO_DEBUG_CAMERA` and `ROCCO_ALLOC_REPORT` are on only for the value
`1`.

| Variable | Effect |
|---|---|
| `ROCCO_SEED=N` | Sets `seed` in the Config. N is an unsigned 64-bit integer. The default is 0. |
| `ROCCO_DEBUG_CAMERA=1` | Gives a fly camera. The host ignores `camera` and `cursor` in the [Scene], and locks the mouse. |
| `ROCCO_EXIT_AFTER_FRAMES=N` | Stops the game after N frames, with exit code 0. N is a positive integer. |
| `ROCCO_LOCKSTEP=1` | Lockstep: each frame runs one fixed step and draws once, whatever the time. Turns vsync off. `0` is the real clock. |
| `ROCCO_HEADLESS=1` | Headless: Lockstep with no window and no GPU. Needs `ROCCO_EXIT_AFTER_FRAMES`. |
| `ROCCO_ALLOC_REPORT=1` | Prints one line for each fixed step: the Roc allocations, frees and reallocations, the live blocks, and the time of `step` and `view` in microseconds. |
| `ROCCO_ASSETS=path` | Gives the path of the `assets` folder. See [Assets and Packs](assets.md). |

`ROCCO_SPANS_CSV` is only for a host that an engine developer builds with
Spans. The host in a release stops with exit code 1 if it is set.

### The debug camera

The debug camera flies with W, A, S and D. The mouse turns it. The game
still gets all of the [Input], so these keys also move your game. Use the
debug camera to look at a Scene from a different place.

### Lockstep and Headless

In Lockstep, each frame runs exactly one fixed step. So the same run does
the same work each time, at any speed. Use it with a fixed seed to repeat a
run.

Headless runs the game with no window. The host still calls each function,
runs the Commands, calls `loaded` and answers the Queries. It draws nothing,
and it lays out the UI at the size in the [Launch] with a DPI scale of 1. Use it to
run a game in a script or in CI. For example:

```sh
ROCCO_HEADLESS=1 ROCCO_EXIT_AFTER_FRAMES=600 ROCCO_SEED=7 roc main.roc
```

The game gets no key presses in Headless, because it has no window.

[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Manifest]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Manifest
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Input]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Input
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Mesh.resolve]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.resolve
