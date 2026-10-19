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
CSV_A = (
    "frame,steps,step_us,view_us\n"
    "1,1,900.000,800.000\n"
    "2,1,700.000,600.000\n"
    "3,1,10.000,5.000\n"
    "4,1,20.000,1.000\n"
    "5,1,30.000,4.000\n"
    "6,1,40.000,2.000\n"
    "7,1,50.000,3.000\n"
)

# A slower process: every measured step is 10 us later than in CSV_A.
CSV_B = (
    "frame,steps,step_us,view_us\n"
    "1,1,950.000,850.000\n"
    "2,1,750.000,650.000\n"
    "3,1,20.000,5.000\n"
    "4,1,30.000,1.000\n"
    "5,1,40.000,4.000\n"
    "6,1,50.000,2.000\n"
    "7,1,60.000,3.000\n"
)

# The warmup steps allocate a lot; the measured steps allocate 2 and free 2.
HEAP_LOG = (
    "alloc step=1 allocs=90 deallocs=10 reallocs=7 live=80 step_us=1.0 view_us=1.0\n"
    "alloc step=2 allocs=50 deallocs=50 reallocs=3 live=80 step_us=1.0 view_us=1.0\n"
    "alloc step=3 allocs=2 deallocs=2 reallocs=0 live=80 step_us=1.0 view_us=1.0\n"
    "alloc step=4 allocs=2 deallocs=2 reallocs=1 live=80 step_us=1.0 view_us=1.0\n"
    "alloc step=5 allocs=2 deallocs=2 reallocs=0 live=81 step_us=1.0 view_us=1.0\n"
    "alloc step=6 allocs=2 deallocs=2 reallocs=1 live=80 step_us=1.0 view_us=1.0\n"
    "alloc step=7 allocs=2 deallocs=2 reallocs=0 live=80 step_us=1.0 view_us=1.0\n"
    "Frame Count: 7\n"
)

MACHINE = {
    "date": "2026-10-19",
    "slug": "apple-m5",
    "chip": "Apple M5",
    "model": "Mac17,2",
    "memory_bytes": 17179869184,
    "os": "macOS 26.5.1 (25F80)",
    "power": "ac",
    "low_power_mode": False,
}

META = {
    "game": "model-size",
    "n": 64,
    "mode": "headless",
    "warmup_frames": 2,
    "measured_frames": 5,
    "processes": 2,
    "csvs": ["model-size-64-p1.csv", "model-size-64-p2.csv"],
    "heap_log": "model-size-64.heap.log",
    "cooldown_ms": 1000,
    "shuffle_seed": 42,
    "seed": 0,
    "git_hash": "abc123",
    "target": "arm64mac",
    "odin_debug": False,
    "roc_heap": "header",
    "build_flags": {
        "host": ["build", "engine", "-o:speed", "-define:ROCCO_SPANS=true"],
        "game": ["build", "--target=arm64mac", "main.roc"],
    },
    "machine": MACHINE,
}


def summary():
    return analyse.summarise([CSV_A, CSV_B], META, HEAP_LOG)


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


class WarmupTest(unittest.TestCase):
    def test_drops_the_warmup_frames_of_each_process(self):
        rows = analyse.measured_rows(CSV_A, 2, 5)
        self.assertEqual([row["frame"] for row in rows], ["3", "4", "5", "6", "7"])

    def test_no_warmup_value_reaches_the_summary(self):
        spans = summary()["spans"]
        self.assertEqual(spans["step_us"]["max"], 60.0)
        self.assertEqual(spans["view_us"]["max"], 5.0)

    def test_refuses_a_process_with_missing_frames(self):
        short = "".join(CSV_A.splitlines(keepends=True)[:-1])
        with self.assertRaises(ValueError):
            analyse.summarise([short, CSV_B], META, HEAP_LOG)


