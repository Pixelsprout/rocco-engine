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
meshes, skies, Sounds and Images, that load and unload together. Your game lists the
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
[Scene]. A Sound id goes in a Play or a Speaker, as [Sound](sound.md) shows.
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
| Image | a `.png` file in `assets/images/` | `image/` and the file stem, such as `image/coin` for `coin.png` |

The six faces of a sky are `px.png`, `nx.png`, `py.png`, `ny.png`,
`pz.png` and `nz.png`. Names are case-sensitive.

At startup, the host lists the mesh names, then the sky names, then the
Sound names, then the Image names, each in sorted order, and puts the list in `Config.assets`. It doesn't load any of
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
- The material's emissive draws: `emissiveFactor`, `emissiveTexture` and
  `KHR_materials_emissive_strength`. An emissive surface lights nothing
  else.
- A mesh with `KHR_materials_unlit` skips the lights and draws its base
  colour plus its emissive.
- A file with a Skin loads as one skinned mesh. See
  [Skinned meshes](#skinned-meshes).

### Skinned meshes

A `.glb` with a Skin loads as one skinned mesh, and its Manifest entry
lists its Clips, each with a name, an id and a duration. A Draw plays a
Clip through its `pose`. With no Clip named, the mesh draws in its bind
pose. [Tutorial chapter 10](tutorial/10-animation.md) walks through it.

The file must follow these rules:

- It has at most one Skin, with at most 64 Joints.
- Every mesh node uses that Skin. A file that mixes skinned and unskinned
  mesh nodes does not load.
- Each primitive has `JOINTS_0` and `WEIGHTS_0`. The host reads up to 4
  Joints for each vertex, and keeps each weight in 8 bits.
- Clip keys are LINEAR or STEP, not CUBICSPLINE. A Clip can key the
  translation, the rotation and the scale of a Joint.
- No Joint scales more along one axis than another. The host turns the
  normals with the skin matrix, so a non-uniform scale lights the mesh
  wrong. The file loads, so nothing warns you.

If a file breaks one of the first four rules, it does not load, its name
gets id 0, and the host logs the reason, for example:

```
pack "pip" names "pip", but the file has more than one Skin; its id is 0
```

The other reasons are "the file mixes skinned and unskinned mesh nodes",
"the Skin has more than 64 Joints", "a Clip has CUBICSPLINE keys; export
LINEAR or STEP keys", "a skinned primitive has no JOINTS_0 or WEIGHTS_0",
and two for a broken file: one for a bad Skin and one for a bad Clip.

A Clip that moves morph weights or a node that is not a Joint still
loads. The host skips that part of the Clip and logs a line that ends in
"so the Clip skips that channel". A file with no Skin loads as a rigid
mesh, and the host ignores its Clips.

The host pads the box of a skinned mesh by a quarter of its largest side.
The shadow map fits the boxes, so an arm or a leg that a Clip swings out
still casts its shadow.

### Images

An Image is a PNG file. The host decodes it to 8-bit RGBA and uploads it
with no mipmaps. Its Manifest entry carries its width and height in pixels.
In `loaded`, `Image.resolve(manifest, "image/coin")` gives the id and
`Image.size(manifest, "image/coin")` gives the size. Keep both in your Model.

Before the upload, the host gives each fully transparent pixel the colour
of the nearest visible pixels. Alpha stays 0, so nothing new shows, but a
scaled Image gets no dark fringe at its edges.

An `Image` value names an Image, the part of it to show, a tint and a
filter. Start from `Image.default` and set its `id`. A `Px` region counts
in the pixels that `Image.size` reports, from the top-left corner, so one
sprite sheet can hold many pictures.

### Capacities

The [Launch] sets the size of each asset table: `capacity.meshes`,
`capacity.skies`, `capacity.sounds` and `capacity.images`. When a table is full, a `Load` gives the new name id 0,
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
