# 0007: A fifth call, launch, runs before the window opens

Status: accepted, 2026-10-20.
Supersedes: ADR 0006 (Config carries the command line).

## Context

Some decisions must hold before the window and the GPU exist, and cannot
change after: the window size, `high_dpi`, the MSAA sample count, vsync,
the fixed step rate, the shadow map size and the table capacities. Each was
a host constant, so every game got the same values. Nothing went from the
game to the host before `init`. Config goes the other way.

## Decision

- The game defines a fifth required function, `launch : Config -> Launch`.
  The host calls it once, before `init` and before the window opens, with
  the same Config that `init` gets. Hot reload does not call it again.
- The game reads its command line from `Config.args`. The host does not
  parse it.
- `pf.Launch.default` holds the defaults. A game changes a field with a
  record update from it.
- `launch` cannot fail. The host exits with the field's name on a bad
  value. A game that rejects its Args does so from `init` with `Quit`.
- Where the person's run mode meets Launch, the run mode wins.

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
- Build a bench size into each game as a constant, or encode it in the
  Seed. Rejected. A constant needs a rebuild per size, and the Seed would
  then mean two things.

## Consequences

- `fullscreen` and `title` in Launch are start-up values. If a later
  `Scene.window` carries their run-time state, the host toggles fullscreen
  only when the game's value changes between two Scenes, never because it
  differs from the OS. The person may use the OS's own fullscreen button.
- Shader knobs that can change per level, such as the shadow biases, belong
  in the Scene, not in Launch.
- A game cannot print a usage line for bad Args. A `Quit` that carries a
  reason is the natural later Command change.
- Past a capacity at run time, the host logs once and draws the first N.
