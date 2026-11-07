# Windows village debug camera diagnostic, 6 November 2026

Finding: the largest recorded delays are inside CPU Spans. Renderer pass entry and drawable acquisition are negligible in this run. After-commit gaps contribute to some smaller spikes. Braeden reported: "I am flying around the scene and it seems pretty smooth now". The earlier repeated-forward stutter was not confirmed reproduced. No rendering code was changed.

Source: origin/diagnose/windows-village-capture at dd8d3662c8bdee3cdcf8b1c6dcd2e57a94bb6df5. The texture-cache commit 9a89f8817e1bb11daa88093853f5275125a11618 is an ancestor. The only tracked worktree change is the diagnostic dex task. The original checkout remains on test/texture-cache with its existing build_miniaudio.cmd edit.
Executable SHA-256: d0f5fbd775f14c614476bf9fb39f4e38594d6164455346708b1b50d07d777ff4
Executable: `examples/village/capture-20261106-2225/village-debug.exe`, retained alongside release build logs, build commands, tool versions and native library hashes. Existing prepared release Sokol/Clay/miniaudio libraries were reused; they were not rebuilt. The shader asset builder validated its pinned compiler and generated five shaderpacks. Shader manifest and hashes are retained in the local capture directory.

Run: PID 1236; 2026-11-06T09:28:05.3600335Z through 09:32:24.6553188Z; exit 0; all 7200 bounded frames recorded; Real_Clock; human debug camera; sweep/Bridge/Lockstep/Headless disabled. Environment and launcher retained. NVIDIA RTX 2070 SUPER, driver 32.0.15.9186, desktop 2560x1440 at 60 Hz. Actual capture dimensions stayed 1920x1080. MSAA X4, shadow maps 2048, two cascades, 120 Hz fixed steps. Raw metadata retains the final scene: 1436 source Draws, 21993 field Draws, 41 emitters, one Post, no selected groups. This is an ordinary debug-camera diagnostic, not the controlled full-route acceptance run.

Summary: scripts/village_debug_camera_summary.py, default 120-step settling after last Load at step 96. Selected 7161 intervals (frames 39 through 7199); final frame has no following callback and cannot yield an interval. 4003 moving, 3158 stationary; no missing CPU rows and no clock clamp in selected samples. Movement includes rotation as well as translation. Contiguous movement segments are retained in frame-analysis.json; no input/route markers prove exact repeated-path equivalence.

## Callback intervals

Milliseconds, nearest-rank percentiles:

```text
                 N       p50       p95       p99       max
Moving         4003   23.5368   26.9639   29.0289   31.5733
Stationary     3158   24.1905   34.9773   51.1464   88.3790

```

213 intervals were at least 30 ms: 15 moving and 198 stationary. All 20 slowest occurred before first observed camera movement (frame 436). A separate summary-from-first-motion.json retains frames 436 onward: stationary max 35.9984 ms, p99 29.9366 ms. The primary summary keeps all early post-load spikes.

Moving CPU work excluding Commit: median 21.8315 ms; p95 25.2607 ms. Moving median Interpolation 9.6413 ms and Render_Submit 9.8326 ms. These per-Span medians are separate statistics, not a synthetic frame.

## Slowest frames

Milliseconds. CPU excludes Commit; drawable is a subset of pass entry, so never add it again.

```text
Frame   Moving Steps Interval    CPU     Pass-entry Drawable Commit    After-commit
  135   False     7  88.3790  87.3893     0.0109   0.0004  0.0002       0.9590
  183   False     5  71.6419  70.7492     0.0098   0.0004  0.0003       0.8713
  102   False     5  71.2247  70.4056     0.0108   0.0005  0.0002       0.7948
  185   False     7  66.2888  65.3285     0.0094   0.0006  0.0002       0.9350
   59   False     7  63.3753  62.3096     0.0113   0.0004  0.0003       1.0398
 4404    True     3  31.5733  29.8717     0.0087   0.0004  0.0003       1.6828
 6584    True     3  31.5289  23.4159     0.0109   0.0005  0.0002       8.0920
 6714    True     3  31.5104  29.6893     0.0300   0.0015  0.0003       1.7799

```

Frame 135: eye (2, 1.5, 5), stationary, seven fixed steps. Step 57.6299 ms, View 9.1330 ms, Interpolation 9.6463 ms, Render_Submit 9.9053 ms. Callback entry through commit return 87.4200 ms. Unattributed callback work after subtracting CPU Spans and pass entry is 0.0195 ms.

Frame 4404: eye (7.1420484, 5.198361, 20.622313), moving, three steps. Step 0.8574 ms, View 1.3961 ms, Interpolation 12.3147 ms, Render_Submit 14.8351 ms. Callback through commit return 29.8905 ms. Unattributed callback work 0.0097 ms.

Frame 6584: moving, interval 31.5289 ms with CPU 23.4159 ms and after-commit gap 8.0920 ms. This is evidence that after-commit time contributes to some smaller spikes, although it is not the dominant location of the worst stalls.

## Measurement limits

- These clocks locate wall time; CPU Spans do not distinguish executing CPU instructions from driver waits or thread descheduling. Render_Submit can include driver work. Step detail and Interpolation detail need deeper profiling before a code-level cause is established.
- begin_pass_ticks aggregates renderer pass entries; it does not identify a particular pass. drawable_ticks measures the swapchain acquisition call and is already included in pass entry.
- No D3D GPU timestamps, PresentMon, presentation trace, GPU activity, actual displayed cadence, scheduling trace, or thermal/power/HAGS observations were collected. Callback cadence and tiny Commit CPU cost do not establish GPU cost or displayed FPS. The after-commit gap does not identify its internal cause.
- The last Load is in frame 9; frame 10 starts 80.700 seconds after first callback. That includes initial shader/asset work and is not an observed readiness timestamp. The one-second settling rule is simulation steps; it does not discard every early startup effect.
- No paired run of 1e4aeb8 or the earlier cached executable was made. This run cannot attribute the reported 50-to-70-second load regression or establish that the cache fixed Windows stutter. Diagnostic clocks, Spans and the isolated setup can change timings.
- The first attempt in the parent evidence directory lacked generated shaderpacks, was closed normally, and remains marked INVALID-ATTEMPT.txt. It is excluded from conclusions. Its exit-code field is null because the first launcher did not retain a native process handle; the successful replacement records exit 0.

## Retained evidence

Local capture directory: `examples/village/capture-20261106-2225/run-02/`.
Its parent holds the build logs and executable. Raw captures remain local and are not included in this report commit.

boundaries.csv + .meta.json + .commands.jsonl; cpu.csv; game stdout/stderr logs; summary.json; summary-from-first-motion.json; frame-analysis.json; slowest-frames.csv; analyse-frames.py; shader-build.json and hashes; launch/exit/environment records. Build logs, exact source commit, executable/hash, and native library hashes are in the parent evidence directory.

Validation: official summary completed successfully; full 1..7200 boundary sequence and matching CPU frame IDs; positive QPC frequency; no capture error; process exit 0. No screenshot, readback, Bridge stepping or diagnostic GPU waits were introduced during measurement.
