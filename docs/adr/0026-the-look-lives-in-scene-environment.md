# 0026: The look lives in Scene.environment

Status: accepted, 2026-11-04.

## Context

The tone map moved out of the mesh shader into a Post pass, so a game can
choose its tone map and exposure, and add fog and bloom. Before that, the
Scene had two loose fields for the look, `sky` and `clear`, and the mesh
shader ended in a fixed ACES fit. Each new effect would add one more Scene
field, and a Theme that changes the look per level would have to set each
one.

`Config` goes from the host to the game, so it cannot carry a choice the
other way. A one-time Command at start-up could, but then a Theme could not
change the look per level, and the look would be the only part of the
picture that is not a Description.

## Decision

- The Scene holds one record, `environment : Environment`, with the sky, a
  Sky blend, the clear colour, the tone map, exposure, fog and bloom.
  `Scene.empty` holds `Environment.default`: no sky, a black clear colour,
  ACES, exposure 1, and every effect off.
- Fog, fog on the sky, the Sky blend and bloom are plain records, not
  `[None, Fog(...)]` unions. The default value of one field turns each off:
  an amount or a strength of 0. Their other defaults are a starting point,
  so a game turns one on by raising that field alone.
- The host takes the Environment from the current Scene, with no
  interpolation, as it takes the Cursor and the UI. A game that wants a fade
  writes the in-between values itself.
- Everything in the HDR target goes through the tone map: lit and unlit
  surfaces, the sky and the clear colour. The Post pass multiplies by
  `exposure`, applies the tone map (ACES, AgX or Khronos PBR Neutral) and
  encodes sRGB.
- The UI draws after the tone map in the Post pass, so the Environment
  never changes a UI colour.
- A Sky blend renders both skies' light into blend cubes, so the Surface
  shader contract keeps its slots.
- The host corrects a bad value and logs it once per run. The Bridge
  `scene` op shows the record as the game wrote it.

## Considered options

- One Scene field per effect, such as `Scene.tone_map` and `Scene.fog`.
  Rejected: the Scene grows with each effect, and `Scene.empty` must name
  each default.
- A one-time Command at start-up. Rejected: the look could not change per
  level, and it would be the only part of the frame that a Description does
  not hold.
- Interpolate the Environment between Scenes. Rejected for now: a tone map
  is a tag and cannot blend, and an exposure change of one step is not
  visible at 60 Hz. A game can step the numbers itself.
- Keep the UI under the tone map. Rejected: a UI colour would not show as
  authored, and an exposure change would dim the UI.
- `fog : [None, Fog({ color, start, end })]` and the same for bloom.
  Rejected: `docs/roc-style.md` rules out `None` as an empty case, and a
  game would rebuild every field to turn an effect on.
- `fog : [Off, Linear({...})]`, which leaves room for exponential fog.
  Rejected: fog would be the one effect whose default is not an ordinary
  value. Exponential fog can add a field later.

## Consequences

- A new effect fills a field of the record, not a new Scene field.
- The host maps each tone map tag to a shader branch through one table, so
  a new tone map changes the table and not the shader's numbers.
- A zero `Environment` in Odin has exposure 0, which the host corrects and
  logs. Host tests start from a copy of `Environment.default`.
- The fog and bloom passes skip their work when the effect is off.
