# D3D11 GPU timestamps

This diagnostic records GPU timestamp intervals for frames and actual render passes.
It adds no game API.
Ordinary builds compile out the hooks, query state, query calls, and environment reads.
The compile flag enables the diagnostic only on Windows.
An environment variable alone cannot enable it.

## Build and capture

Use the repository's pinned Odin and Roc versions.
Build the native Sokol and miniaudio libraries first.
Use a separate worktree for this instrumented host.
The following PowerShell commands build a release host with both GPU timestamps and CPU Spans.
Run these commands from the repository root.

```powershell
roc scripts/build.roc -- inputs --release
Remove-Item platform/targets/x64win/host.lib -ErrorAction SilentlyContinue
odin build engine -build-mode:static -out:platform/targets/x64win/host.lib -no-crt -no-thread-local -o:speed -define:ROCCO_D3D_GPU_TIMING=true -define:ROCCO_SPANS=true -vet -strict-style
roc scripts/build.roc -- game village
$env:ROCCO_D3D_GPU_CSV = "$PWD/build/village-gpu-run1.csv"
$env:ROCCO_SPANS_CSV = "$PWD/build/village-cpu-run1.csv"
$env:ROCCO_EXIT_AFTER_FRAMES = '10000'
$env:ROCCO_SEED = '0'
$env:ROCCO_LOCKSTEP = '0'
Push-Location examples/village
.\village.exe
Pop-Location
```

The instrumented window requires a CSV path and a positive frame limit.
The host reserves its rows before rendering.
The host writes the CSV at normal shutdown.
A failed CSV write fails the run.
A forced process termination can lose the CSV.
Headless runs produce no GPU samples.

Use unique filenames for each run.
Keep the raw CSV and host log.
Select an explicit measured frame range after warmup.
This example summarises frames 6001 through 9600:

```powershell
python scripts/gpu_timing_summary.py build/village-gpu-run1.csv --first-frame 6001 --last-frame 9600 --out build/village-gpu-run1.json
```

The example range does not define a camera route.
Record the route boundaries for the actual run.
Use the same accepted camera route for each comparison.
Do not take screenshots or perform texture readback during the measured range.
Those operations can wait for the GPU.
Bridge captures remain useful for deterministic image checks.
Bridge pauses and Lockstep runs do not establish real-clock pacing.

To restore the ordinary host, clear the capture variables and rebuild:

```powershell
Remove-Item Env:ROCCO_D3D_GPU_CSV -ErrorAction SilentlyContinue
Remove-Item Env:ROCCO_SPANS_CSV -ErrorAction SilentlyContinue
Remove-Item Env:ROCCO_EXIT_AFTER_FRAMES -ErrorAction SilentlyContinue
roc scripts/build.roc -- host --release
roc scripts/build.roc -- inputs --release
roc scripts/build.roc -- game village
```

## Output contract

Each rendered frame has one `scope=frame` row.
Each recorded pass has one `scope=pass` row.
Rows stay in frame order when queries finish out of order.
The frame number starts at one and matches the CPU Spans frame number.

| Column | Meaning |
| --- | --- |
| `frame` | Engine frame number. |
| `scope` | `frame` or `pass`. |
| `pass_index` | Zero-based actual pass order within the frame; `-1` for the frame. |
| `pass` | Pass kind; empty for the frame. |
| `status` | Validity or exclusion reason for the complete frame. |
| `frequency_hz` | Disjoint query frequency, only for valid samples. |
| `start_tick`, `end_tick` | GPU counter values, only for valid samples. |
| `gpu_ms` | `(end_tick - start_tick) * 1000 / frequency_hz`, only for valid samples. |

Invalid and missing rows have four empty numeric fields.
They never contain zero-duration substitutes.
An absent pass has no row.
A pass with valid equal timestamps can have zero duration at the device's counter resolution.

The frame interval starts immediately before the first actual pass begins.
It ends after the final pass and before `sg.commit`.
It includes commands between passes, attachment clears, resolves, and the final swapchain copy.
It excludes presentation, display wait, and screenshot readback after the frame.

Each pass pair surrounds its actual `sg.begin_pass` and `sg.end_pass` calls.
The end timestamp follows pass resolves.
These are GPU timestamps, not estimates from CPU submit time.

| Pass kind | Commands inside the pair |
| --- | --- |
| `Shadow` | One shadow cascade. Repeated rows follow cascade submission order. |
| `Main` | Opaque and blended geometry, sky, particles, and main attachment operations. |
| `Scene_Depth` | The optional scene coverage and nearest-depth pass. |
| `Selection` | The optional selected geometry coverage and nearest-depth pass. |
| `Game_Post_HDR` | One enabled game effect before bloom. |
| `Game_Post_LDR` | One enabled game effect after tone mapping. |
| `Bloom_Prefilter`, `Bloom_Down`, `Bloom_Up` | One actual bloom step; repeated rows follow mip submission order. |
| `Post` | Tone mapping and UI when uninterrupted. After LDR effects, another Post pass composites and draws UI. |
| `Blit` | The final colour copy into the swapchain. |
| `Unlabelled` | A pass without a recognised label; inspect the hook before attributing its cost. |

The raw pass index distinguishes repeated passes.
A game effect's pass index follows actual submission order after skipped effects.
The CSV does not identify assets, Draws, or shader names.
The summary adds same-kind pass intervals within each valid frame.
It excludes frames without that pass kind from that pass distribution.
It reports each distribution's sample count.
It uses nearest-rank p50, p95, and p99.
The frame interval can exceed the sum of pass intervals.

