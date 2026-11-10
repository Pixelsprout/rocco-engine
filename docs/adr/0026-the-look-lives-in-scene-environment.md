# 0026: The look lives in Scene.environment

Status: accepted, 2026-11-04. Milestone 37.

## Context

Milestone 37 moves the tone map out of the mesh shader into a Post pass, so
a game can choose its tone map and exposure, and later add fog and bloom.
Before it, the Scene had two loose fields for the look, `sky` and `clear`,
and the mesh shader ended in a fixed ACES fit. Each new effect would add
one more Scene field, and a Theme that changes the look per level would
have to set each one.

`Config` goes from the host to the game, so it cannot carry a choice the
other way. A one-time Command at start-up could, but then a Theme could not
change the look per level, and the look would be the only part of the
picture that is not a Description.

## Decision

- The Scene loses `sky` and `clear` and gains one record,
  `environment : Environment`, with `sky`, `clear`, `tone_map`, `exposure`,
  `fog` and `bloom`. `Scene.empty` holds `Environment.default`: no sky, a
  black clear colour, ACES, exposure 1, no fog and no bloom.
- Fog and bloom are plain records, not `[None, Fog(...)]` unions. The
  default value of one field turns each off: a fog `amount` of 0 and a
  bloom `strength` of 0. Their other defaults are a starting point, so a
  game turns one on by raising that field alone.
- The host takes the Environment from the current Scene, with no
  interpolation, as it takes the Cursor and the UI. A game that wants a fade
  writes the in-between values itself.
- Everything in the HDR target goes through the tone map: lit and unlit
  surfaces, the sky and the clear colour. The Post pass multiplies by
  `exposure`, applies the tone map (ACES, AgX or Khronos PBR Neutral) and
  encodes sRGB.
- The UI draws after the tone map in the Post pass, so the Environment
  never changes a UI colour.
- The host clamps a bad value and logs it once per run: an exposure at or
  below 0 draws with 1, a fog `amount` outside 0 to 1 is clamped into it,
  and a negative bloom number draws as 0. With fog on, a NaN `start` draws
  as 0 and an `end` at or below `start` moves at least 0.001 past it. The Bridge `scene` op shows the record as the game
  wrote it, and its protocol goes to 10.

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
  game would rebuild every field to turn an effect on. A tag such as
  `NoFog` or `Off` reads badly in a record update.
- `fog : [Off, Linear({...})]`, which leaves room for exponential fog.
  Rejected: fog would be the one effect whose default is not an ordinary
  value. Exponential fog can add a field later.

## Consequences

- One Vocabulary change now, and none for fog or bloom, which fill fields
  the record already has.
- A game that set `sky` or `clear` writes
  `environment: { ..Environment.default, sky: ... }`.
- The glue numbers the tags of `tone_map` in name order. The host maps each
  tag to a shader branch through one table, so a new tone map changes the
  table and not the shader's numbers.
- A zero `Environment` in Odin has exposure 0, which the host clamps and
  logs. Host tests start from a copy of `Environment.default`.
- The fog and bloom passes test `amount > 0` and `strength > 0` to skip
  their work.

## Later changes

- 2026-11-11: Environment gained `sky_blend` (a second sky and an amount)
  and `fog.sky` (fog on the sky by height). Both are off by default, like
  fog and bloom. A blend renders both skies' light into blend cubes, so the
  Surface shader contract keeps its slots. See docs/ENVIRONMENT-LIGHTING.md.
