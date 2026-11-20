# Village capture prerequisite

Status: implementation requires native operation validation.
Hardware performance and human scene acceptance remain open.

The capture uses the complete village, Group 20, all effects, and full density.
The full route requires 1920 by 1080 physical pixels.
It uses X4 MSAA, 2048 shadow maps, and two cascades.
It preserves the source tour, 75-degree lens, speed, hold, and all six waypoints.

The game waits for observed complete asset readiness.
It then warms the complete scene in the moving Hero view for 1,800 fixed steps.
The first measured tour retains its route-specific visibility and shader costs.
Both full measured tours remain in the primary result.
It runs two 3,600-step source tours and drains 120 steps before normal Quit.
The step rate remains 120 Hz.
The 60 simulation seconds of measured route can take more wall time.
The game preserves wind time and particle state between tour cycles.
It ignores ordinary controls during capture.
Escape aborts the capture.

`--capture-route=operation-v1` is a short operation check.
It uses 120 warmup steps, two 120-step route cycles, and 120 drain steps.
It renders 960 by 540 physical pixels with the full scene and effects.
It does not reach every waypoint or establish performance acceptance.

## Windows package

The artifact contains these adjacent files:

```text
village-ordinary.exe
village-cpu.exe
village-gpu.exe
bench-draws.exe
bench-mixed.exe
assets/
scripts/
tools/PresentMon-2.6.0-x64.exe
tools/python/
Capture-Village.ps1
Capture-BenchSweeps.ps1
Summarize-VillageCapture.ps1
machine.example.json
manifest.json
credits/
```

Every executable shares one adjacent assets directory.
The package includes its Python runtime and required licences.
The PC needs no Odin, Roc, Visual Studio, SDK rebuild, or Python installation.
The manifest records the source commit, build modes, tool versions, sizes, and SHA-256 hashes.
It also freezes source, field, and supplement record counts.
The original source assets remain 93, with 1,436 source records and 22,000 field records.
The supplement has its own count and source manifest hash.
Freeze the accepted visual revision before native final measurement.
The launcher verifies every packaged file before launching the game.

The ordinary executable contains no Spans or D3D timestamp hooks.
The CPU executable records Spans only.
The GPU executable records D3D timestamps and Spans.
Use the separate CPU executable for CPU acceptance.
Its measurements exclude the GPU diagnostic's added commands and polling.

The package pins PresentMon 2.6.0 with SHA-256:
`b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`.
The launcher verifies that digest before PresentMon starts.
It retains dropped display results and missing values.

Build the package on native Windows with the pinned tools and prepared native libraries:

```powershell
python scripts/package_village_capture.py build/village-pc
```

Run the package checks on the reference PC before sharing the package:

```powershell
cd build/village-pc
powershell -NoProfile -File .\Capture-Village.ps1 -Mode cpu -Runs 1 -Operation -Output C:\RoccoEvidence\package
powershell -NoProfile -File .\Capture-Village.ps1 -Mode gpu -Runs 1 -Operation -Output C:\RoccoEvidence\package
powershell -NoProfile -File .\Capture-Village.ps1 -Mode pacing -Runs 1 -Operation -Output C:\RoccoEvidence\package
powershell -NoProfile -File .\Capture-BenchSweeps.ps1 -Operation -Output C:\RoccoEvidence\package-bench
```

Keep the operation results with the package.
An operation check does not establish a reference-machine performance result.

## Reference PC procedure

Confirm the i7-9700F, RTX 2070 SUPER, 16 GB RAM, and Windows 11.
Record the actual display refresh rate and active display mode.
Do not require a 60 Hz monitor or change the display mode silently.
Record the driver, HAGS, power source, power mode, background work, and thermal restrictions.
Copy `machine.example.json` to `machine.json`.
Replace its prompts with the verified machine details.
Keep the same recorded conditions for repeated runs.
If background conditions change, collect fresh paired samples before making a comparison.

Run these commands from the extracted package:

```powershell
powershell -NoProfile -File .\Capture-Village.ps1 -Mode cpu -Runs 3 -Machine .\machine.json -Output C:\RoccoEvidence\village
powershell -NoProfile -File .\Capture-Village.ps1 -Mode gpu -Runs 3 -Machine .\machine.json -Output C:\RoccoEvidence\village
powershell -NoProfile -File .\Capture-Village.ps1 -Mode pacing -Runs 3 -Machine .\machine.json -Output C:\RoccoEvidence\village
powershell -NoProfile -File .\Capture-BenchSweeps.ps1 -Machine .\machine.json -Output C:\RoccoEvidence\sweeps
powershell -NoProfile -File .\Summarize-VillageCapture.ps1 -InputDirectory C:\RoccoEvidence\village
```

