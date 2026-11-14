# 0038: A game's Page loads rocco.js and listens for events

Status: accepted, 2026-11-15.

## Context

`scripts/web_package.py` copies the same Default page into every Web build.
A game author may want their own Page, for example a start screen or their
own end screen after `rocco:quit` (ADR 0037). The Default page holds the
engine's start-up code inline: the WebGPU checks, the `Module` hooks, the
load order of `index.data.js` before `index.js`, and the key press that
unlocks miniaudio. Those details can change with the engine.

## Decision

- If `<game dir>/web/` exists, `web_package.py` copies the whole folder into
  the page folder and the zip. Its `index.html` replaces the Default page.
  A file with a reserved name (`index.js`, `index.wasm`, `index.data`,
  `index.data.js`, `rocco.js`) stops the build with an error.
- The start-up code moves into an engine script, `rocco.js`, next to the
  loader in `platform/targets/wasm32`. The Default page uses it too.
- A Page has two hard requirements: `<canvas id="canvas">`, which sokol_app
  finds by its default selector, and a script tag that loads `rocco.js`.
  `web_package.py` checks for both by text search and stops the build if one
  is missing.
- The Page calls `rocco_start()` to start the game. A second call does
  nothing. If `?bridge` is set on `localhost` or `127.0.0.1`, `rocco.js`
  starts the game at once, so a Driver can run any Page.
- `rocco.js` tells the Page what happens through events on `window`:
  - `rocco:ready`, once, after the host draws its first frame. No detail.
  - `rocco:unsupported`, with `{ reason, message }`. `reason` is
    `insecure`, `no-webgpu` or `no-adapter`.
  - `rocco:stopped`, with `{ reason, message }`. `reason` is `load`,
    `canvas`, `abort` or `exit`.
  - `rocco:quit`, as ADR 0037 decides.
- `rocco.js` writes each message to the console and shows nothing itself.
  The Page decides what the player sees.
- `rocco.js` owns the audio unlock on a key press.
- The host gets a platform hook after the first frame. On the web it
  dispatches `rocco:ready`. On native hosts it does nothing.

## Considered options

- Copy the Default page and document what must stay. Rejected: the load
  order and the `Module` hooks would become a contract that every copied
  Page breaks when the engine changes.
- A template with slots. Rejected: it fixes a set of slots before we know
  what authors want to change.
- Callbacks passed to `rocco_start`. Rejected: events match `rocco:quit`,
  and a Page that ignores one still works.
- Cancelable events with a built-in message when no listener cancels.
  Rejected: `rocco.js` would own DOM and styling that every Page opts out of.
- `rocco:ready` when the Emscripten runtime starts. Rejected: the canvas is
  still black until `init` ends and the first frame draws.
- `rocco_start` takes the canvas. Rejected: it changes the host for no gain.

## Consequences

- The `rocco.js` events and `rocco_start()` are a public contract for game
  authors. A change to them breaks every game's Page.
- A Page with no listener for `rocco:unsupported` shows a black tab to a
  player without WebGPU. The guide's example Page listens for all four events.
- A start screen does not block `scripts/screenshot.sh --web` or an agent.
