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
| `index.html` | The page. A game without a `web/` folder gets the default page. 08-sound has [its own page](#your-own-page), with a Click to play screen. |
| `rocco.js` | The engine's start-up code. It checks for WebGPU, then loads the two scripts below. |
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
for a key press gives the player that first input. So does a page with a
Click to play screen, as in the example under [Your own page](#your-own-page).

## Your own page

Every game gets the default page unless it has its own. The default page
shows a Loading line, then the game, and a short message if something goes
wrong. For your own start screen, end screen or style, give the game a page
of its own.

Make a `web/` folder next to the game's `main.roc`, and put an `index.html`
in it. The web build copies the folder into `build/web/<game>/` and the
zip, so the page can use its own images, fonts and scripts. It skips files
and folders whose names start with a dot. Its `index.html` takes the place
of the default page.
[`examples/tutorial/08-sound/web/index.html`](../examples/tutorial/08-sound/web/index.html)
is a full example.

If `web/` has no `index.html`, the build stops. The page must also have two
things, or the build stops with an error that names the missing one:

- A `<canvas id="canvas">`. The engine finds the canvas by this id and
  draws into it.
- A `<script src="rocco.js"></script>` tag. `rocco.js` is the engine's
  start-up code. The build writes it next to the page, so don't copy it
  into `web/`.

The build also writes `index.js`, `index.wasm`, `index.data` and
`index.data.js`. If a file at the top of `web/` has one of these names, or
`rocco.js`, the build stops. Upper and lower case count as the same name.

### Start the game

The page calls `rocco_start()` to start the game. Nothing loads before
that call, and a second call does nothing. A page with no start screen
calls it at once. A page with a Click to play button calls it from the
click.

A Driver can't click a button. So when the page is served from `localhost`
or `127.0.0.1` with `?bridge=PORT`, `rocco.js` starts the game at once,
as if the page had called `rocco_start()`. `scripts/screenshot.sh --web`
and an agent can then drive a page with any start screen. On itch.io, the
page waits for its own call as usual.

### Events

The engine shows nothing itself. It tells the page what happens through
four events on `window`, and it also writes each `message` to the browser
console. The page decides what the player sees.

| Event | When | `event.detail` |
| --- | --- | --- |
| `rocco:ready` | Once, after the game draws its first frame. | None. |
| `rocco:unsupported` | The browser can't run the game, so nothing loads. | `{ reason, message }`. `reason` is `insecure` (not served from `https://` or `localhost`), `no-webgpu` or `no-adapter` (no GPU for WebGPU). |
| `rocco:stopped` | The game could not start, or it stopped with an error. | `{ reason, message }`. `reason` is `load` (a file did not load), `canvas` (no `id="canvas"`), `abort` (the engine hit an error) or `exit` (an exit code other than 0). |
| `rocco:quit` | A `Quit` Command or the Bridge's `quit` has ended the run. | None. |

Each `message` is a sentence for the player that says what went wrong and
what to try, so a page can show it as it is. Listen for all four events. A
page that ignores `rocco:unsupported` shows a black tab to a player whose
browser has no WebGPU.

After `rocco:quit`, the game can't start again in the same page. To let
the player play again, reload the page with `location.reload()`, as the
default page's button does.

### An example page

This page shows a Click to play button, then the game. It shows each
message in place of the game, and a line of thanks when the game quits:

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>My game</title>
<style>
html, body { margin: 0; height: 100%; background: #000; color: #eee; font: 16px sans-serif; }
canvas { display: block; width: 100%; height: 100%; }
#screen { position: absolute; inset: 0; display: grid; place-content: center; padding: 2em; text-align: center; background: #000; }
</style>
</head>
<body>
<canvas id="canvas"></canvas>
<div id="screen"><button id="play">Click to play</button></div>
<script src="rocco.js"></script>
<script>
var screen = document.getElementById("screen");

function show(text) {
	screen.textContent = text;
	screen.style.display = "grid";
}

document.getElementById("play").onclick = function () {
	show("Loading");
	rocco_start();
};
window.addEventListener("rocco:ready", function () { screen.style.display = "none"; });
window.addEventListener("rocco:unsupported", function (event) { show(event.detail.message); });
window.addEventListener("rocco:stopped", function (event) { show(event.detail.message); });
window.addEventListener("rocco:quit", function () { show("Thanks for playing!"); });
</script>
</body>
</html>
```

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
- **Quit.** A `Quit` Command stops the game, but the browser tab stays
  open. The page gets a `rocco:quit` event and decides what to show, as
  [Events](#events) explains.

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
down and dispatches `rocco:quit`. A run driven over the Bridge gets
`rocco:ready` and the other [events](#events) too.

## Shader packs

Every shader pack holds four backends: `glsl430`, `hlsl5`, `metal_macos`
and `wgsl`. A pack built by an older tool has no `wgsl` code, and the
engine refuses it with a message to rebuild it. Run your game's build once
to rebuild its packs.

A Post shader reads `scene_depth` and `selection_depth` one texel at a
time, with no filter, on every backend. WebGPU cannot filter the 32-bit
float textures that hold them.
