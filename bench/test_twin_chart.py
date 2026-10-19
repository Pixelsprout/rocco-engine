# Run from the repository root: python3 -m unittest bench/test_twin_chart.py

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse
import twin_chart


def summary(game, n, median, p99, debug=False):
    return {
        "game": game,
        "n": n,
        "odin_debug": debug,
        "build_flags": {"host": ["build"], "game": []},
        "spans": {"step_us": {"median": median, "p95": p99, "p99": p99, "max": p99}},
    }


SUMMARIES = [
    summary("model-size", 128, 4.0, 6.0),
    summary("model-size", 64, 2.0, 3.0),
    summary("model-size-twin", 64, 1.0, 1.5),
    summary("empty-step", 64, 0.2, 0.4),
    summary("draws", 64, 9.0, 9.0),
]


class SeriesTest(unittest.TestCase):
    def test_sorts_each_line_by_n(self):
        lines = twin_chart.series(SUMMARIES)
        self.assertEqual(lines[("model-size", "median")], [(64, 2.0), (128, 4.0)])
        self.assertEqual(lines[("model-size", "p99")], [(64, 3.0), (128, 6.0)])

    def test_keeps_only_the_twin_games(self):
        games = {game for game, _ in twin_chart.series(SUMMARIES)}
        self.assertEqual(games, {"model-size", "model-size-twin", "empty-step"})

    def test_refuses_a_debug_build(self):
        with self.assertRaises(analyse.DebugBuild):
            twin_chart.series([summary("model-size", 64, 1.0, 1.0, debug=True)])


class SvgTest(unittest.TestCase):
    def test_draws_a_median_and_p99_line_per_game(self):
        text = twin_chart.svg(twin_chart.series(SUMMARIES))
        for game in ["model-size", "model-size-twin", "empty-step"]:
            for stat in ["median", "p99"]:
                self.assertIn(f'data-series="{game} {stat}"', text)

    def test_refuses_no_data(self):
        with self.assertRaises(ValueError):
            twin_chart.svg({})


class MainTest(unittest.TestCase):
    def test_writes_the_chart_from_a_results_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            for s in SUMMARIES:
                Path(tmp, f"{s['game']}-{s['n']}.json").write_text(json.dumps(s))
            out = Path(tmp, "charts", "twin.svg")
            script = Path(__file__).with_name("twin_chart.py")
            result = subprocess.run([sys.executable, str(script), tmp, "--out", str(out)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("<svg", out.read_text())


if __name__ == "__main__":
    unittest.main()
