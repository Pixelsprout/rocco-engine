# Web lit slice

This spike draws the engine's lit pass with sokol on WebGPU in Chrome. It
uses the real `render.odin`, `frame_render.odin` and `shader_package.odin`.

It works. The page draws the `glow` Scene at time 0: the floor, the wall,
the glowing window, the salvage block, the ribbed panel, both orbs, the
glass tube and the spark. The Scene has the Sun's shadows, clustered point
lights, bloom and the Aces tone map, with 4x MSAA. One extra green cube
draws with the `IndirectSurface` pack of `examples/surface`, and it casts a
shadow. The web frame and the native frame look the same by eye. A one-off
pixel comparison of frame 30 by hand gave a mean largest-channel difference
of 1.4 out of 255. 0.56% of the pixels differ by more than 16, at MSAA
edges and in the bloom. A repeatable pixel diff waits for the web Bridge
(32954kz7).

The console shows:

```
init: sokol_gfx backend WGPU
init: shader shader/IndirectSurface ready true failed false
init: renderer ready
frame 30: window [1280, 720] dpi 1, placed draws 10
```

Pins: emscripten 7.0.0, Odin dev-2026-11, sokol-odin b13d03c with one
patched line (see the findings), and sokol-shdc from
`platform/shader-tools/contract-v1/compiler.json`.

## Build and check

```sh
sh scripts/toolchain.sh run sh spikes/web-lit/build.sh all
sh spikes/web-lit/native-shot.sh /tmp/native.png
sh spikes/web-lit/web-shot.sh /tmp/web.png
```

Then compare the two PNGs by eye. Both are 1280 x 720 at DPI 1.

- `native-shot.sh` runs the native twin under the Bridge. It runs 30 steps
  in Lockstep and saves the frame with the engine screenshot readback
  (ADR 0010).
- `web-shot.sh` serves the page and opens it in a Chrome window. It reads
  the console over the Chrome DevTools Protocol, waits for the `frame 30`
  line and saves a screenshot. Headless Chrome on macOS runs only one
  frame, so it needs a window. It also prints every WebGPU validation
  error, through a page hook on `uncapturederror`.

## What the build does

1. `scene/` builds the Scene in Odin. The web host and the native twin both
   use it. The `slice` collection names the engine. It is the slice copy on
   the web and the real engine natively.
2. `slice.sh` copies the engine into `build/web/slice/engine`. It leaves
   out the files that need an OS, a socket, audio or the game loop: the app
   and the Seam, the Bridge, gamepads, audio, capture, input and shader
   reload. It moves `../` imports onto the `rocco` collection, imports
   `webos` as `os` and sends `fmt.eprint*` to the browser console.
   `slice/stub.odin` stands in for about ten missing names.
3. `slice.sh` also copies `core:image` and `core:image/png`, without their
   file loaders. Those files build on every OS but js and import `core:os`,
   which does not build on freestanding wasm.
4. `webos/` holds the part of `core:os` that the copied files call, on top
   of emscripten's libc. File reads and directory listings reach the
   preloaded file system.
5. emcc builds sokol for WGPU, Odin builds the host as a
   `freestanding_wasm32` object, and emcc links the page.
   `--preload-file` puts the meshes and the shader pack at `/assets`.
6. The native twin is an Odin twin, as in `bench/`. It runs the same Scene
   through `engine.run`, with the real Seam and Packs.

## Findings

- **The lit pass needs no second lighting path.** The clustered lights,
  the Sun's shadow cascades, bloom, the tone map and the glTF materials run
  on WebGPU with the same shaders, compiled to WGSL.
- **basic.glsl compiles to WGSL after two changes.**
  - `Cluster` and `LightIndices` were each one `uvec4` with a different
    member name. The SPIR-V to WGSL step merges structs with the same
    layout, and sokol-shdc then stops with "struct member range not found".
    Both members are now `lanes`. `contract-v1/surface.glsl` has the same
    change.
  - `prefilter_box` divided its sum by the tap count. That stopped the WGSL
    compile with "function-scope 'var' must have a constructible type".
    The caller now divides the weighted mean once.
  - The native `glow`, `surface`, `post` and `authoring` screenshots are
    byte-identical before and after.
- **sokol bug: sparse uniform slots on WGPU.** The pinned sokol_gfx.h fills
  the WebGPU dynamic offset map at the sokol slot index. It then sorts and
  reads only the first N entries. A shader whose uniform slots have a gap,
  such as 0, 1, 2, 4 and 5, gets wrong offsets. Every custom pack has such a
  gap. Its draws then read the wrong `mvp`, and draw nothing, with no
  error. The engine's skinned shadow, shadow mask and coverage shaders use
  slots 0 and 3, so skinned meshes hit the bug too. `glow` has no skinned
  mesh, so the slice does not show it. Upstream sokol indexes the map by the
  bind group entry. `build.sh` applies that one-line fix to a copy. The Web
  host task must move the sokol-odin pin past the fix.
- **emscripten's 64 KB stack overflows** in `renderer_init`, which holds
  many sokol descriptors. The page links with `-sSTACK_SIZE=4MB`.
- **The R32F Post inputs are unfilterable.** WebGPU cannot filter R32F.
  The engine samples every Post input with a nearest sampler, so
  `scene_depth` and `selection_depth` are now `unfilterable_float` with
  `nonfiltering` samplers on all backends. No `float32-filterable` feature
  is needed.
- **MSAA.** WebGPU supports 1 and 4 samples. The slice host draws any
  Launch MSAA above 1 with 4. `guide/web.md` lists this. The Web host task
  must move the clamp into the engine's web host.
- `core:time` builds on freestanding wasm. The slice links with no missing
  symbol.
- The glue orders record fields by name. `Rgb` is `{b, g, r}` and `Quat` is
  `{w, x, y, z}`, so Odin code must name the fields in those literals.
- `index.wasm` is 3.4 MB and `index.js` is 310 KB, in a debug build with
  function names. `index.data` holds 650 KB of meshes and the shader pack.

## What the slice does not test

- The Roc app on wasm32. The host builds the Scene in Odin.
- Skinned meshes, custom packs with game textures, Post packs, the
  selection pass, skies and Images on WebGPU. The cube's pack ran in the
  instanced layout only.
- More than one frame of the same Scene, steps and animation.

## Superseded

The web host in `scripts/web/` builds the whole engine for wasm32, so this
slice is no longer needed. The engine has changed since, and the slice no
longer builds against it. CI does not build this page. See `guide/web.md`.
