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
| Roc | `nightly-2026-10-11-7d256b9`, on `PATH` | In the Docker image | `nightly-2026-10-11-7d256b9` windows_x86_64 zip, on `PATH` |
| System tools | Xcode command line tools | Docker | Visual Studio Build Tools with the Desktop development with C++ workload and its Windows SDK, for the sokol build. Python 3 and Zig 0.16.0, only to change an import library |
| sokol archives | `sh build_clibs_macos.sh` in `sokol-odin/sokol/`, once | The Linux check builds them | `scripts\windows\build_sokol.cmd` from the repo root, once |
| miniaudio archive | `sh scripts/macos/build-miniaudio.sh`, once | The Linux check builds it | `scripts\windows\build_miniaudio.cmd` from the repo root, once |
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
- `miniaudio/` is mackron/miniaudio, pinned at the `0.11.24` tag. The
  build-miniaudio script for each OS compiles `scripts/miniaudio/rocco_miniaudio.c`,
  which holds miniaudio and its `extras/stb_vorbis.c`, into one archive in
  `build/miniaudio/`. `engine/miniaudio.odin` binds the calls the host makes.
  See ADR 0011.

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
| `host` | When `engine/` changes. | `odin build engine -build-mode:static -debug -define:ROCCO_TRACK_ALLOC=true -vet -strict-style` into `platform/targets/<target>/`. With `--release`, it uses `-o:speed` and drops `-debug` and `ROCCO_TRACK_ALLOC`. `--release --track-alloc` keeps `ROCCO_TRACK_ALLOC`, which turns on the host tracking allocator and its leak report at exit. `--spans` and `--release --spans` add `-define:ROCCO_SPANS=true`, which turns on the Span timers. The step deletes the old library first. |
| `inputs` | Once, and after a sokol, Clay, miniaudio or SDK update. | Copies the debug sokol archives, Clay's `clay.a` and the debug miniaudio archive into `platform/targets/<target>/`. With `--release`, it copies the release sokol and miniaudio archives. The copies drop the mode from the name, for example `sokol_gfx.a`. On macOS, copies compiler-rt. On Linux, copies nothing more: the CRT objects and stubs are committed. On Windows, copies nothing more: the import libraries are committed. |
| `game <name>` | When anything changes. | `roc build` in `examples/<name>/`. The binary takes the name of the last folder, so `game tutorial/01-window` writes `examples/tutorial/01-window/01-window.bin`. |
| `shaders` | When `engine/shaders/basic.glsl` changes. | `sokol-shdc` with the command in the header of `engine/shader_basic.odin`. Skips if `sokol-shdc` is not on `PATH`. |
| `font` | When the bake tool or the font changes. | `odin run scripts/font_bake`, which writes `engine/font_baked.odin` from `scripts/fonts/AtkinsonHyperlegible-Regular.ttf`. Keeps the committed file if `odin` is not on `PATH` or the tool fails. On Linux, build Odin's stb libraries first with `"$(odin root)/vendor/stb/src/build_stb.sh"`. |
| `keys` | After a `sokol-odin` update. | Writes `platform/Key.roc` and `engine/key_tags.odin` from the `Keycode` enum in `sokol-odin/sokol/app/app.odin`. `scripts/host-check.sh` fails if either file is stale. |
| `docs` | When a guide page, a region in its source or a `##` comment changes. | `roc docs` for `platform/main.roc`, `packages/linalg`, `packages/mesh`, `packages/ui` and `packages/camera`, each into `build/docs/<name>/`. It fails if an item in the API pages has no `##` comment. Then it copies each region into the `guide/` pages. With `--check`, it writes no guide page and fails if a page differs from its source. See "Docs". |
| `target` | When a check script runs. | Prints `target=`, `suffix=` and `host_lib=` lines for this machine. `scripts/alloc-check.sh` and `scripts/host-check.sh` read them. |
| `bench <game>[,<game>...] [n...] [--windowed]` | To measure one or more bench games. | `host --release --spans`, `inputs --release` and `roc build` in each `bench/<game>/`. Then it runs one sweep over N from 64 to 16,384 in powers of two, or only the N given, with all games and N in one shuffled order. See "Benchmarks". A Spans host stops any run without `ROCCO_SPANS_CSV` and `ROCCO_EXIT_AFTER_FRAMES`, so run `all` again before you run the examples. |
| `all` | From a fresh checkout. | `glue`, `host`, `inputs`, `game cards`, `game entity-game`, `game pong`, then `game` for each tutorial chapter, such as `game tutorial/01-window`. With `--release`, it passes `--release` to `host` and `inputs`. |

