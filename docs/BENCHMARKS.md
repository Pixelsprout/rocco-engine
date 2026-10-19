# Benchmarks

This document states how rocco measures its CPU time per Frame. It gives
every step that a reader needs to repeat a run and check a number.

The main question is the cost of the Seam: the price of a pure game behind
the Game calls, with a new Scene from every fixed step. The second question
is capacity: how far each axis scales before a Frame misses its budget.

The terms Lockstep, Headless, Bench game, Odin twin, Span and Args have the
meanings in [CONTEXT.md](../CONTEXT.md).

## Results

- Reference result directory: TODO(reference run): link
  `bench/results/<date>-<machine>/` here.
- Headline figure: TODO(reference run): N = ? on the reference machine, from
  `headline.txt` in that directory.

The section "Reference run" tells how to make these results. No results are
committed yet. An earlier directory, `bench/results/2026-10-19-apple-m5/`,
held a sweep made on battery power with other programs running. Its numbers
were noise, so it is deleted.

## What the numbers do not claim

- **No comparison with other engines.** A fair comparison needs the same
  game, written well in each engine, on the same machine, with the same
  render work. A port written by one author measures the port, not the
  engine. Engines also put work in different places: one engine does work in
  a worker thread, and another engine does the same work on the GPU. A single
  number hides that difference. The Odin twins are the control instead. They
  run the same logic through the same run loop with no Roc, so the difference
  is the cost of the Seam and of Roc.
- **No GPU time.** The Spans measure CPU time only. `render_submit` and
  `commit` measure the CPU cost of the sokol calls, not the GPU work.
- **No CI timing.** On macOS, CI runs each bench game once at N=64 as a
  smoke test. On Linux and Windows, CI runs `model-size` and
  `model-size-twin` once at N=64. CI runners share their hardware, so CI
  makes no timing claims.
- **No Windows numbers yet.** The harness runs on Windows with the same
  protocol. The first results come from the Mac.

## Run modes

| Mode | How to set it | Fixed steps per Frame | Window and GPU |
|---|---|---|---|
| Real clock | the default | 0 or more, from the wall clock | yes |
| Lockstep | `ROCCO_LOCKSTEP=1` | exactly 1 | yes, vsync off |
| Headless | `ROCCO_HEADLESS=1` with `ROCCO_EXIT_AFTER_FRAMES` | exactly 1 | no |

In the real clock mode, a slow Frame runs more fixed steps in the next
Frame, so the work changes with the measurement. Lockstep and Headless give
each run the same work.

Lockstep turns vsync off on each backend:

- Metal: the engine sets `disable_display_sync`. CADisplayLink still calls
  `frame_cb` once per display refresh. A windowed Lockstep run therefore
  takes about Frames / refresh rate seconds.
- GL: the engine uses a swap interval of 0.
- D3D11: the engine presents with `DXGI_PRESENT_DO_NOT_WAIT`.

The wait between Frames is outside every Span, so it does not change the
Span times. On Metal, sokol waits in the first `begin_pass` of a Frame for a
free in-flight frame. It also waits in the Main `begin_pass` for the
swapchain drawable. The `render_submit` Span leaves out each `begin_pass`
call, so it does not hold these waits. On GL and D3D11, the present runs
after `frame_cb` returns, so it is outside every Span.

Headless renders nothing, so its `render_submit` and `commit` Spans are
zero. It still runs the interpolation and the UI layout. The game still gets
its Queries answered and gets `loaded` with the Manifest.

## Spans

A Span is a pair of clock reads around one named section of a Frame. A host
built with `host --spans` or `host --release --spans` has Spans. Without the
define `ROCCO_SPANS`, the Span calls compile to nothing.

The host writes the Spans to the CSV file in `ROCCO_SPANS_CSV` at exit. The
first row is a header. Then each Frame has one row: the Frame number, the
fixed steps in the Frame, one column per Span in microseconds and
`span_cost_us`.

A Spans host stops at startup with exit code 1 if `ROCCO_SPANS_CSV` or
`ROCCO_EXIT_AFTER_FRAMES` is not set. The host reserves one row per Frame of
the limit, so the Spans do not allocate during a run. If the CSV does not
write, the host exits with code 1.

