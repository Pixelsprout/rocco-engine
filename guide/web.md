---
title: Web builds
summary: Build a game for the browser, upload it to itch.io, and learn what changes when it runs through WebGPU.
order: 15
---

# Web builds

You can build a rocco game into a web page and upload it to itch.io. The
game keeps one source for native and web builds, and the Vocabulary has no
web flag. Where the browser cannot do what a native build does, the host
changes the request or ignores it. This page lists each case.

The page draws with WebGPU. There is no WebGL fallback, because the
clustered lights need storage buffers, which WebGL2 does not have.

## Build a page

You need emscripten next to Odin and Roc. Install the pinned version once:

```sh
sh scripts/toolchain.sh install-emsdk
```

Then build a game from `examples/` for the web:

```sh
sh scripts/toolchain.sh run roc scripts/build.roc web tutorial/08-sound
```

The command writes `build/web/08-sound/`:

| File | What it holds |
| --- | --- |
| `index.html` | The page. It checks for WebGPU, then loads the two scripts. |
| `index.data.js` | The loader for `index.data`. |
| `index.data` | Every file in the game's `assets/` folder. A game with no `assets/` folder has no `index.data`. |
| `index.js` | emscripten's loader for the wasm. |
| `index.wasm` | The engine and your game. |
| `08-sound-web.zip` | The files above, with `index.html` at the top. |

The first web build also builds the web host into `platform/targets/wasm32/`,
which takes about a minute. That host is a debug build. For a smaller and
faster page, build a release host first:

```sh
sh scripts/toolchain.sh run roc scripts/build.roc web-host --release
sh scripts/toolchain.sh run roc scripts/build.roc web tutorial/08-sound
```

Run `web-host` again after you change the engine.

To try the page, serve the folder from any static web server and open it in
Chrome:

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/web/08-sound
```

Then open http://127.0.0.1:8000. A browser gives WebGPU only to a page from
`localhost`, `127.0.0.1` or an `https://` address. Without `--bind`, the
server prints `http://[::]:8000/`, and that address gets no WebGPU. A page
opened from a `file://` URL cannot load `index.data`, so it needs a server
too.

## Upload to itch.io

1. Create a new project and set its kind to **HTML**.
2. Upload the zip, and tick **This file will be played in the browser**.
3. Set the viewport to your Launch window size, such as 1280 by 720.
4. Turn on the fullscreen button if you want one.

The canvas fills the page, so the game takes the size of the itch.io
viewport, not the Launch `width` and `height`. The tab title is the Launch
`title`.

## Browsers

The page needs WebGPU. Chrome and Edge 113 and later have it on Windows,
macOS and ChromeOS. Recent Safari and Firefox releases have it too, but
rocco is checked in Chrome only. A browser without WebGPU gets a short
message in place of the game.

## Sound

Browsers start a page's audio only after the player clicks, taps or
presses a key. Until then the game runs silently. A title screen that waits
for a key press gives the player that first input.

## Differences

- **MSAA.** WebGPU supports only 1 and 4 samples per pixel. A
  `Launch.window.samples` of `X2`, `X4` or `X8` draws with 4 samples on the
  web, and `Off` draws with 1.
- **Gamepads.** The web host reports no connected gamepad yet. The game's
  `gamepads` list is always empty.
- **Environment.** A page has no environment variables and no command line.
  `Config.args` is empty, the Seed is 0, and the `ROCCO_*` switches such as
  `ROCCO_HEADLESS` and `ROCCO_EXIT_AFTER_FRAMES` do nothing.
- **The Bridge.** A page cannot listen on a socket, so it connects out to
  a Relay. The next section shows how.
- **Vsync.** The browser draws on its own refresh, so the page ignores a
  Launch `vsync` of `False`.
- **Shader reload.** The page's files never change, so the host does not
  watch the shader packs.
- **Spans, capture and GPU timing.** These measure native runs only. A web
  build has none of them.
- **Quit.** A `Quit` command stops the game, but the browser tab stays
  open. The page gets a `rocco:quit` event, as the next section explains.

## The Bridge

A script, a CI test or an agent can drive a web build through the
[Bridge](bridge.md), as it drives a native run. The page connects out to a
Relay, and the Driver connects to the same Relay:

```sh
python3 scripts/bridge.py relay --port 7878 &
python3 -m http.server 8000 --bind 127.0.0.1 --directory build/web/pong &
```

Then open http://127.0.0.1:8000/index.html?bridge=7878 in Chrome, and
send requests with `python3 scripts/bridge.py --port 7878 hello` and the
other commands. Each command is its own connection, and the page keeps its
place between them. The Relay exits after it passes on the reply to `quit`.

The page reads `?bridge` only when it was served from `localhost` or
`127.0.0.1`. On itch.io or any other host, the page ignores it and opens
no connection. So you upload the same build that you test.

To save one frame in a single command, build the page and run:

```sh
sh scripts/screenshot.sh --web pong out.png 60
```

It starts the Relay, the server and a Chrome window, runs 60 steps and
saves the frame. On macOS the window must stay open, because headless
Chrome there stops drawing after the first frame. CI runs it headless on
Linux, with WebGPU on Mesa's software Vulkan, and compares the frame with a native
screenshot of the same step. The two differ a little, so the check allows
a small difference in each pixel and a small count of changed pixels.
To run that same headless browser on your own machine, start Docker and
run:

```sh
sh scripts/linux/web-shot.sh pong build/web-check/pong-web.png 60
```

It builds a small Linux image with Chrome and Mesa, and screenshots the
page you built. A page that fails in CI fails here too, so you can fix it
before you push.

`scripts/web/shot.sh` stays for checks of the page itself: it prints the
page's messages and presses a key to start the audio.

The Bridge's `quit` and a `Quit` Command from the game end a web run in
the same way. The engine sends any reply it owes, stops drawing, shuts
down and dispatches `rocco:quit` on `window`, with no detail. The default
page listens for it and shows that the game has ended, with a button that
loads the page again. A page of your own can listen for the same event.

## Shader packs

Every shader pack holds four backends: `glsl430`, `hlsl5`, `metal_macos`
and `wgsl`. A pack built by an older tool has no `wgsl` code, and the
engine refuses it with a message to rebuild it. Run your game's build once
to rebuild its packs.

A Post shader reads `scene_depth` and `selection_depth` one texel at a
time, with no filter, on every backend. WebGPU cannot filter the 32-bit
float textures that hold them.