Use debug for local work. Use `--release` for CI and the bundle, so CI tests
the files that ship. `platform/main.roc` names the sokol archives with no
mode, so it links the mode that `inputs` copied last. Run `host` and `inputs`
with the same mode.

The script stops at the first step that fails. After a change, run `glue`,
`host` and `game` in that order. Each tool consumes the previous one's output
and cannot tell whether that output is stale.

`roc test scripts/build.roc` runs the script's tests. `roc test
scripts/Keys.roc` runs only the tests of the Key generator. `roc test
scripts/Regions.roc` runs only the tests of the region copy. `roc test
scripts/DocCheck.roc` runs only the tests of the missing-comment check.
`./scripts/host-check.sh` runs the tests inside `platform/Key.roc`. `odin test
engine -debug` runs the engine's tests. `odin test scripts/font_bake` runs
the tests of the font bake tool. `python3 -m unittest
scripts/test_make_macos_sysroot.py` runs the tests of the sysroot generator.
`python3 -m unittest scripts/test_make_linux_stubs.py` runs the tests of the
stub generator. `python3 -m unittest scripts/test_make_windows_import_libs.py`
runs the tests of the Windows import library generator.
`python3 -m unittest scripts/test_bridge.py` runs the tests of the Bridge
Driver against a fake host.
`./scripts/test-all.sh` runs `roc check` and `roc test` on every app, every
package and the build scripts, then the engine tests.
`sh bench/check.sh` runs `roc check` and `roc test` on every bench game, and
`odin test` on every Odin twin.
`python3 -m unittest bench/test_analyse.py bench/test_chart.py bench/test_compare_chart.py bench/test_headline.py bench/test_machine.py bench/test_realclock.py`
runs the tests of the bench scripts.

`.github/workflows/ci.yml` runs on each push to `main` and on each pull
request. The macOS job builds with `--release`, runs cards, entity-game,
pong and each tutorial chapter for one frame, runs the Bridge check and runs `scripts/test-all.sh`. It regenerates the macOS
sysroot, fails on a diff and runs the audit. The Linux job runs
`scripts/linux/in-container.sh --release` in the Docker image and runs the
stub audit. The container script also runs `docs --check` and the Bridge
check under xvfb. The Windows job
builds sokol with `scripts\windows\build_sokol.cmd` and miniaudio with
`scripts\windows\build_miniaudio.cmd`, then builds with
`--release`, runs the same games, the Bridge check and
`scripts/test-all.sh`, and runs `make_windows_import_libs.py --check`. Only
the sokol and miniaudio step runs `vcvars64.bat`, so the Roc link runs with `LIB` unset. A
fourth job runs the generator tests, regenerates the Linux stubs
and fails on a diff.

`.github/workflows/release.yml` runs on each `v*` tag. Each OS builds its
host and inputs with `--release` and uploads `platform/targets/<target>/`. A
Linux job runs `roc bundle` for the platform and for `packages/linalg`,
`packages/mesh`, `packages/ui` and `packages/camera`. It publishes each
bundle in a prerelease, named `<name>-<hash>.tar.zst`. Roc takes URLs that
differ only in the hash as one package, so the name must stay in front. The
notes name each bundle URL and the Roc nightly. Next, a job on each OS
installs only Roc and runs cards from the bundle URLs. If all three pass, the last job
marks the release final and latest. If one fails, the release stays a
prerelease. A tag with a hyphen, such as `v0.2.0-rc.1`, also stays a
prerelease. `scripts/release.py` points the header of
`examples/cards/main.roc` at the bundle URLs and writes the notes. `python3 -m
unittest scripts/test_release.py` runs its tests.

The bundle job also runs `roc scripts/build.roc docs --check` and attaches
`docs.tar.gz` to the release. The tarball holds the API HTML of each bundle
and `urls.json`. `urls.json` gives the value of each marker in the guide
pages: `platform_url`, `linalg_url`, `mesh_url`, `ui_url`, `camera_url` and
`roc_nightly`. `scripts/release.py docs` makes the tarball. After the
publish, `scripts/release.py check-docs` reads the published tarball. It
fails if a URL names no asset of the release. When the release workflow
passes, `.github/workflows/grow-site.yml` asks Vercel to rebuild
pixelsprout.dev.

The macOS sysroot in `platform/targets/macos-sysroot/` is committed. After
a sokol, Clay or engine change, run `python3 scripts/make_macos_sysroot.py
--audit`. If it lists a symbol, add the symbol to the catalog as
`scripts/macos-sysroot/PROVENANCE.md` says.

The Linux CRT objects and stubs in `platform/targets/x64glibc/` are
committed. After a sokol, Clay or engine change, run `python3
scripts/make_linux_stubs.py --audit`. If it lists a symbol, add the symbol to
the catalog as `scripts/linux-stubs/README.md` says.

Roc files follow `roc fmt`. Run `git config core.hooksPath .githooks` once
per clone. The pre-commit hook then stops a commit that stages a `.roc` file
that `roc fmt --check` rejects.

`ROCCO_EXIT_AFTER_FRAMES=N` makes the game quit after N rendered frames. The
game then prints `Frame Count: N` and exits with code 0. Without the variable,
the game runs until it returns `Quit` or you close the window. The entity
game quits on Escape. A value that is not a positive integer stops the game
at startup with exit code 1.

The words after the game's name on the command line reach the game as
`Config.args`, in the order typed. The host does not parse them. For
example, `./pong.bin --draws 64` gives `args: ["--draws", "64"]`. With no
words, `args` is an empty list.

The other variables the engine reads:

| Variable | Effect |
|---|---|
| `ROCCO_SEED=N` | The seed in `Config`. The default is 0. A value that is not an unsigned 64-bit integer stops the game with exit code 1. |
| `ROCCO_DEBUG_CAMERA=1` | A fly camera on WASD and the mouse, with the mouse locked. The host ignores `Scene.camera`. The game still gets all input. |
| `ROCCO_ALLOC_REPORT=1` | One line per fixed step: Roc allocs, deallocs, reallocs, live blocks, and `step` and `view` time in microseconds. |
| `ROCCO_LOCKSTEP=1` | Lockstep: one fixed step and one render per Frame, whatever the time, with vsync off. On macOS the display link still starts one Frame per display refresh, but the render no longer waits for a drawable. `0` or unset is the real clock. Any other value stops the game with exit code 1. |
| `ROCCO_HEADLESS=1` | Headless: Lockstep with no window and no GPU. The game still gets Queries answered and `loaded` with the Manifest. It needs `ROCCO_EXIT_AFTER_FRAMES`. Without it, or with a value other than `0` or `1`, the game stops with exit code 1. |
| `ROCCO_SPANS_CSV=path` | A host built with `host --spans` writes the Spans there at exit: a header row, then one row per Frame with the Frame number, the fixed steps, the Spans in microseconds and `span_cost_us`. The Spans are `input`, `step`, `commands`, `view`, `queries` and `query_results`, summed over the fixed steps of the Frame, then `interpolation`, `ui_layout` (Clay and the quad build), `render_submit` and `commit` (`sg.commit`). Headless rows have zero `render_submit` and `commit`. `span_cost_us` is the time one Span adds, measured once at startup. A Spans host stops with exit code 1 without it or without `ROCCO_EXIT_AFTER_FRAMES`, and exits with code 1 if the CSV does not write. Any other host stops with exit code 1 if it is set. |

`./scripts/alloc-check.sh` builds each game under `--opt=dev` and
`--opt=speed`, runs it with no input, and checks every step after the first
10: the game's expected allocs and as many deallocs, the game's expected
reallocs and a constant live block count. cards expects 2 allocs and 1
realloc: the box shell and the cards list, which the concat after the Lights
grows. entity-game expects 33 allocs and 4 reallocs under `--opt=speed`, and
42 under `--opt=dev`. Its `view` makes one list for the leaves of each
entity, and `List.keep_if` makes one list for each root it keeps. Under
`--opt=dev`, `List.map` copies the entity list in each of the 9 stages that
map it. With no input the player carries no drops, so the Scene has no
Group. pong expects 6 allocs and 1 realloc: the box shell, the nodes list,
the ui list, the scoreboard's children and its two cells' children. The
realloc is the concat that joins the scoreboard, the banner and the hints.
Tutorial chapter 10 expects 14 allocs and 6 reallocs: its `view` builds the
Nodes, the pickup Draws and Colliders, the HUD with its count text and the
Loops, and each concat grows a list. It is the one skinned game in the
check. Each count records what the game makes today. None is a target. The games
stay in plain Roc, so a change that moves a count updates the script, and
its commit says why. The script rebuilds the host with
`host --release --track-alloc` and fails on a `LEAK` or `BAD Free` line. It
leaves that host in place, so run `host` again after it. Run `inputs`
first. Each game opens a window. Do not type into it during the check,
because a key press allocates the `Input` lists.

`./scripts/host-check.sh` regenerates the glue and links cards, entity-game
and pong, then checks that the host library and the glue did not change.

### Benchmarks

[docs/BENCHMARKS.md](docs/BENCHMARKS.md) is the single source for the
benchmarks: the run modes, the Spans, the build flags, the bench games, the
protocol, the headline figure, the hardware rules and the reference run.

The bench games live in `bench/`, outside `examples/`. `run-games.sh`,
`test-all.sh` and `screenshot.sh` do not run them. To run a quick sweep and
draw its curves:

```sh
roc scripts/build.roc bench model-size,model-size-twin 64 1024
python3 bench/chart.py
roc scripts/build.roc all   # a Spans host stops the examples, so rebuild
```

A manual sweep writes its summaries to `bench/out/results/`, which git
ignores. Only `sh bench/reference-run.sh` writes the committed results in
`bench/results/`.

### Screenshots

`scripts/screenshot.sh <game> <out.png> [steps]` runs a built game with the
Bridge (see `guide/bridge.md`), runs `steps` fixed steps with no Input
(default: one second of steps at the game's step rate), saves the frame to
`out.png` and quits the game. It prints the `screenshot` reply, which has
the PNG's `physical` size and the window's `logical` size. The PNG has the
window's pixels and no title bar, so a `high_dpi` window on a Retina display
gives a PNG twice the window's size in points. The host reads the frame
back itself, so other windows can cover the game and no Screen Recording
permission is needed. `ROCCO_*` variables pass through, so
`ROCCO_DEBUG_CAMERA=1` and `ROCCO_SEED` work. Build the game first with
`roc scripts/build.roc -- game <game>`.

The script works on macOS, Linux and Windows (from Git Bash). It needs
Python 3. Set `PYTHON=python` where the command is not `python3`. It picks a
free port for `ROCCO_BRIDGE` unless you set one.

`scripts/bridge.py` is the Driver behind it. Use it as a CLI to drive a
game by hand, or import its `Bridge` class in a Python script.
`python3 scripts/bridge_check.py` is the Bridge check that CI runs: it
drives tutorial chapter 3 and checks that Pip moves and that the screenshot
has the right size. Then it drives chapter 8 to a pickup and checks that the
`step` reply holds the `Play` of the blip. Then it walks Pip in chapter 9
with a pad's stick halfway up and checks the half speed. Then it holds D in
chapter 10, checks that Pip's Pose faded to Walk, saves a screenshot of
Pip mid-walk and checks that it differs from a screenshot of Pip standing.
Last it drives pong and checks that the `scene` reply holds a
Box nested in a Box.

### Docs

`guide/` holds the docs for game authors, as Markdown that reads correctly
on GitHub. Each page starts with YAML frontmatter: `title`, `summary` and
`order`. The site sorts the pages of each folder by `order`. `docs/` holds
the internal documents, not the guide.

The code in a page comes from a region in a Roc file, so it builds. The Roc
file marks the region:

```roc
# region: game
launch = |_config| Launch.default
# endregion
```

The page marks the place for the region with two region lines around a
fenced block. The path is from the repository root:

```md
<!-- region: examples/cards/main.roc#game -->
<!-- endregion -->
```

`roc scripts/build.roc docs` replaces the lines between the two region lines
of a page with the region in a `roc` fenced block. Do not edit those lines by
hand. `docs --check` names each page and region that differs from its source.
It also names a missing file, a missing region and a region with no end line.

The API pages come from `##` comments in the platform and in the bundled
packages. Every exposed module, type and function has a `##` block directly
above its declaration. A `#` line between the block and the declaration
hides the block from `roc docs`. `roc docs` shows no `##` on a record field,
so the type's block describes its fields in a Markdown list. The `docs` step
names each item with no `##` comment, such as `platform: Light.point`, and
fails.

