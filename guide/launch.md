---
title: Launch
summary: The fields of the Launch, their defaults, the checks at startup, and what a run mode overrides.
order: 8
---

# Launch

Some decisions must hold before the window opens, and cannot change after
it opens. Your game makes them in `launch`, which returns a [Launch]. The
host calls `launch` once, before `init`, and never again. Hot reload does
not call it again.

## Start from the default

[`Launch.default`][Launch.default] is the Launch that most games want. To
keep all of it, return it, as the entity game does:

<!-- region: examples/entity-game/main.roc#launch -->
```roc
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| Launch.default
```
<!-- endregion -->

To change a field, start a record update from the default. Pong changes
only the title of its window:

<!-- region: examples/pong/main.roc#launch -->
```roc
launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| { ..Launch.default, window: { ..Launch.default.window, title: "pong" } }
```
<!-- endregion -->

`launch` gets the [Config], so a Launch can follow the Args. For example, a
game can open fullscreen when its Args hold `--fullscreen`.

## The fields

The [Launch], [Window] and [Capacity] types tell what each field means.

| Field | Default | A run mode overrides it |
|---|---|---|
| `window.width`, `window.height` | 960 by 540 | Headless lays out the UI at this size and opens no window. |
| `window.title` | `"rocco"` | Headless ignores it. |
| `window.fullscreen` | `False` | Headless ignores it. |
| `window.high_dpi` | `True` | Headless lays out the UI at a DPI scale of 1. |
| `window.samples` | `X4` | Headless ignores it. |
| `window.vsync` | `True` | Lockstep and Headless turn vsync off. |
| `step_hz` | 120 | No |
| `shadow_map` | 2048 | No |
| `capacity.meshes` | 64 | No |
| `capacity.skies` | 16 | No |
| `capacity.draws` | 16384 | No |
| `capacity.ui_quads` | 16384 | No |

[Running and debugging](running.md) tells about the run modes. Each field
changes only when the game starts again. Today, no [Scene] field changes a
field of the Launch.

## The checks at startup

The host checks the Launch before it opens the window. A number field must
not be zero. Each capacity must be inside its limits. If a field fails, the
host prints the name of the field and the rule. Then it exits with code 1.
For example:

```text
Launch.capacity.meshes must be at least 4, for the Fallback mesh and the three Primitives, so the run ends
```

`launch` cannot fail by itself. A `Quit` from `init` does not stop a
windowed run yet. So if your game rejects its Args, return `Quit` from the
first `step`.

## Past a capacity

A capacity sets the size of a table. During the run, the host does not stop
when a table is full. It logs once and continues:

- `meshes` or `skies`: a `Load` gives the new name id 0.
- `draws`: the host draws the first Draws of the Scene and drops the rest.
- `ui_quads`: the host draws the first quads of the UI and drops the rest.

[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Window]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Window
[Capacity]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Capacity
[Launch.default]: https://pixelsprout.dev/projects/rocco/api/platform/Launch/#Launch.default
