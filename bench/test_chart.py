# Run from the repository root: python3 -m unittest bench/test_chart.py

import copy
import json
import os
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import chart


def summary(n, step_median, debug=False):
    return {
        "game": "model-size",
        "n": n,
        "odin_debug": debug,
        "build_flags": {"host": ["build", "engine", "-o:speed"]},
        "spans": {
            "step_us": {"median": step_median, "p95": step_median * 1.5, "p99": step_median * 2, "max": step_median * 3, "process_medians": [step_median * 0.9, step_median * 1.1], "spread": step_median * 0.2},
            "commit_us": {"median": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0, "process_medians": [0.0, 0.0], "spread": 0.0},
        },
    }


def write(tmp, summaries):
    for s in summaries:
        (tmp / f"{s['game']}-{s['n']}.json").write_text(json.dumps(s))


class ChartTest(unittest.TestCase):
    def test_draws_one_svg_per_game_with_n_in_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            write(tmp, [summary(1024, 4.0), summary(64, 0.25), summary(256, 1.0)])
            games = chart.load(tmp)
            self.assertEqual(list(games), ["model-size"])
            self.assertEqual([s["n"] for s in games["model-size"]], [64, 256, 1024])
            self.assertEqual(chart.main([str(tmp), "--out-dir", str(tmp / "charts")]), 0)
            root = ET.parse(tmp / "charts" / "model-size.svg").getroot()
            self.assertTrue(root.tag.endswith("svg"))

    def test_a_span_that_is_always_zero_has_no_curve(self):
        curves = chart.curves([summary(64, 0.25), summary(128, 0.5)])
        self.assertEqual(list(curves), ["step_us"])
        self.assertEqual([p["n"] for p in curves["step_us"]], [64, 128])
        self.assertAlmostEqual(curves["step_us"][0]["high"], 0.275)

    def test_the_frame_budget_is_one_more_curve(self):
        with_budget = []
        for n, step in [(64, 0.25), (128, 0.5)]:
            s = summary(n, step)
            s["frame_budget_steps"] = 2
            s["frame_budget_us"] = {**s["spans"]["step_us"], "median": step * 2}
            with_budget.append(s)
        curves = chart.curves(with_budget)
        self.assertEqual(list(curves), ["step_us", "frame_budget_2_steps_us"])
        self.assertEqual([p["median"] for p in curves["frame_budget_2_steps_us"]], [0.5, 1.0])

    def test_refuses_a_debug_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            write(tmp, [summary(64, 0.25), summary(128, 0.5, debug=True)])
            self.assertNotEqual(chart.main([str(tmp), "--out-dir", str(tmp / "charts")]), 0)
            self.assertFalse((tmp / "charts").exists())

    def test_draws_a_single_n(self):
        svg = chart.svg("model-size", "2026-10-19-apple-m5", chart.curves([summary(64, 0.25)]))
        ET.fromstring(svg)

    def test_latest_results_prefers_the_manual_sweeps(self):
        with tempfile.TemporaryDirectory() as tmp:
            manual, committed = Path(tmp) / "out" / "results", Path(tmp) / "results"
            (committed / "2026-10-21-apple-m5").mkdir(parents=True)
            self.assertEqual(chart.latest_results([manual, committed]).name, "2026-10-21-apple-m5")
            (manual / "2026-10-19-apple-m5").mkdir(parents=True)
            (manual / "2026-10-20-apple-m5").mkdir()
            self.assertEqual(chart.latest_results([manual, committed]), manual / "2026-10-20-apple-m5")

    def test_latest_results_is_none_with_no_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(chart.latest_results([Path(tmp) / "out" / "results", Path(tmp) / "results"]))


if __name__ == "__main__":
    unittest.main()
