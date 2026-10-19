# Run from the repository root: python3 -m unittest bench/test_compare_chart.py

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse
import compare_chart

TWIN = compare_chart.COMPARISONS["twin"]
TUNED = compare_chart.COMPARISONS["tuned"]


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
    summary("model-size-tuned", 64, 1.5, 2.0),
    summary("empty-step", 64, 0.2, 0.4),
    summary("draws", 64, 9.0, 9.0),
]


class SeriesTest(unittest.TestCase):
    def test_sorts_each_line_by_n(self):
        lines = compare_chart.series(SUMMARIES, TWIN)
        self.assertEqual(lines[("model-size", "median")], [(64, 2.0), (128, 4.0)])
        self.assertEqual(lines[("model-size", "p99")], [(64, 3.0), (128, 6.0)])

    def test_keeps_only_the_games_of_the_comparison(self):
        self.assertEqual({game for game, _ in compare_chart.series(SUMMARIES, TWIN)}, {"model-size", "model-size-twin", "empty-step"})
        self.assertEqual({game for game, _ in compare_chart.series(SUMMARIES, TUNED)}, {"model-size", "model-size-tuned"})

    def test_refuses_a_debug_build(self):
        with self.assertRaises(analyse.DebugBuild):
            compare_chart.series([summary("model-size", 64, 1.0, 1.0, debug=True)], TWIN)


class SvgTest(unittest.TestCase):
    def test_draws_a_median_and_p99_line_per_game(self):
        for games in [TWIN, TUNED]:
            text = compare_chart.svg(compare_chart.series(SUMMARIES, games), games)
            for game in games:
                for stat in ["median", "p99"]:
                    self.assertIn(f'data-series="{game} {stat}"', text)

    def test_refuses_no_data(self):
        with self.assertRaises(ValueError):
            compare_chart.svg({}, TUNED)


class MainTest(unittest.TestCase):
    def test_writes_the_chart_from_a_results_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            for s in SUMMARIES:
                Path(tmp, f"{s['game']}-{s['n']}.json").write_text(json.dumps(s))
            out = Path(tmp, "tuned.svg")
            script = Path(__file__).with_name("compare_chart.py")
            result = subprocess.run([sys.executable, str(script), "tuned", tmp, "--out", str(out)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('data-series="model-size-tuned median"', out.read_text())

    def test_refuses_an_unknown_comparison(self):
        script = Path(__file__).with_name("compare_chart.py")
        result = subprocess.run([sys.executable, str(script), "draws"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
