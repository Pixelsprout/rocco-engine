---
title: Shipping a game
summary: Pin the bundle URLs and the Roc nightly, build a binary for each target, and ship it with its assets.
order: 10
---

# Shipping a game

Each rocco release gives a bundle for the platform and for each bundled
package. A bundle has a URL. Your game names the URLs in its header, and
`roc` downloads them. You need only Roc to build the game.

If you read this page on GitHub, the bundle URLs and the Roc nightly show as
markers in double braces. Get the values from the notes of the
[latest release](https://github.com/Pixelsprout/rocco-engine/releases/latest).

## The header

This header names every bundle and the Roc nightly:

```roc
app [init, launch, loaded, step, view] { cam: "{{camera_url}}", linalg: "{{linalg_url}}", mesh: "{{mesh_url}}", pf: platform "{{platform_url}}", roc: "{{roc_nightly}}", ui: "{{ui_url}}" }
```

Name only the packages that your game imports:

| Name | Bundle | Gives |
|---|---|---|
| `pf` | `{{platform_url}}` | the [platform][Platform]: the vocabulary, `Key`, `Light`, `Query` and the defaults |
| `mesh` | `{{mesh_url}}` | the [mesh package][Mesh]: `Mesh.primitive` and `Mesh.resolve` |
| `ui` | `{{ui_url}}` | the [ui package][Ui]: `Ui.box` and `Ui.text` |
| `linalg` | `{{linalg_url}}` | the [linalg package][Linalg]: `Vec3` and `Quat` |
| `cam` | `{{camera_url}}` | the [camera package][Camera]: `Cam.look_at` and `Cam.follow` |

Each URL ends with a hash of the bundle. Roc checks the hash, so the files
behind a URL cannot change. Take all of the URLs from one release. The ui
package copies the UI types of the platform. URLs from two releases can
have types that do not match.

## The Roc nightly

Roc changes from one nightly to the next. The `roc` field of the header
names the nightly that the release was built with. Install that nightly.
Run `roc version` to check it. To move to a new release, change the
nightly and all of the URLs at the same time.

## Build for each target

Roc builds for the OS that it runs on. Build your game on each OS that you
ship to. rocco does not test a build for one OS on a different OS.

| OS | Run this on that OS | Binary |
|---|---|---|
| macOS arm64 | `roc build --target=arm64mac --output=./my-game main.roc` | `my-game` |
| Linux x64 | `roc build --target=x64glibc --output=./my-game main.roc` | `my-game` |
| Windows x64 | `roc build --target=x64win --output=./my-game.exe main.roc` | `my-game.exe` |

On Linux, give `--target`. Without it, `roc build` picks a static musl
target, and the platform has no musl target.

`roc build` uses `--opt=speed` by default. The binary is fast, but the
build is slower than a `roc run`.

If your game imports the mesh package, `roc build` warns about the `dbg`
in `Mesh.resolve`. Roc then exits with code 2, but it writes the binary.

On Windows, run `roc` in a shell where `LIB` is not set.

## What to ship

Ship these files together:

- the binary,
- the `assets/` folder, beside the binary.

The binary holds the engine and your game. When you start it by a path,
such as `./my-game`, it finds `assets/` in its own folder.

The binary loads some libraries of the OS when it starts:

| OS | Libraries |
|---|---|
| macOS | the system frameworks, such as Metal |
| Linux | `libX11.so.6`, `libXi.so.6`, `libXcursor.so.1`, `libGL.so.1` and the C library. The player needs an X11 desktop and an OpenGL driver. |
| Windows | `ucrtbase.dll`, `kernel32.dll`, `user32.dll`, `gdi32.dll`, `shell32.dll` and `d3d11.dll` |

[Platform]: https://pixelsprout.dev/projects/rocco/api/platform/
[Mesh]: https://pixelsprout.dev/projects/rocco/api/mesh/
[Ui]: https://pixelsprout.dev/projects/rocco/api/ui/
[Linalg]: https://pixelsprout.dev/projects/rocco/api/linalg/
[Camera]: https://pixelsprout.dev/projects/rocco/api/camera/
