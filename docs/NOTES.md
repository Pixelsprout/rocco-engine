# rocco notes

Ideas and findings that are not in the task list yet.

## Generate our own macOS .tbd stubs

Recorded 2026-09-23. This is Alpha work, not part of milestone 1. It would
come before "Alpha: publish the platform with roc bundle".

The idea: stop copying .tbd files from the Xcode SDK
(`scripts/make-macos-sysroot.sh`) for the bundled platform. Generate our own
stubs from a symbol catalog in the repo instead.

Why:

- A bundled platform cannot depend on the user's Xcode.
- We must not redistribute Apple SDK .tbd files.
- A Zulip reply confirmed that macOS support needs .tbd stubs.

### How roc-gui does it

See `lukewilliamboswell/roc-gui`, in `dependencies/macos-interfaces/` and
`scripts/build_macos_stubs.py`.

- `interfaces.json` is a committed catalog. It lists each library with its
  install name, and each symbol the host uses.
- Each symbol has public evidence: an Apple documentation URL, or a pinned
  open-source declaration, with a response hash.
- The generator writes one small TBD v4 file per library. Each file holds the
  target, the install name and the listed symbols. It writes no re-exports.
- The generator reads no SDK files. `PROVENANCE.md` states this.
- The stubs are released as a pinned, signed dependency and packed into the
  platform bundle. The catalog holds 21 libraries and 576 symbols.

### How rocco compares

| | rocco (now) | roc-gui |
|---|---|---|
| Stub source | Copied from the installed SDK. | Generated from the catalog. |
| Contents | Apple's full .tbd files for about 16 frameworks. | Only the symbols the host uses. |
| Re-exports | Stripped today. `qh98bnhz` keeps them with the real `Versions/` layout. | None. Each library has its own stub. |
| libobjc | A fake `objc.framework`. `qh98bnhz` links it through the Foundation re-export. | Its own `usr/lib` stub with 17 runtime functions. |
| Needs Xcode | Yes. | No. It can link from Linux or Windows. |
| Committed | No. | Yes, as a released dependency. |
| Upkeep | Re-run the script after an Xcode update. | Review a catalog entry for each new system symbol. |

### Facts measured for rocco

- `libhost.a` and the sokol archives in `platform/targets/arm64mac/` import
  216 system symbols. The count is `nm -gu` minus `nm -gU`, without `_roc*`.
- 29 of the 216 are ObjC class references, for example
  `_OBJC_CLASS_$_CAMetalLayer`. They come from sokol's Objective-C code.
  roc-gui emits plain symbols only, because GPUI calls `objc_getClass` at
  runtime. TBD v4 should accept `_OBJC_CLASS_$_` names as plain symbols. This
  is not tested.
- roc-gui ships `libobjc` and `libc++` as `usr/lib` stubs. Roc emits
  `-framework` for each sysroot framework, plus `-lSystem`. We do not know how
  roc-gui gets libobjc into the link.

### Possible steps

1. Find how roc-gui links libobjc: `build.py`, the Roc version, extra `-l`
   flags, or a re-export.
2. Write a catalog of the 216 symbols, grouped by owning library, with
   evidence for each symbol.
3. Write a generator that writes TBD v4 files into
   `platform/targets/macos-sysroot` from the catalog. It must not read the SDK.
4. Link `examples/cards` against the generated sysroot and run it.
   `otool -L` must list the same system libraries as the SDK-copy build.
5. Add a check that lists archive symbols the catalog does not cover. A sokol
   or engine change must then fail loudly.

Keep `scripts/make-macos-sysroot.sh` for local development until the
generated stubs link and run.

## Hot reload after a Model type change

Recorded 2026-09-24. Milestone 2 supports hot reload only when the `Model`
type does not change. A changed type is undefined, because the host cannot
see the layout.

The follow-up: the platform wrappers export a layout fingerprint of `Model`,
for example `model_version_for_host`. After a reload the host compares it
with the old one. If it differs, the host drops the old box and calls `init`
again. The state is lost, but the run does not crash.

## Findings from the milestone 2 grilling

Recorded 2026-09-24, on `nightly-2026-09-12-220fd47`.

- OdinGlue fails on `U32` before it reaches `Str` or `Box`:
  `OdinGlue: no Odin spelling for u32 (type id 4)`.
- The Zig glue emits `RocStr` (24 bytes, up to 23 bytes inline, small when
  the last byte has its top bit set), `RocBox` as an opaque pointer, and
  `decref` and `incref` for every struct. A list of records that hold a `Str`
  has a 16-byte header in front of the data. Other lists and strings have an
  8-byte header. The refcount is the `isize` just before the data.
- A local package works as the camera library. `camera/main.roc` is
  `package [Camera] {}` with `import Camera`. `Camera.roc` must hold a
  nominal type: `Camera := [].{ View : {...}, look_at = ..., follow = ... }`.
  A structural alias nested in the nominal type, such as `Cam.View`, unifies
  with the platform's inline camera record. The app header adds
  `cam: "../../packages/camera/main.roc"`.
- An exposed platform module also works, but it needs `exposes [Camera]` and
  `import Camera` in the platform body. `import pf.Camera` then clashes with
  a local alias named `Camera`.
- When `roc check` fails, `roc test` still prints "All (N) tests passed" and
  exits 1. Scripts must read the exit code.
