# 0041: The Preview loads rocco.js unchanged and speaks postMessage

Status: accepted, 2026-11-17.

## Context

Each Run of a Tour step makes a new same-origin iframe, the Preview, which
runs the Tour host (ADR 0040). The Tour page talks to the Preview only
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
  - Page to Preview: `tour:image { image }`, with the `ArrayBuffer`
    transferred. A Preview takes one image and ignores any more.
  - Preview to page:
    - `tour:waiting`: the Preview loader listens for the image.
    - `rocco:ready`, `rocco:unsupported { reason, message }`,
      `rocco:stopped { reason, message }`, `rocco:quit`: the `rocco.js`
      events, forwarded with the same names and reasons.
    - `tour:crash { message }`, `tour:dbg { text }`, `tour:expect { text }`:
      posted by the glue from `roc_crashed`, `roc_dbg` and
      `roc_expect_failed`. A crash ends the run.
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
- Send the image on the iframe's `load` event. Rejected: the Preview loader
  may not listen yet.
- A static `rocco.js` tag, with `main` waiting on a promise. Rejected: it
  needs Asyncify or a wait in the frame loop.

## Consequences

- The message names and payloads are a contract between this repo and the
  site. A change needs a matching site change in the same engine release.
- How the reader sees a crash, `dbg` or `expect` message is still open.
- The `web_package.py` tag check (ADR 0038) does not apply to `host.html`,
  which is not a game Page.
