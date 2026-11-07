# Village camera wait diagnostic, 2026-11-06

The existing sweep narrows the unexplained delay to work before commit returns.
It does not identify a GPU, display, or scheduling cause.
Two new capture attempts stopped at warning memory pressure.
Neither attempt produced frame samples.
No performance fix follows from these results.

## Existing slow frames

The analysis uses the unchanged wide-sweep archive from [the earlier evidence](village-camera-sweep-2026-11-06.md).
It retains the same 120-step settling rule and all 14 callback intervals of at least 30 ms.
Each interval runs from a frame's callback entry to the next callback entry.
CPU Spans join by that frame's engine ID.
Commit return uses that same frame's `commit_end_tick`.

| Frame | Callback, ms | CPU Spans, ms | Callback through commit return, ms | After commit return, ms |
| --- | ---: | ---: | ---: | ---: |
| 91 | 39.915 | 39.622 | 39.749 | 0.166 |
| 661 | 58.266 | 11.924 | 58.076 | 0.189 |
| 1336 | 51.109 | 12.009 | 50.357 | 0.752 |

All 14 slow frames spend less than 0.753 ms between commit return and the next callback.
Thirteen contain at least 20 ms before commit return outside the measured CPU Spans.
Frame 91 instead spends 27.210 ms in Step.
These are wall-clock intervals, so a long Span can also include thread descheduling.

`frame_render_begin_pass` deliberately excludes renderer pass entry from Render_Submit.
The first Metal pass can wait for an available frame.
Main pass entry acquires the swapchain drawable and fits render targets.
The old CSV cannot separate these operations from other unmeasured callback work, such as device polling.

## Added capture clocks

The opt-in capture records `begin_pass_ticks` around renderer pass entry.
It records `drawable_ticks` around Main's swapchain acquisition.
Drawable time is part of pass-entry time; these fields must not be added together.
The summary reports these fields alongside each slow frame.
It also reports callback entry through commit return and commit return through the next callback.
Old captures retain missing pass-entry measurements instead of receiving zero values.

These clocks locate wall time.
They do not distinguish GPU execution, presentation waits, driver work, or thread descheduling.
Ordinary runs make no additional clock calls.

## Interrupted attempts

Both attempts used the full scene and the existing wide camera sweep.
Neither attempt changed resolution, shadows, MSAA, assets, or scene features through command-line options.
Neither attempt completed, so final capture metadata cannot verify the effective scene settings.
The monitor checked native memory pressure every two seconds.
It terminated only the test game when `kern.memorystatus_vm_pressure_level` changed from 1 to 2.
No unrelated process was stopped.

The native attempt used the original binary hash:
`02191ca0a6783be6cdadc22bebd1fe7efae9fa90db92951f9ce568786c03e599`.
It requested Metal System Trace, Display, and Thread State Trace for at most 55 seconds.
The game had a 1,800-frame limit and a 90-second wall limit.
The eighth memory sample reported warning pressure, 14.4 seconds after the first sample.
Spotlight processes used substantial CPU during this attempt.
The game exited with signal 15 before it wrote boundary or CPU CSVs.
The recorder did not finish within its 30-second shutdown limit.
Its interrupted trace remains at `/tmp/village-stutter-native-20261106/gpu.trace` and occupies about 5.2 GiB.
The trace export failed with `Document Missing Template Error` and exit code 10.
It establishes no GPU or display timing result.

The lightweight attempt used binary hash:
`9b400163d886506bf02e113385bfb1332eac78847db9f3d5913aad7ce52e279a`.
Its optimized Spans host hash was:
`a8fcf4f267c340c72a0b848e50732b302777a10f091f9253be1890ff41db202e`.
The host build passed strict style checks.
The game build reported no errors or warnings.
This attempt added the pass-entry clocks without native tracing or native pass labels.
It had a 1,200-frame limit and a 90-second wall limit.
Initial memory pressure was normal.
The tenth sample reported warning pressure, 18.5 seconds after the first sample.
The game exited with signal 15 before it wrote boundary or CPU CSVs.
Background load differed between attempts; they are not a performance comparison.

## Checks and retained evidence

All 873 engine tests passed.
All 18 capture script tests passed.
The script tests check same-frame interval association, optional wait fields, and nested drawable timing.
The new summary processed the complete old wide-sweep capture successfully.
The new pass-entry clocks still need a completed native run.

The [evidence archive](village-camera-waits-2026-11-06.tar.gz) retains both launch records, monitors, logs, and probe scripts.
It also retains the export failure, revised wide-sweep summary, and all 14 slow-frame phase records.
It excludes the large, unusable native trace, which remains at the local path above.
Archive SHA-256: `db090f74e2845f38c5b13770b833e32bba3aab70afb8ed86579505adfa5bb84a`.

## Next measurement

Use a session with enough memory for the complete village and normal pressure throughout loading and the sweep.
Keep one heavy workload active.
Record background load without stopping unrelated processes.
Use the same full scene and sweep.

The retained lightweight probe accepts a new output directory.
The exact next command on this machine is:

```sh
python3 /tmp/village-stutter-waits.py /tmp/village-stutter-waits-next
```

It uses `examples/village/village-waits.bin` and rejects an existing output directory.
It checks initial pressure and stops at warning pressure.
After a complete run, use:

```sh
python3 scripts/village_debug_camera_summary.py /tmp/village-stutter-waits-next/boundaries.csv \
  --cpu /tmp/village-stutter-waits-next/cpu.csv \
  --out /tmp/village-stutter-waits-next/summary.json
```

Compare CPU Spans, pass-entry time, and drawable time on the same slow frame IDs.
If pass entry explains the gaps, collect a native trace with enough memory to finish and export successfully.
The trace must cover GPU command intervals, actual display events, and thread scheduling for those frames.
Use engine pass labels to establish GPU association; do not equate native frame IDs with engine frame IDs.
If labels or clock association remain incomplete, leave GPU and display attribution open.
