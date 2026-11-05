# Source-resolution baseline evidence

Date: 2026-11-05.
Status: loader prerequisite verified; human composition review remains pending.

The prepared GLBs contain the original PNG payloads.
The texture cap is zero.
The 33 GLBs occupy 384,288,532 bytes.
Two conversions from the checksum-verified archive produced identical manifests and layouts.
The validator checks every embedded PNG against the original texture hashes.
The archive checksum remains `2f766abd37bc15c19053eaa99f3eec49790724315f7e486f5e08a1bc5c8eff2d`.

A direct source comparison checked all 154 placements against cumulative `world.tscn` transforms.
The maximum reconstructed matrix error was `4.996e-16`, at `Trees/CommonTree_57`.
The engine still renders 155 Draws, including the ground plane.

## Loading and memory

The village shows loading progress before it shows geometry.
All 33 assets must resolve to nonzero ids before the complete scene appears.
A failed asset keeps the scene hidden and shows an error.
The loading screen and complete scene were captured at 1920 by 1080 physical pixels.

The loader gives each file load, GLB parse, and PNG decode a separate growing arena.
Each PNG arena survives through the copy into retained texture pixels.
Each arena ends before the next operation at its boundary.
Retained arrays use the caller's allocator, even when that allocator equals the caller's temporary allocator.
File errors copy their reason into the caller's temporary allocator.
The frame arena remains 64 MB.
No simulation delay establishes loader memory safety.

The regression failed before the change.
Eight small two-texture loads retained 31,825,672 bytes in frame scratch.
The fixed loader retains zero scratch bytes there after each successful load.
Tests cover two loads within one frame, repeated unloads, retained allocator aliases, texture errors, and truncated PNGs.

A temporary probe sampled arena usage before each nested arena ended.
The arenas do not free individual allocations, so their final usage records their peak usage.
The peak simultaneous scratch usage was 122,970,822 bytes, or 117.27 MiB.
That total includes the active file, parser, and PNG arenas, with allocation padding.
It excludes retained assets, virtual memory metadata, and unused reservation.
The largest PNG arena used 99,373,400 bytes.
The largest parser arena used 1,785,080 bytes.
The largest file arena used 23,558,934 bytes.
The probe was removed from the final build.

The probed real-clock launch loaded 12, 12, and 9 assets across three rendered frames.
The last load completed in CSV frame 4.
Both the probed launch and final build completed 720 frames without loader errors.
This verifies several loads within one frame at source resolution.
The final launch completed its loading work in CSV frame 5.
The warm CPU sample excludes that frame and the next 120 frames.
The remaining 595 samples measured median 0.663 ms, p95 0.756 ms, and p99 0.788 ms of CPU work.
CPU Spans exclude GPU duration and display wait.
They do not establish real-clock frame pacing or final-scene performance acceptance.
The synchronous startup can pause rendering while each frame loads its assets.

## Merged material metadata check

The merged loader preserves named slots, raw `COLOR_0`, and source material indices after parser scratch ends.
Regression tests cover repeated loads, unload cleanup, and a caller allocator that equals the caller's temporary allocator.
The raw colour stream remains separate from the factored `Vertex.color` stream.
Both engine builds passed all 778 tests, including the Spans build.
The village passed all 163 Roc tests and the prepared-asset validator.
The release Spans host and village build passed.

The merged Bridge run showed loading feedback before asset loading.
At fixed step 33, the complete scene contained 155 Draws with nonzero mesh ids.
The loading screen and source hero image used 1920 by 1080 physical pixels.
The agent inspected both images.
The host exited successfully without loader errors.
The artifacts are in `/tmp/village-merged-loader/`.

## Source-resolution Metal baseline

The trace was captured on 2026-11-05 from `/tmp/rocco-loader-scratch` at commit `c71088d`.
The binary SHA-256 was `477bdb456a2e0659ee45c15f22e73be4e673c615bcee321a542cf37ddf35df3b`.
The host used release Odin optimization with Spans.
The Roc game used development compilation.
The machine was the Apple M5 described below.
The machine used AC power with Low Power Mode off.
Other development work shared the machine.

