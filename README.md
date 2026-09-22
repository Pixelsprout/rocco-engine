# rocco

A 3D game engine in Odin that runs games written in Roc.

Odin owns the systems: window, clock, input, GPU, memory, audio, collision.
Roc owns the game: its state and its rules, as pure functions. The engine is
a Roc platform. The game is a Roc app. `docs/DESIGN.md` says where the line
goes and why. `docs/ROADMAP.md` says what is built next.

## Requirements

- Odin `dev-2026-08:251d8eb0b` at `~/tools/Odin`.
- Roc `nightly-2026-09-12-220fd47`. The pin lives in `platform/main.roc` and
  in every app under `examples/`. A different compiler warns and builds anyway.
  Fix the `PATH`, never the pin.
- macOS on Apple silicon. The renderer is Metal through sokol.
- Xcode command line tools, for the SDK stubs the sysroot script copies.
- `sokol/`: a clone of `floooh/sokol-odin` with the macOS archives built.
  It is not committed. Clone it to `sokol/` and run its
  `build_clibs_macos.sh`.
- `../roc-odin-glue`: the glue spec that generates `engine/roc_platform_abi.odin`.

## Build

```sh
# Set these paths for your local toolchain and glue checkout.
export PATH="/path/to/Odin:/path/to/Roc:$PATH"
GLUE_DIR="/path/to/roc-odin-glue"
SOKOL_DIR="./sokol"
TARGET_DIR="platform/targets/arm64mac"

# 0. Once, and again after an Xcode update. Prints 17 frameworks.
./scripts/make-macos-sysroot.sh platform/targets/macos-sysroot

# 1. Copy the sokol archives and compiler-rt into the link inputs. Once.
cp "$SOKOL_DIR"/{app,gfx,glue,log}/sokol_*_macos_arm64_metal_debug.a "$TARGET_DIR"/
cp "$(find "$(xcode-select -p)" -name libclang_rt.osx.a | head -1)" "$TARGET_DIR"/

# 2. Whenever the platform header changes: regenerate the Odin ABI.
roc glue "$GLUE_DIR/OdinGlue.roc" ./engine platform/main.roc

# 3. Whenever engine/ changes: engine -> static library.
odin build engine -build-mode:static \
  -out:"$TARGET_DIR/libhost.a" -debug -vet -strict-style

# 4. Whenever anything changes: Roc links a game against the platform.
cd examples/bodies && roc build --output=./bodies.bin main.roc && ./bodies.bin
```

Run steps 2, 3 and 4 as one chain with `&&`. Each tool consumes the previous
one's output and cannot tell whether that output is stale.

Hot reload: `cd examples/bodies && roc run --watch main.roc`. Edit `main.roc`. The
running game picks up the new code and keeps its state. Requires the dev
backend, which is `roc run`'s default.

## Layout

| Path | Contents |
|---|---|
| `engine/` | The Odin engine. Builds to `libhost.a`. |
| `engine/roc_platform_abi.odin` | Generated. Do not edit. |
| `platform/main.roc` | The platform: the header every game links against, and the host wrappers. |
| `platform/targets/` | Link inputs: `libhost.a`, sokol archives, compiler-rt, sysroot. Not committed. |
| `examples/bodies/` | The game that links today: three bodies on a track. Points at `../../platform/main.roc`. |
| `scripts/` | The sysroot generator. |
| `docs/DESIGN.md` | The design. Read first. |
| `docs/ROADMAP.md` | Milestones and what is out of scope. |
| `docs/GLOSSARY.md` | Terms as rocco uses them. |
| `docs/examples/` | The generic platform from the design and two games for it. They check and test. They do not link yet; roadmap milestone 1 promotes them to `platform/` and `examples/`. |

## A game outside this repo

A game is a Roc app whose header names this platform. Point `pf` at a
checkout of this repo:

```roc
app [init, step] { roc: "nightly-2026-09-12-220fd47", pf: platform "../rocco-engine/platform/main.roc" }
```

The game author needs Roc and the Xcode command line tools, and runs step 0
once. They do not need Odin, sokol or the glue. Publishing the platform as a
Roc package URL is not set up yet.

## Status

The engine renders three cubes, flies a camera, and runs a Roc script per
fixed step with the host honouring `roc_dealloc`. The platform header still
names a concrete state record. Roadmap milestone 1 replaces it with the
generic header in the design.
