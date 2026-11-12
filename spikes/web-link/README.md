# Web link spike

This spike tests whether a Roc app built with `roc build --target=wasm32` can
link against an Odin host that emscripten prebuilt, and run in a browser with
the JS loader emscripten wrote for that host.

It works. Chrome prints the file read line and one line from each of five
`step` calls. Odin reads `/hello.txt` through the emscripten file system.

Pins: emscripten 7.0.0, Odin dev-2026-11, Roc nightly-2026-11-04-2622062.

## Build and run

```sh
sh scripts/toolchain.sh install-emsdk
sh scripts/toolchain.sh run sh spikes/web-link/build.sh
python3 -m http.server 8000 --directory spikes/web-link/build/page
```

Open http://127.0.0.1:8000/index.html and read the console or the page text.

Headless Chrome on macOS fires `requestAnimationFrame` once and then stops, so
the steps never run there. A normal Chrome window runs them. Node runs them
too, with a loader linked with `-sENVIRONMENT=node`.

## The link model

Roc does the final link. It runs wasm-ld with `--no-entry`, `--import-undefined`,
`--gc-sections`, `--strip-all`, `--stack-first` and an 8 MB stack. It exports
only the names in the target's `exports` list. It wraps every platform input in
`--whole-archive`.

The platform therefore ships three files in `targets/wasm32`:

- `host.o`, one relocatable wasm object. It holds the Odin host, `main.c` and
  the members of the emscripten system libraries that they use.
- `index.js`, the loader that emcc wrote for a reference link of the same host.
- `index.html`, the page from `host/shell.html`.

The loader works with Roc's wasm when two rules hold:

- Every import of the Roc wasm is an import of the reference wasm. The loader
  supplies only those.
- Every export of the reference wasm is an export of the Roc wasm. The
  platform's `exports` list names them, `__indirect_function_table` included.

`check_link.py` checks both rules after each build.

## Commands

`build.sh` runs these steps.

1. `odin build host -target:freestanding_wasm32 -build-mode:obj -no-entry-point -default-to-nil-allocator -out:build/host_odin.o`
2. `emcc -c host/main.c -o build/main.o`
3. `emcc -v build/main.o build/host_odin.o -o targets/wasm32/index.html --shell-file host/shell.html -sALLOW_MEMORY_GROWTH=1 -sFORCE_FILESYSTEM=1 -sERROR_ON_UNDEFINED_SYMBOLS=0`

   This is the reference link. It writes the loader. Its `-v` output names the
   system libraries. `roc_init` and `roc_step` stay undefined, and the loader
   gets an unused stub for each.
4. `wasm-ld -r -o targets/wasm32/host.o build/main.o build/host_odin.o -L<sysroot> -lstubs-debug -lnoexit -lc-debug -ldlmalloc-debug -lemcc -lclang_rt.builtins` (plus the other `-l` flags from step 3)
5. `roc build --target=wasm32 --output=build/page/index.wasm main.roc`
6. Copy `index.html` and `index.js` into the page.
7. `file_packager build/page/pack.data --preload app/hello.txt@/hello.txt --js-output=build/page/pack.js`

Steps 1 to 4 are the platform prebuild. Steps 5 to 7 are the game build.
`--opt=speed` (the default) and `--opt=dev` both link.

## The smallest script after roc build

The prebuilt loader works unchanged with Roc's output, so no step patches the
wasm or the JS. The game build still needs a step after `roc build`:

- Roc writes only the `.wasm`. The page needs `index.html` and `index.js` next to
  it.
- The `.data` file holds the game's files, so the platform cannot prebuild it.

The script copies two files and runs `file_packager`. `pack.js` is a separate
script that the page loads before `index.js`, so `index.js` stays the same for
every game. `roc scripts/build.roc web <game>` can do these steps.

## Findings

- Odin reserves the link name `main`. `host/main.c` defines `main` and calls
  `rocco_web_main`.
- Odin's `-target:js_wasm32` runtime imports from `odin_env`, which the
  emscripten loader does not supply. The host uses `freestanding_wasm32` and
  calls libc through `foreign import env "env.o"`.
- Odin's default wasm allocator grows memory itself, and emscripten's `sbrk`
  does the same. The host builds with `-default-to-nil-allocator`, and Roc
  allocates through `memalign` and `free`.
- emscripten's `aligned_alloc` returned nil for some Roc allocations. Roc then
  wrote through a near-null pointer and overwrote the stack cookie. `memalign`
  works.
- `core:os` has no emscripten file system backend. `fopen` and `fread` from
  emscripten's libc reach the preloaded files.
- `wasm-ld -r` refuses `-u`, so `main.c` keeps the loader's runtime exports,
  such as `emscripten_stack_init`, alive through a used pointer table.
- A hand-written 32-bit `Roc_Str` with the fields in the wrong order made Roc
  read a length of 4096 and crash. The order is bytes, capacity, length, as in
  the 64-bit glue. The OdinGlue spike for 32-bit layouts (nuwkrpm8) removes
  this risk.
