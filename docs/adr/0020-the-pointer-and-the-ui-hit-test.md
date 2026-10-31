# 0020: The pointer and the UI hit test

Status: accepted, 2026-10-31. It amends ADR 0004 and closes its consequence
"Pointer input for the UI reopens this decision". The host still lays out
the UI. Later on 2026-10-31 the `Box` tag became `Panel`. A tagged Box
below is a tagged Panel now.

## Context

Agent Town needs hover, clicks and scrolling logs on its stage. ADR 0004
sent no layout result back to the game, so a game could not tell which Box
is under the pointer, and the Input had no mouse buttons. Clay, which lays
out the UI in the host, already hit tests a pointer and clips its elements.
`ui_frame` ignored Clay's scissor commands, so a Box could not cut its
children.

## Decision

- `Input.pointer : { x, y, inside, held, pressed, released, wheel }`. The
  position is in logical window pixels, with the origin at the top left.
  `inside` is false when the pointer is outside the window, or while
  `Scene.cursor` is `Locked`. Then the position keeps its last value. The
  buttons follow the rules of the keys, with `pf.MouseButton` naming the
  codes `Left` 0, `Right` 1 and `Middle` 2. `wheel` is in the units that
  the OS gives. `Input.mouse` stays for mouse look.
- `BoxConfig.id : U64` tags a Box for the hit test. 0 is not tagged.
- `BoxConfig.overflow : [Visible, Clip, Scroll({ x, y })]`. `Clip` cuts the
  children at the Box edges. `Scroll` cuts them and moves them by the offset
  from the Scene. The UI pass applies Clay's scissor commands as one clip
  rect per run of quads.
- `Float({ to : [Window, Parent], attach, on, offset })`. A floating Box
  puts its `attach` point on the `on` point of the window or of its parent.
- `QueryResults.ui : { over, scroll }`. After each Frame's layout, the host
  hit tests the pointer of the last step with `Clay_SetPointerState`, at the
  dpi of the layout. `over` lists the tagged Boxes under it, innermost
  first. `scroll` lists each tagged `Scroll` Box with its view size and its
  content size. Both arrive every step with no Query, as Contacts do for
  their Queries.
- A floating Box blocks the pointer when it, or any Box inside it, has a
  non-zero `id`. A floating Box with no tagged Box inside it lets the
  pointer through. The host gives the first kind Clay's `Capture` mode and
  the second kind `Passthrough`.
- The game owns the scroll offset. The host never feeds a wheel delta or a
  drag to Clay, and keeps external scroll handling off, so Clay lays out
  from the Scene's offset.
- Clay holds at most 100 clip records, and only its scroll update removes
  them. The host calls the update twice after each layout, with drag off
  and a zero delta, so no record outlives its layout. A kept record points
  at a reused element and takes the sizes of a new Box.
- A repeated `id` logs once. The host gives the second Box Clay's automatic
  id, so it is laid out and drawn but never appears in `over` or `scroll`.
- The Bridge `step` request takes a `pointer` with `x`, `y`, `inside`,
  `held`, `tap` and `wheel`. Pressed and released follow from `held` across
  steps, as for keys and pads. A request with no pointer gives one that is
  outside the window with no button held. The `scene` reply's results carry
  `ui`. `BRIDGE_PROTOCOL` becomes 4.

## Considered options

- Layout in Roc. Rejected again: Roc can now measure text, but a full
  layout in Roc means owning a layout engine.
- Hit results in Input. Rejected: they are facts about the previous Scene,
  as Contacts are, so they belong in QueryResults.
- A hit Query per Box. Rejected: a UI needs the results every step, and a
  Query per Box repeats the tree in `Scene.queries`.
- Clay's own scroll state, with the wheel and drag fed to it. Rejected: the
  host would keep UI state that the game cannot see or save.
- Every floating Box blocks the pointer, Clay's default. Rejected: an
  untagged label or HUD panel would hide the Boxes under it.
- No floating Box blocks the pointer. Rejected: a click on a menu item
  would also reach the button under the menu.

## Consequences

- `over` lags by one step. Step N gets the Boxes under the pointer of the
  last step before the Frame's layout, against the layout that the window
  showed. A new Box appears in `over` one step after the Scene that adds
  it. Every step of one Frame gets the same `ui`.
- This is a Vocabulary change. The host and every game rebuild. An Odin
  literal of a Box config must set `overflow`, and a Float must set `to`,
  because the zero values of their tags are `Clip` and `Parent`.
- The Driver protocol rises to 4.
- The widgets in the platform and real devices through the Bridge build on
  this: the first reads `over` and `scroll`, the second lets a person's
  clicks reach a game that a Driver steps.
