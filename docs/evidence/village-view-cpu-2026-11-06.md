# Village View CPU and parity evidence

The cache reduces Step plus View p95 from 8.443 ms to 0.424 ms.
All 24 visibility rebuilds remain in the measured samples.
The isolated CPU p95 remains 22.145 ms, above the 16.67 ms target.
Depth batching is absent from both runs.
Combined measurements must determine the remaining CPU work.
The reporting basis remains 22 items.

## Change

Preparation creates immutable field Nodes for both grass material modes.
Each ready Step compares exact visibility for every relevant field ID.
The cache rebuilds when visibility membership or Node settings change.
Its key includes lighting, vegetation, and selected Group settings.
Ready loaded callbacks rebuild preparation and cached Nodes.
Failed readiness clears the Node cache.
View computes current camera, shader values, queries, environment, effects, emitters, cursor, and UI.
Each fixed step still calls View.
Field density, source placement order, the distance envelope, and source casting remain unchanged.

## Build and workload

The baseline source is `25faba2`.
The candidate source is `91da4b99d2160be0d366dea2e55b266541344796`.
Both binaries use the verified Surface reuse host.
The host SHA-256 is `3a961182fe073fcacd5a26cfb3ab03d16cad27a187eb1d92ce34888c40d6809e`.
Both use pinned Odin, optimized Roc, release Spans, and `taskpolicy -a`.
The archive records exact commands, compiler versions, archive hashes, and binary hashes.
The driver records the current worktree commit for both binaries.
`final-build.json` identifies each binary's actual source commit.

Each run loads all 93 meshes and 1,436 source placements.
Field density stays at 22,000, with all effects and Group 20 selected.
The physical output stays at 1920 by 1080 pixels.
Readiness occurs at fixed step 96.
Four setup steps precede the unchanged 1,800-step warmup.
Measurement includes all 3,600 fixed steps from cumulative steps 1,901 through 5,500.
Every measured frame contains one actual fixed step.
Paused frames and warmup rows remain in the raw CSV files.
Sampling and diagnostic hosts are absent from these timing runs.

## CPU results

All values use milliseconds and nearest-rank percentiles.

| Work | Baseline p50 | Baseline p95 | Baseline p99 | Candidate p50 | Candidate p95 | Candidate p99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Step | 0.106 | 0.122 | 0.136 | 0.135 | 0.154 | 0.182 |
| View | 6.426 | 8.337 | 10.067 | 0.245 | 0.272 | 0.623 |
| Step + View | 6.533 | 8.443 | 10.169 | 0.377 | 0.424 | 1.055 |
| Actual CPU, one fixed step | 23.434 | 29.145 | 32.025 | 16.956 | 22.145 | 24.013 |
| Derived CPU, two fixed steps | 30.164 | 37.272 | 41.855 | 17.356 | 22.601 | 24.506 |

The candidate has exactly 24 Step spans above 1 ms.
All occur within the first 600 route steps.
`comparison.json` records every spike's frame, fixed step, Step time, and View time.
Candidate maximum Step time is 12.721 ms.
Candidate maximum Step plus View time is 13.449 ms.
These samples remain in every reported percentile.
Derived CPU adds another copy of each row's fixed-step spans.
This estimate does not establish real pacing.

## Attribution and memory

Native sampling identified repeated copies, allocations, and reference counts within the inlined View path.
The bounded prepared-Node experiment reduced median View time from 6.916 ms to 5.128 ms.
Those attribution runs used 120 warmup steps and 600 measured steps.
The baseline sample includes profiler overhead.
A separate membership probe counted 24 changes across 600 route steps.
Its median Step time increased from 0.096375 ms to 0.113167 ms.

Three alternating headless startup pairs measured requested Roc allocation bytes.
These counters exclude allocator headers, native allocations, GPU memory, and RSS.
After ready Hero Views, requested live bytes increase from 25,122,664 to 25,362,704.
The difference is 240,040 bytes because Scenes share the cached Node list.
Peak requested bytes increase from 34,358,136 to 35,339,608.
The final three View snapshots match within each run.
Both prepared Node variants remain available for controls.

The last-ready callback median increases from 6.499 ms to 12.391 ms.
The candidate callback includes the initial Node build.
The baseline performs that build during its first ready View.
The candidate callback samples are 10.332, 31.053, and 12.391 ms.
The raw logs retain all three samples.
These instrumented headless timings provide diagnostics, separate from acceptance timing.
The archive preserves both diagnostic host patches and their build hashes.
The verified host was restored before final timing and parity.

## Semantic and pixel verification

All 187 optimized Roc tests pass.
Tests compare complete Scene values across cameras, controls, selected Groups, and loaded callbacks.
A synthetic route compares every Scene across 3,600 fixed steps.
Field tests compare every Node against the original filter and map operations.
They cover full placements, density controls, exact distance boundaries, and changed IDs with an unchanged visible count.

Seven native 1920 by 1080 images are byte-identical to the verified Surface baseline.
All eight Bridge snapshots also match exactly.
Bridge omits Post and shader values; the Roc comparisons include both.
Route captures use cumulative steps 2,500, 3,100, 3,700, 4,300, 4,900, and 5,500.
The initial selected image also matches.
Visual inspection confirms the complete village at route step 600.
Pixel runs provide parity evidence, separate from CPU timing.
The reference binary SHA-256 is `7848c12a73960f7f53f0cb2cd9fdcd921fc5dd59a011e16fe567905fbf2380d2`.
The reference archive is [Surface reuse evidence](surface-reuse-cpu-2026-11-06.tar.gz).

## Retained artifacts

[Machine-readable results](village-view-cpu-2026-11-06.json) contain the comparison, hashes, spike records, and parity results.
[Committed timing evidence](village-view-cpu-2026-11-06.tar.gz) contains every CSV, log, build record, probe, and patch.
The full archive preserves every screenshot, Scene snapshot, and measurement binary outside Git.
Its path is `/tmp/rocco-village-view-full-evidence.tar.gz`.
Its SHA-256 is `6487c5c04eed900bd182fd4c17b9a0263004c85911ba9b03e06398f1dc16c52c`.
The result JSON records every preserved file digest and both archive verification results.
Original files remain at their recorded paths.
The archive SHA-256 is `c44c74ef3000db8bf199fbef94462c324b0151fc7469a61618cd7ecff653fe26`.
GPU timing, real pacing, PC evidence, and human acceptance remain separate.
