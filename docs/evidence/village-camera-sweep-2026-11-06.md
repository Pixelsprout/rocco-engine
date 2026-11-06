# Village debug camera sweep, 2026-11-06

The wide sweep moved the debug camera across the village while it turned 180 degrees each second.
The run reached its 3,600-frame limit with no capture error.
This diagnostic does not establish displayed frame cadence or a stutter cause.

## Build and controls

Source commit `4b48795` adds `ROCCO_DEBUG_CAMERA_SWEEP=1`.
The opt-in sweep replaces human camera input inside `camera_fly`.
It keeps the normal camera view and render path.
The sweep changes pitch and follows four three-second world-axis legs.
The game used 1920 by 1080 physical pixels, X4 MSAA, 2048 shadow maps, and two cascades.
The final capture metadata reports 1,436 source Draws and 21,993 field Draws.

The wide binary SHA-256 is `02191ca0a6783be6cdadc22bebd1fe7efae9fa90db92951f9ce568786c03e599`.
The Spans host SHA-256 is `10d183c458b03956aea4d97f9d401e12ed32579f2fce63ef83a0e66c55324b4d`.
The test used pinned Roc and Odin with a release Spans host.
The release host build passed strict style checks.
The engine test run passed 873 tests before the final translation change.

The actual wide run used this command from `examples/village`:

```sh
ROCCO_DEBUG_CAMERA=1 ROCCO_DEBUG_CAMERA_SWEEP=1 \
ROCCO_CAPTURE_DEBUG_CAMERA=1 \
ROCCO_CAPTURE_CSV=/tmp/rocco-village-wide-sweep-20261106-boundaries.csv \
ROCCO_SPANS_CSV=/tmp/rocco-village-wide-sweep-20261106-cpu.csv \
ROCCO_EXIT_AFTER_FRAMES=3600 \
/tmp/RoccoVillageWideSweep.app/Contents/MacOS/village-wide-sweep
```

The temporary app bundle linked `village-wide-sweep.bin` and the adjacent village assets.
The app bundle did not change the binary or the assets.
The same command can launch the binary directly with `ROCCO_ASSETS` set to the village assets directory.

## Measured motion and timing

The summary excludes frames before step 216, which is 120 steps after the last Load at step 96.
All 3,565 settled frames in the wide run moved the camera.
Recorded yaw ranged from 0.04 to 179.96 degrees.
Recorded pitch ranged from -20.05 to 20.05 degrees.
The eye moved across x=1.90 to 14.00 and z=-7.01 to 5.04.

| Run | Settled moving frames | Callback p95 / p99 / max, ms | CPU p95 / p99 / max, ms |
| --- | ---: | ---: | ---: |
| CUA keyboard translation | 1,032 of 3,541 | 16.934 / 17.331 / 27.609 | 10.835 / 11.302 / 12.402 |
| Short sweep | 3,557 of 3,557 | 17.061 / 23.162 / 70.583 | 15.383 / 18.817 / 31.675 |
| Wide sweep | 3,565 of 3,565 | 17.006 / 21.455 / 66.741 | 15.324 / 18.383 / 39.622 |

The CUA keyboard run moved the camera but did not turn it.
CUA mouse drags did not change the recorded camera direction.
The short sweep covered about five by three world units.
The wide sweep covered about twelve units on each world axis.
The runs used different motion paths and uncontrolled background load.
Do not treat their percentiles as a controlled comparison.

The wide run had 14 callback intervals of at least 30 ms.
Three occurred within ten degrees of a yaw reversal; eleven occurred at other angles.
Eight occurred in frames 1 to 719, four in frames 720 to 1,439, and two in frames 2,160 to 2,879.
The other 720-frame blocks had no interval of at least 30 ms.
The slow intervals occurred at several camera positions and angles.

Frame 91 took 39.915 ms between callbacks and 39.622 ms of measured CPU work.
Its Step span took 27.210 ms.
Frame 661 took 58.266 ms between callbacks and 11.924 ms of measured CPU work.
Frame 1336 took 51.109 ms between callbacks and 12.009 ms of measured CPU work.
CPU Spans do not explain the full callback gaps in frames 661 and 1336.
The capture has no GPU or display timing for those frames.

Spotlight indexing used substantial CPU before the runs.
The test did not stop that process or measure background CPU use during every run.
The memory CLI showed a minimum of 16% free memory during the wide run.
It did not report a memory warning state.

## Retained files

The [raw evidence archive](village-camera-sweep-2026-11-06.tar.gz) contains 19 files.
It contains every boundary CSV, command record, metadata record, and CPU CSV from four launches.
It also contains the summaries for the three complete captures.
The first launch could not load assets from its temporary app path.
It ended after 1,026 frames and establishes no scene timing result.
The archive SHA-256 is `3d873761aacc37d38db6c04afe7b05f4d79c0064c5f42675ab04309686a2669c`.

Human input, native GPU timing, and display presentation still need separate checks.
