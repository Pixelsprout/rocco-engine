# Roc 0.1.0_RC1 compile times against nightly-2026-11-04

## Question

Does the move from `nightly-2026-11-04-2622062` to the `0.1.0_RC1` release
change how long rocco games take to check, test and build? Does RC1 change
the speed of the code it makes?

## Result

RC1 is faster in 19 of 20 cases. `roc check` takes 40% to 49% less time.
`roc test` takes 50% to 68% less time. A cold `--opt=speed` build, the mode
that `scripts/build.roc game` uses, takes 20% to 29% less time.

A cold `--opt=dev` build of village is 58% slower. In RC1, `--opt=dev` uses
boxy lowering by default (`--specialize=no`). The village Field module holds
much static data, and the boxy unit steps take 1.9 s for it. With
`--specialize=yes`, the same build takes 1.2 s, against 2.1 s on the nightly.
rocco does not build with `--opt=dev`, so this does not change a rocco build.

The code is as fast as before. With a release host (`roc scripts/build.roc
host --release`), village takes 162 to 163 ms per step on RC1 and 163 to
164 ms per step on the nightly, over 119 steps of asset streaming.

Median of 3 runs, in seconds:

| Game | Step | nightly-2026-11-04 | 0.1.0_RC1 | Change |
|---|---|---:|---:|---:|
| primitives | check (cold) | 0.05 s | 0.03 s | -40% |
| primitives | test (cold) | 0.12 s | 0.04 s | -64% |
| primitives | build speed (cold) | 0.23 s | 0.19 s | -20% |
| primitives | build speed (cached) | 0.25 s | 0.17 s | -34% |
| primitives | build dev (cold) | 0.07 s | 0.06 s | -21% |
| pong | check (cold) | 0.07 s | 0.04 s | -40% |
| pong | test (cold) | 0.17 s | 0.06 s | -67% |
| pong | build speed (cold) | 0.43 s | 0.33 s | -24% |
| pong | build speed (cached) | 0.37 s | 0.31 s | -18% |
| pong | build dev (cold) | 0.10 s | 0.07 s | -28% |
| widgets | check (cold) | 0.08 s | 0.05 s | -44% |
| widgets | test (cold) | 0.21 s | 0.07 s | -68% |
| widgets | build speed (cold) | 0.73 s | 0.56 s | -24% |
| widgets | build speed (cached) | 0.65 s | 0.53 s | -18% |
| widgets | build dev (cold) | 0.14 s | 0.09 s | -37% |
| village | check (cold) | 2.05 s | 1.05 s | -49% |
| village | test (cold) | 15.04 s | 7.48 s | -50% |
| village | build speed (cold) | 4.70 s | 3.34 s | -29% |
| village | build speed (cached) | 2.67 s | 2.23 s | -16% |
| village | build dev (cold) | 2.20 s | 3.47 s | +58% |

"Cold" runs pass `--no-cache`. "Cached" runs follow one warm-up build. Each
build targets `arm64mac` and links the same host archive. The times include
the link.

## Setup

- Machine: Apple M5, 10 cores, macOS 26.7.2.
- Commit: `3d98cad` with the RC1 changes of dex task `7b0b64d3` in the
  working tree. Both compilers read the same source. The nightly warns about
  the `0.1.0-rc1` header pin and builds anyway.
- Compilers: `roc_nightly-macos_apple_silicon-2026-11-04-2622062` and
  `roc-macos_apple_silicon-0.1.0_RC1`, from `~/tools`.

## Commands

```sh
python3 -I compile_bench.py <out dir>
roc build --no-cache --timings --opt=dev --target=arm64mac main.roc
roc build --no-cache --timings --opt=dev --specialize=yes --target=arm64mac main.roc
```

The script `compile_bench.py` below runs each step 3 times for each compiler and each game, and
writes the medians. Raw data: `docs/evidence/raw/roc-rc1-compile-times-2026-11-22.json`,
SHA-256 `a2dcacc8742df8ea14fd493136f29b47a51e7703f6d8338bd18d441b0739ebcc`.
Git ignores the raw folder. `roc-rc1-compile-times-2026-11-22.json` beside
this report holds the medians.

```python
import json, os, statistics, subprocess, sys, time

# Run from the repo root.
root = os.getcwd()
out_dir = sys.argv[1]
compilers = {
    'nightly-2026-11-04': os.path.expanduser('~/tools/roc_nightly-macos_apple_silicon-2026-11-04-2622062/roc'),
    '0.1.0_RC1': os.path.expanduser('~/tools/roc-macos_apple_silicon-0.1.0_RC1/roc'),
}
games = ['primitives', 'pong', 'widgets', 'village']
runs = 3
modes = {
    'check (cold)': lambda roc, game: [roc, 'check', '--no-cache', 'main.roc'],
    'test (cold)': lambda roc, game: [roc, 'test', '--no-cache', 'main.roc'],
    'build speed (cold)': lambda roc, game: [roc, 'build', '--no-cache', '--target=arm64mac', f'--output={out_dir}/{game}.bin', 'main.roc'],
    'build speed (cached)': lambda roc, game: [roc, 'build', '--target=arm64mac', f'--output={out_dir}/{game}.bin', 'main.roc'],
    'build dev (cold)': lambda roc, game: [roc, 'build', '--no-cache', '--opt=dev', '--target=arm64mac', f'--output={out_dir}/{game}-dev.bin', 'main.roc'],
}


def timed(cmd, cwd):
    t = time.perf_counter()
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    elapsed = time.perf_counter() - t
    # Exit 2 means warnings only.
    if result.returncode not in (0, 2):
        return None, (result.stdout + result.stderr)[-400:]
    return elapsed, None


rows = []
for game in games:
    cwd = os.path.join(root, 'examples', game)
    for mode, make in modes.items():
        for name, roc in compilers.items():
            if mode.endswith('(cached)'):
                timed(make(roc, game), cwd)
            samples, error = [], None
            for _ in range(runs):
                elapsed, error = timed(make(roc, game), cwd)
                if elapsed is None:
                    break
                samples.append(elapsed)
            row = dict(game=game, mode=mode, compiler=name, samples=samples, median=statistics.median(samples) if samples else None, error=error)
            rows.append(row)
            print(json.dumps({k: v for k, v in row.items() if k != 'samples'}), flush=True)

with open(os.path.join(out_dir, 'compile-bench.json'), 'w') as f:
    json.dump(rows, f, indent=2)
```
