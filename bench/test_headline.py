# Run from the repository root: python3 -m unittest bench/test_headline.py

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import headline


def summary(n, p99_us, mode="lockstep", debug=False):
    return {
        "game": "mixed",
        "n": n,
        "mode": mode,
        "odin_debug": debug,
        "build_flags": {"host": ["build", "engine", "-o:speed"]},
        "spans": {},
        "frame_budget_steps": 2,
        "frame_budget_us": {"median": p99_us / 2, "p95": p99_us * 0.9, "p99": p99_us, "max": p99_us * 1.2, "process_medians": [p99_us / 2], "spread": 0.0},
    }


def write(tmp, summaries):
    for s in summaries:
        (tmp / f"{s['game']}-{s['n']}.json").write_text(json.dumps(s))


class HeadlineTest(unittest.TestCase):
    def test_is_the_largest_n_under_the_budget(self):
        summaries = [summary(64, 900.0), summary(256, 16_599.0), summary(128, 4_000.0), summary(512, 30_000.0)]
        self.assertEqual(headline.headline(summaries), 256)

    def test_a_p99_of_exactly_the_budget_misses_it(self):
        self.assertEqual(headline.headline([summary(64, 900.0), summary(128, 16_600.0)]), 64)

    def test_stops_at_the_first_n_that_misses_the_budget(self):
        summaries = [summary(64, 900.0), summary(128, 17_000.0), summary(256, 16_000.0)]
        self.assertEqual(headline.headline(summaries), 64)

    def test_is_none_when_the_smallest_n_misses_the_budget(self):
        self.assertIsNone(headline.headline([summary(64, 20_000.0)]))

    def test_refuses_a_headless_sweep(self):
        with self.assertRaises(headline.NotHeadline):
            headline.check([summary(64, 900.0, mode="headless")])

    def test_refuses_a_summary_without_the_budget(self):
        old = summary(64, 900.0)
        del old["frame_budget_us"]
        with self.assertRaises(headline.NotHeadline):
            headline.check([old])


class CommandLineTest(unittest.TestCase):
    def run_main(self, tmp):
        out = io.StringIO()
        with redirect_stdout(out):
            code = headline.main([str(tmp)])
        return code, out.getvalue()

    def test_prints_each_n_and_the_headline(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            write(tmp, [summary(64, 900.0), summary(128, 12_000.0), summary(256, 20_000.0)])
            code, out = self.run_main(tmp)
            self.assertEqual(code, 0)
            self.assertIn("Headline: N = 128.", out)
            self.assertIn("     256", out)

    def test_ignores_the_other_games(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            write(tmp, [summary(64, 900.0), {**summary(128, 900.0), "game": "draws"}])
            code, out = self.run_main(tmp)
            self.assertEqual(code, 0)
            self.assertIn("Headline: N = 64.", out)

    def test_fails_on_a_debug_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            write(tmp, [summary(64, 900.0, debug=True)])
            self.assertEqual(self.run_main(tmp)[0], 1)

    def test_fails_with_no_mixed_summaries(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_main(Path(tmp))[0], 1)


if __name__ == "__main__":
    unittest.main()
