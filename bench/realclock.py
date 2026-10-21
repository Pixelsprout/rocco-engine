#!/usr/bin/env python3
"""Summarise one real-clock run of an example, as a reference for what a player
experiences.

Usage: python3 bench/realclock.py <spans.csv> --game <name> --out <summary.json> [--warmup 120]

The run uses the real clock, so a Frame runs 0, 1 or more fixed steps and the
work changes with the timing. bench/analyse.py needs Lockstep and does not read
such a run. This script drops the warmup Frames, then writes the median, p95,
p99 and max of each Span and of the Frame CPU time (the sum of the Spans of a
Frame), the count of Frames per fixed step count, the machine and the git hash.
bench/reference-run.sh runs it after a run with a release host with Spans.
"""

import argparse
import csv
import datetime
import io
import json
import subprocess
import sys
from pathlib import Path

import analyse
import machine

WARMUP_FRAMES = 120


def stats(values):
    out = {key: round(analyse.percentile(values, p), 3) for key, p in analyse.PERCENTILES.items()}
    out["max"] = round(max(values), 3)
    return out


def summarise(csv_text, game, warmup):
    rows = list(csv.DictReader(io.StringIO(csv_text)))
    if len(rows) <= warmup:
        raise ValueError(f"the CSV has {len(rows)} Frames, not more than the {warmup} warmup Frames")
    rows = rows[warmup:]
    span_names = [name for name in rows[0] if name.endswith("_us") and name != analyse.SPAN_COST]
    steps = {}
    for row in rows:
        steps[row["steps"]] = steps.get(row["steps"], 0) + 1
    return {
        "game": game,
        "mode": "real-clock",
        "warmup_frames": warmup,
        "measured_frames": len(rows),
        "span_cost_us": float(rows[0][analyse.SPAN_COST]) if analyse.SPAN_COST in rows[0] else None,
        "steps_per_frame": dict(sorted(steps.items(), key=lambda item: int(item[0]))),
        "frame_cpu_us": stats([sum(float(row[name]) for name in span_names) for row in rows]),
        "spans": {name: stats([float(row[name]) for row in rows]) for name in span_names},
    }


def git_hash():
    """The reference run writes bench/results/ before this summary, so a change
    there does not make the hash dirty."""
    head = subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True, text=True)
    status = subprocess.run(["git", "status", "--porcelain", "--", ".", ":(exclude)bench/results"], capture_output=True, text=True)
    if head.returncode != 0:
        return "unknown"
    return head.stdout.strip() + ("-dirty" if status.stdout.strip() else "")


def main(argv):
    parser = argparse.ArgumentParser(description="Summarise one real-clock run of an example.")
    parser.add_argument("csv", type=Path)
    parser.add_argument("--game", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--warmup", type=int, default=WARMUP_FRAMES)
    args = parser.parse_args(argv)

    try:
        summary = summarise(args.csv.read_text(), args.game, args.warmup)
    except (OSError, ValueError, KeyError) as err:
        print(f"realclock: {args.csv}: {err}", file=sys.stderr)
        return 1
    summary["git_hash"] = git_hash()
    summary["machine"] = machine.machine(datetime.date.today())
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(summary, indent=2) + "\n")
    print(f"realclock: wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
