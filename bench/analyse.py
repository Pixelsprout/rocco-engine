#!/usr/bin/env python3
"""Turn the runs of one bench configuration into a summary JSON.

Usage: python3 bench/analyse.py <run.json>... [--out-dir <dir>]

`roc scripts/build.roc bench <game> [n]` writes one <game>-<n>.run.json per N
in bench/out/<game>/, with the Spans CSV of each process and the Roc heap log
beside it, and then runs this script. Each summary goes to
bench/results/<date>-<machine>/<game>-<n>.json unless --out-dir names a
directory. A debug build is refused, so a debug number cannot reach a chart.
"""

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path

PERCENTILES = {"median": 50, "p95": 95, "p99": 99}

RESULTS_DIR = Path(__file__).resolve().parent / "results"

# The run.json fields that a summary copies unchanged.
RUN_FIELDS = [
    "game",
    "n",
    "mode",
    "seed",
    "git_hash",
    "target",
    "odin_debug",
    "roc_heap",
    "build_flags",
    "warmup_frames",
    "measured_frames",
    "processes",
    "cooldown_ms",
    "shuffle_seed",
    "machine",
]

# The engine repeats the timer cost of one Span on every row. It is not a Span.
SPAN_COST = "span_cost_us"

HEAP_LINE = re.compile(r"^alloc step=(\d+) allocs=(\d+) deallocs=(\d+) reallocs=(\d+) live=(\d+)")


class DebugBuild(ValueError):
    pass


def percentile(values, p):
    """Linear interpolation between the closest ranks."""
    ordered = sorted(values)
    rank = p / 100 * (len(ordered) - 1)
    low = int(rank)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (rank - low)


def is_debug(meta):
    return bool(meta.get("odin_debug")) or "-debug" in meta.get("build_flags", {}).get("host", [])


def measured_rows(csv_text, warmup, measured):
    """Drops the warmup Frames of one process."""
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    if len(rows) != warmup + measured:
        raise ValueError(f"the CSV has {len(rows)} Frames, expected {warmup + measured}")
    return rows[warmup:]


def heap_counters(log_text, warmup, measured):
    """Per-step Roc heap counters over the measured steps. A Lockstep Frame runs
    one fixed step, so step k is Frame k."""
    steps = []
    for line in log_text.splitlines():
        found = HEAP_LINE.match(line)
        if found:
            steps.append([int(value) for value in found.groups()])
    if len(steps) != warmup + measured:
        raise ValueError(f"the Roc heap log has {len(steps)} steps, expected {warmup + measured}")
    kept = steps[warmup:]
    totals = {name: sum(step[i] for step in kept) for i, name in [(1, "allocs"), (2, "deallocs"), (3, "reallocs")]}
    counters = {f"{name}_per_step": round(total / len(kept), 3) for name, total in totals.items()}
    counters.update(totals)
    counters["live_max"] = max(step[4] for step in kept)
    counters["live_last"] = kept[-1][4]
    return counters


def summarise(process_csvs, meta, heap_log):
    if is_debug(meta):
        raise DebugBuild("the run is from a debug build, so its numbers are not valid")
    if len(process_csvs) != meta["processes"]:
        raise ValueError(f"the run has {len(process_csvs)} processes, expected {meta['processes']}")

    warmup, measured = meta["warmup_frames"], meta["measured_frames"]
    processes = [measured_rows(text, warmup, measured) for text in process_csvs]

    columns = processes[0][0]
    span_names = [name for name in columns if name.endswith("_us") and name != SPAN_COST]
    spans = {}
    for name in span_names:
        per_process = [[float(row[name]) for row in rows] for rows in processes]
        pooled = [value for values in per_process for value in values]
        stats = {key: round(percentile(pooled, p), 3) for key, p in PERCENTILES.items()}
        stats["max"] = max(pooled)
        medians = [round(percentile(values, 50), 3) for values in per_process]
        stats["process_medians"] = medians
        stats["spread"] = round(max(medians) - min(medians), 3)
        spans[name] = stats

    summary = {key: meta[key] for key in RUN_FIELDS}
    summary["span_cost_us"] = float(columns[SPAN_COST]) if SPAN_COST in columns else None
    summary["spans"] = spans
    summary["roc_heap_counters"] = heap_counters(heap_log, warmup, measured)
    return summary


def results_dir(meta):
    machine = meta["machine"]
    return RESULTS_DIR / f"{machine['date']}-{machine['slug']}"


def analyse(run_path, out_dir):
    meta = json.loads(run_path.read_text())
    process_csvs = [(run_path.parent / name).read_text() for name in meta["csvs"]]
    heap_log = (run_path.parent / meta["heap_log"]).read_text()
    summary = summarise(process_csvs, meta, heap_log)
    out_dir = out_dir or results_dir(meta)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{meta['game']}-{meta['n']}.json"
    out.write_text(json.dumps(summary, indent=2) + "\n")
    return out


def main(argv):
    parser = argparse.ArgumentParser(description="Summarise the runs of bench configurations.")
    parser.add_argument("runs", type=Path, nargs="+", help="the <game>-<n>.run.json of each configuration")
    parser.add_argument("--out-dir", type=Path)
    args = parser.parse_args(argv)

    failed = False
    for run_path in args.runs:
        try:
            out = analyse(run_path, args.out_dir)
        except OSError as err:
            print(f"analyse: {run_path}: {err}. Run roc scripts/build.roc bench first.", file=sys.stderr)
            failed = True
        except KeyError as err:
            print(f"analyse: {run_path}: the run.json has no {err} field", file=sys.stderr)
            failed = True
        except ValueError as err:
            print(f"analyse: {run_path}: {err}", file=sys.stderr)
            failed = True
        else:
            print(f"analyse: wrote {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
