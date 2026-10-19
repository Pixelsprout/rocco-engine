#!/usr/bin/env python3
"""Draw the step Span of the Roc bench game, its Odin twin and the empty step.

Usage: python3 bench/twin_chart.py [results dir] [--out <chart.svg>]

Reads every <game>-<n>.json summary in the results dir (default: the latest
bench/results/<date>-<machine>/) for the games model-size, model-size-twin and
empty-step. It draws the median and the p99 of the step Span against N, on log
scales, as one SVG, by default bench/out/twin.svg. A summary from a debug build
is refused, as in analyse.py.
"""

import argparse
import json
import math
import sys
from pathlib import Path

from analyse import DebugBuild, is_debug
from chart import BENCH_DIR, latest_results

GAMES = {
    "model-size": ("Roc bench game", "#2a6fdb"),
    "model-size-twin": ("Odin twin", "#d9480f"),
    "empty-step": ("Empty step", "#5c940d"),
}
STATS = {"median": "", "p99": "6 4"}
SPAN = "step_us"

WIDTH, HEIGHT = 720, 440
LEFT, RIGHT, TOP, BOTTOM = 70, 180, 40, 50


def series(summaries):
    """{(game, stat): [(n, us), ...]} sorted by N, for the known games."""
    out = {}
    for summary in summaries:
        if is_debug(summary):
            raise DebugBuild(f"{summary['game']} at N={summary['n']} is from a debug build")
        if summary["game"] not in GAMES:
            continue
        for stat in STATS:
            us = summary["spans"][SPAN][stat]
            out.setdefault((summary["game"], stat), []).append((summary["n"], us))
    for points in out.values():
        points.sort()
    return out


def log_ticks(low, high, base):
    first = math.floor(math.log(low, base))
    last = math.ceil(math.log(high, base))
    return [base**k for k in range(first, last + 1)]


def svg(lines):
    points = [p for pts in lines.values() for p in pts]
    if not points:
        raise ValueError("no summaries of the twin games")
    xs = log_ticks(min(n for n, _ in points), max(n for n, _ in points), 2)
    ys = log_ticks(max(min(us for _, us in points), 0.01), max(us for _, us in points), 10)
    plot_w, plot_h = WIDTH - LEFT - RIGHT, HEIGHT - TOP - BOTTOM

    def x_at(n):
        span = math.log2(xs[-1]) - math.log2(xs[0]) or 1
        return LEFT + (math.log2(n) - math.log2(xs[0])) / span * plot_w

    def y_at(us):
        span = math.log10(ys[-1]) - math.log10(ys[0]) or 1
        return TOP + plot_h - (math.log10(max(us, ys[0])) - math.log10(ys[0])) / span * plot_h

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" font-family="sans-serif" font-size="12">',
        f'<rect width="{WIDTH}" height="{HEIGHT}" fill="white"/>',
        f'<text x="{LEFT}" y="22" font-size="14">step Span per Frame against N (median solid, p99 dashed)</text>',
    ]
    for n in xs:
        x = x_at(n)
        parts.append(f'<line x1="{x:.1f}" y1="{TOP}" x2="{x:.1f}" y2="{TOP + plot_h}" stroke="#ddd"/>')
        parts.append(f'<text x="{x:.1f}" y="{TOP + plot_h + 16}" text-anchor="middle">{n}</text>')
    for us in ys:
        y = y_at(us)
        parts.append(f'<line x1="{LEFT}" y1="{y:.1f}" x2="{LEFT + plot_w}" y2="{y:.1f}" stroke="#ddd"/>')
        parts.append(f'<text x="{LEFT - 6}" y="{y + 4:.1f}" text-anchor="end">{us:g}</text>')
    parts.append(f'<text x="{LEFT + plot_w / 2}" y="{HEIGHT - 10}" text-anchor="middle">N (entities)</text>')
    parts.append(f'<text transform="translate(16 {TOP + plot_h / 2}) rotate(-90)" text-anchor="middle">microseconds</text>')

    for (game, stat), pts in sorted(lines.items()):
        _, color = GAMES[game]
        coords = " ".join(f"{x_at(n):.1f},{y_at(us):.1f}" for n, us in pts)
        dash = f' stroke-dasharray="{STATS[stat]}"' if STATS[stat] else ""
        parts.append(f'<polyline data-series="{game} {stat}" points="{coords}" fill="none" stroke="{color}" stroke-width="2"{dash}/>')
    for i, (game, (label, color)) in enumerate(GAMES.items()):
        y = TOP + 10 + i * 20
        parts.append(f'<line x1="{WIDTH - RIGHT + 16}" y1="{y}" x2="{WIDTH - RIGHT + 40}" y2="{y}" stroke="{color}" stroke-width="2"/>')
        parts.append(f'<text x="{WIDTH - RIGHT + 46}" y="{y + 4}">{label}</text>')
    parts.append("</svg>")
    return "\n".join(parts) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description="Chart the Roc bench game, its Odin twin and the empty step.")
    parser.add_argument("dir", type=Path, nargs="?")
    parser.add_argument("--out", type=Path, default=BENCH_DIR / "out" / "twin.svg")
    args = parser.parse_args(argv)

    results = args.dir or latest_results()
    if results is None or not results.is_dir():
        print("twin_chart: no results directory. Run roc scripts/build.roc bench first.", file=sys.stderr)
        return 1
    summaries = [json.loads(p.read_text()) for p in sorted(results.glob("*.json"))]
    try:
        text = svg(series(summaries))
    except ValueError as err:
        print(f"twin_chart: {results}: {err}", file=sys.stderr)
        return 1
    out = args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text)
    print(f"twin_chart: wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
