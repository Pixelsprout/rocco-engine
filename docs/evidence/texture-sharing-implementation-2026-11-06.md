# Shared immutable mesh textures, 2026-11-06

Compatible mesh textures now share immutable GPU images and views.
The complete village acquires 358 image references across 60 cache images.
The clean memory run reduced settled process footprint from 8.037–8.325 GB to 2.228–2.239 GB.
Four controlled views produced byte-identical baseline and cached PNG files.
These results establish memory savings and unchanged images in those views.
They do not establish a stutter fix, bandwidth improvement, or displayed frame cadence.

## Ownership and image identity

Each mesh table owns one cache.
Each mesh texture slot acquires one image reference and owns its sampler.
Mesh parts borrow those resources through the mesh lifetime.
Cache entries have stable addresses when the lookup map grows.
The final reference releases the shared view and image through Sokol's existing destruction procedures.
Mesh removal and shutdown release references before deleting mesh storage.
Packs retain their existing mesh reference counts and stale ID behaviour.

The key includes SHA-256 across every prepared mip level.
It also includes every mip dimension, mip count, format, cutoff bits, image type, usage flags, slice count, and sample count.
The image descriptor supplies creation flags, including its existing default values.
This boundary creates only immutable 2D images with one slice and one sample.
The key separates sRGB, linear, ordinary, and cutoff variants.
Different samplers can share compatible image storage.
The standard map compares complete keys after lookup hash collisions.
The cache assumes that a SHA-256 content collision is infeasible.
The cache retains no decoded pixels or source paths for equality checks.

Failed image creation releases partial GPU objects.
Failed acquisition releases its sampler without publishing an entry.
Partial mesh texture upload releases every acquired reference.
Existing owners remain valid during another load's failure.
A failed upload to an already uploaded mesh table returns asset ID zero.
Deferred upload failure keeps the existing mesh ID and draws the mesh without its textures.
Headless loading retains prepared data until removal or shutdown and creates no GPU objects.
Shader images, render targets, and other mutable images keep their existing ownership.

## Machine and binaries

The machine is an Apple M5 MacBook Pro with 17,179,869,184 bytes of RAM.
It runs macOS 26.7.2, build 25G332, on arm64.
The implementation starts from source commit `c5043af78833dd25b1302e41063a8f1cb575eaa2`.
The evidence archive retains the implementation patch and build records.
The host uses a release build with Spans enabled.
Roc uses the pinned `nightly-2026-10-11-7d256b9` compiler.

| Binary | SHA-256 |
| --- | --- |
| Unchanged baseline `village-waits.bin` | `9b400163d886506bf02e113385bfb1332eac78847db9f3d5913aad7ce52e279a` |
| Final cached `village-texture-shared.bin` | `ebaf67b9bf4855f993d7c930cba3c0ea827f12f9a2ec8b444d3cdc40b440b5f1` |
| Final release Spans host | `00d1b4ff197705806f76583151e45488858c6e073307fcf90247478334e372b4` |

Odin's SHA-256 implementation detects CPU features through `sysctlbyname` on this Mac.
The macOS link catalog now includes that symbol with public Apple evidence.
The catalog generator and archive audit passed.
No game, Vocabulary, asset, quality setting, or render capacity changed.

## Native grass proof

The harness retains its decoded mip, colour-space, cutoff, and sampler comparisons.
It also checks both unload orders and reloads through the mesh loader.
The final harness reports these results:

| Resource | Before | After |
| --- | ---: | ---: |
| Native images for the grass pair | 2 | 1 |
| Native allocated bytes | 2,850,816 | 1,425,408 |
| Avoided native allocated bytes | 0 | 1,425,408 |
| Final live cache images and references | Not measured | 0 and 0 |

