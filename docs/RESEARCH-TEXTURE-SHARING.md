# Texture sharing before atlases

Research date: 2026-11-06.
Status: recommendation only; no cache or atlas implementation.

## Recommendation

First, add shared ownership for compatible GPU images across meshes.
Then measure allocation savings with the existing native check and the unchanged village scene.
Consider compression or texture residency only if the remaining memory cost justifies that work.
Consider atlases only after measurements show a material binding or batching cost.

This order addresses a proven duplicate allocation through a bounded change to image ownership.
It does not assume that texture memory caused the reported stutter.

## Rocco evidence

The two grass meshes upload matching 512-by-512 images with ten matching mip levels.
Metal reports distinct native objects, each with 1,425,408 allocated bytes.
Sharing this compatible pair could avoid one such allocation.
The [native check](evidence/texture-sharing-2026-11-06.md) uses the real loader and uploader without launching the village.

The [village audit](evidence/village-camera-resumed-2026-11-06.md) found 320 embedded PNG records across 93 GLBs.
Those records contain 53 distinct encoded PNG hashes.
One RGBA8 mip chain per record gives a theoretical 6,217,151,824-byte total.
Counting each encoded hash once gives 971,359,860 bytes under the same calculation.
Neither calculation measures native allocation or proves a final cache budget.
Colour space, prepared mip content, cutoff variants, and resource use can require separate images.

The user saw no visible stutter during the later run after closing other applications.
The earlier visual symptom remains unreproduced.
Process footprint and IOAccelerator allocation measure capacity, not memory bandwidth.

## What other engines do