class SpreadTest(unittest.TestCase):
    def test_gives_the_median_of_each_process(self):
        self.assertEqual(summary()["spans"]["step_us"]["process_medians"], [30.0, 40.0])

    def test_spread_is_the_range_of_the_process_medians(self):
        spans = summary()["spans"]
        self.assertEqual(spans["step_us"]["spread"], 10.0)
        self.assertEqual(spans["view_us"]["spread"], 0.0)

    def test_percentiles_pool_the_frames_of_all_processes(self):
        step = summary()["spans"]["step_us"]
        # Pooled: 10, 20, 20, 30, 30, 40, 40, 50, 50, 60.
        self.assertEqual(step["median"], 35.0)
        self.assertAlmostEqual(step["p95"], 55.5)
        self.assertAlmostEqual(step["p99"], 59.1)

    def test_refuses_a_run_with_missing_processes(self):
        with self.assertRaises(ValueError):
            analyse.summarise([CSV_A], META, HEAP_LOG)


class HeapCountersTest(unittest.TestCase):
    def test_counts_only_the_measured_steps(self):
        heap = summary()["roc_heap_counters"]
        self.assertEqual(heap["allocs"], 10)
        self.assertEqual(heap["deallocs"], 10)
        self.assertEqual(heap["reallocs"], 2)
        self.assertEqual(heap["allocs_per_step"], 2.0)
        self.assertEqual(heap["reallocs_per_step"], 0.4)
        self.assertEqual(heap["live_max"], 81)
        self.assertEqual(heap["live_last"], 80)

    def test_refuses_a_log_with_missing_steps(self):
        with self.assertRaises(ValueError):
            analyse.heap_counters(HEAP_LOG.replace("alloc step=7", "x"), 2, 5)


class SummaryShapeTest(unittest.TestCase):
    def test_has_the_run_fields_spans_and_heap_counters(self):
        self.assertEqual(sorted(summary()), sorted(analyse.RUN_FIELDS + ["span_cost_us", "spans", "frame_budget_steps", "frame_budget_us", "roc_heap_counters"]))

    def test_each_span_has_the_same_statistics(self):
        for stats in summary()["spans"].values():
            self.assertEqual(sorted(stats), ["max", "median", "p95", "p99", "process_medians", "spread"])

    def test_records_the_run_and_the_machine(self):
        s = summary()
        self.assertEqual(s["n"], 64)
        self.assertEqual(s["mode"], "headless")
        self.assertEqual(s["git_hash"], "abc123")
        self.assertEqual(s["build_flags"], META["build_flags"])
        self.assertEqual(s["roc_heap"], "header")
        self.assertEqual(s["processes"], 2)
        self.assertEqual(s["machine"]["power"], "ac")
        self.assertFalse(s["odin_debug"])

    def test_the_summary_is_json(self):
        self.assertEqual(json.loads(json.dumps(summary())), summary())


FULL_ROW = {
    "frame": "1",
    "steps": "1",
    "input_us": "1.0",
    "step_us": "100.0",
    "commands_us": "2.0",
    "view_us": "50.0",
    "queries_us": "40.0",
    "query_results_us": "7.0",
    "interpolation_us": "300.0",
    "ui_layout_us": "200.0",
    "render_submit_us": "1000.0",
    "commit_us": "10.0",
}


