---
title: Shipping a game
summary: Pin the bundle URLs and the Roc nightly, build a binary on each target OS, and ship it with its assets.
order: 13
---

# Shipping a game

To share your game, you need a binary that runs on the player's machine
without Roc, and you need your builds to stay the same over time. rocco
helps with both. Each release gives a bundle for the platform and for each
bundled package, and each bundle has a fixed URL. Your game names those
URLs in its header, and `roc` downloads them, so Roc is all you need to
build. The binary you build holds the engine and your game together.

If you read this page on GitHub, the bundle URLs and the Roc nightly show
as markers in double braces. You can find the values in the notes of the
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
| `ui` | `{{ui_url}}` | the [ui package][Ui]: `Ui.default_box`, `Ui.label` and `Ui.panel` |
| `linalg` | `{{linalg_url}}` | the [linalg package][Linalg]: `Vec3`, `Quat` and `Pose` |
| `cam` | `{{camera_url}}` | the [camera package][Camera]: `Cam.look_at` and `Cam.follow` |

Each URL ends with a hash of the bundle. Roc checks the hash, so the files
behind a URL cannot change. Take all of the URLs from one release. The ui
package copies the UI types of the platform, so URLs from two releases can
have types that don't match.

## The Roc nightly

Roc changes from one nightly to the next. The `roc` field of the header
names the nightly that the release was built with, so install that nightly
and run `roc version` to check it. To move to a new release, change the
nightly and all of the URLs at the same time.

## Build for each target

Roc builds for the OS that it runs on, so build your game on each OS that
you ship to. rocco does not test a build for one OS made on a different OS.

| OS | Run this on that OS | Binary |
|---|---|---|
| macOS arm64 | `roc build --target=arm64mac --output=./my-game main.roc` | `my-game` |
| Linux x64 | `roc build --target=x64glibc --output=./my-game main.roc` | `my-game` |
| Windows x64 | `roc build --target=x64win --output=./my-game.exe main.roc` | `my-game.exe` |

A few things to watch for:

- On Linux, always give `--target`. Without it, `roc build` picks a static
  musl target, and the platform has no musl target.
- `roc build` uses `--opt=speed` by default. The binary is fast, but the
  build is slower than a `roc run`.
- If your game imports the mesh package, `roc build` warns about the `dbg`
  in `Mesh.resolve`. Roc then exits with code 2, but it still writes the
  binary.
- On Windows, run `roc` in a shell where `LIB` is not set.

## What to ship

Ship these files together:

- the binary,
- the `assets/` folder, next to the binary.

When the player starts the binary by a path, such as `./my-game`, it finds
`assets/` in its own folder.

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
