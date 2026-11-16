# 0039: A game makes its Web build in its own folder

Status: accepted, 2026-11-16.

## Context

`build.roc web <name>` builds only `examples/<name>`, and `web_package.py`
reads the loader, `rocco.js` and the Default page from the checkout's
`platform/targets/wasm32`. A game in its own repository had to be copied into
a rocco checkout at the same tag, with its header pointed at the checkout.
Packing `assets/` also needed emsdk, for `file_packager`.

The platform bundle already holds every file a Web build needs:
`targets/wasm32/` has `host.o`, `index.js`, `rocco.js`, `index.html` and
`reference.wasm`. Roc unpacks a bundle into its cache, in a folder named by the
hash in the bundle URL.

## Decision

- `scripts/rocco_web.py` replaces `web_package.py`. It takes a game folder,
  runs `roc build --target=wasm32`, and writes the page folder and the zip.
  Each release uploads it as an asset, and the docs link it as
  `{{rocco_web_url}}`.
- It finds the platform through the `platform "..."` string in the game's
  `main.roc`:
  - A local path names the platform's `main.roc`. The platform folder is its
    folder. `examples/` games take this path.
  - A URL ends in `<hash>.tar.zst`. The platform folder is
    `<Roc cache>/packages/<hash>`. The Roc cache is `ROC_CACHE_DIR`, then
    `XDG_CACHE_HOME/roc`, then `~/.cache/roc`, then `LOCALAPPDATA/roc`.
  - `--platform <dir>` overrides both.
- It reads the target files from `<platform>/targets/wasm32/`. A platform
  with no `reference.wasm` there is older than v0.14.0, and the build stops.
- It packs `assets/` in Python. `index.data` holds the files end to end.
  `index.data.js` makes the folders and files in the Emscripten FS in
  `preRun`, as `file_packager` did. If `index.data` does not load, it
  dispatches `rocco:stopped` with reason `load`.
- `build.roc web <name>` keeps its interface. It builds the web host if there
  is none, then runs `rocco_web.py`.
- `rocco.js` focuses the window on `pointerdown`. sokol cancels `mousedown` on
  the canvas, so a click never moved focus back to a Page in an iframe, and
  the keys went elsewhere.

## Considered options

- `build.roc web <path>` for any folder. Rejected: the game still needs a
  checkout at the same tag and emsdk.
- Ship `rocco_web.py` inside the platform bundle. Rejected: to run it, the
  author must first find the bundle in the Roc cache.
- A loader that reads the EM_ASM offset at load time, and assets fetched at
  run time, so a game needs no package step. Rejected for now: it changes the
  host and the loader. It stays open.

## Consequences

- A game needs Roc and Python 3 for a Web build. It needs no rocco checkout
  and no emsdk. Building the web host still needs emsdk.
- `rocco_web.py` depends on Roc's cache layout. If Roc moves its cache, the
  script stops with the folders it tried, and `--platform` works around it.
- `rocco_web.py` from one release can build a game pinned to another release
  from v0.14.0 on, because it reads every target file from the game's bundle.
