# 0007: A fifth call, launch, runs before the window opens

Status: accepted, 2026-10-20.

## Context

Some decisions must hold before the window and the GPU exist, and cannot
change after: the window size, `high_dpi`, the MSAA sample count, vsync, the
fixed step rate, the shadow map size and the table capacities. Each was a
host constant, so every game got 960 by 540, no `high_dpi`, 4x MSAA, 120 Hz,
a 2048 shadow map and the same tables. Nothing went from the game to the
host before `init`. Config goes the other way.

## Decision

- The game defines a fifth required function, `launch : Config -> Launch`.
  The host calls it once, before `init` and before the window opens, with
  the same Config that `init` gets. Hot reload does not call it again.
- Launch is `{ window : Window, step_hz : U32, shadow_map : U32, capacity :
  Capacity }`. Window is `{ width : U32, height : U32, title : Str,
  fullscreen : Bool, high_dpi : Bool, samples : Msaa, vsync : Bool }` with
  `Msaa : [Off, X2, X4, X8]`. Capacity is `{ meshes : U32, skies : U32,
  draws : U32, ui_quads : U32 }`.
- `pf.Launch.default` is today's constants with one change: `high_dpi` is
  on. A game that wants the defaults writes `launch = |_config|
  Launch.default`.
- `launch` cannot fail. The host exits with the field's name on a zero in
  any numeric field, or on `ui_quads` past 16,384, the u16 index bound. A
  game that rejects its Args does so from `init` with `Quit`.
- Where the person's run mode meets Launch, the run mode wins. Lockstep
  turns vsync off. Headless opens no window and lays out the UI against
  Launch's width and height at dpi 1.

## Considered options

- A project file beside the game, such as `rocco.toml`. Rejected. It moves
  the decision out of Roc, it cannot read the Args, and `roc test` cannot
  see it.
- A zero-argument value, `launch : Launch`. Rejected. It cannot read the
  Args, so `--fullscreen` stops being the game's decision, and the Odin
  glue has not emitted a zero-argument procedure.
- A third field on the `init` result, `{ model, commands, launch }`.
  Rejected. A `Load` in init's Commands fills the mesh table that the same
  value sizes, so the host must hold the Commands, allocate, then run them,
  and that order hides inside one record. Two calls make the order visible,
  and `init` keeps one job.

## Consequences

- This is a Vocabulary change. It rebuilds the host and every game. Kula
  adds one line when it moves to the next bundle.
- `fullscreen` and `title` in Launch are start-up values. A later
  `Scene.window` may carry their run-time state. When it does, the host
  toggles fullscreen when the game's value changes between two Scenes, and
  never because it differs from the OS, because the person may use the OS's
  own fullscreen button. The Launch value is the baseline for the first
  Scene. The cursor lock adopts the same rule then.
- The shadow biases, the normal offset and the PCF kernel are shader knobs
  and can change per level, so they go to the Look record (dex yjtqgdd4).
  The cascade count sizes a shader array and stays an engine constant.
- `extensions` waits for the extension ABI. A field with no reader has no
  test and no known shape.
- A game cannot print a usage line for bad Args. A `Quit` that carries a
  reason is the natural later Command change.
- Past a capacity at run time, the host keeps today's rule: log once, draw
  the first N.
