# Diagnostic baseline evidence

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

## Pending loader prerequisite

Original 2048 PNGs exhausted shared frame memory during texture decoding.
A 1024 diagnostic also exhausted that memory.
The 512 diagnostic renders through the Bridge.
A real-clock launch also exposed several asset loads within one rendered frame.
The diagnostic uses a 0.1-second simulation cadence to avoid that usual startup case.
That cadence does not establish a safe memory lifetime.
The user observed incremental mesh appearance during loading.

The loader prerequisite must bound decode and file scratch lifetimes.
Retained texture and mesh arrays must outlive that scratch.
The follow-up must restore source-resolution textures with `--max-texture-side 0`.
The follow-up must remove reliance on fixed-step staging.
The follow-up must show loading feedback until every required asset is ready.
The follow-up must show the complete scene only after that ready state.

The exact reproducer is `/tmp/rocco-village-memory.md`.
The final source-resolution run, real-clock frame pacing, and human review remain pending.