A page cannot hold the bundle URLs of its own release, because the URLs come
from the bundle hashes. The header block of a page holds markers instead:
`{{platform_url}}`, `{{linalg_url}}`, `{{mesh_url}}`, `{{ui_url}}`,
`{{camera_url}}` and `{{roc_nightly}}`. The site replaces them. On GitHub, the page tells the
reader to get the values from the latest release.

### macOS

```sh
cd sokol-odin/sokol && sh build_clibs_macos.sh && cd ../..
sh scripts/macos/build-miniaudio.sh
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
archives and the miniaudio archive. Then it runs the `all` command of the build script. Then it runs
each game under `xvfb-run` with software GL and `ROCCO_EXIT_AFTER_FRAMES=120`.
Each run passes on exit code 0 and one `Frame Count: 120` line. Then it runs
`scripts/test-all.sh`, the host check and the alloc check. The script builds
the debug and the release sokol archives. `./scripts/linux/check.sh --release` checks the
release build.

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
sh scripts/linux/build-miniaudio.sh
roc scripts/build.roc -- all
./examples/entity-game/entity-game_linux.bin
```

The link reads the committed CRT objects and stub shared libraries in
`platform/targets/x64glibc/`. The system libraries load at run time.
`build_clibs_linux.sh` builds the debug and the release
archives. It also builds modules the engine does not use, and it needs the
ALSA headers. `scripts/linux/in-container.sh` shows how to build only the
four archives the engine links.

