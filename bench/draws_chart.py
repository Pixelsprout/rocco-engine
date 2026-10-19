#!/usr/bin/env python3
"""Draw the Draws curve: the render Spans of the draws bench game against N.

Usage: python3 bench/draws_chart.py [summary dir] [--out <chart.svg>]

Reads every draws-<n>.summary.json in the directory (default bench/out) from a
windowed Lockstep run. It draws the median and the p99 of the interpolation,
render submit and sg.commit Spans against N, on log scales, as one SVG. A
summary from a debug build is refused, as in analyse.py.
"""

import argparse
import json
import sys
from pathlib import Path

from analyse import DebugBuild, is_debug
from twin_chart import STATS, svg

GAME = "draws"
# Headless renders nothing, so only a windowed Lockstep run has render Spans.
MODE = "lockstep"
SPANS = {
    "interpolation_us": ("interpolation", "#2a6fdb"),
    "render_submit_us": ("render submit", "#d9480f"),
    "commit_us": ("sg.commit", "#5c940d"),
}
# engine/frame_render.odin PAIRING_CAPACITY: past it the Pairing map grows.
PAIRING_CAPACITY = 4096


def series(summaries):
    """{(span, stat): [(n, us), ...]} sorted by N, for windowed draws runs."""
    out = {}
    for summary in summaries:
        if summary["game"] != GAME or summary.get("mode") != MODE:
            continue
        if is_debug(summary):
            raise DebugBuild(f"{GAME} at N={summary['n']} is from a debug build")
        for span in SPANS:
            for stat in STATS:
                us = summary["spans"][span][stat]
                out.setdefault((span, stat), []).append((summary["n"], us))
    for points in out.values():
        points.sort()
    return out


def main(argv):
    parser = argparse.ArgumentParser(description="Chart the render Spans of the draws bench game.")
    parser.add_argument("dir", type=Path, nargs="?", default=Path("bench/out"))
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)

    summaries = [json.loads(p.read_text()) for p in sorted(args.dir.glob(f"{GAME}-*.summary.json"))]
    try:
        text = svg(
            series(summaries),
            legend=SPANS,
            title="Render Spans per Frame against Draws",
            marker=(PAIRING_CAPACITY, "Pairing map grows"),
        )
    except ValueError as err:
        print(f"draws_chart: {args.dir}: {err}", file=sys.stderr)
        return 1
    out = args.out or args.dir / "draws.svg"
    out.write_text(text)
    print(f"draws_chart: wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
