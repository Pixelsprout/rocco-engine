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
4. Link `examples/bodies` against the generated sysroot and run it.
   `otool -L` must list the same system libraries as the SDK-copy build.
5. Add a check that lists archive symbols the catalog does not cover. A sokol
   or engine change must then fail loudly.

Keep `scripts/make-macos-sysroot.sh` for local development until the
generated stubs link and run.