### Windows

Run every step in one `cmd` window where `vcvars64.bat` has run, so that `cl`
and `lib` are on `PATH`. The Start menu calls this window the x64 Native
Tools Command Prompt.

Roc links x64win with no Visual Studio CRT. `build_sokol.cmd` builds the
sokol libraries with `/Zl /GS-`, so they name no CRT library. sokol's own
`build_clibs_windows.cmd` does not, and its libraries fail that link.
The C runtime comes from `ucrtbase.dll`. `build_miniaudio.cmd` builds
miniaudio with the same flags.

The import libraries in `platform/targets/x64win/` are committed, so the link
needs no Windows SDK and no `LIB` variable. `make_windows_import_libs.py`
writes them from `scripts/windows-import-libs/` with Zig 0.16.0. `python
scripts\make_windows_import_libs.py --check` fails if a committed library
differs from its `.def` file. The sokol build still needs the Windows SDK for
`windows.h`, `d3d11.h` and `dxgi.h`.

```bat
scripts\windows\build_sokol.cmd
scripts\windows\build_miniaudio.cmd
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
- sokol's Windows build needs `cl` and the Windows SDK headers.

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

The host calls `launch` once per process, before the window opens. Hot reload
does not call it again. After a change to `launch`, restart the game.

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
| `engine/key_tags.odin` | Generated by `roc scripts/build.roc -- keys`: the Key names that a Bridge request uses. Do not edit. |
| `platform/Vocabulary.roc` | The vocabulary types, among them `Node`, the tree of Groups, Draws, Lights and Colliders in `Scene.nodes`. Games import them as `import pf.Vocabulary exposing [...]`. |
| `platform/Query.roc` | Builds the Queries a game puts in `Scene.queries`, for example `Query.contacts_of(owner)`. |
| `platform/QueryResults.roc` | Gives `QueryResults.empty`, which is what the first step gets. Tests use it. |
| `platform/Scene.roc` | Gives `Scene.empty`, the Scene a game starts a record update from in `view`. |
| `platform/Draw.roc` | Gives `Draw.default`, the Draw a game starts a record update from and puts in `Scene.nodes` as `Draw(...)`. |
| `platform/Sound.roc` | Builds the Play Command, for example `Sound.play(id)`. |
| `platform/Pose.roc` | Builds the Pose of a Draw with `Pose.still(clip, time)`, and wraps a Clip's time with `Pose.loop(time, duration)`. |
| `platform/Loop.roc` | Gives `Loop.default`, the Loop a game starts a record update from in `Scene.loops`. |
| `platform/Launch.roc` | Gives `Launch.default`, the Launch a game returns from `launch` or starts a record update from. |
| `platform/Config.roc` | Gives `Config.empty`, the Config a test gives `launch` and `init`. |
| `platform/Input.roc` | Gives `Input.empty`, the Input a test gives `step`. |
| `platform/targets/arm64mac/` | `libhost.a`, the sokol Metal archives, `clay.a`, `miniaudio.a` and compiler-rt. Not committed. |
| `platform/targets/macos-sysroot/` | The stubs the macOS link reads. `scripts/make_macos_sysroot.py` writes them. Committed. Do not edit. |
| `platform/targets/x64glibc/` | `libhost.a`, the sokol GL archives, `clay.a` and `miniaudio.a` are not committed. `scripts/make_linux_stubs.py` writes the CRT objects and the stub shared libraries. They are committed. Do not edit them. |
| `platform/targets/x64win/` | `host.lib`, the sokol D3D11 libraries, `clay.lib` and `miniaudio.lib` are not committed. `scripts/make_windows_import_libs.py` writes the import libraries. They are committed. Do not edit them. |
| `examples/cards/` | A game with no entities: SPACE deals a card. |
| `examples/entity-game/` | A game with entities: WASD moves the player, the camera follows, pickups open a door. Its meshes are in `assets/meshes/` and its sky in `assets/sky/meadow/`. |
| `examples/pong/` | Two-player pong: W and S move the left paddle, UP and DOWN the right, SPACE pauses. Its `Scene.ui` shows the score, a banner when paused or won, and the keys. It is the UI test for CI. |
| `examples/tutorial/<nn>-<name>/` | One app for each tutorial chapter in `guide/tutorial/`. Each chapter starts from the one before it, so `git diff --no-index` of two `main.roc` files shows the change. |
| `examples/tutorial/source/make_meshes.py` | Builds `pip.glb`, the tutorial character with a 12-Joint Skin and the Clips Idle and Walk, into each chapter in its `CHAPTERS` list. It also writes `engine/testdata/skinned.glb`, the small skinned fixture for the loader tests. Run it from the repository root with `/Applications/Blender.app/Contents/MacOS/Blender --background --python examples/tutorial/source/make_meshes.py`. Tested with Blender 5.2.1. A rerun writes the same bytes. |
| `examples/tutorial/source/make_sounds.py` | Writes the tutorial Sounds `blip.wav`, `hum.wav` and `music.wav` into the `assets/sound/` folder of each chapter in its `CHAPTERS` list. Python standard library only: `python3 examples/tutorial/source/make_sounds.py`. A rerun writes the same bytes. |
| `packages/camera/` | The camera package: `look_at` and `follow`. Games import it as `import cam.Camera as Cam`. |
| `packages/mesh/` | The mesh package resolves mesh ids from the manifest with `primitive` and `resolve`, and Clip ids and durations with `clip` and `clip_duration`. Games import it as `import mesh.Mesh as Mesh`. |
| `packages/ui/` | The UI package for the `Scene.ui` tree. Games write `Box(config, [...])` and `Text(...)` themselves and take the configs from here: `default_box` holds Clay's defaults, `default_text` the Text defaults, and `float_at`, `panel`, `label` and `pad_all` are small helpers. Games import it as `import ui.Ui`. |
| `bench/model-size/` | The idiomatic Model size bench game: `step` moves N entities, N from the first Arg, and `view` always returns 100 Draws. The Seed places the entities. |
| `bench/model-size/positions.golden` | The entity positions of `bench/model-size` after 600 steps at Seed 7 and N=100. The Roc game and its twin both check them. |
| `bench/model-size/model.golden` | The full Model of `bench/model-size` after 600 steps at Seed 7 and N=100. The idiomatic and the tuned game both check it. |
| `bench/model-size-tuned/` | The tuned Model size bench game: the behaviour of `bench/model-size`, with a `step` that keeps the entity list unique and walks it once. |
| `bench/model-size-twin/` | The Odin twin of `bench/model-size`: the same Model fields and the same logic through the same run loop. |
| `bench/empty-step/` | The Model size bench game with a `step` that does nothing: the lower limit of the seam. |
| `bench/colliders/` | The Colliders bench game: `step` moves N Colliders, N from the first Arg, and `view` asks 8 raycasts, 8 overlaps and one ContactsOf. The arena grows with N, so each Collider keeps 4 square units. The Seed places the Colliders. |
| `bench/colliders/colliders.golden` | The Colliders of `bench/colliders` after 600 steps at Seed 7 and N=100. The Roc game and its twin both check them. |
| `bench/colliders-twin/` | The Odin twin of `bench/colliders`: the same Colliders, motion and Queries through the same run loop. |
| `bench/draws/` | The Draws bench game: `step` moves N primitive cubes, N from the first Arg, and `view` returns one Draw per cube under one Sun with shadows on. The cubes stay in a fixed square at every N. The Seed places the cubes. |
| `bench/ui/` | The UI bench game: N Box and Text elements, N from the first Arg, in one column of N / 2 cells. One lit cell moves each step. It has no Draws. Run it with `--windowed`, so the UI curve has the render Spans too. |
| `bench/analyse.py` | Turns the runs of one bench game at one N into a summary JSON in `bench/out/results/`, or in the directory you name. |
| `bench/chart.py` | Draws one SVG curve per bench game from the summaries. |
| `bench/machine.py` | Prints the machine, the OS and the power state of a sweep as JSON. `--check` fails unless the machine is ready for a reference run. |
| `bench/realclock.py` | Summarises one real-clock run of an example with the Spans. |
| `bench/reference-run.sh` | Runs the reference run in `docs/BENCHMARKS.md`: every bench game and Odin twin, the real-clock run, the charts and the headline figure. |
| `bench/results/` | The committed summaries of the reference runs, one directory per date and machine. |
| `bench/compare_chart.py` | Draws the `step` Span of several bench games against N on one SVG: `twin`, `tuned` or `colliders`. |
| `bench/check.sh` | Runs `roc check` and `roc test` on every bench game and `odin test` on every Odin twin. |
| `bench/shared/` | The Roc package that every Roc bench game imports: the N Arg, the random generator and the test helpers. |
| `bench/roc-heap/` | The Roc heap micro benchmark: alloc and free pairs and realloc lists through the Roc heap hooks. `odin run bench/roc-heap -o:speed -out:build/roc-heap` runs it. |
| `scripts/build.roc` | The build script. Its `target` command gives the check scripts the Roc target, binary suffix and host library. |
| `scripts/Keys.roc` | The Key generator. `build.roc` imports it to write `platform/Key.roc`. |
| `scripts/Regions.roc` | The region copy. `build.roc` imports it to copy each region into the `guide/` pages. |
| `scripts/DocCheck.roc` | The missing-comment check. `build.roc` imports it to find each API item with no `##` comment. |
| `guide/` | The docs for game authors. `guide/install.md` is the first page. `guide/tutorial/` holds the tutorial chapters and `guide/images/` their screenshots. See "Docs". |
| `scripts/run-games.sh` | Runs each named game for FRAMES frames and checks its exit code and its `Frame Count` line. |
| `scripts/test-all.sh` | Runs `roc check` and `roc test` on every app, every package and the build scripts, then `odin test engine -debug`. |
| `scripts/alloc-check.sh` | Checks the allocations per fixed step of cards, entity-game, pong and tutorial chapter 10. |
| `scripts/host-check.sh` | Checks that linking cards, entity-game and pong does not change the host library or the glue. |
| `scripts/make_macos_sysroot.py` | Writes `platform/targets/macos-sysroot/` from `scripts/macos-sysroot/interfaces.json`. `--audit` lists the archive references that the catalog does not cover. |
| `scripts/macos-sysroot/` | The reviewed catalog of macOS system symbols, its `PROVENANCE.md`, and `evidence.py`, which adds a symbol with its evidence. |
| `scripts/make_linux_stubs.py` | Writes the CRT objects and stub shared libraries in `platform/targets/x64glibc/` with Zig. `--audit` lists the archive references that the catalog does not cover. |
| `scripts/linux-stubs/` | The CRT assembly sources, the catalog `stubs.json`, and a `README.md` that says how to change a stub. |
| `scripts/make_windows_import_libs.py` | Writes the import libraries in `platform/targets/x64win/` from the `.def` files with Zig. `--check` fails if a committed library differs. |
| `scripts/windows-import-libs/` | The `.def` files, one per DLL, and a `README.md` that says how to change one. |
| `scripts/windows/build_sokol.cmd` | Builds the sokol D3D11 libraries with no CRT library names. |
| `scripts/miniaudio/rocco_miniaudio.c` | The one C file of the miniaudio archive: its defines, miniaudio and stb_vorbis. |
| `scripts/macos/build-miniaudio.sh`, `scripts/linux/build-miniaudio.sh`, `scripts/windows/build_miniaudio.cmd` | Build the debug and release miniaudio archive for each OS into `build/miniaudio/`. |
| `scripts/screenshot.sh` | Runs a game with the Bridge and saves a frame to a PNG. |
| `scripts/bridge.py` | The Bridge Driver: a Python library and a CLI with one command per op. |
| `scripts/bridge_check.py` | The Bridge check: drives tutorial chapter 3, checks Pip's movement and the screenshot size, then drives chapter 8 to a pickup and checks the `Play` in the `step` reply, then walks Pip in chapter 9 with a Bridge pad's stick, then walks Pip in chapter 10 and checks its Pose and that its screenshot differs from the still one, then checks pong's nested Boxes in the `scene` reply. |
| `scripts/linux/` | The Linux Docker image, the script that runs in it, and `check.sh`, the wrapper that runs the check from any machine with Docker. |
| `sokol-odin/` | Submodule: floooh/sokol-odin. The engine imports its `sokol/` folder. |
| `glue/` | Submodule: the roc-odin-glue spec. |
| `clay/` | Submodule: nicbarker/clay. The engine imports `bindings/odin/clay-odin/`. |
| `miniaudio/` | Submodule: mackron/miniaudio at `0.11.24`. `scripts/miniaudio/rocco_miniaudio.c` compiles it. |
| `docs/DESIGN.md` | The design. Read first. |
| `docs/ROADMAP.md` | Milestones and what is out of scope. |
| `docs/BENCHMARKS.md` | How the benchmarks measure, how to repeat a run, and the reference results. |
| `docs/GLOSSARY.md` | Terms as rocco uses them. |

## A game outside this repo

`guide/install.md` tells a game author how to run a game from the release
bundles with only Roc installed.

A game is a Roc app whose header names this platform. Point `pf` at a
checkout of this repo:

```roc
app [init, launch, loaded, step, view] { roc: "nightly-2026-10-11-7d256b9", pf: platform "../rocco-engine/platform/main.roc" }
```

The game defines five calls: `launch`, `init`, `step`, `loaded` and `view`.
`docs/DESIGN.md` section 2 gives their types. The host calls `launch` first,
before the window opens. A game that wants the default window, step rate,
shadow map size and capacities returns `Launch.default`:

```roc
import pf.Vocabulary
import pf.Launch

launch : Vocabulary.Config -> Vocabulary.Launch
launch = |_config| Launch.default
```

A game that wants a different window starts a record update from the
default, for example `{ ..Launch.default, window: { ..Launch.default.window,
width: 1280, height: 720 } }`.

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
three games (`cards`, `entity-game`, `pong`) link against one host library.
Kula, a Kula World clone, lives in
[Pixelsprout/kula](https://github.com/Pixelsprout/kula) and runs on the
release bundles.
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
