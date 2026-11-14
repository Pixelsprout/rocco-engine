# 0036: Web builds through WebGPU

Status: accepted, 2026-11-14.

## Context

`docs/ROADMAP.md` listed web builds as out of scope until Odin and sokol had
a shared web path. An outside author asked if their game, whose maintained
build is a web page, could move to rocco. Six spikes (dex task 4wr6g8k3)
tested the path: a Roc wasm32 app linked to an Odin host, 32-bit layouts
from OdinGlue, arenas without virtual reserve, sokol WebGPU with the UI pass,
a wgsl shader backend with the lit pass, and the web host with Packs, audio
and an itch.io zip. Each spike passed.

## Decision

- Web comes into scope, for demos. itch.io is the target host.
- The web build draws with the sokol WebGPU backend through emdawnwebgpu.
  There is no WebGL2 fallback: WebGL2 has no storage buffers, and the
  clustered lights read one (ADR 0033).
- The shader pipeline has a fourth backend, `wgsl`. Engine shaders and game
  shader packs (ADR 0028) both carry it.
- A game has one source for native and web. The Vocabulary has no web flag.
  The host changes or ignores what a browser cannot do, and `guide/web.md`
  lists each case.
- The engine builds as an Odin `freestanding_wasm32` object. The `system`
  package gives one file and print interface over `core:os` natively and
  over emscripten libc on the web. Arenas use the heap on the web.
- emcc prebuilds the host, sokol, miniaudio and the JS loader into
  `platform/targets/wasm32`, and the candidate SDK and release bundle ship
  it. `roc build --target=wasm32` makes the final link.
- `roc scripts/build.roc web <game>` runs `roc build`, then
  `scripts/web_package.py`. The package step checks the link, moves the
  loader's EM_ASM table to the game's addresses, packs `assets/` into one
  `.data` file with the emscripten file_packager, and writes the itch.io zip.
- The page needs a secure context (`localhost`, `127.0.0.1` or https). It
  names the reason when WebGPU is missing, and a key press, click or tap
  starts the audio.

## Considered options

- WebGL2 through sokol GLES3. Rejected: the clustered lights would need a
  second lighting path without storage buffers.
- A web flag in the Vocabulary. Rejected: a game would branch on platform,
  and one source per game is the goal.
- A fetch per Pack. Deferred: one preloaded `.data` file is enough for
  demos.
- Porting the outside author's game in the same task. Deferred: the engine
  path comes first.

## Consequences

- CI builds the web host and three games (08-sound, surface and pong) in
  its web job. It does not run a page yet. A headless browser check waits
  for the web Bridge (dex task 32954kz7).
- The web host has no Bridge yet; ADR 0037 adds one through a Relay. It
  has no gamepads, no environment switches, no shader
  reload and no Spans, capture or GPU timing.
- emsdk is a pinned tool. `scripts/toolchain.sh install-emsdk` installs it.
- The sokol WebGPU backend at the first pin gave no fragment stage to a
  pipeline with no colour target, so a cutout shadow cast a solid shadow.
  The sokol-odin pin moved to baf5f3e, which has the upstream fix, and
  `scripts/web/build-host.sh` no longer patches sokol.
- A change to the engine needs `roc scripts/build.roc web-host` before a web
  build sees it.
