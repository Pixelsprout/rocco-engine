# rocco

A 3D game engine in Odin that runs games written in Roc.

Odin owns the systems: window, clock, input, GPU, memory, audio, collision.
Roc owns the game: its state and its rules, as pure functions. The engine is
a Roc platform. The game is a Roc app. `docs/DESIGN.md` says where the line
goes and why. `docs/ROADMAP.md` says what is built next.

## Requirements

- Odin `dev-2026-08:251d8eb0b` at `~/tools/Odin`.
- Roc `nightly-2026-09-12-220fd47`. The pin lives in `game/main.roc` and
  `game/platform/main.roc`. A different compiler warns and builds anyway.
  Fix the `PATH`, never the pin.
- macOS on Apple silicon. The renderer is Metal through sokol.
- Xcode command line tools, for the SDK stubs the sysroot script copies.
- `sokol/`: a clone of `floooh/sokol-odin` with the macOS archives built.
  It is not committed. Clone it to `sokol/` and run its
  `build_clibs_macos.sh`.
- `../roc-odin-glue`: the glue spec that generates `engine/roc_platform_abi.odin`.

## Build

```sh
export PATH="$HOME/playground/roc-odin-game-engine-platform/toolchain/\
roc_nightly-macos_apple_silicon-2026-09-12-220fd47:$PATH"

# 0. Once, and again after an Xcode update. Prints 17 frameworks.
./scripts/make-macos-sysroot.sh game/platform/targets/macos-sysroot

# 1. Copy the sokol archives and compiler-rt into the link inputs. Once.
cp sokol/{app,gfx,glue,log}/sokol_*_macos_arm64_metal_debug.a game/platform/targets/arm64mac/
cp "$(find "$(xcode-select -p)" -name libclang_rt.osx.a | head -1)" game/platform/targets/arm64mac/

# 2. Whenever the platform header changes: regenerate the Odin ABI.
roc glue ../roc-odin-glue/OdinGlue.roc ./engine game/platform/main.roc

# 3. Whenever engine/ changes: engine -> static library.
odin build engine -build-mode:static \
  -out:game/platform/targets/arm64mac/libhost.a -debug -vet -strict-style

# 4. Whenever anything changes: Roc links the game.
cd game && roc build --output=./engine.bin main.roc && ./engine.bin
```

Run steps 2, 3 and 4 as one chain with `&&`. Each tool consumes the previous
one's output and cannot tell whether that output is stale.

Hot reload: `cd game && roc run --watch main.roc`. Edit `main.roc`. The
running game picks up the new code and keeps its state. Requires the dev
backend, which is `roc run`'s default.

## Layout

| Path | Contents |
|---|---|
| `engine/` | The Odin engine. Builds to `libhost.a`. |
| `engine/roc_platform_abi.odin` | Generated. Do not edit. |
| `game/main.roc` | The game. |
| `game/platform/main.roc` | The platform header and the host wrappers. |
| `game/platform/targets/` | Link inputs. Not committed. |
| `scripts/` | The sysroot generator. |
| `docs/DESIGN.md` | The design. Read first. |
| `docs/ROADMAP.md` | Milestones and what is out of scope. |
| `docs/GLOSSARY.md` | Terms as rocco uses them. |
| `docs/examples/` | Two games and the generic platform from the design. They check and test. They do not link yet; see roadmap milestone 1. |

## Status

The engine renders three cubes, flies a camera, and runs a Roc script per
fixed step with the host honouring `roc_dealloc`. The platform header still
names a concrete state record. Roadmap milestone 1 replaces it with the
generic header in the design.
