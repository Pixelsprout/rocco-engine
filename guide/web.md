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
- **The Bridge.** The web host does not open a Bridge yet. A later web
  Bridge will connect to the Driver over a WebSocket.
- **Shader reload.** The page's files never change, so the host does not
  watch the shader packs.
- **Spans, capture and GPU timing.** These measure native runs only. A web
  build has none of them.
- **Quit.** A `Quit` command stops the game, but the browser tab stays
  open.

## Shader packs

Every shader pack holds four backends: `glsl430`, `hlsl5`, `metal_macos`
and `wgsl`. A pack built by an older tool has no `wgsl` code, and the
engine refuses it with a message to rebuild it. Run your game's build once
to rebuild its packs.

A Post shader reads `scene_depth` and `selection_depth` one texel at a
time, with no filter, on every backend. WebGPU cannot filter the 32-bit
float textures that hold them.