Each run creates a new directory and refuses existing outputs.
The launcher clears unrelated capture settings.
It disables Bridge, Lockstep, Headless, the debug camera, asset overrides, and allocation reporting.
It records native machine observations and the explicit environment.
It preserves command lines, PIDs, exit codes, logs, boundaries, raw samples, and summaries.
A failed run retains its failure record.

PresentMon filters the actual ordinary game's PID.
The launcher starts it before the readiness-relative warmup ends.
It captures raw margins around the measured route and validates route coverage.
It uses `--v2_metrics --qpc_time` and records actual CSV headers.
If PresentMon reports a permission error, retain its log and use its documented permission procedure.
Do not omit that run or replace its missing results with zero durations.

The sweep uses all sizes from 64 through 16,384 in powers of two.
Each Draw and mixed size runs five processes in one recorded shuffled order.
Each process retains 120 warmup frames and 2,000 measured frames.
The sweep preserves seed zero, one-second cooldowns, and the existing windowed Lockstep workload.
These sweeps do not replace village real-clock evidence.
Retain their raw samples for the existing reference analysis and budget scaling.
Do not update the benchmark headline from hosted or Mac results.

## Boundary and exclusion contract

The private `ROCCO_CAPTURE_CSV` sink requires Real_Clock and a positive limit of at most 30,000 frames.
It rejects Bridge, Headless, relative paths, and existing output files.
It accepts the debug camera only when `ROCCO_CAPTURE_DEBUG_CAMERA=1` is set.
The final route launcher clears that setting.
Without the setting, ordinary launches allocate no sink and take no diagnostic clocks.
They serialize no diagnostic commands and write no capture files.
Ordinary Tell behavior and the public ABI remain unchanged.

The sink observes existing command serialization before Roc frees command strings.
The game records its actual vegetation, casting, lighting, and effect switches at readiness.
The summary rejects reduced density or disabled required effects.
It reserves frame rows, command records, command buffers, and optional labels before rendering.
It never grows these buffers during capture.
It fails on buffer overflow instead of dropping markers.
It writes evidence at normal shutdown.
A failed write or minimized window fails the capture.
The frame limit is a safety bound.
A frame-limit exit without the complete marker fails validation.

The boundary CSV records actual render IDs and actual fixed-step ranges.
The CSV also records previous scene steps, interpolation alpha, physical size, DPI, camera, and native clocks.
Final metadata separates source, field, supplement, and other Draws.
Source IDs range from 100 through 11435.
Field IDs range from 100000 through 121999.
Supplement IDs range from 200000 through 200159.
The summary checks the supplement against the frozen source manifest.
It never adds supplements to source or field counts.
`start_tick` comes from callback entry, before polling or GPU diagnostic work.
Commit entry and return ticks bracket submission separately.
Windows uses raw QueryPerformanceCounter ticks and records its frequency.
Other systems use native monotonic nanoseconds.

The host preserves zero-step renders and frames with several fixed steps.
A phase marker belongs to its producing fixed step and render frame.
A render can interpolate a warmup scene and a measured scene.
The summary includes every frame with measured work or measured interpolation endpoints.
It retains entire mixed frames and reports them separately.
It counts measured fixed steps through the exact marker interval, with each end marker exclusive.
The following transition step never adds a measured step to the preceding route.
It does not subtract guessed warmup work or discard boundary stalls.
It preserves original callback deltas and the clock's 0.25-second clamp amounts.
Clamped simulation time never replaces native wall time.

CPU Spans and D3D rows join boundary rows by the same engine frame ID.
CPU work sums the engine Spans and reports Commit separately.
D3D frame intervals end before `sg.commit` and exclude presentation and display wait.
Repeated pass indices remain in the raw data.
The summary checks required Scene_Depth, Selection, HDR outline, LDR colour, bloom, shadow, Main, Post, and Blit passes.

D3D summaries preserve Disjoint, Invalid, Overflow, Missing_Busy, Missing_Shutdown, Query_Error, and absent-frame counts.
They preserve empty numeric fields for invalid samples.
They never replace missing samples with zero-cost frames.
Review every exclusion because missing slow samples can bias valid-only percentiles.

PresentMon CPUStartQPC is a frame metric, not an engine frame ID.
The summary selects a native QPC route time window and preserves the surrounding raw rows.
It makes no row-position join or exact per-frame association claim.
It reports missing display values, swapchains, FrameTime, GPUBusy, GPUWait, and GPUTime separately.
D3D elapsed timestamps are not PresentMon GPU activity.
Record HAGS because it can affect PresentMon GPU timing accuracy.
Do not change HAGS silently.

