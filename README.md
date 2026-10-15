# rocco

Project page: <https://pixelsprout.dev/projects/rocco/>

A 3D game engine in Odin that runs games written in Roc.

Odin manages the systems: window, clock, input, GPU, memory, audio, collision.
Roc manages the game: its state and its rules, as pure functions. The engine
is a Roc platform. The game is a Roc app. `docs/DESIGN.md` says where the line
goes and why. `docs/ROADMAP.md` says what is built next.

rocco builds for three desktop targets from one checkout. Each machine
builds its own target. The renderer goes through sokol with a different
backend per OS.

| | macOS arm64 | Linux x64 | Windows x64 |
|---|---|---|---|
| Roc target | `arm64mac` | `x64glibc` | `x64win` |
| sokol backend | Metal | GL core | D3D11 |
| Host library | `libhost.a` | `libhost.a` | `host.lib` |
| Game binary | `examples/<game>/<game>.bin` | `examples/<game>/<game>_linux.bin` | `examples/<game>/<game>.exe` |
| Tested | Natively | In the Docker image, under `xvfb-run` | Natively, by hand |

## Requirements

Clone with the submodules:

```sh
git clone --recurse-submodules https://github.com/Pixelsprout/rocco-engine.git
```

In an existing clone, run `git submodule update --init`.

| | macOS arm64 | Linux x64 | Windows x64 |
|---|---|---|---|
| Odin | `dev-2026-08`, on `PATH` | In the Docker image | `dev-2026-08` windows-amd64 release, on `PATH` |
| Roc | `nightly-2026-09-27-a3ce7f1`, on `PATH` | In the Docker image | `nightly-2026-09-27-a3ce7f1` windows_x86_64 zip, on `PATH` |
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
- `clay/` is nicbarker/clay, pinned to a commit on main. The engine imports
  its Odin bindings, and the `inputs` step copies their prebuilt `clay.a`.
  The x64win target does not link Clay yet.

You need `sokol-shdc` only to change the shader. The generated
`engine/shader_basic.odin` is committed. The tested setup is a clone of
`floooh/sokol-tools-bin` at `~/tools/sokol-tools-bin`, commit `11d0cf6`, with
`~/tools/sokol-tools-bin/bin/osx_arm64` on `PATH`.

## Build

`scripts/build.roc` runs every build step. Run it from the repository root.
The target is the machine it runs on. Odin and Roc come from `PATH`.

| Command | When | What it runs |
|---|---|---|
| `glue` | When `platform/main.roc` changes. | `roc glue --no-cache glue/OdinGlue.roc ./engine platform/main.roc` |
| `host` | When `engine/` changes. | `odin build engine -build-mode:static -debug -vet -strict-style` into `platform/targets/<target>/` |
| `inputs` | Once, and after a sokol, Clay or SDK update. | Copies the sokol archives and Clay's `clay.a` into `platform/targets/<target>/`. On macOS, copies compiler-rt and runs `scripts/make-macos-sysroot.sh`. On Linux, copies the CRT objects and shared libraries. On Windows, copies the SDK import libraries. |
| `game <name>` | When anything changes. | `roc build` in `games/<name>/`, or else `examples/<name>/` |
| `shaders` | When `engine/shaders/basic.glsl` changes. | `sokol-shdc` with the command in the header of `engine/shader_basic.odin`. Skips if `sokol-shdc` is not on `PATH`. |
| `font` | When the bake tool or the font changes. | `odin run scripts/font_bake`, which writes `engine/font_baked.odin` from `scripts/fonts/AtkinsonHyperlegible-Regular.ttf`. Keeps the committed file if `odin` is not on `PATH` or the tool fails. On Linux, build Odin's stb libraries first with `"$(odin root)/vendor/stb/src/build_stb.sh"`. |
| `keys` | After a `sokol-odin` update. | Writes `platform/Key.roc` from the `Keycode` enum in `sokol-odin/sokol/app/app.odin`. `scripts/host-check.sh` fails if `platform/Key.roc` is stale. |
| `target` | When a check script runs. | Prints `target=`, `suffix=` and `host_lib=` lines for this machine. `scripts/alloc-check.sh` and `scripts/host-check.sh` read them. |
| `all` | From a fresh checkout. | `glue`, `host`, `inputs`, `game cards`, `game entity-game`, `game pong`, `game kula` |

The script stops at the first step that fails. After a change, run `glue`,
`host` and `game` in that order. Each tool consumes the previous one's output
and cannot tell whether that output is stale.

