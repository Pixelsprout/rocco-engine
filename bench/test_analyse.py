# Run from the repository root: python3 -m unittest bench/test_analyse.py

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyse

# Two warmup Frames with large times, then five measured Frames.
CSV = (
    "frame,steps,step_us,view_us\n"
    "1,1,900.000,800.000\n"
    "2,1,700.000,600.000\n"
    "3,1,10.000,5.000\n"
    "4,1,20.000,1.000\n"
    "5,1,30.000,4.000\n"
    "6,1,40.000,2.000\n"
    "7,1,50.000,3.000\n"
)

META = {
    "game": "model-size",
    "n": 64,
    "mode": "headless",
    "warmup_frames": 2,
    "measured_frames": 5,
    "seed": 0,
    "git_hash": "abc123",
    "target": "arm64mac",
    "odin_debug": False,
    "build_flags": {
        "host": ["build", "engine", "-o:speed", "-define:ROCCO_SPANS=true"],
        "game": ["build", "--target=arm64mac", "main.roc"],
    },
}


class PercentileTest(unittest.TestCase):
    def test_interpolates_between_the_closest_ranks(self):
        values = [10.0, 20.0, 30.0, 40.0, 50.0]
        self.assertEqual(analyse.percentile(values, 50), 30.0)
        self.assertAlmostEqual(analyse.percentile(values, 95), 48.0)
        self.assertAlmostEqual(analyse.percentile(values, 99), 49.6)
        self.assertEqual(analyse.percentile(values, 100), 50.0)

    def test_does_not_need_sorted_values(self):
        self.assertEqual(analyse.percentile([3.0, 1.0, 2.0], 50), 2.0)

    def test_gives_the_one_value_of_a_single_frame(self):
        self.assertEqual(analyse.percentile([7.0], 99), 7.0)


class SummariseTest(unittest.TestCase):
    def test_drops_the_warmup_frames(self):
        summary = analyse.summarise(CSV, META)
        self.assertEqual(summary["spans"]["step_us"]["max"], 50.0)
        self.assertEqual(summary["measured_frames"], 5)

    def test_gives_the_median_p95_p99_and_max_of_each_span(self):
        spans = analyse.summarise(CSV, META)["spans"]
        self.assertEqual(sorted(spans), ["step_us", "view_us"])
        self.assertEqual(spans["step_us"]["median"], 30.0)
        self.assertAlmostEqual(spans["step_us"]["p95"], 48.0)
        self.assertAlmostEqual(spans["step_us"]["p99"], 49.6)
        self.assertEqual(spans["view_us"], {"median": 3.0, "p95": 4.8, "p99": 4.96, "max": 5.0})

    def test_records_the_run(self):
        summary = analyse.summarise(CSV, META)
        self.assertEqual(summary["n"], 64)
        self.assertEqual(summary["mode"], "headless")
        self.assertEqual(summary["git_hash"], "abc123")
        self.assertEqual(summary["build_flags"], META["build_flags"])
        self.assertFalse(summary["odin_debug"])

    def test_refuses_a_debug_build(self):
        with self.assertRaises(analyse.DebugBuild):
            analyse.summarise(CSV, {**META, "odin_debug": True})

    def test_refuses_debug_host_flags_even_if_odin_debug_says_false(self):
        flags = {**META["build_flags"], "host": ["build", "engine", "-debug"]}
        with self.assertRaises(analyse.DebugBuild):
            analyse.summarise(CSV, {**META, "build_flags": flags})

    def test_refuses_a_run_with_missing_frames(self):
        short = "".join(CSV.splitlines(keepends=True)[:-1])
        with self.assertRaises(ValueError):
            analyse.summarise(short, META)


class CommandLineTest(unittest.TestCase):
    def run_script(self, *args):
        script = Path(__file__).with_name("analyse.py")
        return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)

    def test_writes_the_summary_beside_the_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "model-size-64.csv"
            csv_path.write_text(CSV)
            (Path(tmp) / "model-size-64.run.json").write_text(json.dumps(META))
            result = self.run_script(str(csv_path))
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads((Path(tmp) / "model-size-64.summary.json").read_text())
            self.assertEqual(summary["spans"]["step_us"]["median"], 30.0)

    def test_fails_on_a_debug_build_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "model-size-64.csv"
            csv_path.write_text(CSV)
            (Path(tmp) / "model-size-64.run.json").write_text(json.dumps({**META, "odin_debug": True}))
            result = self.run_script(str(csv_path))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("debug", result.stderr)
            self.assertFalse((Path(tmp) / "model-size-64.summary.json").exists())

    def test_fails_with_no_run_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            csv_path = Path(tmp) / "model-size-64.csv"
            csv_path.write_text(CSV)
            result = self.run_script(str(csv_path))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("run.json", result.stderr)


if __name__ == "__main__":
    unittest.main()
