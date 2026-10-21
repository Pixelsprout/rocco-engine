---
title: Assets and Packs
summary: Where the asset files go, how a Pack loads and unloads them, what the Manifest holds, and the meshes that need no file.
order: 4
---

# Assets and Packs

An asset is a file that the host loads, such as a mesh or a sky. A Pack is
a named set of assets that load and unload together. Your game names the
assets of each Pack in Roc. It sends the [Command]s `Load` and `Unload`.
The host owns the files, the GPU data and the ids.

## The assets folder

Put the asset files in a folder with the name `assets`, beside your
`main.roc`. Put each kind of asset in its own folder:

| Kind | Where | Name |
|---|---|---|
| Mesh | a `.glb` file in `assets/meshes/` | the file stem, such as `sprout` for `sprout.glb` |
| Sky | a folder in `assets/sky/` with six PNG files | `sky/` and the folder name, such as `sky/meadow` |

The six faces of a sky are `px.png`, `nx.png`, `py.png`, `ny.png`,
`pz.png` and `nz.png`. Names are case-sensitive.

The host finds `assets/` in the folder of the program path:

- With `roc main.roc` or `roc run main.roc`, that is the folder of
  `main.roc`.
- With a built binary, it is the folder of the binary. If you start the
  binary by its name from `PATH`, the path has no folder. Then the host
  reads `assets/` in the working directory.

The variable `ROCCO_ASSETS` gives a different path for the `assets` folder.

At startup, the host lists the mesh names, then the sky names, each in
sorted order. It puts the list in `Config.assets` and loads none of the
files. See [Config]. Your game can read the list in `init`. The cards game in
[Install and first run](install.md) asks for its card mesh only when the
file is on disk.

## Load a Pack

Send `Load({ pack, assets })` from `init` or from `step`. The host runs it
after the call that returned it:

1. The host loads each named asset that is not loaded yet.
2. The host calls `loaded` with the pack name and the [Manifest].
3. The host calls `view` with the Model that `loaded` returned.

The host loads the files before it calls `loaded`, in the same frame. A
`Load` from `init` runs before the first `view`.

The Manifest holds each name that the `Load` asked for, in the order asked,
with its id. A name that is not on disk, or a file that does not load, gets
id 0. The host logs that name once.

`loaded` is the only place where ids exist. Find each id that you need in
the Manifest. Keep it in your Model. The entity game loads one mesh and
one sky:

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

[`Mesh.resolve`][Mesh.resolve] finds a name in the Manifest. Call it in
`loaded`, not in `view`. A sky id goes in `sky` of the [Scene]. A mesh id
goes in `mesh` of a [Draw].

## Unload a Pack

When your game no longer needs a Pack, send `Unload(pack)`. The host drops
the Pack, and unloads each asset that no other loaded Pack holds.

Packs do not depend on each other. Any number of Packs can be loaded at one
time, and they can unload in any order. An asset that two loaded Packs name
loads once and keeps one id.

To change from one Pack to a new Pack:

1. Send `Load` for the new Pack.
2. In `loaded`, keep the new ids.
3. In a later step, send `Unload` for the old Pack.

The new ids exist before the old ids go, so no frame draws a stale id.

These Commands do nothing, and the host logs each one once:

- a `Load` for a Pack that is loaded,
- a second `Load` of one Pack in one step,
- an `Unload` for a Pack that is not loaded.

## The fallback mesh

Id 0 is the fallback mesh, a magenta cube. The host draws it for each mesh
id that it does not know. So a misspelt name shows on the screen and does
not stop the game.

An id from a Pack that unloaded is stale. A stale id draws the fallback
mesh, and the host logs it once. It never draws the mesh that took its
place.

## The Primitives

The host makes three meshes itself: a cube, a sphere and a plane. They load
at startup, belong to no Pack and never unload. Use them with no `Load`.
[`Mesh.primitive`][Mesh.primitive] gives the id of each one from a
[Primitive] tag, such as `Mesh.primitive(Cube)`. Pong draws only the cube,
so it has no `assets/` folder.

## Meshes from glTF

A mesh file is a binary glTF (`.glb`) file. In glTF, a mesh has one or
more parts, each with its own triangles. The host merges each part of each
mesh node in the glTF scene into one mesh. Each part must hold triangles.
If one part does not, the file does not load, and its name gets id 0. The
merged mesh draws with one material and one base colour texture: those of
its first part. The material is glTF metallic-roughness. A mesh with
`KHR_materials_unlit` skips the lights and draws its base colour.

## Capacities

The [Launch] sets the size of each asset table: `capacity.meshes` and
`capacity.skies`. When a table is full, a `Load` gives the new name id 0
and the host logs once. [Launch](launch.md) tells about the capacities.

[Command]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Command
[Config]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Config
[Scene]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Scene
[Draw]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Draw
[Launch]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Launch
[Manifest]: https://pixelsprout.dev/projects/rocco/api/platform/Vocabulary/#Vocabulary.Manifest
[Mesh.resolve]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.resolve
[Mesh.primitive]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.primitive
[Primitive]: https://pixelsprout.dev/projects/rocco/api/mesh/#Mesh.Primitive
