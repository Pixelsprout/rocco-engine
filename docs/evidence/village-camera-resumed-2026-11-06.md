# Village camera capture after closing other apps

The user closed other apps before these captures.
Both full-scene runs completed 1,200 frames with normal memory pressure.
The user reported no visible stutter during the resumed testing.
The original visual symptom is therefore not reproduced.
One memory-diagnostic frame still contains a 50 ms callback interval.
No performance fix or bandwidth cause is established.

## Controls and timing

Both runs used the unchanged diagnostic binary from [the pass-entry investigation](village-camera-waits-2026-11-06.md).
Its SHA-256 is `9b400163d886506bf02e113385bfb1332eac78847db9f3d5913aad7ce52e279a`.
Both used the same wide debug-camera sweep and seed 0.
The boundary files confirm 1920 by 1080 pixels at DPI 1.
Metadata confirms X4 MSAA, 2048 shadow maps, two cascades, 1,436 source Draws, and 21,993 field Draws.
No scene feature, asset, or quality setting changed.
Native pass labels and Instruments remained disabled.

| Run | Settled moving frames | Callback p95 / p99 / max, ms | CPU p95 / p99 / max, ms |
| --- | ---: | ---: | ---: |
| Lightweight | 1,143 | 16.954 / 20.221 / 21.266 | 16.095 / 19.934 / 21.064 |
| Memory diagnostic | 1,138 | 16.814 / 19.610 / 50.081 | 15.721 / 19.298 / 21.416 |

The lightweight run has no settled interval of at least 30 ms.
Its 22 pressure samples all report normal state 1.
The memory diagnostic has one such interval.
Its 18 pressure samples also report state 1.
Each run retains the existing 120-step settling rule after the last Load.
The memory diagnostic adds native memory queries and one footprint snapshot.
These runs are not a controlled comparison of instrumentation cost.
Background load also differs from earlier captures.

| Run / frame | Callback, ms | CPU Spans, ms | Pass entry, ms | Drawable subset, ms |
| --- | ---: | ---: | ---: | ---: |
| Lightweight / 201 | 21.266 | 21.064 | 0.068 | 0.018 |
| Lightweight / 726 | 20.737 | 10.881 | 9.719 | 9.655 |
| Memory / 193 | 50.081 | 11.401 | 38.554 | 13.790 |

Frame 201 spends 8.758 ms in Step.
Several other lightweight CPU outliers also spend about 9 ms in Step.
Frame 726 instead waits mostly inside drawable acquisition.
Frame 193 contains another 24.764 ms inside pass entry outside drawable acquisition.
The clocks do not separate that time into driver work, an in-flight frame wait, or thread scheduling.
These wait measurements do not establish GPU execution time or actual display intervals.

Frame 193 starts 27.750 seconds after the memory probe starts.
The footprint snapshot runs from 32.788 through 35.972 seconds.
The snapshot does not overlap the 50 ms interval.
Other monitoring overhead remains possible.
A callback outlier alone does not contradict the user's report of smooth visible movement.

## Memory measurements

The user saw about 7 GB in Activity Monitor but did not identify its field.
The following native measurements distinguish process RSS, physical footprint, and system VM counters.
All GB values in this section use decimal bytes.
MiB values use 1,048,576 bytes.

The lightweight monitor records a peak game RSS of 6,269.8 MiB.
Its final 20 seconds show about 4,363 through 4,424 MiB RSS.
The monitor uses Python's monotonic clock, which differs from the engine's clock on this Mac.
These old monitor timestamps must not join directly to engine frame timestamps.

The memory diagnostic uses `CLOCK_MONOTONIC_RAW`, matching Odin's `core:time` implementation on Darwin.
It reads `proc_pid_rusage` version 0 for process RSS and physical footprint.
It also records `vm_stat`, native pressure state, background processes, and `memory_pressure -Q`.
The first settled frame starts 25.566 seconds after the probe starts.