Both final mesh slots used image ID 65537 and native address `0x1043DCAE0`.
The remaining image stayed valid after either mesh unloaded.
The reloaded pair used a fresh shared image before its final release.
The final check took 0.52 seconds and peaked at 27,869,184 bytes RSS.
The additional reload checks make its process timing incomparable with the original single-upload harness.
The original native proof and its asset hashes remain in [the baseline evidence](texture-sharing-2026-11-06.md).

## Full-scene controls and allocation

The clean runs retain the complete village and the existing wide debug-camera sweep.
Each run completed 1,200 frames with seed zero.
Metadata confirms 1,436 source Draws and 21,993 field Draws.
Boundary rows confirm 1920 by 1080 physical pixels at DPI one.
The runs retain X4 MSAA, 2048 shadow maps, and two cascades.
Lighting, materials, vegetation, particles, effects, and post processing remain enabled.
Readback and screenshots ran separately from timing captures.

| Cache measurement | Value |
| --- | ---: |
| Live unique images | 60 |
| Owning image references | 358 |
| Compatible acquisition hits | 298 |
| Ordinary images | 53 |
| Cutoff images | 7 |
| Unique logical mip bytes | 1,056,323,536 |
| Logical mip bytes counted per reference | 6,801,353,752 |
| Unique native Metal allocated bytes | 1,066,205,184 |

Logical bytes count prepared RGBA8 mip payloads without driver padding.
Native allocated bytes sum each unique Metal image's `allocatedSize` once.
Reference bytes count each owning texture slot, including ordinary fallback slots.
The seven cutoff images preserve separate preparation variants.
The ordinary count does not imply that encoded PNG identity alone defines compatibility.
The cache excludes targets, buffers, skies, and independently owned images.

All GB values below use decimal bytes.
RSS, physical footprint, native image allocation, and system pressure measure different things.

| Memory measurement | Baseline | Clean cached run |
| --- | ---: | ---: |
| Settled sampled RSS | 5.980–6.192 GB | 1.583–1.632 GB |
| Settled sampled physical footprint | 8.037–8.325 GB | 2.228–2.239 GB |
| Maximum sampled RSS | 7.151 GB | 1.632 GB |
| Loading and settling maximum sampled footprint | 7.550 GB | 1.816 GB |
| Native footprint snapshot | 8.333 GB | 2.230 GB |
| Native peak physical footprint | 8.343 GB | 2.254 GB |
| IOAccelerator graphics category | 7.341 GB | 1.544 GB |

The remaining graphics category includes allocations outside the mesh image cache.
The footprint categories do not form a native image allocation census.
The clean memory run recorded 21 normal pressure samples.
It used no concurrent build or test process.
The clean lightweight run used the same final binary after the memory run exited.

## Timing and loading

The summaries retain the existing 120-step settling rule after the final Load at step 96.
Callback intervals and CPU Spans do not measure GPU duration or display intervals.
The separate summaries retain all raw rows and every settled callback interval of at least 30 ms.

| Run | Samples | Callback p95 / p99 / max, ms | CPU p95 / p99 / max, ms | Pass entry p95 / p99 / max, ms | Drawable p95 / p99 / max, ms |
| --- | ---: | --- | --- | --- | --- |
| baseline-lightweight | 1143 | 16.954 / 20.221 / 21.266 | 16.095 / 19.934 / 21.064 | 6.621 / 7.210 / 9.719 | 6.575 / 7.168 / 9.655 |
| baseline-memory | 1138 | 16.814 / 19.610 / 50.081 | 15.721 / 19.298 / 21.416 | 5.486 / 6.517 / 38.554 | 5.433 / 6.469 / 13.790 |
| initial-lightweight | 1136 | 17.016 / 19.365 / 21.847 | 15.572 / 18.975 / 19.988 | 6.666 / 7.395 / 10.867 | 6.626 / 7.335 / 10.800 |
| initial-memory | 1136 | 17.076 / 19.890 / 24.959 | 15.793 / 19.513 / 20.274 | 6.550 / 7.651 / 14.071 | 6.500 / 7.589 / 14.018 |
| final-lightweight-before-cleanup | 1136 | 16.808 / 18.922 / 24.064 | 15.295 / 18.676 / 19.852 | 0.073 / 0.089 / 0.116 | 0.018 / 0.022 / 0.035 |
| clean-lightweight | 1138 | 16.834 / 20.207 / 26.236 | 16.117 / 19.929 / 26.005 | 5.698 / 6.434 / 6.697 | 5.646 / 6.386 / 6.654 |
| clean-memory | 1136 | 16.813 / 18.988 / 20.163 | 15.671 / 18.741 / 19.967 | 0.079 / 0.102 / 0.129 | 0.019 / 0.024 / 0.037 |

