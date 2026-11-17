# 0041: The Preview loads rocco.js unchanged and speaks postMessage

Status: accepted, 2026-11-17. Amended 2026-11-18: a Preview takes later
images for hot reload.

## Context

A Run of a Tour step either hot reloads the live Preview or makes a new
same-origin iframe, the Preview, which runs the Tour host (ADR 0040). The Tour page talks to the Preview only
through postMessage, so a later cross-origin move is a URL change. The Tour
host needs the LIR image from the compile worker before `main` runs.

`rocco.js` (ADR 0038) replaces `window.Module` and has no hooks. Its events
and `rocco_start()` are a public contract for game authors. The spike on
branch `research/tour-end-to-end` did not use `rocco.js`: it set its own
`Module` and copied the image in `onRuntimeInitialized`.

## Decision

- The engine repo builds the whole Preview document in one folder:
  `host.html`, the Preview loader, `rocco.js`, `index.js`, `index.wasm`,
  `index.data` and `index.data.js`. The site treats it as a URL that speaks
  the protocol below.
- `rocco.js` does not change. The Preview loader gets the image, keeps it in
  a JS global, and only then adds the `rocco.js` script and calls
  `rocco_start()`. `host.html` has no static `rocco.js` tag, so `?bridge`
  cannot start `main` before the image is there.
- The Tour host's `main` pulls the image through an `EM_JS` call that
  allocates and copies it. No `Module` hook is needed.
- Messages are `{ type, ... }` objects:
  - Page to Preview: `tour:image { image, identity }`, with the
    `ArrayBuffer` transferred. `identity` holds the image's host boundary
    digests, the Merkle hashes of what `init`, `loaded` and `launch` reach,
    and the erased-callable count. The first image starts the Tour host and
    becomes the baseline. A later image is a hot reload.
  - Preview to page:
    - `tour:waiting`: the Preview loader listens for the image.
    - `rocco:ready`, `rocco:unsupported { reason, message }`,
      `rocco:stopped { reason, message }`, `rocco:quit`: the `rocco.js`
      events, forwarded with the same names and reasons.
    - `tour:crash { message }`, `tour:dbg { text }`, `tour:expect { text }`:
      posted by the glue from `roc_crashed`, `roc_dbg` and
      `roc_expect_failed`. A crash ends the run.
    - `tour:swapped`: after the first game call on a later image. The
      Model is kept.
    - `tour:need-iframe { reason }`: the Preview refuses a later image.
      `reason` is `crashed`, `stopped` (after `rocco:stopped`, `rocco:quit`
      or `rocco:unsupported`), `erased-callable`, `digest`, `init`,
      `loaded` or `launch`.
- The Preview loader compares each later identity with the baseline, never
  with the last swapped image, because the Model still comes from the first
  image's `init`. A refused image does not change the baseline. The engine
  owns this rule; the page only reacts to the reply.
- On `tour:need-iframe`, the page starts a new Preview with its own copy of
  the image. The page sends a copy and keeps the original until it gets a
  reply.
- The page sends later images only after `rocco:ready`, with at most one
  image in flight. While it waits for a reply, a newer edit replaces any
  unsent one.
- The Preview loader applies a later image at the start of a frame callback,
  before the engine's frame, when no game call runs.
- On wasm, a Roc crash throws `ExitStatus` inside the frame callback and
  `onAbort` does not run. The Preview loader catches it, marks the Preview
  crashed, and refuses later images with `crashed`.
- The page sends `tour:image` after `tour:waiting`, never on the iframe's
  `load` event. The page accepts a message only from the current Preview's
  `contentWindow`, which drops late messages from an earlier Run. The Preview
  loader accepts a message only from `window.parent`. The page posts with
  the Preview URL's origin as `targetOrigin`.
- On `localhost` or `127.0.0.1`, `?image=<url>` makes the Preview loader
  fetch the image itself, so a Driver, CI or `screenshot.sh --web` can run a
  Tour host without the Tour page.

## Considered options

- A hidden Tour hook in `rocco.js`, such as a `Module` merge. Rejected: it
  adds internal surface to a public contract.
- A Tour loader of its own, copied from `rocco.js`. Rejected: the WebGPU
  checks, load order, audio unlock and focus fix would drift apart.
- The site owns `host.html`. Rejected: the protocol would split across two
  repos.
- One image per Preview, with a new iframe on every Run. Rejected after
  `research/tour-native-hot-reload`: hot reload keeps the Model on 83 % of
  Tutorial literal edits and is about 40 ms faster per edit.
- A separate message for later images, such as `tour:swap`. Rejected: the
  payload is the same as `tour:image`.
- The page compares identities. Rejected: the meaning of each digest and
  hash would leave the engine repo.
- Send the image on the iframe's `load` event. Rejected: the Preview loader
  may not listen yet.
- A static `rocco.js` tag, with `main` waiting on a promise. Rejected: it
  needs Asyncify or a wait in the frame loop.

## Consequences

- The message names and payloads are a contract between this repo and the
  site. A change needs a matching site change in the same engine release.
- How the reader sees a crash, `dbg` or `expect` message is still open.
- A Restart button on the page starts a new Preview with the current image.
  It needs no message.
- The `web_package.py` tag check (ADR 0038) does not apply to `host.html`,
  which is not a game Page.
