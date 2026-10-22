---
title: Assets and Packs
summary: Why assets load in named Packs, how to load and unload a Pack, what the Manifest holds, and the meshes that need no file.
order: 5
---

# Assets and Packs

A game rarely needs every asset at once. A puzzle game may need a different
set of blocks and a different sky for each theme, and a larger game needs
to bring content in and out as the player moves. If the engine loaded
everything at startup, you could never change what is loaded. If your game
loaded files one by one, it would have to track which ones are still in
use.

rocco solves this with Packs. A Pack is a named set of assets, such as
meshes, skies and Sounds, that load and unload together. Your game lists the
assets of each Pack in Roc, and sends a `Load` or `Unload` [Command]. The
host takes care of the files, the GPU data and the ids.

## Load a Pack

The entity game loads one mesh and one sky in a Pack called `sprout`:

<!-- region: examples/entity-game/main.roc#load -->
```roc
init : Vocabulary.Config -> { model : Model, commands : List(Command) }
init = |_config| { model: new_game(primitive_meshes, round_pickups, 0), commands: [Load({ pack: "sprout", assets: ["sprout", sky_name] })] }

loaded : Model, Str, Manifest -> Model
loaded = |model, _pack, manifest| { ..model, meshes: resolve_meshes(manifest) }

sky_name : Str
sky_name = "sky/meadow"

# sprout is 0, the fallback, until loaded. A sky of 0 draws no sky.
primitive_meshes : MeshIds
primitive_meshes = {
	cube: Mesh.primitive(Cube),
	sphere: Mesh.primitive(Sphere),
	plane: Mesh.primitive(Plane),
	sprout: 0,
	sky: 0,
}

resolve_meshes : Manifest -> MeshIds
resolve_meshes = |manifest| { ..primitive_meshes, sprout: Mesh.resolve(manifest, "sprout"), sky: Mesh.resolve(manifest, sky_name) }
```
<!-- endregion -->

You can send `Load({ pack, assets })` from `init` or from `step`. The host
runs it right after the call that returned it:

1. The host loads each named asset that is not loaded yet.
2. The host calls `loaded` with the pack name and the [Manifest].
3. The host calls `view` with the Model that `loaded` returned.

All of this happens in the same frame, so a `Load` from `init` is done
before the first `view`.

The Manifest holds each name that the `Load` asked for, in the order asked,
with its id. `loaded` is the only place where you get ids, so find the ones
you need there and keep them in your Model. [`Mesh.resolve`][Mesh.resolve]
finds a name in the Manifest. Call it in `loaded`, not in `view`.

A mesh id goes in the `mesh` of a [Draw]. A sky id goes in the `sky` of the
[Scene]. A Sound id goes in a Play or a Loop, as [Sound](sound.md) shows.
`Mesh.resolve` finds any name in the Manifest, so it gives sky ids too.
`Sound.resolve` gives Sound ids.

If a name is not on disk, or its file does not load, it gets id 0 in the
Manifest, and the host logs the name once.

## The assets folder

Put the asset files in a folder called `assets`, next to your `main.roc`.
Each kind of asset has its own folder:

| Kind | Where | Name |
|---|---|---|
| Mesh | a `.glb` file in `assets/meshes/` | the file stem, such as `sprout` for `sprout.glb` |
| Sky | a folder in `assets/sky/` with six PNG files | `sky/` and the folder name, such as `sky/meadow` |
| Sound | a `.wav` or `.ogg` file in `assets/sound/` | `sound/` and the file stem, such as `sound/blip` for `blip.wav` |

The six faces of a sky are `px.png`, `nx.png`, `py.png`, `ny.png`,
`pz.png` and `nz.png`. Names are case-sensitive.

At startup, the host lists the mesh names, then the sky names, then the
Sound names, each in sorted order, and puts the list in `Config.assets`. It doesn't load any of
the files yet. Your game can read the list in `init`. For example, the
cards game in [Install and first run](install.md) asks for its card mesh
only when the file is on disk. See [Config].

## Unload a Pack

When your game no longer needs a Pack, send `Unload(pack)`. The host drops
the Pack, and unloads each asset that no other loaded Pack holds.

Packs don't depend on each other. You can have any number loaded at one
time, and unload them in any order. If two loaded Packs name the same
asset, it loads once and keeps one id.

To switch from one Pack to a new one:

1. Send `Load` for the new Pack.
2. In `loaded`, keep the new ids.
3. In a later step, send `Unload` for the old Pack.

This way the new ids exist before the old ids go, so no frame draws a
stale id.

## The fallback mesh

Id 0 is the fallback mesh, a magenta cube. The host draws it for each mesh
id that it does not know. So a misspelt name shows up on the screen instead
of stopping the game.

An id from a Pack that has unloaded is stale. A stale id draws the fallback
mesh, and the host logs it once. It never draws whatever mesh took its
place.

## The Primitives

The host makes three meshes itself: a cube, a sphere and a plane. They load
at startup, belong to no Pack and never unload, so you can use them with no
`Load`. [`Mesh.primitive`][Mesh.primitive] gives the id of each one from a
[Primitive] tag, such as `Mesh.primitive(Cube)`. Pong draws only the cube,
so it has no `assets/` folder.

## Reference

### Where the host looks for assets

The host looks for `assets/` in the folder of the program path:

- With `roc main.roc` or `roc run main.roc`, that is the folder of
  `main.roc`.
- With a built binary, it is the folder of the binary. If you start the
  binary by its name from `PATH`, the path has no folder, so the host reads
  `assets/` in the working directory.

The variable `ROCCO_ASSETS` gives a different path for the `assets` folder.

### Commands that do nothing

The host ignores these Commands, and logs each one once:

- a `Load` for a Pack that is already loaded,
- a second `Load` of one Pack in one step,
- an `Unload` for a Pack that is not loaded.

### Meshes from glTF

A mesh file is a binary glTF (`.glb`) file. In glTF, a mesh has one or
more parts, each with its own triangles. The host merges each part of each
mesh node in the glTF scene into one mesh.

- Each part must hold triangles. If one part does not, the file does not
  load, and its name gets id 0.
- The merged mesh draws with one material and one base colour texture:
  those of its first part.
- The material is glTF metallic-roughness.
- A mesh with `KHR_materials_unlit` skips the lights and draws its base
  colour.

### Capacities

The [Launch] sets the size of each asset table: `capacity.meshes`,
`capacity.skies` and `capacity.sounds`. When a table is full, a `Load` gives the new name id 0,
and the host logs once. See [Launch](launch.md) for the capacities.

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Draw]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Draw
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Manifest]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Manifest
[Mesh.resolve]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.resolve
[Mesh.primitive]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.primitive
[Primitive]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.Primitive