The scene used original PNG payloads at 1920 by 1080 physical pixels.
The renderer used 4-sample MSAA and two 2048 shadow cascades.
The capture used the source baseline's hero camera and windowed Lockstep mode.
This capture establishes initial GPU evidence for the source baseline.
It does not establish real-clock frame pacing, final-scene acceptance, or human composition approval.

The Metal trace recorded 720 GPU frames for one village process.
The CPU CSV also recorded frames 1 through 720.
The last asset-load command occurred in frame 33.
The fixture independently established complete-scene readiness at step 33.
The summary excludes frames 1 through 153: loading followed by 120 warmup frames.
The measured sample contains frames 154 through 720, or 567 frames.

| Work | Median | p95 | p99 | Maximum |
| --- | --- | --- | --- | --- |
| GPU active time | 4.817 ms | 5.934 ms | 6.192 ms | 6.751 ms |
| CPU spans during profiling | 0.678 ms | 2.827 ms | 3.687 ms | 4.316 ms |

GPU time is the union of Active Metal intervals for `village.bin` within each GPU frame.
The calculation excludes other processes and counts overlapping GPU intervals once.
Percentiles use the nearest-rank method.
CPU spans sum the recorded work columns and exclude the instrumentation-cost estimate.
The unprofiled real-clock CPU result remains separate, with p95 0.756 ms.

Artifacts:

- `/tmp/village-source-baseline.trace`
- `/tmp/village-source-gpu-intervals.xml`
- `/tmp/village-source-gpu.json`
- `/tmp/village-source-gpu.csv`
- `/tmp/village-source-gpu-cpu.csv`
- `/tmp/village-source-gpu-cpu.json`
- `/tmp/rocco-metal-gpu-summary.py`

Capture from `examples/village`:

```sh
xcrun xctrace record --template 'Metal System Trace' --time-limit 30s \
  --output /tmp/village-source-baseline.trace --env ROCCO_LOCKSTEP=1 \
  --env ROCCO_EXIT_AFTER_FRAMES=720 \
  --env ROCCO_SPANS_CSV=/tmp/village-source-gpu-cpu.csv --launch -- ./village.bin
xcrun xctrace export --input /tmp/village-source-baseline.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
  --output /tmp/village-source-gpu-intervals.xml
python3 /tmp/rocco-metal-gpu-summary.py /tmp/village-source-gpu-intervals.xml \
  --discard 153 --out /tmp/village-source-gpu.json
```

## Captures and replay

The fixture checked both building collisions, centre-ray selection, mouse look, and free camera movement.
The fixture reached the complete scene at fixed step 33.
It checked loading feedback before that step.
The first complete scene contained all 155 Draws.
No partial village appeared during loading.

The agent inspected the loading screen, hero view, and square view.
The textures and foliage alpha render coherently at source resolution.
The source ground and sky still use the plain baseline colours.
Human composition approval remains pending.

Evidence remains outside the repository:

- `/tmp/village-source-evidence/loading.png`
- `/tmp/village-source-evidence/hero.png`
- `/tmp/village-source-evidence/square.png`
- `/tmp/village-source-evidence/walk.png`
- `/tmp/village-source-evidence/route.mp4`
- `/tmp/village-source-evidence/observations.json`
- `/tmp/village-source-replay/observations.json`
- `/tmp/village-source-scratch.json`
- `/tmp/village-source-scratch-probe.patch`
- `/tmp/village-source-realclock-probe.log`
- `/tmp/village-source-realclock-probe.csv`
- `/tmp/village-source-realclock.log`
- `/tmp/village-source-realclock.csv`
- `/tmp/village-source-realclock-warm.json`

Both source-resolution route runs produced `89c2afa9417c08f57e3eb2963baf3bb7e2e1f885b7e0f48e050b37be0602a4dc`.
That checksum also matches the earlier diagnostic route.
The movie contains 150 frames at five frames per second.
Each frame advances 24 fixed simulation steps.

## Checks

The release host built with CPU Spans, strict Odin style, and vet checks.
The game used the build script's default development compilation.
The Roc checks passed 163 tests.
The prepared-asset validator passed.
Both merged engine suites passed 778 tests, including the Spans build.
The textured mask and skinned animation examples also built and rendered.
The final checks used the Apple M5 machine described below.
Other development work shared the machine during these checks.