| Span | Runs | Measures |
|---|---|---|
| `input` | per fixed step | the copy of Input into Roc |
| `step` | per fixed step | the game's `step` |
| `commands` | per fixed step | Command execution and the decref of the Commands |
| `view` | per fixed step | the game's `view` |
| `queries` | per fixed step | the collision search and the Queries |
| `query_results` | per fixed step | the copy of the QueryResults into Roc |
| `interpolation` | per Frame | the Pairing and the interpolation of the Scene |
| `ui_layout` | per Frame | Clay layout and the quad build |
| `render_submit` | per Frame | the shadow pass and the Main pass, one draw call per Draw, the sky and the UI submit, without the `begin_pass` calls |
| `commit` | per Frame | `sg.commit` |

A per-step Span sums over the fixed steps of its Frame.

### The error in a Span

- The clock on the reference Mac ticks every 41.67 ns (24 MHz). One clock
  read costs about 28 ns.
- So a median under 1 us is correct to about +/-0.04 us. A Span that is
  shorter than one tick can read 0.
- `span_cost_us` is the mean time that one Span adds. The host measures it
  once at startup, over 100,000 Span closes, and writes it on every row. Each
  summary copies it. Test runs gave 0.011 to 0.030 us. Compare a small Span
  with it before you quote the Span.

## Build flags

A bench run uses a true release build:

| Part | Command | Flags |
|---|---|---|
| Host | `roc scripts/build.roc host --release --spans` | `odin build engine -build-mode:static -o:speed -define:ROCCO_SPANS=true -vet -strict-style` |
| sokol and Clay | `roc scripts/build.roc inputs --release` | the release sokol archives |
| Roc bench game | `roc build` in `bench/<game>/` | Roc's default, `--opt=speed` |
| Odin twin | `odin build bench/<game>-twin` | the host's target flags (`-no-crt -no-thread-local` on Windows), then `-o:speed -define:ROCCO_SPANS=true -vet -strict-style`, one executable with the engine and no Roc app |

- The release host has no `-debug`, so `ODIN_DEBUG` is false.
- The release host has no host tracking allocator. Only a debug host or
  `host --release --track-alloc` has it.
- `bench/analyse.py` and the chart scripts refuse a summary from a debug
  build. Each summary records the build flags and `odin_debug`.

### The Roc heap

The Roc heap stores the size of each block in a header before the block.
Realloc reads the old size from the header and resizes the block in the
backing allocator, in place when it can. An A/B comparison chose this version
over the allocation map, and the map version is deleted. Each summary records
`"roc_heap": "header"`.

The A/B results come from the Roc heap micro benchmark, `bench/roc-heap/`,
with `-o:speed`:

| Micro benchmark | Allocation map | Size header |
|---|---|---|
| One alloc and free pair | about 50 ns | about 15 ns |
| 12 doubling reallocs, 16 B to 64 KiB | 1.7 to 2.0 us | 0.98 us |
| 255 reallocs of +16 B, to 4 KiB | 24 to 25 us | 4.6 us |

The Model size bench game makes 2 allocs and no reallocs per step. So only
the micro benchmarks show the realloc gain. In the Model size sweep, the size
header was faster at N <= 512 (0.12 us against 0.21 us at N=64) and equal
within the noise above. That sweep ran with other programs on the machine.

#### Run the Roc heap micro benchmark

The micro benchmark calls `roc_alloc`, `roc_dealloc` and `roc_realloc`
directly, with no game and no window. It prints 3 rounds of ns per alloc and
free pair and us per realloc list. To run it on the current Roc heap:

```sh
odin run bench/roc-heap -o:speed -out:build/roc-heap
```

To repeat the A/B, use commit `78ae3bd`. That commit has both versions,
chosen with `-define:ROCCO_ROC_HEAP=map` or `header`:

```sh
git worktree add ../rocco-ab 78ae3bd
cd ../rocco-ab
git submodule update --init
mkdir -p bench/roc-heap build
git show main:bench/roc-heap/main.odin > bench/roc-heap/main.odin
odin run bench/roc-heap -o:speed -define:ROCCO_ROC_HEAP=map -out:build/roc-heap-map
odin run bench/roc-heap -o:speed -define:ROCCO_ROC_HEAP=header -out:build/roc-heap-header
```

No chart shows the Roc heap, because only one Roc heap version remains.

## Bench games

Each bench game reads N from its first Arg and stops if N is missing or not a
positive integer. Each bench game uses the Seed for its randomness, so a run
is repeatable. Each bench game changes one axis. The bench games live in
`bench/`, outside `examples/`, so `run-games.sh`, `test-all.sh` and
`screenshot.sh` do not run them. `sh bench/check.sh` runs `roc check` and
`roc test` on each bench game and `odin test` on each Odin twin.

