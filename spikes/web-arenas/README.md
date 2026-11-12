# Web arenas spike

On wasm, `core:mem/virtual` reserve returns nil with no error. A virtual
arena then writes its block header through a nil pointer. Under Roc's
`--stack-first` link, address 0 is the bottom of the stack, so the write
corrupts memory and does not trap.

## Result

The engine arenas work in a wasm32 build in a browser. The package
`engine/arenas` gives the engine one `Arena` type:

- Native targets keep `core:mem/virtual`. The frame arena reserves 64 MB of
  virtual memory and commits pages as it uses them.
- wasm32 and wasm64p32 use `base:runtime`'s `Arena`. It takes each block from
  the context allocator. On the web, the host sets that allocator to libc.
- A zero-value arena takes its blocks from the context allocator at the
  first `arenas.allocator` call.
- `arenas.init_static` takes the whole block at once. On the heap, a static
  arena refuses to grow, so it returns `Out_Of_Memory` past its size, as the
  virtual static arena does.

`-define:ROCCO_ARENAS_HEAP=true` selects the heap arenas on a native build.
`scripts/test-all.sh` and CI run the `engine/arenas` tests both ways.

A Chrome window showed this console output for the default build:

```
perm: used bytes 262144
frame: reserved bytes 67108864
scratch: used bytes 12582912 0
step: frame used bytes 1 8388608
step: frame used after free_all 1 0
... (steps 2 and 3 are the same)
done: the arenas freed their blocks
```

## Memory limit

On the web, the 64 MB frame block is real memory from the start. emscripten's
default fixed memory is 16 MB.

| emcc flag | Result |
| --- | --- |
| `-sALLOW_MEMORY_GROWTH=0` (16 MB) | Aborts: "Cannot enlarge memory arrays to size 71376896 bytes (OOM)" |
| `-sINITIAL_MEMORY=96MB` | Works for this page |
| `-sALLOW_MEMORY_GROWTH=1` | Works |

The web host links with `-sALLOW_MEMORY_GROWTH=1`, as the link spike does.
A game's peak use is not known before it runs, and growth also makes
`malloc` return nil instead of aborting (`ABORTING_MALLOC` defaults off with
growth). So a failed arena block returns `Out_Of_Memory` to the engine.

## Build and run

```
sh scripts/toolchain.sh run sh spikes/web-arenas/build.sh [emcc memory flags]
python3 -m http.server <port> --directory spikes/web-arenas/build/page
```

Open `http://localhost:<port>/index.html` in a Chrome window and read the
console. Headless Chrome on macOS runs only one frame.

## Findings

- `vmem.Arena` and `runtime.Arena` both have `total_used`, so the engine
  tests that read it need no change.
- The heap frame arena zeroes its used bytes on `free_all`, as the virtual
  static arena does. It keeps its one block.
- `runtime.Arena` falls back to `default_allocator()` when it has no backing
  allocator. The web host builds with `-default-to-nil-allocator`, so the
  arenas capture the context allocator instead. That allocator must outlive
  the arena.
- `runtime.Arena` starts with 4 MB blocks. The heap arenas start at 1 MB, as
  vmem does. Each scratch arena on the web mallocs and zeroes at least 1 MB at
  its first allocation. vmem commits pages only as it uses them.
- `runtime.Arena` has no mutex. The web build has no threads, so this is safe
  now. A wasm pthreads build would need a lock.
- This page tests `engine/arenas`, not `memory_init`. The full engine package
  does not build for wasm yet. The engine call sites run only with the virtual
  arenas until it does.
