# rocco

A 3D game engine in Odin that runs games written in Roc.

Odin owns the systems: window, clock, input, GPU, memory, audio, collision.
Roc owns the game: its state and its rules, as pure functions. The engine is
a Roc platform. The game is a Roc app. `docs/DESIGN.md` says where the line
goes and why. `docs/ROADMAP.md` says what is built next.

rocco builds for three desktop targets from one checkout. Each machine
builds its own target. The renderer goes through sokol with a different
backend per OS.

| | macOS arm64 | Linux x64 | Windows x64 |
|---|---|---|---|
| Roc target | `arm64mac` | `x64glibc` | `x64win` |
| sokol backend | Metal | GL core | D3D11 |
| Host library | `libhost.a` | `libhost.a` | `host.lib` |
| Game binary | `examples/bodies/bodies.bin` | `examples/bodies/bodies_linux.bin` | `examples/bodies/bodies.exe` |
| Tested | Natively | In the Docker image, under `xvfb-run` | Natively, by hand |

## Requirements

Clone with both submodules:

```sh
git clone --recurse-submodules https://github.com/Pixelsprout/rocco-engine.git
```

In an existing clone, run `git submodule update --init`.

| | macOS arm64 | Linux x64 | Windows x64 |
|---|---|---|---|
| Odin | `dev-2026-08`, on `PATH` | In the Docker image | `dev-2026-08` windows-amd64 release, on `PATH` |
| Roc | `nightly-2026-09-12-220fd47`, on `PATH` | In the Docker image | `nightly-2026-09-12-220fd47` windows_x86_64 zip, on `PATH` |
| System tools | Xcode command line tools | Docker | Visual Studio Build Tools with the Desktop development with C++ workload, and a Windows SDK |
| sokol archives | `sh build_clibs_macos.sh` in `sokol-odin/sokol/`, once | The Linux check builds them | `build_clibs_windows.cmd` in `sokol-odin/sokol/`, once |
| sokol-shdc, dev-only | `bin/osx_arm64` from sokol-tools-bin | Not tested | Not tested |

The tested macOS Odin is build `dev-2026-08:251d8eb0b`. The Docker image
uses the `dev-2026-08` release archive, which reports `902106f`.

The Roc pin lives in `platform/main.roc`, in every app under `examples/` and
in `scripts/build.roc`. A different compiler warns and builds anyway. Fix the
`PATH`, never the pin.

The submodules:

- `sokol-odin/` is floooh/sokol-odin. The engine imports its `sokol/` folder.
  Built archives stay untracked in the submodule.
- `glue/` is roc-odin-glue. `roc glue` uses it to generate
  `engine/roc_platform_abi.odin`.

You need `sokol-shdc` only to change the shader. The generated
`engine/shader_basic.odin` is committed. The tested setup is a clone of
`floooh/sokol-tools-bin` at `~/tools/sokol-tools-bin`, commit `11d0cf6`, with
`~/tools/sokol-tools-bin/bin/osx_arm64` on `PATH`.

## Build

`scripts/build.roc` runs every build step. Run it from the repository root.
The target is the machine it runs on. Odin and Roc come from `PATH`.

| Command | When | What it runs |
|---|---|---|
| `glue` | When `platform/main.roc` changes. | `roc glue glue/OdinGlue.roc ./engine platform/main.roc` |
| `host` | When `engine/` changes. | `odin build engine -build-mode:static -debug -vet -strict-style` into `platform/targets/<target>/` |
| `inputs` | Once, and after a sokol or SDK update. | Copies the sokol archives into `platform/targets/<target>/`. On macOS, copies compiler-rt and runs `scripts/make-macos-sysroot.sh`. On Linux, copies the CRT objects and shared libraries. On Windows, copies the SDK import libraries. |
| `game <example>` | When anything changes. | `roc build` in `examples/<example>/` |
| `shaders` | When `engine/shaders/basic.glsl` changes. | `sokol-shdc` with the command in the header of `engine/shader_basic.odin`. Skips if `sokol-shdc` is not on `PATH`. |
| `all` | From a fresh checkout. | `glue`, `host`, `inputs`, `game bodies` |

The script stops at the first step that fails. After a change, run `glue`,
`host` and `game` in that order. Each tool consumes the previous one's output
and cannot tell whether that output is stale.

