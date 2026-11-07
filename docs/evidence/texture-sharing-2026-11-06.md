# Two-mesh Metal texture allocation check

The two grass meshes allocate separate GPU copies of identical texture content.
This proves duplicate allocation for this pair, not a stutter cause or bandwidth limit.
No atlas or shared cache was implemented.

## Method and commands

The [native harness](../../scripts/texture-sharing-check/main.odin) loads only `Grass_Common_Short.glb` and `Grass_Common_Tall.glb`.
It uses the real GLB parser, mesh table, and texture upload procedures.
It creates a Metal device without a window or village scene.
Before upload, it compares all decoded mip bytes, dimensions, colour space, alpha cutoff, and sampler settings.
After upload, it calls `sg.mtl_query_image_info` and reads each native resource's `allocatedSize`.

Run from the repository root:

```sh
odin build scripts/texture-sharing-check -o:speed -vet -strict-style -out:/tmp/village-texture-sharing-check
/usr/bin/time -l /tmp/village-texture-sharing-check examples/village/assets/meshes > /tmp/village-texture-sharing-native-result.txt 2>&1
```

The strict build passed.
The native run exited successfully in 0.60 seconds.
Maximum RSS was 23,347,200 bytes.
The time tool reported an 11,436,560-byte peak physical footprint.
These process metrics differ from the sum of individual GPU resource sizes.

The first run used the sandbox and could not create a Metal device.
Its [failure output](texture-sharing-2026-11-06/sandbox.txt) remains available.
The successful run used approved native access; its [complete output](texture-sharing-2026-11-06/native.txt) is retained.

The executable SHA-256 is `070c9f5e488f86d7de7fe3826f3c8fe4311d8cdf25c240ba11944e1a60e95cb9`.
The engine source was commit `2c17639`; this change adds the harness.
Short mesh SHA-256: `c9f5ba19c92d5dbaad0a1eaac3fbcf090e8ffb2123785324e25240a02b862316`.
Tall mesh SHA-256: `e2b65fb8b7af3a5a79677e1c157e0adcacbcd464bf68a22ee04faad54b57bc8e`.

## Result

Both meshes load one texture without loader notes.
The decoded textures match across all ten mip levels.
Each texture is 512 by 512, uses sRGB, and has an alpha cutoff of zero.
Both use linear minification, magnification, and mip filtering, with Repeat on both axes.
The mip payload is 1,398,100 bytes per texture.

| Mesh | Sokol image ID | Native texture address | Allocated bytes |
| --- | ---: | --- | ---: |
| Grass_Common_Short | 65537 | `0x100918EE0` | 1,425,408 |
| Grass_Common_Tall | 65538 | `0x1008F02B0` | 1,425,408 |

The native objects differ and come from separate image creation calls.
Together they report 2,850,816 allocated bytes for matching texture content.
The addresses identify this run only.
Sharing this compatible pair could avoid one 1,425,408-byte texture allocation.
That is an allocation opportunity, not a measured performance improvement.

## Cache and atlas implications

A shared texture cache is the direct change for these identical uploads.
It can preserve existing UVs and repeat behaviour.
A cache must preserve decoded content, mip levels, colour space, and alpha-cutoff mip generation.
It must preserve ordinary and cutoff variants where they differ.
Sampler filtering and wrap modes must remain correct, whether samplers share or remain separate.
Reference counts must preserve Pack unload and reload lifetimes.
Reloaded content must not reuse a stale cached texture.

An atlas targets binding changes and requires UV remapping, mip padding, and correct repeat and cutout sampling.
It would not automatically merge this renderer's batches because their keys also contain mesh identity and index range.
This check does not establish the total savings across all village assets.
The larger [texture audit](village-camera-resumed-2026-11-06.md) remains an estimate with additional compatibility constraints.