`roc test scripts/build.roc` runs the script's tests. `roc test
scripts/Keys.roc` runs only the tests of the Key generator.
`./scripts/host-check.sh` runs the tests inside `platform/Key.roc`. `odin test
engine -debug` runs the engine's tests. `odin test scripts/font_bake` runs
the tests of the font bake tool.

Roc files follow `roc fmt`. Run `git config core.hooksPath .githooks` once
per clone. The pre-commit hook then stops a commit that stages a `.roc` file
that `roc fmt --check` rejects.

`ROCCO_EXIT_AFTER_FRAMES=N` makes the game quit after N rendered frames. The
game then prints `Frame Count: N` and exits with code 0. Without the variable,
the game runs until it returns `Quit` or you close the window. The entity
game quits on Escape. A value that is not a positive integer stops the game
at startup with exit code 1.

The other variables the engine reads:

| Variable | Effect |
|---|---|
| `ROCCO_SEED=N` | The seed in `Config`. The default is 0. A value that is not an unsigned 64-bit integer stops the game with exit code 1. |
| `ROCCO_DEBUG_CAMERA=1` | A fly camera on WASD and the mouse, with the mouse locked. The host ignores `Scene.camera`. The game still gets all input. |
| `ROCCO_ALLOC_REPORT=1` | One line per fixed step: Roc allocs, deallocs, reallocs, live blocks, and `step` and `view` time in microseconds. |

`./scripts/alloc-check.sh` builds each game under `--opt=dev` and
`--opt=speed`, runs it with no input, and checks every step after the first
10: the game's expected allocs and as many deallocs, 0 reallocs and a
constant live block count. cards expects 2 allocs and entity-game 3. Build
the host library first. Each game opens a window. Do not type into it during the
check, because a key press allocates the `Input` lists.

`./scripts/host-check.sh` regenerates the glue and links cards, entity-game
and kula, then checks that the host library and the glue did not change.

### Screenshots

`scripts/screenshot.sh <game> <out.png> [delay]` runs a built game, waits
`delay` seconds (default 3), saves the game window to `out.png` and stops the
game. The capture works when other windows cover the game window. `ROCCO_*`
variables pass through, so `ROCCO_DEBUG_CAMERA=1` and `ROCCO_SEED` work.
Build the game first with `roc scripts/build.roc -- game <game>`.

The script runs on macOS only. It builds `scripts/macos/wincap.swift` into
`build/wincap` with `swiftc` when the source changes. The first capture
asks for Screen Recording permission for the terminal. Grant it, then run the
script again.

### macOS

```sh
cd sokol-odin/sokol && sh build_clibs_macos.sh && cd ../..
roc scripts/build.roc -- all
./examples/entity-game/entity-game.bin
```

On macOS, the script also calls `xcrun` to find compiler-rt and the SDK.

### Linux, in Docker

```sh
./scripts/linux/check.sh
```

The script needs Docker and runs on any machine that has it. It builds the
Docker image in `scripts/linux/`. In the Docker image, it builds the sokol GL
archives. Then it runs the `all` command of the build script. Then it runs
each game under `xvfb-run` with software GL and `ROCCO_EXIT_AFTER_FRAMES=120`.
Each run passes on exit code 0 and one `Frame Count: 120` line. Then it runs
the alloc check and the host check.

The first run builds the Docker image. On Apple silicon, Docker emulates
x86_64, so that first run takes several minutes. Later runs take about 15
seconds.

The Docker image writes into the same checkout as the macOS build. That is
why the Linux binary has its own name.

The check runs the game with no screen. To see the picture, build on a Linux
x64 desktop.

### Linux, on the machine

You need Odin and Roc on `PATH`, a C compiler, glibc 2.39 or newer, and the
X11, Xi, Xcursor and GL libraries with their headers.

| Distro | Packages |
|---|---|
| Ubuntu, Debian | `build-essential libx11-dev libxi-dev libxcursor-dev libgl-dev libglx-mesa0` |
| Arch, tested on Omarchy through XWayland | `base-devel libx11 libxi libxcursor libglvnd mesa`. Omarchy has them all by default. |

```sh
cd sokol-odin/sokol && sh build_clibs_linux.sh && cd ../..
roc scripts/build.roc -- all
./examples/entity-game/entity-game_linux.bin
```

The `inputs` step copies the CRT objects and the shared libraries from the
first of `/usr/lib/x86_64-linux-gnu`, `/usr/lib64` and `/usr/lib` that holds
`Scrt1.o`. `build_clibs_linux.sh` also builds modules the engine does not
use, and it needs the ALSA headers. `scripts/linux/in-container.sh` shows how
to build only the four archives the engine links.

### Windows

Run every step in one `cmd` window where `vcvars64.bat` has run, so that `cl`
and `lib` are on `PATH`. The Start menu calls this window the x64 Native
Tools Command Prompt.

```bat
cd sokol-odin\sokol
build_clibs_windows.cmd
cd ..\..
roc scripts\build.roc -- all
examples\entity-game\entity-game.exe
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

`cd examples/entity-game && roc run main.roc`. Edit `main.roc`. The
running game picks up the new code and keeps its state. Hot reload needs the
dev backend, which is `roc run`'s default. `roc build` defaults to
`--opt=speed`. It is tested on macOS.

Hot reload keeps the state only when the `Model` type does not change. After
a change to the `Model` type, restart the game.

## Layout

