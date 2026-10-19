# Run from the repository root: python3 -m unittest bench/test_draws_chart.py

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse
import draws_chart


def summary(n, us, game="draws", mode="lockstep", debug=False):
    stats = {"median": us, "p95": us * 2, "p99": us * 3, "max": us * 4}
    return {
        "game": game,
        "n": n,
        "mode": mode,
        "odin_debug": debug,
        "build_flags": {"host": ["build"], "game": []},
        "spans": {span: dict(stats) for span in ["step_us", "interpolation_us", "render_submit_us", "commit_us"]},
    }


SUMMARIES = [
    summary(8192, 40.0),
    summary(64, 1.0),
    summary(64, 0.0, mode="headless"),
    summary(64, 5.0, game="model-size"),
]


class SeriesTest(unittest.TestCase):
    def test_sorts_each_span_by_n(self):
        lines = draws_chart.series(SUMMARIES)
        self.assertEqual(lines[("render_submit_us", "median")], [(64, 1.0), (8192, 40.0)])
        self.assertEqual(lines[("commit_us", "p99")], [(64, 3.0), (8192, 120.0)])

    def test_keeps_only_the_render_spans_of_windowed_draws_runs(self):
        lines = draws_chart.series(SUMMARIES)
        self.assertEqual({span for span, _ in lines}, {"interpolation_us", "render_submit_us", "commit_us"})
        self.assertTrue(all(len(points) == 2 for points in lines.values()))

    def test_refuses_a_debug_build(self):
        with self.assertRaises(analyse.DebugBuild):
            draws_chart.series([summary(64, 1.0, debug=True)])

    def test_has_no_lines_from_headless_runs_only(self):
        self.assertEqual(draws_chart.series([summary(64, 0.0, mode="headless")]), {})


class MainTest(unittest.TestCase):
    def run_chart(self, summaries):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        for s in summaries:
            Path(tmp.name, f"{s['game']}-{s['n']}-{s['mode']}.summary.json").write_text(json.dumps(s))
        script = Path(__file__).with_name("draws_chart.py")
        result = subprocess.run([sys.executable, str(script), tmp.name], capture_output=True, text=True)
        return result, Path(tmp.name, "draws.svg")

    def test_writes_the_curve_with_the_pairing_mark(self):
        result, chart = self.run_chart(SUMMARIES)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = chart.read_text()
        for span in ["interpolation_us", "render_submit_us", "commit_us"]:
            self.assertIn(f'data-series="{span} median"', text)
        self.assertIn('data-marker="4096"', text)

    def test_fails_with_no_windowed_runs(self):
        result, chart = self.run_chart([summary(64, 0.0, mode="headless")])
        self.assertEqual(result.returncode, 1)
        self.assertFalse(chart.exists())


if __name__ == "__main__":
    unittest.main()
