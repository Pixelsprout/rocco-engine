# Windows village normal-tour CPU capture, 6 November 2026

Both full-v1 tours completed and reached all six waypoints. The largest measured intervals recur near the start of both tours at similar camera positions. They are dominated by CPU Span wall time, with substantial Step and Render_Submit costs. This locates the time; it does not establish a code-level cause. No rendering code was changed.

## Provenance

Source commit: dd8d3662c8bdee3cdcf8b1c6dcd2e57a94bb6df5 (diagnose/windows-village-capture).
Binary SHA-256: d0f5fbd775f14c614476bf9fb39f4e38594d6164455346708b1b50d07d777ff4
The unchanged executable is the release host with Spans and speed-optimized x64win village used in the earlier human debug-camera capture. Matching build logs, compiler versions, native library hashes and retained executable are in ../capture-20261106-2225 relative to this evidence directory's parent. See build-provenance.txt.
Launch command: D:\code\rocco-engine\examples\village\diagnostic-worktree-20261106\examples\village\village-debug.exe --capture-route=full-v1
Launcher: scripts/village_capture.py --mode cpu --binary ... --runs 1 --timeout 600 --machine ../machine.json --output ...; exact command retained in ../capture-command.txt.

## Conditions and validation

Intel Core i7-9700F, RTX 2070 SUPER, 16 GB RAM, Windows 11 Home; driver 32.0.15.9186; desktop 2560x1440 at 60 Hz. Native hardware, HAGS registry observation and active power scheme are in run.json. Effective HAGS default, thermals and power source were not independently verified. This is one diagnostic run, not the full three-run CPU/GPU/pacing acceptance protocol.
Physical capture dimensions 1920x1080, 75-degree lens, X4 MSAA, 2048 shadow maps, two cascades. Final metadata: Group 20 selected, 1436 source Draws, 22000 field Draws, two Posts, 41 emitters. Official summary validated full density and all required scene effect switches. Debug camera, Bridge, Headless and Lockstep disabled; no GPU timestamps or native labels.
Observed readiness at step 97; warmup 1800 steps; two tours of 3600 steps each; drain 120 steps; complete marker at step 9217. Each tour reached waypoint 6. Process exit 0; capture error empty; 2075 total boundary frames; 1745 measured render frames; 7200 measured fixed steps; no missing CPU rows; no measured clock clamps. Whole mixed frames 298 and 2042 are retained.

## Callback intervals

Milliseconds, nearest rank:

```text
             Samples   Median      p95      p99      Max
Both tours      1744  33.1025  41.1051  50.8732  90.0829
Tour 1           870  33.2195  40.4683  50.8732  83.1645
Tour 2           875  32.9655  41.6413  51.0037  90.0829
```

The official combined summary uses consecutive selected callback entries, yielding 1744 intervals. Per-tour analysis uses each selected frame through its next callback, including the final selected frame, yielding 1745 intervals in total. The combined percentiles are unchanged by that additional boundary interval. Tours are not averaged together.

CPU Spans including Commit: median 32.2263 ms, p95 40.1949 ms, p99 49.9914 ms, maximum 88.2124 ms. Commit is tiny (Span p95 0.0007 ms). The CPU p95 exceeds the documented 16.67 ms target; GPU and display acceptance remain unmeasured.
Across measured frames: Interpolation median 9.6475 ms, p95 10.7749 ms; Render_Submit median 19.1513 ms, p95 25.0013 ms. Individual Span medians describe separate distributions and must not be added into a synthetic frame.
Pass-entry aggregate: median 0.0158 ms, p95 0.0201 ms, maximum 0.0419 ms. Drawable acquisition: median 0.0005 ms, maximum 0.0201 ms. Drawable is already included in pass entry. After-commit gap: median 0.7853 ms, p95 1.3285 ms, maximum 2.3403 ms.

## Slowest frames

Milliseconds; CPU excludes Commit.

```text
Frame Tour Steps Interval      CPU    Step   Submit Pass-entry Drawable Commit After-commit
 1212    2     8  90.0829  88.2119 45.6617  24.2177     0.0137   0.0004 0.0005       1.8390
  343    1     7  83.1645  82.0804 33.3802  29.4661     0.0180   0.0006 0.0004       1.0472
 1216    2     6  75.1087  74.2592 33.4279  24.6781     0.0161   0.0005 0.0003       0.8187
  346    1     5  71.5102  70.6815 32.1606  23.5824     0.0171   0.0014 0.0003       0.7969
 1211    2     6  66.7316  65.7767 23.1710  28.0335     0.0168   0.0005 0.0005       0.9256

```

Worst frame 1212 (Tour 2): eye (0.027599193, 1.6999999, 16.539997), eight fixed steps. CPU 88.2119 ms: Step 45.6617 ms, View 7.5550 ms, Interpolation 9.9667 ms, Render_Submit 24.2177 ms. Callback through commit return 88.2439 ms; unaccounted callback work after CPU Spans and pass entry 0.0178 ms.

Tour 1 maximum, frame 343: eye (0.030330399, 1.7, 16.494476), seven fixed steps. Interval 83.1645 ms, CPU 82.0804 ms, Step 33.3802 ms, View 7.1084 ms, Interpolation 11.1832 ms, Render_Submit 29.4661 ms. Pass entry 0.0180 ms; drawable 0.0006 ms; after-commit 1.0472 ms. Similar positions and repeated Step spikes are evidence for further CPU profiling, not proof of the underlying operation or that all repeated-forward stutter has one cause.

## Measurement limits

The human debug-camera capture left no group selected and retained one Post. This controlled tour selects Group 20 and retains two Posts. Camera paths, visibility and fixed-step counts also differ. Its higher frame costs are not a controlled regression comparison with human flying.
CPU Spans and native clocks measure wall time. They cannot separate executing CPU instructions from thread descheduling or waits within engine/driver calls. Multiple fixed steps accumulate in one Step Span. Deep profiling is required before identifying a specific operation to change.
No GPU timestamps, PresentMon, scheduling trace or presentation trace was collected. Callback cadence is not displayed cadence, and tiny Commit CPU time does not establish GPU cost. Aggregate pass entry does not identify a specific pass.
No paired earlier-build capture was collected; this cannot explain the reported 50-to-70-second load regression. Full-v1 route readiness, warmup and exact boundary handling differ from the human debug-camera settling rule.

## Retained evidence

boundaries.csv, boundaries.csv.meta.json, boundaries.csv.commands.jsonl, cpu.csv, host.log, run.json, summary.json, frame-analysis.json, slowest-frames.csv, analyse-frames.py, REPORT.txt. Parent directory retains machine.json, commit.txt, executable-sha256.json, build-provenance.txt, capture-command.txt and launcher.log. Existing captures and local source changes were preserved.

Committed evidence: [raw capture archive](windows-village-tour-2026-11-06.tar.gz), [official summary](windows-village-tour-2026-11-06.json). The archive contains the raw CPU and boundary CSVs, command markers, logs, machine and launch records, slow-frame analysis, matching build logs, frozen summary tools, and a relative-path SHA-256 manifest.

The official summary was recomputed and compared with the retained result before packaging. Every archived file was read back and verified against the archive SHA-256 manifest. The original launcher source-state probe failed on junction-backed submodules; the separate successful status observation is retained as `source-state.txt`.