| Measurement | Loading and settling | Settled |
| --- | ---: | ---: |
| Maximum sampled game RSS | 7.151 GB | 6.192 GB |
| Sampled game RSS range | 0.009–7.151 GB | 5.980–6.192 GB |
| Sampled physical footprint range | 0.002–7.550 GB | 8.037–8.325 GB |

The native footprint snapshot reports 8.333 GB total and an 8.343 GB peak.
Its largest category is 7.341 GB of IOAccelerator graphics memory across 646 regions.
The snapshot also lists 0.563 GB swapped within that graphics category.
That swapped figure is part of the category, not an additional allocation.
Other categories include 0.576 GB of unmapped owned footprint and 0.265 GB of unmapped owned graphics footprint.
These figures support a large game memory cost.
They measure allocated memory and physical accounting, not memory bandwidth.

The exact Activity Monitor system `Memory Used` field was not captured.
System VM counters provide a separate comparison:

| System counter | Before launch | At maximum sampled wired memory | After exit |
| --- | ---: | ---: | ---: |
| Free pages, converted to GB | 7.315 | 0.065 | 8.192 |
| Wired pages, converted to GB | 2.273 | 9.684 | 2.277 |
| Anonymous pages, converted to GB | 2.842 | 2.791 | 2.246 |
| Compressor storage, GB | 1.223 | 1.462 | 1.250 |

These counters are not an exact reconstruction of Activity Monitor's `Memory Used` value.
Normal pressure does not guarantee enough headroom for Instruments.
The earlier native trace alone occupied about 5.2 GiB on disk before export failed.
No new native trace or resolution comparison was run.

The settled footprint decreased slightly across this short run.
System wired memory returned near its starting value after the game exited.
These observations do not show continuing resource growth.
They also cannot exclude a leak over longer sessions.

Earlier runs stopped at warning pressure while more background work was active.
The native failure included substantial Spotlight CPU use.
After the user closed apps, both runs completed under normal pressure.
This supports memory contention as a possible constraint, but does not establish a stutter cause.
The workloads were not randomized or matched, and background CPU remained active.

## Static texture inspection

The audit reads the 93 tracked GLB files in `examples/village/assets/meshes`.
It reads GLB image buffer views and PNG dimensions without loading the game or decoding pixel data.
These files contain 320 embedded PNG image records.
SHA-256 of each encoded PNG gives 53 distinct encoded images.
The audit found 266 images at 2048 by 2048, 41 at 1024 by 1024, five at 1008 by 981, and eight at 512 by 512.

For each record, the audit assumes four bytes per texel.
It sums every mip level down to one by one, halving each axis with integer division.
One such RGBA8 mip chain per embedded image totals 6,217,151,824 bytes, or 6.217 GB.
Counting each distinct encoded image once gives 971,359,860 bytes.
This second value is not a proven achievable allocation budget.

The loader deduplicates image and sampler references within one GLB.
Its texture key also includes colour space and alpha cutoff.
`mesh_upload_loaded` uploads textures for each mesh separately.
It can upload an ordinary copy for a texture with an alpha cutoff.
`texture_upload` uses uncompressed RGBA8 or SRGB8A8 textures with mip levels.
See `engine/gltf.odin`, `engine/mesh.odin`, and `engine/image.odin`.

The arithmetic is not an exact GPU allocation census.
It does not check whether every embedded image is referenced by a loaded material.
It excludes extra colour-space or cutoff variants, ordinary cutoff copies, Metal allocation padding, buffers, targets, skies, and other assets.
Encoded equality alone does not make different sampling or mip-generation contracts interchangeable.
The result plausibly explains much of the large graphics category without establishing its exact total.
It establishes neither bandwidth saturation nor the reported visual stutter's cause.

