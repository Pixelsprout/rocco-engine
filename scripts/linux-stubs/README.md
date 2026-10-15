# Linux CRT objects and stubs

`scripts/make_linux_stubs.py` writes these files in `platform/targets/x64glibc/`:

- `Scrt1.o`, `crti.o` and `crtn.o`, from the `.s` files in this folder.
- One stub shared library for each soname in the catalog, `stubs.json`: `libc.so.6`,
  `libm.so.6`, `libX11.so.6`, `libXi.so.6`, `libXcursor.so.1` and `libGL.so.1`.

The files are committed, so a build needs no C development packages. Only a
maintainer who changes a stub needs Zig.

## What a stub holds

A stub exports each function in the catalog as a bare `ret`, and each object
as zeros of its size. Roc's linker records the soname as `DT_NEEDED`. At run
time the system library supplies every symbol. The program never runs stub
code.

A stub has no symbol versions. The dynamic linker binds each reference to the
oldest version of the symbol, for example `memcpy@GLIBC_2.2.5`.

An object needs its real size. The executable copies the object into its own
memory with a copy relocation, and the stub size sets the copy size. Read the
size from `nm -D -S` on the system library.

`Scrt1.s` calls `__libc_start_main` with no init or fini function. glibc 2.34
and later then run the constructors from the dynamic section. glibc 2.34 also
moved `dlopen` and `dlsym` into `libc.so.6`. So the program needs glibc 2.34 or
later.

## Change a stub

1. Build the host and the inputs in the Linux image. Use debug and `--release`.
2. Run `python3 scripts/make_linux_stubs.py --audit`. It lists the undefined
   references in `platform/targets/x64glibc/` that the catalog lacks.
3. Run a game with `roc main.roc`.
4. Audit Roc's dev shim:
   `python3 scripts/make_linux_stubs.py --audit $TMPDIR/roc/<version>/<hash>/libroc_machine_code_shim.a`.
5. For each new name, find its library with `nm -D --defined-only` on the
   system libraries. Add the name to that library in the catalog.
   If the name has more than one version, read the oldest version's behaviour
   first. For example, `pthread_cond_wait@GLIBC_2.2.5` is an old compat ABI.
6. Install the Zig version that `ZIG_VERSION` in the script names.
7. Run `python3 scripts/make_linux_stubs.py`.
8. Run `scripts/linux/check.sh` and `scripts/linux/check.sh --release`.
9. Commit the catalog and the outputs together.

`roc main.roc` links the dev shim, and `roc build` does not. So step 4 can
find names that step 2 does not find.

If a stub lacks a name, the link fails with `undefined symbol` and the name.

## Check the outputs

Run `python3 scripts/make_linux_stubs.py`, then
`git diff --exit-code platform/targets/x64glibc`. A diff means that the
committed outputs do not match the sources. The outputs depend only on the
sources and the Zig version. Zig on macOS and Zig on Linux write the same bytes.

## Origin

The approach follows roc-ray (`lukewilliamboswell/roc-ray`,
`platform/targets/x64v1glibc/libc_stub.s`, UPL 1.0). The CRT sources and the
generator are written for this repository.
