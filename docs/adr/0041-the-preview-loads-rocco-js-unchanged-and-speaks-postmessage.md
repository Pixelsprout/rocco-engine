# 0041: The Preview loads rocco.js unchanged and speaks postMessage

Status: accepted, 2026-11-17.

## Context

A Run of a Tour step either hot reloads the live Preview or makes a new
same-origin iframe, the Preview, which runs the Tour host (ADR 0040). The
Tour host needs the LIR image from the compile worker before `main` runs.

`rocco.js` (ADR 0038) replaces `window.Module` and has no hooks. Its events
and `rocco_start()` are a public contract for game authors.

## Decision

- The Tour page talks to the Preview only through postMessage, so a later
  cross-origin move is a URL change. The engine repo builds the whole
  Preview document in one folder and owns the protocol. The site treats it
  as a URL that speaks the protocol.
- `rocco.js` does not change. The Preview loader gets the image, keeps it in
  a JS global, and only then adds the `rocco.js` script and calls
  `rocco_start()`. `host.html` has no static `rocco.js` tag, so `?bridge`
  cannot start `main` before the image is there. The Tour host's `main`
  pulls the image through an `EM_JS` call.
- One message carries every image. The first image starts the Tour host and
  becomes the Baseline image. A later image is a hot reload that keeps the Model.
- Each image carries an identity: the image's host boundary digests, its
  erased-callable count, and a build id. The Preview loader compares each
  later identity with the Baseline image, never with the last swapped image,
  because the Model still comes from the first image's `init`. If they
  differ, the Preview refuses the image and the page starts a new Preview.
- CI writes one build id into the compile worker and the Tour host in the
  same build. The Preview loader compares the build id on every image,
  before it starts `rocco.js` or swaps. A mismatch stops the Preview, and
  the page asks the reader to reload the page. `FORMAT_VERSION` and the
  host boundary digests do not cover the shim or the interpreter, so they
  cannot catch a stale compile worker.
- The Preview loader forwards the `rocco.js` events with the same names, and
  reports Roc crashes, `dbg` and `expect` messages. A crash ends the run.
- On `localhost` or `127.0.0.1`, `?image=<url>` makes the Preview loader
  fetch the image itself, so a Driver, CI or `screenshot.sh --web` can run a
  Tour host without the Tour page.

## Considered options

- A hidden Tour hook in `rocco.js`, such as a `Module` merge. Rejected: it
  adds internal surface to a public contract.
- A Tour loader of its own, copied from `rocco.js`. Rejected: the WebGPU
  checks, load order and audio unlock would drift apart.
- The site owns `host.html`. Rejected: the protocol would split across two
  repos.
- One image per Preview, with a new iframe on every Run. Rejected: hot
  reload keeps the Model on most Tutorial literal edits and is faster.
- A separate message for later images. Rejected: the payload is the same.
- The page compares identities. Rejected: the meaning of each digest would
  leave the engine repo.
- No build id; rely on `FORMAT_VERSION` and the digests. Rejected: a
  compile worker from an older deploy can pass both.
- A baked-in `launch` digest in the Tour host for the first image.
  Rejected: CI would lower a game to build the host, and the build id
  already catches a worker from another build.
- A new Preview on a build mismatch. Rejected: a new Preview from the same
  cache fails the same way.
- A static `rocco.js` tag, with `main` waiting on a promise. Rejected: it
  needs Asyncify or a wait in the frame loop.

## Consequences

- The message names and payloads are a contract between this repo and the
  site. A change needs a matching site change in the same engine release.
- The Page checks of `rocco_web.py` (ADR 0038) do not apply to `host.html`,
  which is not a game Page.
