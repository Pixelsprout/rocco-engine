# Windows import libraries

Roc links x64win with no Visual Studio CRT. The host, sokol and Clay call the
C runtime in `ucrtbase.dll` instead. Each `.def` file here names one DLL and
the functions the link takes from it. `scripts/make_windows_import_libs.py`
turns each one into a `.lib` in `platform/targets/x64win/` with
`zig dlltool`.

## The format

```
; A comment.
LIBRARY "ucrtbase.dll"
EXPORTS
abort
ceil
```

- The file name matches the DLL: `ucrtbase.def` names `ucrtbase.dll`.
- One `LIBRARY` line, then `EXPORTS`, then one C identifier per line.
- List each name once, in sorted order. The script rejects anything else.
- A `;` starts a comment. Comments never reach Zig.

## Adding a name

1. Find the name in MinGW's `mingw-w64-crt/lib-common/ucrtbase-common.def.in`.
   Only add names that the DLL exports.
2. Add it to the `.def` file in sorted order.
3. Run `python3 scripts/make_windows_import_libs.py` with Zig 0.16.0. Another
   Zig version can write other bytes.
4. Run `roc scripts/build.roc -- all` and check that every game links.

A link error such as `undefined symbol: floorf` means a name is missing.
