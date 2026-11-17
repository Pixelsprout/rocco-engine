# 0040: The Tour interprets games in the browser

Status: accepted, 2026-11-17.

## Context

The Tour lets a reader edit a game and run it in a Preview. The site is
static. No published Roc browser build writes wasm: Roc's echo, REPL and
playground modules, and roclet, all check, lower to LIR and interpret.
Measured on desktop, Roc's interpreter runs a Tutorial game's `step` and
`view` in about 1.7 to 4 ms per frame in a browser. It is about 5 us per
entity per step, so heavy games and slow phones do not fit.

Research: branches `research/tour-roc-compiler-in-browser`,
`research/tour-link-game-with-web-host`, `research/tour-interpreter-spike`
and `research/tour-web-host-restart-and-assets`.

## Decision

- A compile worker in the Tour page checks the reader's game and lowers it
  to a wasm32 LIR image. It lives for the whole visit, so its cache of the
  checked platform and packages stays warm.
- rocco owns the compile worker: a small Zig embedding of the pinned Roc
  compiler, in roclet's style. CI rebuilds it when the Roc pin moves.
- The compile worker reads the platform and package sources from a source
  bundle that ships beside it.
- On Run, the page starts a new iframe with a Tour host: a web host build
  with Roc's interpreter linked in. The Tour host runs the LIR image. The
  interpreter writes values through the host's `roc_alloc`, so the host
  reads the Scene and Commands with no copy.
- Normal Web builds do not change and do not contain the interpreter.
- Tour steps stay within the interpreter's budget: the Tutorial games and
  small examples.

## Considered options

- Port Roc's wasm backend to the browser and join the game to the web host
  as a second module on one memory. Rejected for now: no upstream build does
  this, and the port is the most work and risk. It stays the upgrade if
  upstream Roc writes wasm in the browser.
- Compile on a server with the native `roc build --target=wasm32`.
  Rejected: the site stops being static, and a public compile service needs
  hosting and abuse limits.
- Link the compiler, the interpreter and the host into one module in the
  iframe. Rejected: each Run would pay a cold check (about 0.3 to 0.6 s) and
  a larger download.
- Put the interpreter in every web host. Rejected: Web builds would grow for
  a feature only the Tour uses.

## Consequences

- A Preview is not a Web build. Speed and failures can differ from the Web
  build of the same source.
- The Tour cannot show heavy examples such as `village`, and it is
  borderline on phones.
- rocco carries its Roc patches (compile worker cache, interpreter shim)
  as one patch file each, in one directory beside the compile worker. The
  build applies them to a copy of the pinned Roc source. Each file names
  its upstream status. The Tour never waits for upstream Roc.
- A Roc pin move fails in CI if a carried patch does not apply. When
  upstream takes a change, the pin move deletes that patch file.