class FrameBudgetTest(unittest.TestCase):
    def test_doubles_the_per_step_spans_and_adds_the_per_frame_spans_once(self):
        names = [name for name in FULL_ROW if name.endswith("_us")]
        # Per step: 1 + 100 + 2 + 50 + 40 + 7 = 200. Per Frame: 300 + 200 + 1000 + 10 = 1510.
        self.assertEqual(analyse.frame_budget(FULL_ROW, names), 2 * 200.0 + 1510.0)

    def test_divides_the_per_step_spans_by_the_steps_of_the_frame(self):
        names = [name for name in FULL_ROW if name.endswith("_us")]
        two_steps = {**FULL_ROW, "steps": "2"}
        self.assertEqual(analyse.frame_budget(two_steps, names), 200.0 + 1510.0)

    def test_refuses_a_span_it_cannot_place(self):
        with self.assertRaises(ValueError):
            analyse.frame_budget({**FULL_ROW, "physics_us": "1.0"}, ["step_us", "physics_us"])

    def test_the_summary_holds_the_budget_statistics_over_all_processes(self):
        s = summary()
        self.assertEqual(s["frame_budget_steps"], 2)
        budget = s["frame_budget_us"]
        # CSV_A gives 30, 42, 68, 84, 106 and CSV_B gives 50, 62, 88, 104, 126.
        self.assertEqual(budget["process_medians"], [68.0, 88.0])
        self.assertEqual(budget["spread"], 20.0)
        self.assertEqual(budget["max"], 126.0)
        self.assertEqual(budget["median"], 76.0)
        self.assertEqual(sorted(budget), ["max", "median", "p95", "p99", "process_medians", "spread"])

    def test_the_p99_of_the_budget_is_not_the_sum_of_span_p99s(self):
        s = summary()
        self.assertLess(s["frame_budget_us"]["p99"], 2 * (s["spans"]["step_us"]["p99"] + s["spans"]["view_us"]["p99"]))


class SpanCostTest(unittest.TestCase):
    def test_records_the_span_cost_and_does_not_treat_it_as_a_span(self):
        add_cost = lambda text: "".join(
            line + (",span_cost_us\n" if i == 0 else ",0.014\n") for i, line in enumerate(text.splitlines())
        )
        s = analyse.summarise([add_cost(CSV_A), add_cost(CSV_B)], META, HEAP_LOG)
        self.assertEqual(sorted(s["spans"]), ["step_us", "view_us"])
        self.assertEqual(s["span_cost_us"], 0.014)

    def test_is_null_for_a_csv_without_it(self):
        self.assertIsNone(summary()["span_cost_us"])


class DebugTest(unittest.TestCase):
    def test_refuses_a_debug_build(self):
        with self.assertRaises(analyse.DebugBuild):
            analyse.summarise([CSV_A, CSV_B], {**META, "odin_debug": True}, HEAP_LOG)

    def test_refuses_debug_host_flags_even_if_odin_debug_says_false(self):
        flags = {**META["build_flags"], "host": ["build", "engine", "-debug"]}
        with self.assertRaises(analyse.DebugBuild):
            analyse.summarise([CSV_A, CSV_B], {**META, "build_flags": flags}, HEAP_LOG)


class CommandLineTest(unittest.TestCase):
    def run_script(self, *args):
        script = Path(__file__).with_name("analyse.py")
        return subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)

    def write_run(self, tmp, meta):
        (tmp / "model-size-64-p1.csv").write_text(CSV_A)
        (tmp / "model-size-64-p2.csv").write_text(CSV_B)
        (tmp / "model-size-64.heap.log").write_text(HEAP_LOG)
        run_path = tmp / "model-size-64.run.json"
        run_path.write_text(json.dumps(meta))
        return run_path

    def test_writes_the_summary_to_the_out_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            run_path = self.write_run(tmp, META)
            result = self.run_script(str(run_path), "--out-dir", str(tmp / "results"))
            self.assertEqual(result.returncode, 0, result.stderr)
            written = json.loads((tmp / "results" / "model-size-64.json").read_text())
            self.assertEqual(written["spans"]["step_us"]["spread"], 10.0)

    def test_names_the_results_dir_by_date_and_machine(self):
        self.assertEqual(analyse.results_dir(META).name, "2026-10-19-apple-m5")
        self.assertEqual(analyse.results_dir(META).parent.name, "results")

    def test_fails_on_a_debug_build_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            run_path = self.write_run(tmp, {**META, "odin_debug": True})
            result = self.run_script(str(run_path), "--out-dir", str(tmp / "results"))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("debug", result.stderr)
            self.assertFalse((tmp / "results").exists())

    def test_fails_with_no_run_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = self.run_script(str(Path(tmp) / "model-size-64.run.json"))
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("run.json", result.stderr)


if __name__ == "__main__":
    unittest.main()
