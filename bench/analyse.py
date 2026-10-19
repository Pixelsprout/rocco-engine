#!/usr/bin/env python3
"""Turn one bench run's Spans CSV into a summary JSON.

Usage: python3 bench/analyse.py bench/out/<game>-<n>.csv [--out <summary.json>]

`roc scripts/build.roc bench <game> <n>` writes the CSV and the <game>-<n>.run.json
beside it. The summary goes to <game>-<n>.summary.json unless --out names a path.
A debug build is refused, so a debug number cannot reach a chart.
"""

import argparse
import csv
import io
import json
import sys
from pathlib import Path

PERCENTILES = {"median": 50, "p95": 95, "p99": 99}


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


def summarise(csv_text, meta):
    if is_debug(meta):
        raise DebugBuild("the run is from a debug build, so its numbers are not valid")

    rows = list(csv.DictReader(io.StringIO(csv_text)))
    warmup = meta["warmup_frames"]
    expected = warmup + meta["measured_frames"]
    if len(rows) != expected:
        raise ValueError(f"the CSV has {len(rows)} Frames, expected {expected}")
    measured = rows[warmup:]

    span_names = [name for name in measured[0] if name.endswith("_us")]
    spans = {}
    for name in span_names:
        values = [float(row[name]) for row in measured]
        stats = {key: round(percentile(values, p), 3) for key, p in PERCENTILES.items()}
        stats["max"] = max(values)
        spans[name] = stats

    keep = ["game", "n", "mode", "seed", "git_hash", "target", "odin_debug", "build_flags", "warmup_frames"]
    summary = {key: meta[key] for key in keep}
    summary["measured_frames"] = len(measured)
    summary["spans"] = spans
    return summary


def main(argv):
    parser = argparse.ArgumentParser(description="Summarise one bench run's Spans CSV.")
    parser.add_argument("csv", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    run_path = args.csv.with_suffix(".run.json")
    if not run_path.is_file():
        print(f"analyse: {run_path} is missing. Run roc scripts/build.roc bench first.", file=sys.stderr)
        return 1
    meta = json.loads(run_path.read_text())

    try:
        summary = summarise(args.csv.read_text(), meta)
    except DebugBuild as err:
        print(f"analyse: {args.csv}: {err}", file=sys.stderr)
        return 1
    except ValueError as err:
        print(f"analyse: {args.csv}: {err}", file=sys.stderr)
        return 1

    out = args.out or args.csv.with_suffix(".summary.json")
    out.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"analyse: wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