The clean lightweight maximum occurred at frame 291, covering fixed steps 674–676.
Its 26.236 ms callback interval contains 26.005 ms of CPU Spans.
Game steps took 11.898 ms, interpolation took 7.645 ms, and render submission took 5.083 ms.
Pass entry took 0.092 ms, including 0.019 ms of drawable acquisition.
These spans locate elapsed time but do not separate CPU execution from scheduling delays.
The other saved cached runs did not repeat this maximum.
The cache performs acquisition during loading and release during unloading, outside this frame.
No repeatable timing regression appears in the saved runs.
The clean memory run had no settled callback interval of at least 30 ms.
The baseline memory run had one such interval, at frame 193.
That frame recorded 50.081 ms between callbacks and 11.401 ms of CPU Spans.
Its pass entry took 38.554 ms, including 13.790 ms of drawable acquisition.
These wall-clock measurements do not identify GPU execution or presentation waits.

| Run | Loading Commands, seconds | First callback to settled sample, seconds |
| --- | ---: | ---: |
| baseline-lightweight | 22.337 | 23.557 |
| baseline-memory | 21.366 | 22.334 |
| initial-lightweight | 22.602 | 23.591 |
| initial-memory | 22.911 | 23.889 |
| final-lightweight-before-cleanup | 22.504 | 23.481 |
| clean-lightweight | 23.680 | 24.640 |
| clean-memory | 22.920 | 23.880 |

Loading time sums Commands Spans through the final loading frame.
That measurement includes synchronous decoding, preparation, upload, and related command work.
The cache still decodes and prepares repeated source images.
SHA-256 adds loading work.
These runs do not isolate its cost from other loading and scheduling costs.
No loading speed improvement is claimed.

## Controlled visual comparison

The successful comparison disables the engine's debug camera.
Bridge reports `devices=false`, so real device input does not reach the game camera.
Both binaries use seed zero and the same fixed steps.
Existing `view` port messages select the foliage, canopy, and square cameras.
The captures use these phases:

| View | Fixed step | Comparison |
| --- | ---: | --- |
| Hero | 240 | PNG bytes and Scene JSON identical |
| Foliage | 241 | PNG bytes and Scene JSON identical |
| Canopy | 242 | PNG bytes and Scene JSON identical |
| Square | 243 | PNG bytes and Scene JSON identical |

Every screenshot contains 1920 by 1080 physical pixels.
Inspection covered close foliage cutouts, distant foliage, repeated roof and wall sampling, material colour, and ordinary textured surfaces.
The archive retains both PNG sets, Scene data, hashes, and camera values.
The user observed lower memory use and initially perceived better scene quality.
The user later suggested that perceived quality could reflect smoother motion.
These are subjective observations, separate from the allocation and image comparisons.
The byte-identical images establish no image quality increase.
Display timing remains necessary before claiming smoother pacing.

## Background load, failures, and exclusions

The probes checked native pressure before launch and throughout each run.
They would terminate only their test game at warning pressure.
All completed runs retained normal pressure.
No unrelated process was stopped.
The raw monitors record background processes, including WindowServer, audio services, Activity Monitor, and browser processes.
Background conditions differ from the earlier baseline session.
The comparisons therefore do not isolate every scheduling or system accounting effect.