`roc test scripts/build.roc` runs the script's tests. `odin test engine
-debug` runs the engine's tests.

`ROCCO_EXIT_AFTER_FRAMES=N` makes the game quit after N rendered frames. The
game then prints `Frame Count: N` and exits with code 0. Without the variable,
the game runs until you press Escape. A value that is not a positive integer
stops the game at startup with exit code 1.

### macOS

```sh
cd sokol-odin/sokol && sh build_clibs_macos.sh && cd ../..
roc scripts/build.roc -- all
./examples/bodies/bodies.bin
```

On macOS, the script also calls `xcrun` to find compiler-rt and the SDK.

### Linux, in Docker

```sh
./scripts/linux/check.sh
```

The script needs Docker and runs on any machine that has it. It builds the
Docker image in `scripts/linux/`. In the Docker image, it builds the sokol GL
archives. Then it runs the `all` command of the build script. Then it runs
the game under `xvfb-run` with software GL and `ROCCO_EXIT_AFTER_FRAMES=120`.
The check passes on exit code 0 and one `Frame Count: 120` line.

The first run builds the Docker image. On Apple silicon, Docker emulates
x86_64, so that first run takes several minutes. Later runs take about 15
seconds.

The Docker image writes into the same checkout as the macOS build. That is
why the Linux binary has its own name.

The check runs the game with no screen. To see the picture, run
`examples/bodies/bodies_linux.bin` on a Linux x64 desktop with X11 and glibc
2.39 or newer. Nobody has tested this yet.

### Windows

Run every step in one `cmd` window where `vcvars64.bat` has run, so that `cl`
and `lib` are on `PATH`. The Start menu calls this window the x64 Native
Tools Command Prompt.

```bat
cd sokol-odin\sokol
build_clibs_windows.cmd
cd ..\..
roc scripts\build.roc -- all
examples\bodies\bodies.exe
```

`lib.exe` prints warning LNK4044 for the `/PDB` and `/DEBUG` options. The
warnings are harmless. The tested setup is Visual Studio Build Tools 2026,
MSVC 14.51.

### Why there is no cross-compiling

- Roc refuses `x64glibc` from a machine that does not run Linux.
- `x64musl` cross-links from macOS but is always static. sokol needs the
  shared X11 and GL libraries, so `x64musl` cannot open a window.
- `x64win` needs a Windows SDK for the import libraries, and sokol's Windows
  script needs `cl`.

So each machine builds its own target. The Roc linker takes only files listed
in the `targets:` block of `platform/main.roc`, from
`platform/targets/<target>/`. The `inputs` step fills that directory for the
OS of the machine.

### Hot reload

`cd examples/bodies && roc run --watch main.roc`. Edit `main.roc`. The
running game picks up the new code and keeps its state. Hot reload needs the
dev backend, which is `roc run`'s default. It is tested on macOS.

## Layout

| Path | Contents |
|---|---|
| `engine/` | The Odin engine. Builds to one host library per target. |
| `engine/platform_darwin.odin`, `platform_linux.odin`, `platform_windows.odin` | The platform files. One per OS, selected by `#+build`. Each holds the expected sokol backend. `when ODIN_OS` may appear only in these files. |
| `engine/roc_platform_abi.odin` | Generated by `roc glue`. Do not edit. |
| `engine/shaders/` | Shader source in sokol-shdc annotated GLSL. |
| `engine/shader_basic.odin` | Generated by sokol-shdc, with MSL, GLSL and HLSL. Do not edit. |
| `platform/main.roc` | The platform: the header every game links against, the host wrappers, and the link inputs per target. |
| `platform/targets/arm64mac/` | `libhost.a`, the sokol Metal archives and compiler-rt. Not committed. |
| `platform/targets/macos-sysroot/` | The SDK stubs from `scripts/make-macos-sysroot.sh`. Not committed. |
| `platform/targets/x64glibc/` | `libhost.a`, the sokol GL archives, the CRT objects and the shared libraries from the Docker image. Not committed. |
| `platform/targets/x64win/` | `host.lib`, the sokol D3D11 libraries and the SDK import libraries. Not committed. |
| `examples/bodies/` | The game that links today: three bodies on a track. Points at `../../platform/main.roc`. |
| `scripts/build.roc` | The build script. |
| `scripts/make-macos-sysroot.sh` | Copies the SDK stubs the macOS link needs. |
| `scripts/linux/` | The Linux Docker image, the script that runs in it, and `check.sh`, the wrapper that runs the check from any machine with Docker. |
| `sokol-odin/` | Submodule: floooh/sokol-odin. The engine imports its `sokol/` folder. |
| `glue/` | Submodule: the roc-odin-glue spec. |
| `docs/DESIGN.md` | The design. Read first. |
| `docs/ROADMAP.md` | Milestones and what is out of scope. |
| `docs/GLOSSARY.md` | Terms as rocco uses them. |
| `docs/examples/` | The generic platform from the design and two games for it. They check and test. They do not link yet; roadmap milestone 2 promotes them to `platform/` and `examples/`. |

## A game outside this repo

A game is a Roc app whose header names this platform. Point `pf` at a
checkout of this repo:

```roc
app [init, step] { roc: "nightly-2026-09-12-220fd47", pf: platform "../rocco-engine/platform/main.roc" }
```

The platform is not published as a Roc package URL yet. Until then, the
checkout needs one full build on each OS.

1. On each OS, build the checkout once with the tools under Requirements. Use
   `roc scripts/build.roc -- all`.
2. After that build, `platform/targets/<target>/` holds every link input. The
   game author does not need Odin, sokol or the glue.
3. On macOS and Windows, the game author installs Roc only.
4. The game author runs `roc build` in the game's directory.

Linux has no path for a game outside this repo yet. The Linux link runs in
the Docker image, and the image sees only this checkout.

## Status

The engine renders three cubes, flies a camera, and calls the game's `step`
once per fixed step. The host honours `roc_dealloc`. It builds and runs on
macOS, Linux and Windows from one checkout. The platform header still names a
concrete state record. Roadmap milestone 2 replaces it with the generic header
in the design.