The summary uses nearest-rank p50, p95, and p99 with sample counts.
It reports each run independently.
Do not average run percentiles into a replacement percentile.
Require p95 CPU and GPU frame work each within 16.67 ms on both reference machines.
Report p99 spikes and inspect actual display pacing separately.
Callback cadence alone does not prove displayed 60 FPS.

## Mac capture

Use separate ordinary and Spans release binaries from the same frozen source.
Preserve their hashes and all effective settings.
Pass `--retina-1080` only on a verified 2x display.
The sink checks actual dimensions through the summary.

These commands require native validation before acceptance:

```sh
python3 scripts/village_capture.py --mode cpu --binary /tmp/village-cpu.bin --retina-1080 --machine /tmp/machine.json --output /tmp/village-mac
python3 scripts/village_capture.py --mode pacing --binary /tmp/village-ordinary.bin --retina-1080 --machine /tmp/machine.json --output /tmp/village-mac
python3 scripts/village_capture.py --mode metal-gpu --binary /tmp/village-ordinary.bin --retina-1080 --machine /tmp/machine.json --output /tmp/village-mac
```

The Metal GPU mode enables optional native encoder labels through `ROCCO_CAPTURE_LABELS=1`.
Each label contains the engine frame, actual pass index, and original pass kind.
The opt-in Metal diagnostic sets native labels because release Sokol archives omit them.
The helper allocates and releases one NSString for each pass.
These native allocations add diagnostic CPU cost.
Only the sink byte buffers have fixed capacity.
CPU and ordinary pacing captures keep native labels disabled.
Use the separate CPU capture for CPU acceptance.
The exporter never assumes that Metal trace frame IDs equal engine frame IDs.
It reports active-interval unions and elapsed first-start to last-end intervals separately.
It preserves missing frames, missing passes, and unlabelled process intervals.
The exporter fails operation validation when labels or route intervals are incomplete.
The actual exported schema and label association still need native proof.
A failed trace establishes no GPU performance result.

The Mac pacing mode records callback cadence without Spans or GPU timestamp hooks.
Use a separate native presentation trace to establish actual display cadence.
If display timing is unavailable, leave display pacing acceptance open.
The old Lockstep Metal baseline does not satisfy this requirement.

Keep screenshots, texture readback, Bridge steps, and diagnostic GPU waits outside measured runs.
Keep raw traces and failed captures beside the final evidence.
Human scene approval and the user's final PC run remain separate gates.

## Debug camera stutter diagnostic

Prepare native libraries and build the release host with Spans:

```sh
sh scripts/macos/build-sokol.sh
roc scripts/build.roc inputs --release
roc scripts/build.roc host --release --spans
cd examples/village
roc build --no-cache --opt=speed --target=arm64mac --output=./village-debug.bin main.roc
```

Choose new absolute paths for each run.
Move the debug camera after the village appears.
The frame limit ends the run if the game does not quit first.
Run the built game from `examples/village`:

```sh
ROCCO_DEBUG_CAMERA=1 ROCCO_CAPTURE_DEBUG_CAMERA=1 \
ROCCO_CAPTURE_CSV=/tmp/village-debug-boundaries.csv \
ROCCO_SPANS_CSV=/tmp/village-debug-cpu.csv \
ROCCO_EXIT_AFTER_FRAMES=3600 \
./village-debug.bin
cd ../..
python3 scripts/village_debug_camera_summary.py /tmp/village-debug-boundaries.csv \
  --cpu /tmp/village-debug-cpu.csv --out /tmp/village-debug-summary.json
```

The summary starts one second after the last recorded Load command.
It groups callback intervals by actual debug camera movement.
It retains the 20 slowest frames with their camera positions and CPU commit times.
Use `--first-frame`, `--last-frame`, or `--settle-steps` to inspect a narrower interval.
The diagnostic adds CPU clocks and Spans.
Its callback intervals do not establish displayed frame cadence or GPU work.
The summary separates callback entry through commit return from the following callback gap.
New captures record `begin_pass_ticks` around each renderer pass entry.
These durations cover the pass entries excluded from the Render_Submit Span.
The `drawable_ticks` field measures swapchain acquisition inside Main pass entry.
Drawable time is a subset of pass-entry time; do not add them together.
These wall-clock durations can include driver work, waits, and thread scheduling.
They do not measure GPU execution or displayed frame cadence.
Old captures omit these measurements; the summary does not replace them with zero.

Set `ROCCO_DEBUG_CAMERA_SWEEP=1` for a repeatable camera stress run.
The sweep turns 180 degrees each second and reverses direction each second.
It changes pitch and moves 12 world units along each axis before reversing.
The sweep replaces human camera input during the run.
Keep sweep results separate from human input results.
