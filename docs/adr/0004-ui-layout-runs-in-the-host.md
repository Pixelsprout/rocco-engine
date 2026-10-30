# 0004: UI layout runs in the host

Status: accepted, 2026-10-15. Partly superseded by ADR 0013 on
2026-10-22: the UI crosses the seam as a tree of Elements, not as a flat
stream. The layout decision stands. ADR 0019 on 2026-10-30 gives the
game the window size in Input; the host still lays out. On 2026-10-31,
`Ui.measure`, `Ui.fit` and `Ui.wrap` let the game measure text with a
copy of the host's font table; the host still lays out.

## Context

Games need a UI drawn flat over the 3D view: a key count now, menus and
inventories later. Somebody must lay it out: size the boxes, wrap the text
and anchor panels to the window. The glue cannot carry recursive tag unions,
so a tree of Elements cannot cross the seam as a nested value.

terrocotta (github.com/obust/terrocotta) ports Clay's layout to pure Roc,
so layout inside the platform package is possible.

## Decision

- The host runs C Clay through its Odin bindings. A pinned submodule
  supplies the prebuilt lib per target, copied by the `inputs` step like
  sokol's.
- `Scene.ui` is a flat stream of Elements: `Open(Box)`, `Text`, `Close`.
  The host feeds the stream to Clay's open, configure and close calls in
  order, once per frame, against the window size.
- The host measures text with its one baked font. The game never measures
  and never learns the window size.
- The UI only displays. No layout result flows back to the game.

## Considered options

- Layout in Roc, from terrocotta or a port of it. Games could query bounds
  and hit tests in `step` with no host round trip, and layout would be
  tested with `expect`. It was rejected for now: terrocotta is young, is
  tied to roc-ray types, needs a host call to measure each text run, and
  has no performance data under the new compiler. We would own a layout
  engine.
- A parent index on each Element. "Parents before children" does not give
  the pre-order that Clay needs, so the host would build child lists in
  scratch and check every index. The stream has one error, unbalanced
  Open and Close, and the host repairs it.

## Consequences

- Box fields follow Clay's names and defaults (`Fit`, `Start`), so an empty
  config means the same on both sides.
- Pointer input for the UI reopens this decision. It needs either hit
  results in Input or layout in Roc.
