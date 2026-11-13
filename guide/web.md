---
title: Web builds
summary: What changes when a game runs in a browser through WebGPU.
order: 15
---

# Web builds

rocco is working toward web builds that run in a browser through WebGPU.
A game keeps one source for native and web builds, and the Vocabulary has
no web flag. Where the browser cannot do what a native build does, the host
changes the request or ignores it, and this page lists each case.

The web build is not ready for games yet. The spikes under `spikes/` draw
the engine's UI and lit passes in Chrome, and your shader packs already
carry the `wgsl` code that the web build needs.

## Differences

- **MSAA.** WebGPU supports only 1 and 4 samples per pixel. A
  `Launch.window.samples` of `X2`, `X4` or `X8` draws with 4 samples on the
  web, and `Off` draws with 1.

## Shader packs

Every shader pack holds four backends: `glsl430`, `hlsl5`, `metal_macos`
and `wgsl`. A pack built by an older tool has no `wgsl` code, and the
engine refuses it with a message to rebuild it. Run your game's build once
to rebuild its packs.

A Post shader reads `scene_depth` and `selection_depth` one texel at a
time, with no filter, on every backend. WebGPU cannot filter the 32-bit
float textures that hold them.