| Engine | Shared asset identity | Atlas or memory work |
| --- | --- | --- |
| Bevy | `AssetServer::load` returns the same handle for the same path while a handle remains. `Assets::add` does not generally deduplicate content. [Asset documentation](https://docs.rs/bevy/0.20.1/bevy/asset/) | The explicit atlas builder packs images with configurable padding and sampling. [First-party atlas example](https://github.com/bevyengine/bevy/blob/main/examples/2d/texture_atlas.rs) |
| Godot | `ResourceLoader` caches resources by path. Default loading reuses cached resources. [ResourceLoader](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html) | Multiple `AtlasTexture` resources can reference regions of one texture. The API documents tiling limits and filtering safeguards. [AtlasTexture](https://docs.godotengine.org/en/stable/classes/class_atlastexture.html) |
| Unity | Shared bundle dependencies need explicit shared placement. Otherwise, bundles can contain separate objects that load twice into memory. [Avoiding duplication](https://docs.unity.com/en-us/engine/6000.6/manual/assets-and-media/assets-managing-runtime/assets-avoid-duplication) | Sprite atlases can reduce draw calls. Unity recommends grouping sprites by use and compression needs. [Sprite atlases](https://docs.unity.com/en-us/engine/6000.6/manual/unity2d/sprite/atlas/atlas-introduction) |
| Unreal | References identify assets. `LoadObject` loads an object if it is not already loaded. [Referencing assets](https://dev.epicgames.com/documentation/unreal-engine/referencing-assets-in-unreal-engine) | Unreal provides explicit duplicate-asset consolidation. Material merging can bake textures and generate new UVs. [Consolidation](https://dev.epicgames.com/documentation/unreal-engine/consolidating-assets-in-unreal-engine), [Actor merging](https://dev.epicgames.com/documentation/unreal-engine/merging-actors-in-unreal-engine) |

These sources establish reuse through shared asset identity.
They do not promise automatic content deduplication across arbitrary embedded copies in separate GLB files.
Rocco needs that additional identity step because separate meshes currently own separate copies of matching image content.

Bevy's render source stores prepared assets by source asset ID.
Its preparation and removal paths connect GPU resources to that identity. [Bevy render source](https://github.com/bevyengine/bevy/blob/main/crates/bevy_render/src/render_asset.rs)

Godot shares built-in resources across instances of the same scene.
It releases resources when references disappear. [Godot resources](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html)
Creating a new `ImageTexture` from an image creates a resource with its own rendering texture.
Reusing an existing texture resource differs from creating separate texture resources from matching pixels. [Godot image texture source](https://github.com/godotengine/godot/blob/master/scene/resources/image_texture.cpp)

Unity also distinguishes CPU texture copies from GPU storage.
Readable textures retain an additional CPU copy. [Unity texture readability](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/texture/isreadable)
Unreal's streamer selects resident mip levels within a memory budget.
That controls residency separately from duplicate asset identity. [Unreal texture streaming](https://dev.epicgames.com/documentation/unreal-engine/texture-streaming-overview-for-unreal-engine)

## Proposed first implementation

The following design is a proposal for a bounded change.
It does not change GLB import semantics or the village acceptance scene.

1. Add one shared owner for immutable GPU images.
2. Compute a strong digest from all prepared mip bytes before upload.
3. Combine that digest with the complete image descriptor.
4. Compare complete keys when the lookup table reports a hash match.
5. Acquire an existing compatible image or upload a new image.
6. Release the image only after its last owner releases it.

Include dimensions, pixel format, colour interpretation, mip layout, and relevant creation flags in the descriptor.
Use a compact strong digest, such as SHA-256, rather than a short table hash as content identity.
Do not retain decoded mip bytes solely to compare cache entries.
That retention could replace GPU savings with large CPU allocations.
The design must document the digest collision assumption.
Ordinary lookup-table collisions still require full key equality.

Hashing prepared mips preserves existing decode and mip generation semantics.
It leaves repeated PNG decoding intact.
Later import work could establish shared source identity if loading measurements justify it.

Keep sampler settings per use, or share samplers through a separate compatible key.
Different wrap modes need not force different image storage when the backend uses separate samplers.
Preserve sRGB and linear formats as distinct interpretations.
Preserve ordinary and cutoff mip variants whenever their prepared content differs.
Preserve alpha coverage and each material's cutoff value.

Replace direct mesh-owned image destruction with shared acquire and release operations.
Preserve the Pack lifetime contract: shared assets survive until the final Pack releases them.
Preserve backend rules for resources still referenced by submitted GPU work.
Reloaded content must acquire its new identity before releasing the old image.
Failed loads must release only their own references.

## Bounded validation

1. Extend the two-grass native check to require one shared native image.
2. Confirm that Metal removes one 1,425,408-byte allocation for this pair.
3. Test incompatible formats and mip variants with separate expected images.
4. Test different samplers without changing each material's sampling behaviour.
5. Unload one Pack while another Pack still uses the shared image.
6. Test reload, failed loading, and final release.
7. Record live image count, unique allocated bytes, and cache hits.
8. Compare the unchanged village scene only when memory pressure permits.

Keep the camera path, scene, resolution, and rendering settings unchanged for that comparison.
Record process footprint and system pressure separately.
Check image output for UV, cutout, and mip changes.
Report actual compatible sharing rather than assuming exactly 53 final images.
Run one heavy workload at a time.

## Why an atlas comes later

A shared image cache directly removes matching uploads while preserving UVs.
An atlas combines different images and changes how materials address them.
It can reduce texture binding changes when the renderer can batch compatible draws.
Rocco's batch key also contains mesh identity and index range.
An atlas alone therefore does not merge draws from different meshes. [Rocco allocation evidence](evidence/texture-sharing-2026-11-06.md)

An atlas design must preserve glTF UV coordinates, repeat behaviour, filtering, and material transforms.
It must isolate each region at every mip level to prevent colour bleeding.
Cutout materials also need correct alpha coverage after packing and mip generation.
Godot documents region filtering and tiling limits. [Godot AtlasTexture](https://docs.godotengine.org/en/stable/classes/class_atlastexture.html)
Unreal exposes gutter padding for merged materials and replaces UV layouts when it bakes one material. [Unreal actor merging](https://dev.epicgames.com/documentation/unreal-engine/merging-actors-in-unreal-engine)

Packing unrelated images can also keep unused content resident with the atlas.
Unity recommends atlas groups based on shared use and compression needs. [Unity sprite atlases](https://docs.unity.com/en-us/engine/6000.6/manual/unity2d/sprite/atlas/atlas-introduction)
These costs require a measured binding or batching problem before an atlas becomes the next change.

## Stutter and bandwidth limits

Duplicate allocation is proven for the grass pair.
A bandwidth limit and a stutter cause remain unproven.
Sharing storage does not necessarily reduce texture samples per frame.
It may change cache locality or memory pressure, but measurements must establish those effects.

After sharing, first measure the remaining footprint with the same workload.
If memory remains excessive, evaluate supported GPU compression and mip residency with image quality checks.
Do not reduce the full-scene acceptance path to produce better timing.

If visual stutter returns, collect GPU duration and presentation timing aligned to the same frame IDs.
Use hardware bandwidth counters only when the device and capture tool expose reliable counters.
Collect a short capture after loading while memory pressure remains normal.
Correlate those counters with drawable waits, CPU spans, and callback gaps.
A CPU wait alone cannot distinguish GPU saturation, presentation pacing, scheduling, or capture overhead.

## Source scope

The research uses official documentation and first-party source only.
The comparison uses Bevy 0.20.1, Godot stable documentation, Unity 6 documentation, and Unreal's current documentation.
Repository links track their current branches and can change.
The recommendations apply these documented patterns to Rocco's measured allocation behaviour.
