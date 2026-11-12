# Web UI spike

This spike runs sokol_app and sokol_gfx on the WebGPU backend in a browser,
and draws the engine's unlit UI pass (`engine/ui_render.odin`) with them.

It works. A Chrome window shows a rounded blue Panel at the top left with the
Text "Hello from WebGPU" in it. The console shows:

```
init: sokol_gfx backend WGPU
init: UI pipeline ready
frame: window [800, 600] dpi 1, rect quads 1, glyph quads 15
frame: first quad rect [0, 0, 274.73547, 64]
```

Pins: emscripten 7.0.0 (emdawnwebgpu port v20260423.175430), Odin
dev-2026-11, sokol-odin b13d03c, sokol-shdc from `scripts/shader_contract`.
There is no Roc app. The host builds the Element tree itself.

## Build and run

```sh
python3 scripts/shader_contract/install.py
sh scripts/toolchain.sh run sh spikes/web-ui/build.sh
python3 -m http.server 8000 --directory spikes/web-ui/build/page
```

Open http://127.0.0.1:8000/index.html in a Chrome window. Headless Chrome on
macOS runs only one frame.

## What the build does

1. emcc compiles `sokol_log.c`, `sokol_gfx.c`, `sokol_app.c` and
   `sokol_glue.c` with `-DIMPL -DSOKOL_WGPU --use-port=emdawnwebgpu`. The
   pinned sokol-odin needs no change. Its `build_clibs_wasm.sh` builds GLES3
   only, so the web host needs its own WGPU build step.
2. sokol-shdc compiles the `ui` program and the `srgb` block from
   `engine/shaders/basic.glsl` with `-l wgsl`.
3. The script copies the engine's UI files into `build/engine`, a package
   that holds only the UI. It moves their `../` imports onto a `rocco`
   collection. `slice/stub.odin` stands in for the renderer, the Image table
   and the Roc runtime parts that they touch.
4. Odin builds the host as a `freestanding_wasm32` object, as in the link
   spike.
5. emcc links the host, `main.o` from `host/main.c`, the sokol objects and clay's prebuilt
   `wasm/clay.o` into the page with `--use-port=emdawnwebgpu
   -sDEFAULT_TO_CXX -sALLOW_MEMORY_GROWTH=1`.

The copied files are `ui.odin`, `ui_render.odin`, `font.odin`,
`font_baked.odin`, `vocabulary.odin` and `roc_platform_abi.odin`. Apart from
the import paths, the build changes only `roc_platform_abi.odin` and the
`fmt` import.
See the findings.

## Findings

- WebGPU needs no ASYNCIFY and no JS changes. On emscripten, sokol_app
  chains the adapter and device requests through callbacks, and calls `init`
  when the device is ready.
- emdawnwebgpu needs a C++ link. Without `-sDEFAULT_TO_CXX`, emcc stops with
  "emdawnwebgpu requires C++". This spike does not test the link spike's
  `wasm-ld -r` step. That step takes its `-l` flags from the reference link,
  so it will probably pick up the C++ libraries too. The Web host task must
  check this.
- `basic.glsl` as a whole does not compile to WGSL. sokol-shdc stops at line
  382 with "struct member range not found". That is in the lit pass, which
  p7odbko0 owns. The UI program compiles to WGSL with no change.
- clay's prebuilt `wasm/clay.o` links with emcc as it is.
- `core:fmt` has no `eprint*` procedures on `freestanding_wasm32`, because it
  has no os. `ui.odin` logs repairs with `fmt.eprintfln`. The slice imports
  `webfmt` as `fmt`, which formats with `fmt.ctprintf` and writes with libc
  `puts`. The engine needs one log procedure that the web host can route to
  the console.
- Freestanding Odin has no default temp allocator. `ui_gpu_init` builds its
  index data in `context.temp_allocator`, and it fails with the nil
  allocator. The host sets the temp allocator to a zero-value
  `engine/arenas` Arena, which takes its blocks from libc.
- `roc_platform_abi.odin` asserts 64-bit layouts, so it does not compile for
  wasm32. The slice drops the 814 `#assert` lines. Only Odin reads these
  types here. nuwkrpm8 emits the 32-bit layouts.
- The UI pipeline has no depth image, because it draws in the Post pass.
  The spike draws it straight to the swapchain, so sokol_app must make the
  swapchain with `depth_format = .NONE`. In the full renderer the UI keeps
  drawing into the Post pass target, and the swapchain format does not
  matter to it.
- The zero value of a Vocabulary tag union is its first tag in alphabetical
  order. A zero `floating` is `Float` at `CenterBottom`, so a Panel that a
  host builds by hand must name each tag. Roc fills these in for a game.
- `index.wasm` is 1.2 MB and `index.js` is 200 KB, in a debug build with no
  game.

## What the spike does not test

- The engine draws the UI into an RGBA8 target (`TARGET_COLOR_FORMAT` in
  `engine/render_target.odin`) and then composites it to the swapchain. The
  stub sets `TARGET_COLOR_FORMAT` to `.DEFAULT`, so the pipeline takes the
  WebGPU swapchain format. The RGBA8 target and the composite step did not
  run on WebGPU.
- The UI pipeline ran with a sample count of 1. The engine passes the
  Launch's MSAA count, so an MSAA UI pipeline did not run.
- Image quads did not run. The stub Image table finds no Image.
- The Element tree is built in Odin, so the 32-bit Roc layouts of `Element`
  and `Roc_Str` did not run.

## What the Web host still needs for the UI

- A WGPU build of the sokol objects in the platform prebuild.
- The `wgsl` backend in the shader pipeline (p7odbko0), so the engine's
  generated shader file holds the UI program for WebGPU.
- A log procedure in place of `fmt.eprint*`, and a temp allocator.
- The full engine package building for wasm32, so no slice is needed.
