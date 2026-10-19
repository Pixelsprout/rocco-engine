#!/usr/bin/env python3
"""Draw one curve per axis from committed bench summaries, as SVG.

Usage: python3 bench/chart.py [<results dir>] [--out-dir <dir>]

The results dir defaults to the latest bench/results/<date>-<machine>/. The
script writes one <game>.svg per bench game to bench/out/charts/ unless
--out-dir names a directory. Each chart puts N on the x axis and the time of
each Span on the y axis, both on log scales. A solid line is the median, a
dashed line is p99, and a bar at each median shows the spread between
processes. The script uses only the standard library, so anyone can redraw the
charts. It refuses a summary from a debug build.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import analyse

BENCH_DIR = Path(__file__).resolve().parent
WIDTH, HEIGHT = 720, 440
LEFT, RIGHT, TOP, BOTTOM = 70, 150, 40, 50
COLOURS = ["#2a6fdb", "#d9480f", "#2b8a3e", "#862e9c", "#c2255c", "#1098ad", "#b08900", "#495057"]


def load(results_dir):
    """Summaries grouped by bench game, each group sorted by N."""
    games = {}
    for path in sorted(results_dir.glob("*.json")):
        summary = json.loads(path.read_text())
        if analyse.is_debug(summary):
            raise analyse.DebugBuild(f"{path} is from a debug build")
        games.setdefault(summary["game"], []).append(summary)
    for summaries in games.values():
        summaries.sort(key=lambda s: s["n"])
    return games


def curves(summaries):
    """One curve per Span: N against median, p99 and the process-median range.
    A Span that is zero at every N, such as render submit in Headless, has no curve."""
    names = [name for name in summaries[0]["spans"] if any(s["spans"].get(name, {}).get("max", 0) > 0 for s in summaries)]
    return {
        name: [
            {
                "n": s["n"],
                "median": s["spans"][name]["median"],
                "p99": s["spans"][name]["p99"],
                "low": min(s["spans"][name]["process_medians"]),
                "high": max(s["spans"][name]["process_medians"]),
            }
            for s in summaries
            if name in s["spans"]
        ]
        for name in names
    }


def log_scale(lo, hi, start, end):
    lo, hi = math.log10(lo), math.log10(hi)
    span = hi - lo or 1.0
    return lambda v: start + (math.log10(v) - lo) / span * (end - start)


def svg(game, machine, span_curves):
    points = [p for curve in span_curves.values() for p in curve]
    ns = sorted({p["n"] for p in points})
    # A Span below the timer's resolution can read 0 us; log scales need a floor.
    floor = 0.01
    y_lo = 10 ** math.floor(math.log10(max(floor, min(min(p["low"], p["median"]) for p in points))))
    y_hi = 10 ** math.ceil(math.log10(max(floor * 10, max(max(p["high"], p["p99"]) for p in points))))
    x = log_scale(ns[0], ns[-1] if ns[-1] > ns[0] else ns[0] * 2, LEFT, WIDTH - RIGHT)
    y = log_scale(y_lo, y_hi, HEIGHT - BOTTOM, TOP)

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}" font-family="sans-serif" font-size="12">',
        f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#ffffff"/>',
        f'<text x="{LEFT}" y="22" font-size="15" font-weight="bold">{game}: Span time against N</text>',
        f'<text x="{WIDTH - RIGHT}" y="22" text-anchor="end" fill="#555">{machine}</text>',
    ]
    for n in ns:
        out.append(f'<line x1="{x(n):.1f}" y1="{TOP}" x2="{x(n):.1f}" y2="{HEIGHT - BOTTOM}" stroke="#eee"/>')
        out.append(f'<text x="{x(n):.1f}" y="{HEIGHT - BOTTOM + 16}" text-anchor="middle">{n}</text>')
    decade = y_lo
    while decade <= y_hi * 1.0001:
        out.append(f'<line x1="{LEFT}" y1="{y(decade):.1f}" x2="{WIDTH - RIGHT}" y2="{y(decade):.1f}" stroke="#eee"/>')
        out.append(f'<text x="{LEFT - 6}" y="{y(decade) + 4:.1f}" text-anchor="end">{decade:g}</text>')
        decade *= 10
    out.append(f'<text x="{(LEFT + WIDTH - RIGHT) / 2}" y="{HEIGHT - 12}" text-anchor="middle">N</text>')
    out.append(f'<text transform="translate(18 {(TOP + HEIGHT - BOTTOM) / 2}) rotate(-90)" text-anchor="middle">microseconds per Frame</text>')

    for i, (name, curve) in enumerate(span_curves.items()):
        colour = COLOURS[i % len(COLOURS)]
        clamp = lambda v: max(v, y_lo)
        median = " ".join(f"{x(p['n']):.1f},{y(clamp(p['median'])):.1f}" for p in curve)
        p99 = " ".join(f"{x(p['n']):.1f},{y(clamp(p['p99'])):.1f}" for p in curve)
        out.append(f'<polyline points="{median}" fill="none" stroke="{colour}" stroke-width="2"/>')
        out.append(f'<polyline points="{p99}" fill="none" stroke="{colour}" stroke-width="1.5" stroke-dasharray="5 4"/>')
        for p in curve:
            px = x(p["n"])
            out.append(f'<line x1="{px:.1f}" y1="{y(clamp(p["low"])):.1f}" x2="{px:.1f}" y2="{y(clamp(p["high"])):.1f}" stroke="{colour}" stroke-width="3" opacity="0.5"/>')
            out.append(f'<circle cx="{px:.1f}" cy="{y(clamp(p["median"])):.1f}" r="3" fill="{colour}"/>')
        ly = TOP + 10 + i * 20
        lx = WIDTH - RIGHT + 14
        out.append(f'<line x1="{lx}" y1="{ly}" x2="{lx + 22}" y2="{ly}" stroke="{colour}" stroke-width="2"/>')
        out.append(f'<text x="{lx + 28}" y="{ly + 4}">{name.removesuffix("_us")}</text>')
    key_y = TOP + 20 + len(span_curves) * 20
    lx = WIDTH - RIGHT + 14
    out.append(f'<line x1="{lx}" y1="{key_y}" x2="{lx + 22}" y2="{key_y}" stroke="#333" stroke-width="2"/>')
    out.append(f'<text x="{lx + 28}" y="{key_y + 4}">median</text>')
    out.append(f'<line x1="{lx}" y1="{key_y + 20}" x2="{lx + 22}" y2="{key_y + 20}" stroke="#333" stroke-width="1.5" stroke-dasharray="5 4"/>')
    out.append(f'<text x="{lx + 28}" y="{key_y + 24}">p99</text>')
    out.append(f'<line x1="{lx + 11}" y1="{key_y + 34}" x2="{lx + 11}" y2="{key_y + 48}" stroke="#333" stroke-width="3" opacity="0.5"/>')
    out.append(f'<text x="{lx + 28}" y="{key_y + 45}">process spread</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def latest_results():
    dirs = sorted(d for d in (BENCH_DIR / "results").glob("*") if d.is_dir())
    return dirs[-1] if dirs else None


def main(argv):
    parser = argparse.ArgumentParser(description="Draw one curve per axis from bench summaries.")
    parser.add_argument("results", type=Path, nargs="?")
    parser.add_argument("--out-dir", type=Path, default=BENCH_DIR / "out" / "charts")
    args = parser.parse_args(argv)

    results = args.results or latest_results()
    if results is None or not results.is_dir():
        print("chart: no results directory. Run roc scripts/build.roc bench first.", file=sys.stderr)
        return 1
    try:
        games = load(results)
    except analyse.DebugBuild as err:
        print(f"chart: {err}", file=sys.stderr)
        return 1
    if not games:
        print(f"chart: {results} has no summaries", file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for game, summaries in games.items():
        out = args.out_dir / f"{game}.svg"
        out.write_text(svg(game, results.name, curves(summaries)))
        print(f"chart: wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