The smallest proposed allocation check needs only two grass meshes.
`Grass_Common_Short.glb` and `Grass_Common_Tall.glb` share embedded image 0 at 512 by 512.
Its PNG SHA-256 is `02f5e5562427b6739d36562c42e38ffaa1faa7ef62de45d2ba48ae29cdd0f709`.
One RGBA8 mip chain is 1,398,100 bytes.
A small native harness can load both meshes through the real mesh loader and compare their resulting texture handles.
Use `sg.mtl_query_image_info` to inspect the native textures and their allocated sizes.
Match colour space, sampler, cutoff, and mip content before counting allocations as duplicates.
This check needs no full village launch and changes no scene asset.
The later [two-mesh allocation check](texture-sharing-2026-11-06.md) proves separate native allocations for this pair.

## Texture cache and atlas assessment

A shared GPU texture cache addresses repeated uploads more directly than an atlas.
It can preserve existing glTF UVs and texture dimensions.
Cache keys must preserve decoded content, colour space, mip generation, and alpha-cutoff variants.
Samplers can remain separate, but their filtering and wrap modes must retain the same behaviour.
Shared resource ownership must also preserve Pack unload lifetimes.

An atlas can reduce texture binding changes for compatible materials.
It needs UV remapping for the material maps that currently sample the first glTF UV set.
Each mip needs padding to prevent neighbouring atlas regions from affecting filtering.
Repeat and mirrored-repeat modes need special treatment inside each atlas region.
Cutout coverage must survive mip generation and the ordinary/cutoff texture distinction.

An atlas does not automatically reduce this renderer's draw count.
`Instance_Key` also contains mesh identity, mesh generation, and index range.
Different meshes therefore remain different instance batches even if they share one texture.
Neither a cache nor an atlas is yet a measured stutter or bandwidth fix.

## Bandwidth measurement plan

The current user-visible symptom is absent, so another quality comparison has no specific visual failure to test.
Keep the full-scene acceptance path unchanged.

Apple documents GPU bandwidth counters in Instruments and the Metal debugger.
The lighter Metal HUD exposes GPU timing and presentation delay, but those metrics do not measure bandwidth.
See [GPU bandwidth measurement](https://developer.apple.com/documentation/xcode/measuring-the-gpus-use-of-memory-bandwidth) and [HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics).

A lower-memory next step can record asynchronous GPU and presentation timestamps in a fixed-capacity diagnostic buffer.
Metal exposes command-buffer start and end times after completion.
It also exposes drawable presentation time, with zero indicating an unpresented or dropped drawable.
See [GPU timestamps](https://developer.apple.com/documentation/metal/mtlcommandbuffer/gpustarttime) and [drawable presentation time](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime).

1. Associate each command buffer and drawable with its producing engine frame.
2. Read GPU timestamps from completion handlers without waiting for the GPU.
3. Read display timestamps from presentation handlers.
4. Preserve missing, dropped, and late callback records.
5. Compare those records with CPU work, pass entry, and drawable acquisition on the same slow frames.

Long GPU execution before the wait would support a GPU bottleneck.
Short GPU execution with delayed presentation would support presentation pacing or scheduling instead.
Neither result alone proves bandwidth saturation.
If GPU execution is slow, collect bandwidth and read/write limiter counters on a machine with enough memory for the full scene.
Start that short capture after asset loading.
High bandwidth alone is insufficient; the counters must show that memory access limits GPU progress.
A later resolution comparison could test pixel-work sensitivity, but would not separate bandwidth from shader or fill cost by itself.

## Retained evidence

The [resumed evidence archive](village-camera-resumed-2026-11-06.tar.gz) retains both complete captures and summaries.
It includes CPU Spans, boundary files, command records, metadata, memory monitors, footprint output, scripts, and the static texture audit.
It also records a failed sampling attempt that ran after the lightweight process exited.
Archive SHA-256: `7fa7d69f137b3ff7d90b24d390668b65783be7d3257d2a1ce981a16a38d9a8f4`.

No engine code changed during this resumed investigation.
Both capture summaries parsed successfully.
The stutter attribution task remains open.