| Bench game | Axis | Mode | What stays fixed |
|---|---|---|---|
| `model-size` | N entities moved by ordinary Roc list code | Headless | 100 Draws |
| `model-size-tuned` | the same, with a `step` that keeps the entity list unique and walks it once | Headless | 100 Draws |
| `model-size-twin` | the Odin twin of `model-size` | Headless | 100 Draws |
| `empty-step` | the Model of `model-size` with a `step` that returns the Model unchanged: the lower limit of the Seam | Headless | 100 Draws |
| `colliders` | N moving Colliders | Headless | 8 raycasts, 8 overlaps, one ContactsOf; 4 square units per Collider |
| `colliders-twin` | the Odin twin of `colliders` | Headless | as `colliders` |
| `draws` | N moving primitive cubes, one Draw each | windowed Lockstep | one Sun with shadows; the cubes stay in a fixed square |
| `ui` | N Box and Text elements; one lit cell moves each step | windowed Lockstep | no Draws |
| `mixed` | all axes, see "The headline figure" | windowed Lockstep | 4 Lights and the fixed Queries |

The golden files keep each pair of games equal:

- `bench/model-size/positions.golden` holds the positions after 600 steps at
  Seed 7 and N=100. `model-size` and `model-size-twin` check against it.
- `bench/model-size/model.golden` holds the full Model at the same point.
  `model-size` and `model-size-tuned` check against it.
- `bench/colliders/colliders.golden` holds the Colliders after 600 steps at
  Seed 7 and N=100. `colliders` and `colliders-twin` check against it.

The Draws curve has a step above 4,096 Draws. The Pairing map is reserved for
4,096 Draws (`PAIRING_CAPACITY`), so it grows past that. This is an expected
finding. The renderer draws at most 16,384 Draws per Frame (`DRAW_CAPACITY`
in `engine/frame_render.odin`) and drops the rest.

## Protocol

`roc scripts/build.roc bench <game>[,<game>...] [n...] [--windowed]` builds
and runs one sweep of one or more bench games. With no `n`, the sweep uses
N = 64, 128, 256, ..., 16,384. With `n`, it uses only the N given. For
example, `roc scripts/build.roc bench model-size,model-size-twin 64 1024`
runs two games at two N in one sweep.

1. The command builds the release host with Spans, the release inputs and
   each bench game. For an Odin twin, it builds the one twin executable.
2. Each process runs 120 warmup Frames and 2,000 measured Frames, Headless.
   With `--windowed`, each process runs in windowed Lockstep.
   The command sets `ROCCO_SEED=0` for each process, so a `ROCCO_SEED` in
   your shell cannot change a run. The summary records this Seed.
3. Each game and N runs in 5 separate processes.
4. The sweep shuffles the order of all processes of all games and N, so
   thermal drift spreads over all configurations. It prints the shuffle seed
   and records it in each summary. It pauses for 1 second after each process.
5. One more Headless process per game and N runs with `ROCCO_ALLOC_REPORT=1`. It
   records the Roc heap counters. Nobody uses its times.
6. The sweep writes the raw CSVs, the Roc heap logs and one
   `<game>-<n>.run.json` per N to `bench/out/<game>/`. Git ignores
   `bench/out/`.
7. `bench/analyse.py` drops the warmup Frames and writes one summary per N to
   `bench/results/<date>-<machine>/<game>-<n>.json`.

A summary holds:

- the bench game, N, the run mode (`headless` or `lockstep`) and the Seed;
- the median, p95, p99 and max of each Span over the Frames of all 5
  processes, with linear interpolation between the closest ranks;
- the median of each process and the spread: the largest process median
  minus the smallest;
- `frame_budget_us` (see "The headline figure");
- the Roc heap counters per measured step and the Roc heap version;
- `span_cost_us`;
- the machine, the OS, the power state, Low Power Mode, the date, the git
  hash (with `-dirty` for uncommitted changes), the build flags and
  `odin_debug`;
- the warmup and measured Frames, the process count, the cooldown and the
  shuffle seed.

## The headline figure

The headline figure is the largest N of the mixed bench game for which the
p99 Frame CPU time stays under 16.6 ms, at 2 fixed steps per Frame, on the
reference machine. Every smaller N must also stay under.

The mixed bench game, `bench/mixed/`, scales every axis with one N:

- Each entity has one Draw and one Collider.
- Every 10 entities add one UI element, counted as the UI bench game counts
  its Box and Text elements.
