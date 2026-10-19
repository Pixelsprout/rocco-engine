#!/usr/bin/env python3
"""Report the headline figure from the mixed bench game's summaries.

Usage: python3 bench/headline.py [<results dir>] [--game <game>]

The headline figure is the largest N whose p99 Frame CPU time stays under
16.6 ms at 2 fixed steps per Frame. bench/analyse.py writes that Frame time as
frame_budget_us: the per-step Spans times 2 plus the per-Frame Spans. The
results dir defaults to the latest bench/results/<date>-<machine>/. Only a
windowed Lockstep sweep counts, because Headless renders nothing.
"""

import argparse
import sys
from pathlib import Path

import analyse
import chart

BUDGET_US = 16_600.0

HEADLINE_MODE = "lockstep"


class NotHeadline(ValueError):
    pass


def check(summaries):
    for s in summaries:
        if s["mode"] != HEADLINE_MODE:
            raise NotHeadline(f"N={s['n']} ran {s['mode']}, so its render Spans are missing. Run the sweep with --windowed")
        if "frame_budget_us" not in s:
            raise NotHeadline(f"N={s['n']} has no frame_budget_us. Run bench/analyse.py on its run.json again")
        if s["frame_budget_steps"] != analyse.BUDGET_STEPS:
            raise NotHeadline(f"N={s['n']} has a budget for {s['frame_budget_steps']} fixed steps, not {analyse.BUDGET_STEPS}")


def headline(summaries):
    """The largest N such that it and every smaller N keep p99 under budget, or
    None if the smallest N misses it."""
    best = None
    for s in sorted(summaries, key=lambda s: s["n"]):
        if s["frame_budget_us"]["p99"] >= BUDGET_US:
            break
        best = s["n"]
    return best


def report(game, results, summaries):
    lines = [f"{game} in {results.name}: p99 Frame CPU time at {analyse.BUDGET_STEPS} fixed steps per Frame", ""]
    lines.append(f"{'N':>8}  {'median ms':>10}  {'p99 ms':>10}  under {BUDGET_US / 1000:g} ms")
    for s in sorted(summaries, key=lambda s: s["n"]):
        budget = s["frame_budget_us"]
        under = "yes" if budget["p99"] < BUDGET_US else "no"
        lines.append(f"{s['n']:>8}  {budget['median'] / 1000:>10.3f}  {budget['p99'] / 1000:>10.3f}  {under}")
    lines.append("")
    best = headline(summaries)
    if best is None:
        lines.append(f"Headline: no N keeps p99 under {BUDGET_US / 1000:g} ms.")
    else:
        lines.append(f"Headline: N = {best}.")
    return "\n".join(lines) + "\n"


def main(argv):
    parser = argparse.ArgumentParser(description="Report the largest N whose p99 Frame CPU time stays under 16.6 ms.")
    parser.add_argument("results", type=Path, nargs="?")
    parser.add_argument("--game", default="mixed")
    args = parser.parse_args(argv)

    results = args.results or chart.latest_results()
    if results is None or not results.is_dir():
        print("headline: no results directory. Run roc scripts/build.roc bench mixed --windowed first.", file=sys.stderr)
        return 1
    try:
        summaries = chart.load(results).get(args.game, [])
        if not summaries:
            print(f"headline: {results} has no {args.game} summaries", file=sys.stderr)
            return 1
        check(summaries)
    except (analyse.DebugBuild, NotHeadline) as err:
        print(f"headline: {err}", file=sys.stderr)
        return 1
    print(report(args.game, results, summaries), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