| Path | Contents |
|---|---|
| `engine/` | The Odin engine. Builds to one host library per target. |
| `engine/platform_darwin.odin`, `platform_linux.odin`, `platform_windows.odin` | The platform files. One per OS, selected by `#+build`. Each holds the expected sokol backend. `when ODIN_OS` may appear only in these files. |
| `engine/roc_platform_abi.odin` | Generated by `roc glue`. Do not edit. |
| `engine/seam.odin` | The Seam: the call protocol over the game calls. |
| `engine/roc_runtime.odin` | The Roc heap and the six hooks the Roc app calls. |
| `engine/shaders/` | Shader source in sokol-shdc annotated GLSL. |
| `engine/shader_basic.odin` | Generated by sokol-shdc, with MSL, GLSL and HLSL. Do not edit. |
| `engine/font_baked.odin` | Generated by `roc scripts/build.roc -- font`: the SDF atlas, the glyph metrics and the kerning pairs. Do not edit. |
| `scripts/fonts/` | Atkinson Hyperlegible Regular and its OFL licence. |
| `platform/main.roc` | The platform: the header every game links against, the host wrappers, and the link inputs per target. |
| `platform/Key.roc` | Generated by `roc scripts/build.roc -- keys`. Do not edit. Games import it as `import pf.Key`. |
| `platform/Vocabulary.roc` | The vocabulary types. Games import them as `import pf.Vocabulary exposing [...]`. |
| `platform/targets/arm64mac/` | `libhost.a`, the sokol Metal archives and compiler-rt. Not committed. |
| `platform/targets/macos-sysroot/` | The SDK stubs from `scripts/make-macos-sysroot.sh`. Not committed. |
| `platform/targets/x64glibc/` | `libhost.a`, the sokol GL archives, the CRT objects and the shared libraries from the Docker image. Not committed. |
| `platform/targets/x64win/` | `host.lib`, the sokol D3D11 libraries and the SDK import libraries. Not committed. |
| `examples/cards/` | A game with no entities: SPACE deals a card. |
| `examples/entity-game/` | A game with entities: WASD moves the player, the camera follows, pickups open a door. Its meshes are in `assets/meshes/`. |
| `examples/pong/` | Two-player pong: W and S move the left paddle, UP and DOWN the right, SPACE pauses. |
| `games/kula/` | A Kula World clone: a ball rolls over blocks, collects keys and rolls into the exit. Its `README.md` has the rules and the level format. |
| `packages/camera/` | The camera package: `look_at` and `follow`. Games import it as `import cam.Camera as Cam`. |
| `packages/mesh/` | The mesh package resolves mesh ids from the manifest with `primitive` and `resolve`. Games import it as `import mesh.Mesh as Mesh`. |
| `packages/ui/` | The UI package builds `Scene.ui` from nested `box` and `text` calls. `default_box` holds Clay's defaults. Games import it as `import ui.Ui`. |
| `scripts/build.roc` | The build script. Its `target` command gives the check scripts the Roc target, binary suffix and host library. |
| `scripts/Keys.roc` | The Key generator. `build.roc` imports it to write `platform/Key.roc`. |
| `scripts/alloc-check.sh` | Checks the allocations per fixed step of both games. |
| `scripts/host-check.sh` | Checks that linking cards, entity-game and kula does not change the host library or the glue. |
| `scripts/make-macos-sysroot.sh` | Copies the SDK stubs the macOS link needs. |
| `scripts/screenshot.sh` | Runs a game and saves its window to a PNG. macOS only. |
| `scripts/macos/wincap.swift` | The window capture tool that `screenshot.sh` builds and runs. |
| `scripts/linux/` | The Linux Docker image, the script that runs in it, and `check.sh`, the wrapper that runs the check from any machine with Docker. |
| `sokol-odin/` | Submodule: floooh/sokol-odin. The engine imports its `sokol/` folder. |
| `glue/` | Submodule: the roc-odin-glue spec. |
| `clay/` | Submodule: nicbarker/clay. The engine imports `bindings/odin/clay-odin/`. |
| `docs/DESIGN.md` | The design. Read first. |
| `docs/ROADMAP.md` | Milestones and what is out of scope. |
| `docs/GLOSSARY.md` | Terms as rocco uses them. |

## A game outside this repo

A game is a Roc app whose header names this platform. Point `pf` at a
checkout of this repo:

```roc
app [init, step, view] { roc: "nightly-2026-09-27-a3ce7f1", pf: platform "../rocco-engine/platform/main.roc" }
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

Milestones 1 to 10 of `docs/ROADMAP.md` are done. The engine builds and runs
on macOS, Linux and Windows from one checkout. The platform names no game:
four games (`cards`, `entity-game`, `pong`, `kula`) link against one host library.
Each draw carries a mesh id from a Manifest, and an unknown id draws the
magenta fallback mesh. Games import the seam types from `pf.Vocabulary` and
name keys with `pf.Key`.

At startup the engine loads only its primitives and lists the `.glb` files in
`assets/meshes/` beside the game in `Config.assets`, by file stem. A game
sends `Load` with a pack name and the names it wants. The host loads them and
calls `loaded` with each id before the next `view`. `roc run` and the built
binary both find the assets from any working directory.
`ROCCO_ASSETS` replaces the `assets` path. The entity game draws its player
as the sprout model. Colours and tints are linear, and the shader encodes to
sRGB. Milestone 5, entities in Roc, is next.

## Licence

UPL-1.0. See `LICENSE`.