Four earlier sandbox-blocked test runs left their Odin parents and deadlocked workers alive.
Earlier SIGTERM requests had not ended those workers.
The user observed about 1.26–1.34 GB per Odin process in Activity Monitor.
At inspection, each parent showed 22,560 KiB RSS and zero CPU use.
The Activity Monitor field was not identified as RSS.
The earlier captures retain this background memory confound.
They remain diagnostic evidence but do not replace the clean repeats.
SIGTERM stopped the four owned parents.
Their four workers required SIGKILL.
A process check verified that all eight PIDs exited before the clean runs.
The archive records commands, PIDs, parents, start times, and verification.

An initial memory diagnostic also overlapped a test compilation during loading.
That compilation ended before settling.
The clean memory run excludes that overlap.
The first native grass attempt failed because the sandbox could not create a Metal device.
Two visual attempts exited before startup because required Spans environment values were missing.
The first static debug-camera visual run received manual camera input.
That run is exploratory and is excluded from matched image evidence.
A later controlled hero-only run remains additional evidence.
The successful four-view comparison uses fresh output paths.
All these attempts remain in the archive.

The baseline visual captures intentionally launched the old uncached binary.
The user saw more than 7 GB during a baseline launch.
That observation does not describe the cached binary.
No sampled cached process footprint exceeded 7 GB.

The clean memory run ran at approximately 15:44:45.65–15:45:28.77 NZDT.
Its footprint snapshot ran at 15:45:14.40 NZDT.
The user's 15:45:44 screenshot followed the game's exit by about 15 seconds.
Its recent graph window can include the clean run.
That graph shows system memory pressure, not one process's allocated GB.
The screenshot alone cannot identify the cause of its smaller plateau.
The archive retains the clock correlation separately from the native measurements.

## Checks and remaining platform limits

All 881 engine tests passed.
The eight added tests cover image identity, sampler independence, cache growth, Pack ownership, failure cleanup, reload, slot reuse, and headless loading.
The native grass harness also exercises deferred upload and real unload validity.
Release host checks passed.
All 18 capture script tests passed.
Metal release builds, Linux GL object builds, and Windows D3D object builds passed strict checks.
Linux and Windows semantic checks also passed.
Native GL and D3D execution was unavailable on this Mac.
Their builds do not establish native performance.
The parent task retains GPU timing, display timing, and final PC acceptance.
Original stutter attribution remains open.

## Reproduction and retained files

Run these commands from the repository root with the pinned Roc compiler on PATH:

```sh
odin test engine -o:speed -vet -strict-style
roc scripts/build.roc -- host --release --spans
roc scripts/build.roc -- game village
scripts/host-check.sh
python3 -m unittest discover -s scripts -p 'test_village*.py'
odin build scripts/texture-sharing-check -o:speed -vet -strict-style -out:/tmp/village-texture-shared-check
/usr/bin/time -l /tmp/village-texture-shared-check examples/village/assets/meshes
odin build engine -build-mode:obj -target:linux_amd64 -o:speed -vet -strict-style -out:/tmp/texture-linux-engine.o
odin build engine -build-mode:obj -target:windows_amd64 -o:speed -vet -strict-style -out:/tmp/texture-windows-engine.obj
```

The archive includes the exact guarded probe scripts and their commands.
Each run records its binary hash, effective environment, exit status, and fresh output directory.
The archive excludes binaries and unchanged source assets.
Their hashes and the existing baseline archives identify those inputs.
The [raw archive](texture-sharing-implementation-2026-11-06.tar.gz) contains 183 files plus the tracked implementation patch and manifest.
The archive uses hard links for byte-identical files.
Archive size: 37,043,800 bytes.
Archive SHA-256: `b8518c0eeacb4dd3e263dc49cb47a0ec08cac0b420490f283e96fd62f67446ce`.
The manifest records each retained file size and SHA-256 digest.
The [maximum callback record](texture-sharing-implementation-2026-11-06/maximum-callback.json) retains the inspected frame and its CPU Spans.
