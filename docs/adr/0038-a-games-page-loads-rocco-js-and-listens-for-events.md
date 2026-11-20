# 0038: A game's Page loads rocco.js and listens for events

Status: accepted, 2026-11-15.
Supersedes: ADR 0039 (A game makes its Web build in its own folder).

## Context

Every Web build got the same Default page. A game author may want their own
Page, for example a start screen or their own end screen after `rocco:quit`
(ADR 0037). The Default page held the engine's start-up code inline: the
WebGPU checks, the `Module` hooks, the load order of `index.data.js` before
`index.js`, and the key press that unlocks miniaudio. Those details change
with the engine.

A Web build also needed a rocco checkout at the game's tag and emsdk. A game
in its own repository had to be copied into a checkout to build for the web.
The platform bundle already holds every target file a Web build needs.

## Decision

- `scripts/rocco_web.py` makes a Web build from a game folder. It runs
  `roc build --target=wasm32` and writes the page folder and the itch.io
  zip. Each release uploads it as an asset. `build.roc web <name>` builds
  the web host if there is none, then runs it.
- It finds the platform through the `platform "..."` string in the game's
  `main.roc`: a local path, or a release URL that Roc has unpacked into its
  cache. `--platform <dir>` overrides both. It reads every target file from
  the platform's `targets/wasm32/`.
- It packs `assets/` in Python, so a game needs no emsdk.
- The start-up code lives in an engine script, `scripts/web/rocco.js`, which
  the web host build copies into the platform. The Default page uses it too.
- If `<game dir>/web/` exists, its files replace the Default page. A Page
  needs `<canvas id="canvas">` and a script tag that loads `rocco.js`. A file
  with a name the build writes stops the build, and so does a missing
  requirement.
- The Page calls `rocco_start()` to start the game. If `?bridge` is set on
  `localhost` or `127.0.0.1`, `rocco.js` starts the game at once, so a Driver
  can run any Page.
- `rocco.js` tells the Page what happens through events on `window`. It
  writes each message to the console and shows nothing itself. The Page
  decides what the player sees.
- `rocco.js` owns the audio unlock on a key press.
- The host gets a platform hook after the first frame. On the web it
  dispatches `rocco:ready`.

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
- `build.roc web <path>` for any folder. Rejected: the game still needs a
  checkout at the same tag and emsdk.
- Ship `rocco_web.py` inside the platform bundle. Rejected: to run it, the
  author must first find the bundle in the Roc cache.
- A loader that reads the EM_ASM offset at load time, and assets fetched at
  run time, so a game needs no package step. Rejected for now: it changes
  the host and the loader.

## Consequences

- The `rocco.js` events and `rocco_start()` are a public contract for game
  authors. A change to them breaks every game's Page.
- A Page with no listener for `rocco:unsupported` shows a black tab to a
  player without WebGPU.
- A start screen does not block `scripts/screenshot.sh --web` or an agent.
- A game needs Roc and Python 3 for a Web build, and no rocco checkout.
  Building the web host still needs emsdk.
- `rocco_web.py` depends on Roc's cache layout. If Roc moves its cache, the
  script stops with the folders it tried, and `--platform` works around it.
- `rocco_web.py` from one release can build a game pinned to another
  release, because it reads every target file from the game's bundle.
