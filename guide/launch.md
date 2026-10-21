---
title: Launch
summary: The choices your game makes once before the window opens, their defaults, the checks at startup, and what a run mode overrides.
order: 9
---

# Launch

Some choices have to be made before the window opens, and can't change
once it is open: the window size, the step rate, the size of the shadow map
and of each table. Your game makes these choices in `launch`, which returns
a [Launch].

The host calls `launch` once, before `init`, and never again. Hot reload
doesn't call it again either, so restart the game after you change
`launch`.

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

## The checks at startup

The host checks the Launch before it opens the window. No number field can
be zero, and each capacity must be inside its limits. If a field fails, the
host prints the name of the field and the rule, then exits with code 1. For
example:

```text
Launch.capacity.meshes must be at least 4, for the Fallback mesh and the three Primitives, so the run ends
```

`launch` itself cannot fail. If your game wants to reject its Args, return
`Quit` from the first `step`, because a `Quit` from `init` does not stop a
windowed run yet.

## Past a capacity

A capacity sets the size of a table. If a table fills up during the run,
the host does not stop. It logs once and carries on:

- `meshes` or `skies`: a `Load` gives the new name id 0.
- `draws`: the host draws the first Draws of the Scene and drops the rest.
- `ui_quads`: the host draws the first quads of the UI and drops the rest.

## The fields

The [Launch], [Window] and [Capacity] types describe each field.

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

[Running and debugging](running.md) explains the run modes. A field changes
only when the game starts again. No [Scene] field changes a field of the
Launch today.

[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Window]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Window
[Capacity]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Capacity
[Launch.default]: https://pixelsprout.dev/projects/rocco/api/platform/Launch/#Launch.default
