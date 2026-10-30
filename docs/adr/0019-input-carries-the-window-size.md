# 0019: Input carries the window size

Status: accepted, 2026-10-30. It replaces the rule of ADR 0004 that the
game never learns the window size. The host still lays out the UI.

## Context

ADR 0004 kept the window size away from the game, because the host lays
out the UI and the game had no other use for it. `Camera.project` in
packages/camera now gives a game a use: it turns a world point into window
pixels, so a game can float a label over a character. It needs the size of
the window the host draws into. Agent Town's stage guessed 1280 by 800, so
its labels drifted toward the top left of a resized window.

The host already reads `sapp.width()`, `sapp.height()` and
`sapp.dpi_scale()` once per frame, to lay out the UI and to set the aspect
of the camera.

## Decision

- `Input` gains `window : { width : F32, height : F32 }`, in logical
  pixels: `sapp.width()` and `sapp.height()` over `sapp.dpi_scale()`. It
  is the record that `Camera.project` takes.
- The host reads it once per frame, so it follows a resize, and every
  step of a frame gets the same size.
- Headless gives the Launch width and height, as its layout uses at dpi 1.
  A windowed run under the Bridge gives its real window. The Driver does
  not set the size.
- `Input.empty` has the 960 by 540 window of `Launch.default`.

## Considered options

- The host projects the point. A Box would float at a world point, and
  the host would project it with the camera it draws, which also removes
  the one-step gap between the interpolated camera and the game's camera.
  Rejected for now: it adds an attach mode to the UI and a projection to
  the host, where one Input field is enough.
- The size in physical pixels with the dpi beside it. Rejected: UI sizes
  and `Camera.project` are in logical pixels, so every game would divide.
- The size only in Launch or Config. Rejected: it cannot follow a resize
  or a change to fullscreen.

## Consequences

- This is a Vocabulary change. The host and every game rebuild. A test
  that builds an Input record by hand adds the field; one that starts from
  `Input.empty` does not change.
- The game projects with the camera of its Model, and the host draws an
  interpolated camera, so a projected point can trail the drawn one by up
  to one step.
- A log of `(Input, dt)` now holds the window size, so a replay sees the
  same window.
- `BRIDGE_PROTOCOL` does not change: no request or reply carries the size.