- The Queries stay at 8 raycasts, 8 overlaps and one ContactsOf.
- There are 4 Lights: one Ambient, one Sun with shadows and two Points.
- The arena grows with N, so each entity keeps 4 square units.

A Lockstep Frame runs one fixed step, but a 60 Hz display with a 120 Hz fixed
step runs 2. So `bench/analyse.py` computes `frame_budget_us` for each Frame:

```
frame_budget_us = 2 * (input + step + commands + view + queries + query_results)
                + interpolation + ui_layout + render_submit + commit
```

The percentiles come from these per-Frame sums, not from sums of Span
percentiles. `bench/headline.py` refuses a Headless summary, because Headless
renders nothing. Only a windowed Lockstep sweep of `mixed` gives the headline.

## Hardware rules

The reference machine is the author's Mac: Apple M5, `Mac17,2`, 16 GB of
memory. Each summary records the chip, the model, the memory, the OS, the
power source and Low Power Mode, so a reader can see the machine of each
number.

For a run that you publish:

- Connect the charger. The power source must be AC.
- Turn off Low Power Mode.
- Keep the lid open with a display on. A windowed run needs a display. With
  the lid closed and no display, macOS can stop presenting Frames and the run
  can stop.
- Quit other programs, other builds and other agents. The 1-minute load
  average must be 2.0 or less before the run starts.
- Do not use the machine during the run. Do not type into a bench window.

`python3 bench/machine.py --check` checks the power source, Low Power Mode,
the load average and the lid. It prints each problem and exits 1. It prints
nothing and exits 0 when the machine is ready.

## Tools

| Tool | Use |
|---|---|
| `roc scripts/build.roc bench <game>[,<game>...] [n...] [--windowed]` | Builds and runs one sweep. See "Protocol". |
| `bench/analyse.py <run.json>... [--out-dir <dir>]` | Writes the summaries. The bench command runs it. |
| `bench/chart.py [<results dir>]` | Draws one SVG per bench game to `bench/out/charts/<game>.svg`: N against each Span and the Frame budget, on log scales. A solid line is the median, a dashed line is p99, and a bar shows the spread between processes. |
| `bench/compare_chart.py twin\|tuned\|colliders [<results dir>]` | Draws the median and p99 `step` Span of several bench games on one chart, `bench/out/charts/<comparison>.svg`. `twin` is `model-size`, `model-size-twin` and `empty-step`. `tuned` is `model-size` and `model-size-tuned`. `colliders` is `colliders` and `colliders-twin`. |
| `bench/headline.py [<results dir>] [--game <game>]` | Prints the median and p99 Frame budget per N and the headline figure. |
| `bench/machine.py [--check]` | Prints the machine as JSON, or checks that it is ready for a reference run. |
| `odin run bench/roc-heap -o:speed -out:build/roc-heap` | Runs the Roc heap micro benchmark. See "The Roc heap". |
| `bench/realclock.py <csv> --game <game> --out <json>` | Summarises one real-clock run. See "Real-clock reference". |
| `sh bench/reference-run.sh` | Runs the full reference run. See "Reference run". |

The chart scripts and `headline.py` read the latest
`bench/results/<date>-<machine>/` when you name no directory. They use only
the Python standard library.

## Repeat a run

1. Install the tools in `README.md`, "Requirements". Put the pinned Roc
   compiler on PATH. Python 3 must be on PATH.
2. Build once: `roc scripts/build.roc all`.
3. Prepare the machine as "Hardware rules" says. Run
   `python3 bench/machine.py --check`.
4. Run one sweep, for example `roc scripts/build.roc bench model-size`. For a
   game that renders, add `--windowed`, for example
   `roc scripts/build.roc bench draws --windowed`.
5. Draw the charts: `python3 bench/chart.py`.
6. For a comparison, run the sweep of each game in it, then run
   `python3 bench/compare_chart.py twin` (or `tuned` or `colliders`).
7. For the headline figure, run `roc scripts/build.roc bench mixed --windowed`,
   then `python3 bench/headline.py`.
8. Run `roc scripts/build.roc all` again. A Spans host stops every run that
   has no `ROCCO_SPANS_CSV` and `ROCCO_EXIT_AFTER_FRAMES`, so the examples
   do not run until you do this.

To repeat the full reference run, use `sh bench/reference-run.sh` (see
"Reference run").

## Real-clock reference

Lockstep and Headless show the cost of the work. A player sees the real
clock: a Frame runs 0, 1 or 2 fixed steps, and the display paces the Frames.
The reference run includes one real-clock run of `examples/entity-game`, with
the release host with Spans, for 120 warmup Frames and 2,000 measured Frames.

