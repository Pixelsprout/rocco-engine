# Web pong spike

This spike runs the game logic of `examples/pong` in a browser with no window.
It compares each step result with a native build that gets the same Input.

It works. Headless Chrome runs 600 steps of pong on wasm32. Each line of the
browser trace equals the native line, except the first one, which prints the
pointer width.

Pins: emscripten 7.0.0, Odin dev-2026-11, Roc nightly-2026-11-04-2622062.

## Build and run

```sh
sh scripts/toolchain.sh run roc scripts/build.roc inputs
sh scripts/toolchain.sh run sh spikes/web-pong/build.sh
python3 spikes/web-pong/compare.py
```

On macOS, `build.sh` needs `platform/targets/arm64mac/libclang_rt.osx.a`,
which the `inputs` step copies. On Linux it builds only the page.

`compare.py` runs the native twin, loads the page in headless Chrome and diffs
the two traces. The page runs every step inside `main`, so it needs no
animation frames. Headless Chrome on macOS fires `requestAnimationFrame` only
once, so a game loop on frames would stall there.

## What the spike shows

- `glue/OdinGlue.roc` emits one `engine/roc_platform_abi.odin` for both pointer
  widths. Each size, alignment and offset assert picks its value with
  `when ROC_POINTER_64`. The page build type-checks every rocco ABI type on
  wasm32 against Roc's 32-bit layout, and all asserts pass.
- The generated refcount helpers work on wasm32. The harness builds the Input
  lists with `roc_list_from_slice` and frees the commands and the Scene with
  `roc_list_decref` and `roc_decref`.
- The `Str` and `List` headers are 12 bytes on wasm32. A 15-byte HUD string
  is inline on arm64 and on the heap on wasm32. Both traces show it the same.
- The f32 bits of every Scene match. Pong uses no sin or cos, so this run does
  not compare libm between the two targets.

## Limits

- Pong returns no commands, so every `commands` line is an empty list. Only
  the compile-time asserts check the wasm32 layout of the Command unions.
- The native side is the spike's harness twin, not the engine host in
  `engine/seam.odin`.
- The `engine` package does not build for wasm32 yet. The search for
  hand-written 24-byte header code was by reading only.
- CI builds the page, which runs the 32-bit asserts. CI does not run
  `compare.py`.

## The build

`build.sh` copies `platform/*.roc`, `packages/` and `examples/pong/main.roc`
into `build/mirror`. `mirror_targets.py` replaces the targets of the copied
platform with two spike targets. The real platform is not changed.

- `arm64mac`: the harness as a static `libhost.a`, with `libclang_rt.osx.a`.
- `wasm32`: the harness as one relocatable `host.o`, linked as in
  `spikes/web-link`. The page reuses that spike's `main.c` and
  `check_link.py`.

The harness package gets a copy of `engine/roc_platform_abi.odin` with its
package line changed. It holds no hand-written Roc layout.

## The trace

`host/harness.odin` calls `roc_launch` and `roc_init` with seed 7. Then it
calls `roc_step` 600 times with a fixed Input script: held paddle keys, and
Space presses that pause and resume. After each step it calls `roc_view`.

For the init commands, and for each step's commands and Scene, the harness
writes a text dump from Odin type info. A `Roc_Str` becomes its text, a
`Roc_List` its elements, a union its live tag and payload, and an f32 its
value and bits. The dump has no addresses. Each trace line has the dump's
length and FNV-1a hash. The last line before `done` holds the whole final
Scene.

## Findings

- `roc_view` consumes one reference to the Model box. The host must call
  `roc_incref_box` first, as `engine/seam.odin` does. Without it the next
  `roc_step` reads a freed box.
- Freestanding Odin has no default temp allocator. `fmt.tprintf` and other
  temp allocations fail with no error. The harness sets `runtime.Arena` on
  the libc heap as its temp allocator.
- The platform's `libSystem.tbd` stub has no `posix_memalign` or `puts`. The
  native twin uses `malloc`, which gives 16-byte alignment on macOS.
- Before the temp allocator fix, the page printed garbage and headless Chrome
  died with SIGTRAP. After the fix it exits normally.
- No hand-written engine Odin assumes 24-byte headers. The engine reads
  `size_of(Roc_Str)` and uses `uint` and `int`, which follow the pointer width.
  `spikes/web-link/host/host.odin` still declares its own 32-bit `Roc_Str`,
  because that spike's platform has no glue.
