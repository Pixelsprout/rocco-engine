# macOS sysroot provenance

`scripts/make_macos_sysroot.py` writes `platform/targets/macos-sysroot/` from
`interfaces.json` in this folder. Roc's linker reads the sysroot to link the
host with the system libraries that macOS supplies at run time.

## What the generator reads

The generator reads only `interfaces.json`. It does not read Apple SDK
headers, `.tbd` files, framework binaries, dylibs or any other installed
macOS software. No file in the sysroot comes from Apple's SDK.

Each `.tbd` file holds a target, an install name and the symbol names that the
catalog lists for that library. It holds no re-exports, versions or UUIDs.
macOS supplies every implementation at run time.

## Evidence

Each library records evidence for its install name. Each symbol records one
or more sources. A source is one of these:

- An Apple documentation page. Its JSON names the symbol as its C identifier
  or Objective-C class.
- An Apple man page that shows the function in its synopsis.
- An Apple open-source file or an LLVM file at a pinned revision, with the
  line that holds the identifier.

Each source records the sha256 of the response on the day it was fetched.

Many records are copied from roc-ray's catalog
(`lukewilliamboswell/roc-ray`, `dependencies/macos-interfaces/interfaces.json`,
UPL 1.0), which uses the same evidence rules.

The engine's archives tell us which symbols we need. They do not tell us
which library owns a symbol. Ownership comes from the evidence only.

## Change the catalog

1. Build the host and run `python3 scripts/make_macos_sysroot.py --audit`.
   It lists the undefined references in `platform/targets/arm64mac/` that
   the catalog does not cover.
2. Run a game with `roc main.roc`, then audit Roc's dev shim too:
   `python3 scripts/make_macos_sysroot.py --audit $TMPDIR/roc/<version>/<hash>/libroc_machine_code_shim.a`.
   `roc main.roc` links this shim, and `roc build` does not.
3. For each new symbol, find the public page or pinned source that declares
   it, and the library that owns it.
4. Run `python3 scripts/macos-sysroot/evidence.py <library> <symbol> <url>`.
   The script fetches the page, checks that it names the symbol, and adds the
   record.
5. Review the diff of `interfaces.json`.
6. Run `python3 scripts/make_macos_sysroot.py`. Build and run every
   example with `roc build` in debug and release, and with `roc main.roc`.
7. Commit the catalog and the sysroot together.

A link error can name a symbol that the archives do not show. For example,
compiler-rt and the linker add their own references. Find evidence for these
symbols in the same way.