`bench/analyse.py` needs Lockstep, so `bench/realclock.py` summarises this
run. It writes `real-clock/entity-game.json` in the result directory, with:

- the median, p95, p99 and max of each Span;
- the same statistics for the Frame CPU time: the sum of all Spans of a
  Frame;
- `steps_per_frame`: the count of Frames for each fixed step count. On a
  60 Hz display most Frames run 2 fixed steps; on a 120 Hz display most run 1;
- the machine and the git hash.

The chart scripts and `headline.py` do not read the `real-clock/`
subdirectory.

## Reference run

The reference run gives the committed result directory and the headline
figure. It runs every axis, both Odin twins, the tuned game, the mixed game
and the real-clock reference. Run it on the reference Mac.

### Prepare the machine

1. Connect the charger.
2. Turn off Low Power Mode in System Settings, Battery.
3. Open the lid. Keep a display on.
4. Quit every other program, build and agent.
5. Wait until the machine is cool and idle. Run `top -l 2 -o cpu -n 5` and
   look at the second sample. No process must use a large part of a core.
6. Run `python3 bench/machine.py --check`. If it prints a problem, correct it
   and run the check again.
7. Make sure that `git status` shows no changes. Otherwise the git hash in
   each summary ends in `-dirty`.

### Run it

```sh
export PATH=$HOME/tools/roc_nightly-macos_apple_silicon-2026-10-11-7d256b9:$PATH
roc scripts/build.roc all
sh bench/reference-run.sh
```

The script does these steps. To run them by hand, use the same order:

```sh
python3 bench/machine.py --check
roc scripts/build.roc bench model-size,model-size-tuned,model-size-twin,empty-step,colliders,colliders-twin
roc scripts/build.roc bench draws,ui,mixed --windowed
roc scripts/build.roc host --release --spans
roc scripts/build.roc inputs --release
roc scripts/build.roc game entity-game
(cd examples/entity-game && ROCCO_EXIT_AFTER_FRAMES=2120 \
  ROCCO_SPANS_CSV=$PWD/../../bench/out/real-clock/entity-game.csv ./entity-game.bin)
python3 bench/realclock.py bench/out/real-clock/entity-game.csv \
  --game entity-game --out bench/results/<date>-<machine>/real-clock/entity-game.json
python3 bench/chart.py
python3 bench/compare_chart.py twin
python3 bench/compare_chart.py tuned
python3 bench/compare_chart.py colliders
python3 bench/headline.py
roc scripts/build.roc all
```

The script also does these things:

- It runs all Headless games in one shuffled sweep, and all windowed games
  in a second shuffled sweep.
- It stops if `bench/machine.py --check` fails.
- It stops if `bench/results/<date>-<machine>/` for today already exists.
  Move or delete that directory first.
- It writes every summary again into the directory of the day the run
  started, so a run past midnight stays in one directory.
- It writes the output of `headline.py` to `headline.txt` in the result
  directory.

The Headless sweeps take a few minutes. Each windowed process takes about
2,120 / refresh rate seconds, so the three windowed sweeps take about 50
minutes at 120 Hz and longer at 60 Hz. Do not use the machine until the
script prints its last line.

Two environment variables change the script. Do not use them for a
reference run:

| Variable | Effect |
|---|---|
| `REFERENCE_NS="64 128"` | Runs only these N, to check the script. Delete the result directory after the check. |
| `REFERENCE_FORCE=1` | Starts the run although `bench/machine.py --check` fails. |

### Where the results go

| Output | Path | In git |
|---|---|---|
| Summaries | `bench/results/<date>-<machine>/<game>-<n>.json` | yes |
| Real-clock summary | `bench/results/<date>-<machine>/real-clock/entity-game.json` | yes |
| Headline report | `bench/results/<date>-<machine>/headline.txt` | yes |
| Charts | `bench/out/charts/*.svg` | no |
| Raw CSVs, Roc heap logs, run.json files | `bench/out/<game>/`, `bench/out/real-clock/` | no |

### After the run

1. Read `headline.txt`. The last line gives the headline figure.
2. Look at the charts in `bench/out/charts/`. Check that each curve has every
   N and that the spread bars are small.
3. Open each summary's `machine` object. Check that `power` is `ac` and
   `low_power_mode` is false.
4. In "Results" at the top of this document, replace the two TODO lines with
   the link to the result directory and the headline figure.
5. Commit the result directory and this document together.