The source-resolution GPU measurement above starts after complete-scene readiness and 120 warmup frames.
The earlier GPU measurements below used diagnostic textures.

# Earlier diagnostic evidence

Date: 2026-11-05.
Status: diagnostic only; source-resolution assets and human composition review remain pending.

The baseline contains 155 Draws, including the source ground plane.
All 33 prepared meshes resolved through the Bridge.
The fixture checked collisions against HouseA and HouseB.
The fixture checked centre-ray selection, mouse look, and free camera movement.
The 133 Roc tests and the prepared-asset validator passed.

## Images and movement

The Bridge confirmed 1920 by 1080 physical pixels for these images:

- `/tmp/village-baseline-evidence/hero.png`
- `/tmp/village-baseline-evidence/square.png`
- `/tmp/village-baseline-evidence/walk.png`

The fixed orbit image clears the foreground tree after a camera correction.
The first observations file retains the earlier orbit pose.
The route poses remain unchanged by that correction.

The moving route is `/tmp/village-baseline-evidence/route.mp4`.
It contains 150 frames at five frames per second.
Each frame advances 24 fixed simulation steps.
The route uses the source tour points, hold, and speed.
The route checksum is `89c2afa9417c08f57e3eb2963baf3bb7e2e1f885b7e0f48e050b37be0602a4dc`.
The camera samples are in `/tmp/village-baseline-evidence/observations.json`.

The worker inspected both fixed images.
Textures and foliage alpha render coherently at diagnostic resolution.
The ground and sky use plain baseline colours.
Human composition approval remains pending.

## Initial performance data

The machine was an Apple M5, Mac17,2, with 16 GB RAM and macOS 26.5.1.
The machine used AC power with Low Power Mode off.
Other development work shared the machine.
The host used Odin release optimization with CPU Spans.
The Roc game used the build script's default development compilation.
The image used 1920 by 1080 physical pixels, 4-sample MSAA, and two 2048 shadow cascades.
The prepared texture cap was 512 pixels.

A Metal System Trace recorded 600 windowed Lockstep frames.
The summary discarded the first 120 frames.
The trace measured 480 warm GPU frames.
The GPU measurement takes the union of active intervals for `village.bin` within each GPU frame.

| Measured work | Median | p95 | p99 |
| --- | --- | --- | --- |
| GPU frame | 3.811 ms | 4.507 ms | 4.978 ms |
| CPU spans during the trace | 0.668 ms | 0.710 ms | 0.727 ms |

The CPU spans measure work on the CPU.
They do not measure GPU duration or real-clock frame pacing.
A separate real-clock diagnostic launch completed 720 frames after the cadence workaround.
Its summary discards 480 frames and records 240 warm CPU samples.
The summary is `/tmp/village-baseline-evidence/cpu-realclock.json`.
The GPU trace measures the diagnostic scene before the startup cadence workaround.
These measurements do not establish source-resolution or final-scene acceptance.

Raw and summary artifacts:

- `/tmp/village-baseline.trace`
- `/tmp/village-gpu-intervals.xml`
- `/tmp/village-gpu.csv`
- `/tmp/village-baseline-evidence/gpu.json`
- `/tmp/village-baseline-evidence/cpu-instrumented.json`
- `/tmp/village-machine.json`

Repeat the GPU capture from `examples/village` with a release Spans host:

```sh
xcrun xctrace record --template 'Metal System Trace' --time-limit 30s \
  --output /tmp/village.trace --env ROCCO_LOCKSTEP=1 \
  --env ROCCO_EXIT_AFTER_FRAMES=600 --env ROCCO_SPANS_CSV=/tmp/village.csv \
  --launch -- ./village.bin
xcrun xctrace export --input /tmp/village.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]'
```

With diagnostic cadence enabled, discard at least 480 frames before measuring warm performance.
Use more frames when the loading state changes.

## Diagnostic failure history

Original 2048 PNGs exhausted shared frame memory during decoding.
A 1024 diagnostic also exhausted that memory.
A 512 diagnostic rendered through the Bridge.
Its real-clock launch exposed several asset loads within one frame.
The diagnostic then added a 0.1-second simulation delay.
That delay did not establish memory safety.
The source-resolution checks above replace that workaround.
The original reproducer remains at `/tmp/rocco-village-memory.md`.
