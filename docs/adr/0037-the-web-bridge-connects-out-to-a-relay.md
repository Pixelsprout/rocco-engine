# 0037: The web Bridge connects out to a Relay

Status: accepted, 2026-11-14.

## Context

ADR 0036 brought Web builds into scope with no Bridge. A page cannot listen
on a socket, so the native transport in `engine/bridge_transport.odin` does
not apply. CI builds the web games but cannot run them, and a pixel check
needs a Driver. Each `bridge.py` call today connects, sends one request and
exits, and agents depend on that: the run keeps its place between calls.

## Decision

- A Relay is a long-lived outside process: `bridge.py relay --port P`. The
  page opens a WebSocket to it from `?bridge=P`. A Driver connects to the
  same port with JSON Lines, as it would to a native run. The Relay reads
  the first bytes of a connection: `GET ` is the page, anything else is a
  Driver. Existing Drivers work unchanged.
- One Bridge message goes in each WebSocket message. The host opens the
  connection with `emscripten/websocket.h`.
- The Relay serves one page and one Driver. A new page replaces the old
  one, and its run starts at step 0. A request in flight when the page
  drops gets an error reply.
- The page turns the Bridge on only when `?bridge` is set and the origin is
  `localhost` or `127.0.0.1`. The itch.io zip is the same build and can
  never open a Bridge.
- The page retries the WebSocket until it connects. Until then it shows the
  first Frame and runs no steps, as a native run with no Driver does.
- requestAnimationFrame keeps running while the Bridge is paused. The host
  skips the native sleep, polls each Frame and renders the current Scene.
- `screenshot` reads back the offscreen target, as ADR 0010 decides. The
  WebGPU buffer map is asynchronous, so the reply is held until it ends.
  The reply carries the PNG in base64, and the Relay writes it to `path`
  and drops the bytes. The Driver gets the native reply shape.
- `hello` reports `web`, and `protocol` goes to 11.
- The Relay's WebSocket server uses the Python standard library only.
- On the web, the Bridge `quit` and the game's `Quit` Command end the run
  the same way. The host replies if a reply is owed, stops the frame loop,
  shuts down and dispatches `rocco:quit` on `window` with no detail. The
  page decides what follows. The default page shows that the run ended and
  offers a reload. A restart inside the page is out of scope. The Relay
  exits after it forwards the `quit` reply.
- `scripts/screenshot.sh --web` starts the Relay, a static server and
  Chrome on `?bridge=P`, then makes the native Bridge calls.
  `scripts/web/shot.sh` stays for the page's own messages and the key press
  that starts audio.
- CI runs headless Chrome with WebGPU on Mesa's lavapipe, a software
  Vulkan device. It compares a pong
  screenshot with the native one by a per-channel tolerance and a limit on
  changed pixels, both set from measured runs.

## Considered options

- Each `bridge.py` call serves the WebSocket and the page reconnects for
  each request. Rejected: every request pays a reconnect, and the page must
  retry without end.
- Web Drivers through the Python library only. Rejected: agents lose one op
  per shell call.
- Two Relay ports, one for the page and one for the Driver. Rejected: a
  script would track two numbers.
- Cancel requestAnimationFrame while paused. Rejected: more code, and the
  page would stop showing what `scene` returns.
- Capture the page through the Chrome DevTools Protocol. Rejected for the
  reasons in ADR 0010, and headless capture can miss a WebGPU canvas.
- Turn the Bridge on for any origin with `?bridge`. Rejected: a hosted page
  would connect to a port on the player's machine.
- The `websockets` package. Rejected: no script in `scripts/` needs pip.
- Let the game's page replace `index.html` in this task. Deferred to its
  own task: the page contract is a design question of its own.

## Consequences

- From a Driver's side, a web run is a native run on a port. Only the
  setup differs.
- A web `quit` leaves the tab open. The page, not the host, decides what
  the player sees.
- The CI job needs Chrome and a software Vulkan device. Chrome's own
  SwiftShader gives no WebGPU adapter there, because ANGLE needs
  `VK_KHR_surface`, so the job installs `mesa-vulkan-drivers` and
  `libvulkan1`. Ubuntu 24.04 blocks the user namespaces of Chrome's
  sandbox, so Chrome runs with `--no-sandbox`. Headless Chrome on Linux
  keeps requestAnimationFrame running, so the job needs no `xvfb-run`.
- The web and native screenshots differ by rasterizer, so the check has a
  tolerance, not byte equality.
