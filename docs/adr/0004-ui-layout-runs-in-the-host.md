# 0004: UI layout runs in the host

Status: accepted, 2026-10-15.
Supersedes: ADR 0019 (Input carries the window size), ADR 0020 (The pointer
and the UI hit test).

## Context

Games need a UI drawn flat over the 3D view: a key count, menus, logs that
scroll. Somebody must size the Panels, wrap the Text and anchor Panels to
the window. Games also need hover, clicks and scrolling, so a game must
learn which Panel is under the Pointer. Clay already lays out, hit tests a
pointer and clips its elements.

## Decision

- The host lays out the UI with C Clay, through its Odin bindings, once per
  Frame against the window size. The UI crosses the seam as a tree of
  Elements (ADR 0014).
- Panel fields follow Clay's names and defaults, so an empty config means
  the same on both sides.
- Input carries the window size in logical pixels, so a game can place
  things in window space, such as a label over a character.
- Input carries the Pointer in logical window pixels. `Input.mouse` stays
  for mouse look.
- After each Frame's layout, the host hit tests the Pointer of the last
  step. `QueryResults.ui.over` lists the tagged Panels under it, innermost
  first. `QueryResults.ui.scroll` gives each tagged Scroll Panel's view and
  content size. Both arrive every step with no Query.
- The game owns the scroll offset. The host never feeds a wheel or a drag
  to Clay.
- A floating Panel blocks the Pointer only when it, or a Panel inside it,
  has a Hit id.
- A repeated Hit id logs once. The second Panel is laid out and drawn but
  never hit.

## Considered options

- Layout in Roc, from terrocotta or a port of Clay. Games could hit test in
  `step` with no host round trip. Rejected: we would own a layout engine.
  The game can still measure text with `Ui.measure`, which uses a copy of
  the host's font table.
- Hit results in Input. Rejected: they are facts about the previous Scene,
  as Contacts are, so they belong in QueryResults.
- A hit Query per Panel. Rejected: a UI needs the results every step, and a
  Query per Panel repeats the tree in `Scene.queries`.
- Clay's own scroll state, fed the wheel and drag. Rejected: the host would
  keep UI state that the game cannot see or save.
- Every floating Panel blocks the Pointer, Clay's default. Rejected: an
  untagged label or HUD panel would hide the Panels under it.
- No floating Panel blocks the Pointer. Rejected: a click on a menu item
  would also reach the button under the menu.
- The host projects a world point for a floating Panel. Rejected: one Input
  field is enough, and the host would need an attach mode and a projection.
- The window size in physical pixels. Rejected: UI sizes and
  `Camera.project` are in logical pixels, so every game would divide.

## Consequences

- `ui.over` lags by one step. A new Panel appears in it one step after the
  Scene that adds it. Every step of one Frame gets the same `ui`.
- The game projects with the camera of its Model, and the host draws an
  interpolated camera, so a projected point can trail the drawn one by up
  to one step.
- Clay keeps clip records that only its scroll update removes. The host
  runs that update after each layout with a zero delta, so no record
  outlives its layout.