## Query ownership and exclusions

The diagnostic preallocates eight query slots.
Each slot has one disjoint query and 130 timestamp queries.
Each frame can record 64 passes.
This covers 32 game effects, four shadow cascades, scene depth, Selection, eleven bloom steps, Post passes, and the copy.

The host polls older slots once before starting the next frame.
Every read uses `D3D11_ASYNC_GETDATA_DONOTFLUSH`.
The host never polls the current measured frame.
The host never waits, spins for readiness, or flushes for timing.
Normal application presentation submits the work.

A pending slot keeps its queries until all issued results are ready.
The host skips a new sample when all slots remain owned.
It does not overwrite pending queries.
Shutdown polls once without flushing, records remaining missing samples, and releases every query.
Query creation failure releases all queries already created.

| Status | Treatment |
| --- | --- |
| `Valid` | Include in the distribution. |
| `Disjoint` | Exclude the complete frame and all its passes. |
| `Invalid` | Exclude zero frequency, reversed timestamps, invalid pass bounds, or a frame without a pass. |
| `Overflow` | Exclude the complete frame when it exceeds 64 passes. |
| `Missing_Busy` | Exclude the frame because all eight query slots remain owned. |
| `Missing_Shutdown` | Exclude a pending frame whose queries remain unavailable at shutdown. |
| `Query_Error` | Exclude an API failure. Stop issuing new queries and retain failed slots until cleanup. |
| `Pending` | Internal state only; a completed CSV must not contain this status. |

The summary counts every excluded frame and every absent frame in the selected range.
Keep these counts beside all percentiles.
Missing slow frames can bias the remaining distribution.
Review any exclusion in the accepted route before final acceptance.
A small p95 with unresolved missing samples cannot certify the frame budget.

## Native verification

Run the focused native fixture on Windows:

```powershell
odin test engine -debug -vet -strict-style -define:ROCCO_D3D_GPU_TIMING=true
python scripts/gpu_timing_check.py
```

The tests inject readiness, disjoint, and query-error results at the COM boundary.
They verify bounded slots, pass overflow, missing rows, and current-frame exclusion.
The fixture uses the production hooks and native Sokol D3D11 device.
It checks ready timestamp pairs, actual pass timestamps, overflow reporting, complete cleanup, and repeated cleanup.
It preserves `gpu.csv`, `native.log`, and `evidence.json` in `build/gpu-timing-check`.
Windows CI uploads that directory as `gpu-timing-d3d11`.
Cross-compilation checks types and declarations only.
Native CI verifies diagnostic operation, including WARP fallback.
CI does not establish reference-PC performance.

## Reference-PC acceptance

The complete village and its accepted route remain separate prerequisites.
This diagnostic does not complete shader authoring proof, village integration, or hardware acceptance.

1. Confirm the i7-9700F, RTX 2070 SUPER, 16 GB RAM, Windows 11, and 60 Hz display.
2. Confirm 1920 by 1080 physical rendering dimensions before measurement.
3. Record the commit, binary hash, driver, power state, Windows GPU scheduling setting, and effective quality settings.
4. Record warmup, route boundaries, frame range, instrumentation, and all sample counts.
5. Repeat the accepted route in separate warm runs with unique output filenames.
6. Preserve raw GPU CSV files and summary JSON files.
7. Record CPU work in a separate release Spans run without the GPU diagnostic.
8. Record real-clock pacing in a separate ordinary release run with PresentMon.
9. Report p50, p95, p99, exclusion counts, dropped frames, and pass totals for each run.
10. Investigate exclusions and p99 spikes before accepting a result.

The GPU flag adds timestamp commands and asynchronous polling overhead.
Combined Spans output remains CPU work with that diagnostic enabled.
Use the separate Spans-only run for CPU acceptance.
Do not add CPU durations to GPU intervals.

GPU timestamps measure elapsed GPU-counter intervals.
Those intervals can include idle gaps caused by CPU submission or scheduling.
They are not PresentMon `GPUBusy` or `GPUTime`.
PresentMon pacing and display results describe a separate measurement.
Keep PresentMon missing values and dropped frames in the raw evidence.
Record hardware-accelerated GPU scheduling because it can reduce PresentMon GPU timing accuracy.
Do not silently change that setting.

Use the pinned PresentMon 2.6.0 console after the same warmup.
Verify SHA-256 `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af` for the downloaded executable.
Replace `GAME_PID` with the actual ordinary release process ID:

```powershell
.\PresentMon-2.6.0-x64.exe --process_id GAME_PID --v2_metrics --timed 60 --terminate_after_timed --output_file village-presentmon-run1.csv --no_console_stats
```

The acceptance contract requires warm-run p95 CPU and GPU frame work within 16.67 ms each.
It also requires separate real-clock pacing review.
Run all configured Draw and mixed sweep sizes before changing the reference headline.

Sources: [D3D11 GetData](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11devicecontext-getdata),
[DONOTFLUSH](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ne-d3d11-d3d11_async_getdata_flag),
[timestamp validity](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/ns-d3d11-d3d11_query_data_timestamp_disjoint),
[PresentMon 2.6.0](https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0),
[PresentMon console options](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md),
[PresentMon scheduling limits](https://github.com/GameTechDev/PresentMon#tracking-gpu-work-with-hardware-accelerated-gpu-scheduling-enabled),
and [the village acceptance contract](IMMERSIVE-SCENE.md#performance-and-reviews).
